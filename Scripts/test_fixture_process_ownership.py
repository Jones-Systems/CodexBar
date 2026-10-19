#!/usr/bin/env python3
"""Focused ownership proof. Default runs fakes only; --live adds owned POSIX fixtures."""

from contextlib import ExitStack
import errno
import io
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch

import fixture_process_anchor as helper
import test_fixture_scratch_parent as fixture


class OrderingTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.owned = self.stack.enter_context(tempfile.TemporaryDirectory(dir=PARENT, prefix="ownership-"))
        self.events = []
        self.process = Mock(pid=123, returncode=None)
        self.anchor = Mock(pid=124, returncode=None)
        self.anchor_status = None
        self.process.poll.side_effect = AssertionError("poll would release identity")
        self.process.communicate.side_effect = AssertionError("communicate would release identity")
        self.process.wait.side_effect = self.reap
        self.anchor.wait.side_effect = self.reap_anchor
        self.status = SimpleNamespace(si_status=0, si_code=os.CLD_EXITED)
        self.spawn_hook = None
        self.anchor_spawn_hook = None
        self.kill_hook = None
        self.observe_hook = None
        self.stack.enter_context(patch.object(fixture.subprocess, "Popen", side_effect=self.spawn))
        self.stack.enter_context(patch.object(fixture.os, "waitid", side_effect=self.observe))
        self.stack.enter_context(patch.object(fixture.os, "killpg", side_effect=self.kill))
        self.stack.enter_context(patch.object(fixture.time, "sleep"))
        self.gate, self.gate_child, self.control, self.control_child = [MagicMock() for _ in range(4)]
        for descriptor, control in enumerate((self.gate, self.gate_child, self.control, self.control_child), 100):
            control.fileno.return_value = descriptor
            control.__enter__.return_value = control
        self.pair_count = 0
        self.stack.enter_context(patch.object(socket, "socketpair", side_effect=self.socketpair))
        self.handshake = self.stack.enter_context(patch.object(fixture, "wait_helper_ready"))

    def socketpair(self):
        self.pair_count += 1
        return (self.gate, self.gate_child) if self.pair_count % 2 else (self.control, self.control_child)

    def spawn(self, command, **kwargs):
        self.assertFalse(kwargs.get("start_new_session", False))
        role = command[3]
        self.assertEqual(command[:3], [sys.executable, "-B", str(fixture.HELPER)])
        self.assertEqual(kwargs["process_group"], 0 if role == "command" else self.process.pid)
        self.assertEqual(kwargs["pass_fds"], (int(command[4]),))
        self.assertNotEqual(kwargs["stdout"], subprocess.PIPE)
        if role == "anchor":
            self.events.append("spawn-anchor")
            if self.anchor_spawn_hook:
                self.anchor_spawn_hook()
            return self.anchor
        kwargs["stdout"].write(b"output")
        kwargs["stderr"].write(b"diagnostic")
        self.events.append("spawn")
        if self.spawn_hook:
            self.spawn_hook()
        return self.process

    def observe(self, kind, pid, flags):
        self.assertEqual(kind, os.P_PID)
        self.assertIn(pid, (self.process.pid, self.anchor.pid))
        self.assertEqual(flags, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        self.assertIsNone(self.process.returncode, "observed after reap")
        self.events.append("observe")
        if self.observe_hook:
            return self.observe_hook()
        return self.status if pid == self.process.pid else self.anchor_status

    def kill(self, pid, sig):
        self.assertEqual(pid, self.process.pid)
        self.assertIsNone(self.process.returncode, "signal after reap: recycled PGID risk")
        self.assertIsNone(self.anchor.returncode, "signal after anchor reap")
        self.events.append(sig)
        if self.kill_hook:
            self.kill_hook()

    def reap(self, timeout):
        self.assertGreaterEqual(timeout, 0)
        self.assertLessEqual(timeout, 5)
        self.assertEqual(self.events[-1], signal.SIGKILL)
        self.events.append("reap")
        self.process.returncode = 0
        return 0

    def reap_anchor(self, timeout):
        self.assertGreaterEqual(timeout, 0)
        self.assertLessEqual(timeout, 5)
        self.events.append("anchor-reap")
        self.anchor.returncode = -signal.SIGKILL
        return self.anchor.returncode

    def collect(self, **kwargs):
        self.anchor.returncode = None
        self.anchor.wait.reset_mock()
        return fixture.collect_owned_process(["synthetic"], {}, self.owned, **kwargs)

    def assert_finished(self):
        self.assertEqual(self.events[-3:], [signal.SIGKILL, "reap", "anchor-reap"])
        self.process.wait.assert_called_once()
        self.anchor.wait.assert_called_once()
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
        with patch.object(fixture.time, "monotonic", side_effect=[0, 16, 0, 0, 0]):
            with self.assertRaisesRegex(AssertionError, "seam not reached"):
                self.collect(ready=Mock(exists=Mock(return_value=False)), cancel=signal.SIGTERM)
        self.assert_finished()

    def test_execution_timeout(self):
        self.status = None
        with patch.object(fixture.time, "monotonic", side_effect=[0, 21, 0, 0, 0]):
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
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO):
            with self.assertRaises(ProcessLookupError):
                self.collect()
        self.assert_finished()

    def test_permission_denied_reaps_terminal_leader_but_fails_cleanup(self):
        denied = PermissionError(errno.EPERM, "group signal denied")
        self.kill_hook = Mock(side_effect=denied)
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
            with self.assertRaises(PermissionError) as error:
                self.collect()
        self.assertIs(error.exception, denied)
        self.assert_finished()
        self.assertIn("leader 123 reaped", diagnostic.getvalue())
        self.assertIn("descendant cleanup unknown", diagnostic.getvalue())

    def test_permission_denied_with_pending_leader_still_attempts_bounded_reap(self):
        self.status = None
        self.kill_hook = Mock(side_effect=PermissionError(errno.EPERM, "group signal denied"))
        with patch.object(fixture.time, "monotonic", side_effect=[0, 21, 0, 0, 0]):
            with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
                with self.assertRaises(subprocess.TimeoutExpired):
                    self.collect()
        self.assert_finished()
        self.assertIn("leader 123 reaped", diagnostic.getvalue())
        self.assertIn("cleanup also failed", diagnostic.getvalue())

    def test_signal_denial_and_reap_failure_preserve_both_errors_without_retry(self):
        for reap_error in (subprocess.TimeoutExpired("synthetic", 5), OSError(errno.EIO, "wait failed")):
            with self.subTest(reap_error=reap_error):
                self.events.clear()
                self.process.wait.reset_mock()
                denied = PermissionError(errno.EPERM, "group signal denied")
                self.kill_hook = Mock(side_effect=denied)
                self.process.wait.side_effect = reap_error
                with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
                    with self.assertRaises(PermissionError) as error:
                        self.collect()
                self.assertIs(error.exception, denied)
                self.assertIs(error.exception.__cause__, reap_error)
                self.assertEqual(self.events.count(signal.SIGKILL), 1)
                self.process.wait.assert_called_once()
                self.assertLessEqual(self.process.wait.call_args.kwargs["timeout"], 5)
                self.anchor.wait.assert_called_once()
                self.assertIn("leader 123 reap unproved", diagnostic.getvalue())
                self.assertIn("descendant cleanup unknown", diagnostic.getvalue())
                self.assertIn(str(reap_error), diagnostic.getvalue())
                self.assertNotIn("leader 123 reaped", diagnostic.getvalue())
                self.assertEqual(list(Path(self.owned).iterdir()), [])

    def test_other_group_signal_error_does_not_skip_owned_reap(self):
        failure = OSError(errno.EIO, "signal failed")
        self.kill_hook = Mock(side_effect=failure)
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO):
            with self.assertRaises(OSError) as error:
                self.collect()
        self.assertIs(error.exception, failure)
        self.assert_finished()

    def test_primary_failure_survives_signal_denial_and_reap_failure(self):
        primary = ValueError("readiness failed")
        ready = Mock(exists=Mock(side_effect=primary))
        self.kill_hook = Mock(side_effect=PermissionError(errno.EPERM, "group signal denied"))
        self.process.wait.side_effect = subprocess.TimeoutExpired("synthetic", 5)
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
            with self.assertRaises(ValueError) as error:
                self.collect(ready=ready, cancel=signal.SIGTERM)
        self.assertIs(error.exception, primary)
        self.assertEqual(self.events.count(signal.SIGKILL), 1)
        self.process.wait.assert_called_once()
        self.assertLessEqual(self.process.wait.call_args.kwargs["timeout"], 5)
        self.anchor.wait.assert_called_once()
        self.assertIn("leader 123 reap unproved", diagnostic.getvalue())
        self.assertIn("group signal denied", diagnostic.getvalue())
        self.assertIn("timed out", diagnostic.getvalue())
        self.assertIn("cleanup also failed", diagnostic.getvalue())

    def test_unsupported_waitid_fails_before_spawn(self):
        with patch.object(fixture.os, "waitid"):
            del fixture.os.waitid
            with self.assertRaisesRegex(RuntimeError, "requires waitid/WNOWAIT"):
                self.collect()
        self.assertEqual(self.events, [])

    def test_unsupported_process_group_fails_before_spawn(self):
        with patch.object(fixture.sys, "version_info", (3, 10)):
            with self.assertRaisesRegex(RuntimeError, "requires Python 3.11"):
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


    def test_command_is_released_only_after_both_helper_handshakes(self):
        def ready(control, children):
            self.events.append("command-ready" if control is self.gate else "anchor-ready")
            self.assertEqual(children, (self.process,) if control is self.gate else (self.process, self.anchor))
        self.handshake.side_effect = ready
        self.gate.sendall.side_effect = lambda message: self.events.append(("release", message))
        self.collect()
        self.assertEqual(self.events[:5], ["spawn", "command-ready", "spawn-anchor", "anchor-ready", ("release", b"G")])
        self.assert_finished()

    def test_terminal_command_has_live_anchor_at_group_signal(self):
        def darwin_group_signal():
            self.assertIsNotNone(self.status)
            self.assertIn("spawn-anchor", self.events)
            if self.anchor_status is not None:
                raise PermissionError(errno.EPERM, "zombie-only group")
        self.kill_hook = darwin_group_signal
        self.assertEqual(self.collect()[0], 0)
        self.assert_finished()

    def test_anchor_spawn_failure_drains_gated_command_without_exec(self):
        self.anchor_spawn_hook = Mock(side_effect=OSError("anchor spawn failed"))
        with self.assertRaisesRegex(OSError, "anchor spawn failed"):
            self.collect()
        self.gate.sendall.assert_not_called()
        self.assertEqual(self.events[-2:], [signal.SIGKILL, "reap"])
        self.process.wait.assert_called_once()
        self.anchor.wait.assert_not_called()

    def test_handshake_and_release_failures_reap_all_created_children(self):
        for stage in ("command", "anchor", "release"):
            with self.subTest(stage=stage):
                self.process.returncode = None
                self.process.wait.reset_mock()
                self.events.clear()
                self.gate.sendall.reset_mock(side_effect=True)
                error = OSError("gate failed")
                self.handshake.side_effect = [error] if stage == "command" else [None, error if stage == "anchor" else None]
                if stage == "release":
                    self.gate.sendall.side_effect = error
                with self.assertRaisesRegex(OSError, "gate failed"):
                    self.collect()
                self.process.wait.assert_called_once()
                if stage == "command":
                    self.anchor.wait.assert_not_called()
                    self.gate.sendall.assert_not_called()
                else:
                    self.assert_finished()

    def test_cancellation_during_anchor_spawn_keeps_both_handles(self):
        self.anchor_spawn_hook = lambda: signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
        with self.assertRaises(SystemExit) as error:
            self.collect()
        self.assertEqual(error.exception.code, 128 + signal.SIGTERM)
        self.gate.sendall.assert_not_called()
        self.assert_finished()

    def test_unexpected_anchor_exit_fails_even_if_group_cleanup_succeeds(self):
        self.anchor_status = SimpleNamespace(si_status=1, si_code=os.CLD_EXITED)
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO):
            with self.assertRaisesRegex(RuntimeError, "anchor exited"):
                self.collect()
        self.assert_finished()

    def test_anchor_loses_wait_ownership_denies_signal_but_reaps_known_command(self):
        def observe(kind, pid, flags):
            if pid == self.anchor.pid:
                raise ChildProcessError("anchor ownership lost")
            return self.status
        self.process.wait.side_effect = lambda timeout: 0
        with patch.object(fixture.os, "waitid", side_effect=observe):
            with patch.object(fixture.sys, "stderr", new_callable=io.StringIO):
                with self.assertRaisesRegex(ChildProcessError, "anchor ownership lost"):
                    self.collect()
        self.assertFalse(any(isinstance(event, int) for event in self.events))
        self.process.wait.assert_called_once()
        self.anchor.wait.assert_not_called()
        self.control.close.assert_called()

    def test_leader_loses_wait_ownership_still_reaps_known_anchor(self):
        def observe(kind, pid, flags):
            if pid == self.process.pid:
                raise ChildProcessError("leader ownership lost")
            return None
        with patch.object(fixture.os, "waitid", side_effect=observe):
            with patch.object(fixture.sys, "stderr", new_callable=io.StringIO):
                with self.assertRaisesRegex(ChildProcessError, "leader ownership lost"):
                    self.collect()
        self.assertFalse(any(isinstance(event, int) for event in self.events))
        self.process.wait.assert_not_called()
        self.anchor.wait.assert_called_once()

    def test_anchor_reap_failure_never_retries_group_signal(self):
        self.anchor.wait.side_effect = subprocess.TimeoutExpired("anchor", 5)
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
            with self.assertRaises(subprocess.TimeoutExpired):
                self.collect()
        self.assertEqual(self.events.count(signal.SIGKILL), 1)
        self.process.wait.assert_called_once()
        self.anchor.wait.assert_called_once()
        self.assertIn("leader 123 reaped", diagnostic.getvalue())
        self.assertIn("anchor 124 reap unproved", diagnostic.getvalue())

    def test_anchor_must_exit_from_final_group_signal_on_success(self):
        self.anchor.wait.side_effect = lambda timeout: 0
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO):
            with self.assertRaisesRegex(RuntimeError, "anchor did not terminate"):
                self.collect()
        self.assertEqual(self.events.count(signal.SIGKILL), 1)

    def test_both_reap_errors_are_reported_without_hiding_signal_denial(self):
        denied = PermissionError(errno.EPERM, "group signal denied")
        self.kill_hook = Mock(side_effect=denied)
        self.process.wait.side_effect = OSError("leader wait failed")
        self.anchor.wait.side_effect = OSError("anchor wait failed")
        with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
            with self.assertRaises(PermissionError) as error:
                self.collect()
        self.assertIs(error.exception, denied)
        for message in ("group signal denied", "leader wait failed", "anchor wait failed"):
            self.assertIn(message, diagnostic.getvalue())
        self.process.wait.assert_called_once()
        self.anchor.wait.assert_called_once()
        self.assertEqual(self.events.count(signal.SIGKILL), 1)


class HelperTests(unittest.TestCase):
    def test_command_exec_requires_release_and_closes_private_socket_first(self):
        control = MagicMock()
        control.__enter__.return_value = control
        control.recv.return_value = b"G"
        def execute(program, command, env):
            control.__exit__.assert_called_once()
            self.assertEqual((program, command, env), ("synthetic", ["synthetic", "arg"], os.environ))
        with patch.object(helper.socket, "socket", return_value=control):
            with patch.object(helper.signal, "signal"):
                with patch.object(helper.os, "execvpe", side_effect=execute) as execute_mock:
                    helper.run("command", 100, ["synthetic", "arg"])
        control.sendall.assert_called_once_with(b"R")
        execute_mock.assert_called_once()

    def test_command_eof_or_invalid_release_never_execs(self):
        for message in (b"", b"X"):
            with self.subTest(message=message):
                control = MagicMock()
                control.__enter__.return_value = control
                control.recv.return_value = message
                with patch.object(helper.socket, "socket", return_value=control):
                    with patch.object(helper.os, "execvpe") as execute:
                        with self.assertRaisesRegex(RuntimeError, "not released"):
                            helper.run("command", 100, ["synthetic"])
                execute.assert_not_called()

    def test_anchor_installs_caught_handlers_before_ready_and_exits_on_eof(self):
        control = MagicMock()
        control.__enter__.return_value = control
        control.recv.return_value = b""
        with patch.object(helper.socket, "socket", return_value=control):
            with patch.object(helper.signal, "signal") as install:
                control.sendall.side_effect = lambda _: self.assertEqual(install.call_count, 3)
                with patch.object(helper.os, "execvpe") as execute:
                    helper.run("anchor", 100, [])
        self.assertEqual([call.args[0] for call in install.call_args_list], list(fixture.CANCELLATION_SIGNALS))
        for call in install.call_args_list:
            self.assertTrue(callable(call.args[1]))
            call.args[1](call.args[0], None)
        execute.assert_not_called()

    def test_readiness_requires_retained_children_and_exact_acknowledgment(self):
        process = Mock()
        for message in (b"", b"X", b"R"):
            with self.subTest(message=message):
                control = Mock(recv=Mock(return_value=message))
                with patch.object(fixture, "retained_status", return_value=None) as observe:
                    if message == b"R":
                        fixture.wait_helper_ready(control, (process,))
                    else:
                        with self.assertRaisesRegex(RuntimeError, "Invalid"):
                            fixture.wait_helper_ready(control, (process,))
                observe.assert_called_once_with(process)

    def test_readiness_timeout_and_ownership_loss_fail_closed(self):
        control = Mock(recv=Mock(side_effect=BlockingIOError()))
        with patch.object(fixture, "retained_status", return_value=None):
            with patch.object(fixture.time, "monotonic", side_effect=[0, 6]):
                with self.assertRaises(TimeoutError):
                    fixture.wait_helper_ready(control, (Mock(),))
        control.recv.reset_mock()
        with patch.object(fixture, "retained_status", side_effect=ChildProcessError()):
            with self.assertRaises(ChildProcessError):
                fixture.wait_helper_ready(control, (Mock(),))
        control.recv.assert_not_called()


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

    def test_no_fork_command_and_live_anchor_are_both_direct_children_and_reaped(self):
        children = []
        spawn = subprocess.Popen
        def capture(*args, **kwargs):
            child = spawn(*args, **kwargs)
            children.append(child)
            return child
        with patch.object(fixture.subprocess, "Popen", side_effect=capture):
            status, out, _ = self.collect("import os; print(os.getpid(), os.getppid(), os.getpgrp(), os.getsid(0))")
        self.assertEqual(status, 0)
        self.assertEqual(len(children), 2)
        leader, anchor = children
        self.assertEqual(tuple(map(int, out.split())), (leader.pid, os.getpid(), leader.pid, os.getsid(0)))
        self.assertEqual((leader.returncode, anchor.returncode), (0, -signal.SIGKILL))

    def test_denied_signal_reaps_terminal_command_and_releases_anchor_but_fails(self):
        children = []
        spawn = subprocess.Popen
        def capture(*args, **kwargs):
            child = spawn(*args, **kwargs)
            children.append(child)
            return child
        with patch.object(fixture.subprocess, "Popen", side_effect=capture):
            with patch.object(fixture.os, "killpg", side_effect=PermissionError(errno.EPERM, "synthetic denial")) as kill:
                with patch.object(fixture.sys, "stderr", new_callable=io.StringIO) as diagnostic:
                    with self.assertRaises(PermissionError):
                        self.collect("pass")
        kill.assert_called_once()
        self.assertEqual([child.returncode for child in children], [0, 0])
        self.assertIn("descendant cleanup unknown", diagnostic.getvalue())

    def test_exited_leader_with_multiple_descendants_drains_every_lifeline(self):
        fifo = self.owned / "multiple-lifelines"
        os.mkfifo(fifo, 0o600)
        fd = os.open(fifo, os.O_RDONLY | os.O_NONBLOCK)
        self.addCleanup(os.close, fd)
        source = '''import os, signal, time
fd = os.open(FIFO, os.O_WRONLY)
read_ack, write_ack = os.pipe()
for _ in range(3):
    if os.fork() == 0:
        os.close(read_ack)
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, signal.SIG_IGN)
        os.write(fd, b'x')
        os.write(write_ack, b'1')
        os.close(write_ack)
        time.sleep(10)
        os._exit(0)
os.close(write_ack)
for _ in range(3):
    assert os.read(read_ack, 1) == b'1'
os.close(read_ack)
os.close(fd)
os._exit(53)
'''.replace("FIFO", repr(str(fifo)))
        self.assertEqual(self.collect(source)[0], 53)
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
            self.assertLess(time.monotonic(), deadline, "descendant retained a lifeline")
            time.sleep(0.01)
        self.assertEqual(received, b"xxx")


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
    suite.addTests(loader.loadTestsFromTestCase(HelperTests))
    if live:
        suite.addTests(loader.loadTestsFromTestCase(LiveTests))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
