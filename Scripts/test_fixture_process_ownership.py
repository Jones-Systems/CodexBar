#!/usr/bin/env python3
"""Focused ownership proof. Default runs fakes only; --live adds owned POSIX fixtures."""

from contextlib import ExitStack
import io
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import test_fixture_scratch_parent as fixture


class OrderingTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.owned = self.stack.enter_context(tempfile.TemporaryDirectory(dir=PARENT, prefix="ownership-"))
        self.events = []
        self.process = Mock(pid=123, returncode=None)
        self.process.poll.side_effect = AssertionError("poll would release identity")
        self.process.communicate.side_effect = AssertionError("communicate would release identity")
        self.process.wait.side_effect = self.reap
        self.status = SimpleNamespace(si_status=0, si_code=os.CLD_EXITED)
        self.spawn_hook = None
        self.kill_hook = None
        self.observe_hook = None
        self.stack.enter_context(patch.object(fixture.subprocess, "Popen", side_effect=self.spawn))
        self.stack.enter_context(patch.object(fixture.os, "waitid", side_effect=self.observe))
        self.stack.enter_context(patch.object(fixture.os, "killpg", side_effect=self.kill))
        self.stack.enter_context(patch.object(fixture.time, "sleep"))

    def spawn(self, command, **kwargs):
        self.assertTrue(kwargs["start_new_session"])
        self.assertNotEqual(kwargs["stdout"], subprocess.PIPE)
        kwargs["stdout"].write(b"output")
        kwargs["stderr"].write(b"diagnostic")
        self.events.append("spawn")
        if self.spawn_hook:
            self.spawn_hook()
        return self.process

    def observe(self, kind, pid, flags):
        self.assertEqual((kind, pid), (os.P_PID, self.process.pid))
        self.assertEqual(flags, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        self.assertIsNone(self.process.returncode, "observed after reap")
        self.events.append("observe")
        if self.observe_hook:
            return self.observe_hook()
        return self.status

    def kill(self, pid, sig):
        self.assertEqual(pid, self.process.pid)
        self.assertIsNone(self.process.returncode, "signal after reap: recycled PGID risk")
        self.events.append(sig)
        if self.kill_hook:
            self.kill_hook()

    def reap(self, timeout):
        self.assertEqual(timeout, 5)
        self.assertEqual(self.events[-1], signal.SIGKILL)
        self.events.append("reap")
        self.process.returncode = 0
        return 0

    def collect(self, **kwargs):
        return fixture.collect_owned_process(["synthetic"], {}, self.owned, **kwargs)

    def assert_finished(self):
        self.assertEqual(self.events[-2:], [signal.SIGKILL, "reap"])
        self.process.wait.assert_called_once()
        self.process.poll.assert_not_called()
        self.process.communicate.assert_not_called()
        self.assertEqual(list(Path(self.owned).iterdir()), [])

    def test_success_and_failure_keep_exit_status_before_cleanup(self):
        for status in (0, 1, 37, 41, 53):
            with self.subTest(status=status):
                self.process.returncode = None
                self.process.wait.reset_mock()
                self.status.si_status = status
                self.assertEqual(self.collect(), (status, b"output", b"diagnostic"))
                self.assert_finished()

    def test_signal_exit_status(self):
        self.status = SimpleNamespace(si_status=signal.SIGTERM, si_code=os.CLD_KILLED)
        self.assertEqual(self.collect()[0], -signal.SIGTERM)
        self.assert_finished()

    def test_all_requested_cancellation_signals_precede_reap(self):
        for sig in fixture.CANCELLATION_SIGNALS:
            with self.subTest(signal=sig):
                self.process.returncode = None
                self.process.wait.reset_mock()
                self.events.clear()
                self.collect(ready=Mock(exists=Mock(return_value=True)), cancel=sig)
                self.assertEqual([event for event in self.events if isinstance(event, int)], [sig, signal.SIGKILL])
                self.assert_finished()

    def test_readiness_detects_exited_leader_without_reaping(self):
        with self.assertRaisesRegex(AssertionError, "seam not reached"):
            self.collect(ready=Mock(exists=Mock(return_value=False)), cancel=signal.SIGTERM)
        self.assert_finished()

    def test_readiness_timeout(self):
        self.status = None
        with patch.object(fixture.time, "monotonic", side_effect=[0, 16]):
            with self.assertRaisesRegex(AssertionError, "seam not reached"):
                self.collect(ready=Mock(exists=Mock(return_value=False)), cancel=signal.SIGTERM)
        self.assert_finished()

    def test_execution_timeout(self):
        self.status = None
        with patch.object(fixture.time, "monotonic", side_effect=[0, 21]):
            with self.assertRaises(subprocess.TimeoutExpired):
                self.collect()
        self.assert_finished()

    def test_exception_during_readiness(self):
        ready = Mock(exists=Mock(side_effect=ValueError("readiness failed")))
        with self.assertRaisesRegex(ValueError, "readiness failed"):
            self.collect(ready=ready, cancel=signal.SIGTERM)
        self.assert_finished()

    def test_cancellation_during_spawn_is_deferred_until_handle_owned(self):
        for sig in fixture.CANCELLATION_SIGNALS:
            with self.subTest(signal=sig):
                self.process.returncode = None
                self.process.wait.reset_mock()
                self.spawn_hook = lambda: signal.getsignal(sig)(sig, None)
                with self.assertRaises(SystemExit) as error:
                    self.collect()
                self.assertEqual(error.exception.code, 128 + sig)
                self.assert_finished()

    def test_repeated_cancellation_during_cleanup_cannot_interrupt_reap(self):
        def cancel_again():
            for sig in fixture.CANCELLATION_SIGNALS:
                signal.getsignal(sig)(sig, None)
        self.kill_hook = cancel_again
        with self.assertRaises(SystemExit) as error:
            self.collect()
        self.assertEqual(error.exception.code, 128 + signal.SIGHUP)
        self.assert_finished()

    def test_already_reaped_handle_denies_signal(self):
        self.process.returncode = 0
        with self.assertRaisesRegex(RuntimeError, "already reaped"):
            fixture.signal_retained_group(self.process, signal.SIGKILL)
        self.assertEqual(self.events, [])

    def test_lost_wait_ownership_denies_signal_and_preserves_primary_failure(self):
        self.observe_hook = Mock(side_effect=ChildProcessError("lost wait ownership"))
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
            with self.assertRaises(ChildProcessError):
                self.collect()
        self.assertIn("cleanup also failed", diagnostic.getvalue())
        self.assertFalse(any(isinstance(event, int) for event in self.events))
        self.process.wait.assert_not_called()

    def test_wait_failure_never_retries_group_signal(self):
        self.process.wait.side_effect = subprocess.TimeoutExpired("synthetic", 5)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.collect()
        self.assertEqual(self.events.count(signal.SIGKILL), 1)
        self.process.wait.assert_called_once()

    def test_missing_group_is_reaped_without_retry(self):
        self.kill_hook = Mock(side_effect=ProcessLookupError())
        self.collect()
        self.assert_finished()

    def test_unsupported_waitid_fails_before_spawn(self):
        with patch.object(fixture.os, "waitid"):
            del fixture.os.waitid
            with self.assertRaisesRegex(RuntimeError, "requires waitid/WNOWAIT"):
                self.collect()
        self.assertEqual(self.events, [])

    def test_nondefault_sigchld_fails_before_spawn(self):
        with patch.object(fixture.signal, "getsignal", return_value=signal.SIG_IGN):
            with self.assertRaisesRegex(RuntimeError, "default SIGCHLD"):
                self.collect()
        self.assertEqual(self.events, [])

    def test_spawn_failure_does_not_signal(self):
        self.spawn_hook = Mock(side_effect=OSError("spawn failed"))
        with self.assertRaisesRegex(OSError, "spawn failed"):
            self.collect()
        self.assertEqual(self.events, ["spawn"])


class LiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=PARENT, prefix="ownership-live-")
        self.addCleanup(self.directory.cleanup)
        self.owned = Path(self.directory.name)
        self.env = {"PATH": "/usr/bin:/bin", "HOME": str(self.owned), "TMPDIR": str(self.owned)}

    def collect(self, source, **kwargs):
        return fixture.collect_owned_process([sys.executable, "-c", source], self.env, self.owned, **kwargs)

    def test_large_outputs_do_not_block_on_pipe_capacity(self):
        status, out, err = self.collect("import os; os.write(1, b'x' * 262144); os.write(2, b'y' * 262144)")
        self.assertEqual((status, out, err), (0, b"x" * 262144, b"y" * 262144))

    def test_exited_leader_retains_group_until_descendant_cleanup(self):
        fifo = self.owned / "lifeline"
        os.mkfifo(fifo, 0o600)
        fd = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
        self.addCleanup(os.close, fd)
        source = '''import os, signal, sys, time
fd = os.open(sys.argv[0], os.O_WRONLY)
ack_read, ack_write = os.pipe()
child = os.fork()
if child == 0:
    os.close(ack_read)
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, signal.SIG_IGN)
    os.write(fd, b'ready')
    os.write(ack_write, b'1')
    os.close(ack_write)
    time.sleep(10)
    os._exit(0)
os.close(fd)
os.close(ack_write)
assert os.read(ack_read, 1) == b'1'
os.close(ack_read)
sys.exit(37)
'''.replace("sys.argv[0]", repr(str(fifo)))
        status, _, _ = self.collect(source)
        self.assertEqual(status, 37)
        # EOF proves no fixture descendant retains the writer; no PID lookup or
        # numeric-PID signal is used to check descendant termination.
        deadline = time.monotonic() + 3
        received = b""
        while True:
            try:
                chunk = os.read(fd, 4096)
                if chunk == b"":
                    break
                received += chunk
            except BlockingIOError:
                pass
            self.assertLess(time.monotonic(), deadline, "descendant retained lifeline")
            time.sleep(0.01)
        self.assertEqual(received, b"ready")

    def test_timeout_kills_and_reaps_owned_group(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.collect("import time; time.sleep(10)", timeout=0.1)

    def test_runner_cancellation_still_cleans_owned_child(self):
        for sig in fixture.CANCELLATION_SIGNALS:
            with self.subTest(signal=sig):
                with self.assertRaises(SystemExit) as error:
                    self.collect(f"import os, time; os.kill(os.getppid(), {int(sig)}); time.sleep(10)")
                self.assertEqual(error.exception.code, 128 + sig)


if __name__ == "__main__":
    for sig in fixture.CANCELLATION_SIGNALS:
        signal.signal(sig, fixture.signal_exit)
    live = len(sys.argv) == 3 and sys.argv[1] == "--live"
    if len(sys.argv) != 2 and not live:
        sys.exit("Usage: python3 Scripts/test_fixture_process_ownership.py [--live] OWNED_WORKSPACE_PARENT")
    PARENT = Path(sys.argv[-1])
    if (not PARENT.is_absolute() or ".." in PARENT.parts or PARENT.resolve(strict=True) != PARENT
            or not PARENT.is_dir() or fixture.ROOT not in PARENT.parents):
        sys.exit("Expected an existing canonical directory strictly inside the workspace")
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(OrderingTests)
    if live:
        suite.addTests(loader.loadTestsFromTestCase(LiveTests))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
