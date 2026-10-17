#!/usr/bin/env python3
"""Synthetic fixture and runner lifecycle proof; pass one caller-owned workspace parent.

No Swift semantics are tested. A minimal copied workspace and stub tools keep
native compilation, packaging, and real account state outside this regression.
"""

from contextlib import ExitStack, contextmanager
import os
import importlib.util
import json
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
KEY = "CODEXBAR_TEST_SCRATCH_PARENT"
IDENTITY = "test_jones_identity_overlay.sh"
PROVIDER = "test_provider_session_file_isolation.sh"
CODEX = "test_codex_file_isolation_child.sh"
HELPER = Path(__file__).with_name("fixture_process_anchor.py")
_synthetic_cleanup_safe = True


@contextmanager
def owned_regression_directory(parent):
    owned = Path(tempfile.mkdtemp(prefix="fixture-parent-regression-", dir=parent))
    try:
        yield str(owned)
    finally:
        if _synthetic_cleanup_safe:
            shutil.rmtree(owned)
            if owned.exists():
                raise RuntimeError(f"Regression cleanup failed: {owned}")
        else:
            print(f"Preserving regression evidence after unproved process cleanup: {owned}", file=sys.stderr)


def signal_exit(signum, _frame):
    raise SystemExit(128 + signum)


CANCELLATION_SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


def require_wait_ownership():
    if sys.version_info < (3, 11):
        raise RuntimeError("Fixture containment requires Python 3.11+ process_group (macOS: Python 3.13+)")
    # CPython exposes waitid on macOS starting with 3.13. Never fall back to poll.
    if not all(hasattr(os, name) for name in (
            "waitid", "P_PID", "WEXITED", "WNOHANG", "WNOWAIT", "CLD_EXITED")):
        raise RuntimeError("Fixture containment requires waitid/WNOWAIT (macOS: Python 3.13+)")
    if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
        raise RuntimeError("Fixture containment requires the default SIGCHLD disposition")


def retained_status(process):
    # This standalone, single-threaded runner is the sole wait owner. WNOWAIT
    # pins the leader PID even after exit; no Popen poll/communicate/send_signal.
    if process.returncode is not None:
        raise RuntimeError("Synthetic process leader was already reaped")
    result = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
    if result is None:
        return None
    return result.si_status if result.si_code == os.CLD_EXITED else -result.si_status


def signal_retained_group(process, signum):
    # ECHILD or any other observation error denies signaling. The retained wait
    # identity, not a numeric PID existence check, authorizes this owned group.
    retained_status(process)
    os.killpg(process.pid, signum)


def cleanup_retained_group(process, anchor=None, control=None):
    owned, errors, reaped = [], [], []
    ownership_lost = False
    signaled = False
    for child in (process, anchor):
        if child is None:
            continue
        try:
            status = retained_status(child)
            owned.append(child)
            if child is anchor and status is not None:
                errors.append(RuntimeError("Synthetic group anchor exited before cleanup"))
        except BaseException as error:
            ownership_lost = True
            errors.append(error)
    # Both children are direct, sole-wait-owned identities. The gated command
    # leads their private group; the sibling anchor stays live even when the
    # command exits. Darwin therefore has a live eligible member at final kill.
    # An unexpected anchor exit remains a failure even if draining succeeds.
    if not ownership_lost:
        try:
            os.killpg(process.pid, signal.SIGKILL)
            signaled = True
        except BaseException as error:
            errors.append(error)
    if control is not None:
        # EOF releases only this invocation's anchor even if signaling failed.
        # It never signals anything itself, including after either child reap.
        try:
            control.close()
        except BaseException as error:
            errors.append(error)
    deadline = time.monotonic() + 5
    for child in owned:
        try:
            result = child.wait(timeout=max(0, deadline - time.monotonic()))
            reaped.append(child)
            if child is anchor and signaled and result != -signal.SIGKILL:
                errors.append(RuntimeError("Synthetic anchor did not terminate from final group SIGKILL"))
        except BaseException as error:
            errors.append(error)
    if errors:
        for child, label in ((process, "leader"), (anchor, "anchor")):
            if child is not None:
                outcome = "reaped" if child in reaped else "reap unproved"
                print(f"Synthetic {label} {child.pid} {outcome}; descendant cleanup unknown", file=sys.stderr)
        for error in errors:
            print(f"Synthetic cleanup error: {error}", file=sys.stderr)
        if len(errors) > 1:
            raise errors[0] from errors[1]
        raise errors[0]


def wait_helper_ready(control, children):
    control.setblocking(False)
    deadline = time.monotonic() + 5
    while True:
        for child in children:
            if retained_status(child) is not None:
                raise RuntimeError("Synthetic helper exited before readiness")
        try:
            message = control.recv(1)
        except BlockingIOError:
            message = None
        if message == b"R":
            return
        if message is not None:
            raise RuntimeError("Invalid synthetic helper readiness")
        if time.monotonic() >= deadline:
            raise TimeoutError("Synthetic helper readiness timed out")
        time.sleep(0.02)


def require_live_anchor(anchor):
    if retained_status(anchor) is not None:
        raise RuntimeError("Synthetic group anchor exited before cleanup")


def collect_owned_process(command, env, owned, ready=None, cancel=None, timeout=20):
    global _synthetic_cleanup_safe
    require_wait_ownership()
    deferred = []
    deferring = True

    def cancellation(signum, frame):
        if deferring:
            deferred.append(signum)
        else:
            signal_exit(signum, frame)

    # Files cannot fill a pipe or wait for descendant-held descriptors to close.
    # Both are unlinked/closed by this invocation, under its exact scratch root.
    with ExitStack() as resources:
        stdout = resources.enter_context(tempfile.TemporaryFile(dir=owned))
        stderr = resources.enter_context(tempfile.TemporaryFile(dir=owned))
        gate, gate_child = (resources.enter_context(s) for s in socket.socketpair())
        control, control_child = (resources.enter_context(s) for s in socket.socketpair())
        previous = {}
        process = None
        anchor = None
        try:
            for sig in CANCELLATION_SIGNALS:
                previous[sig] = signal.signal(sig, cancellation)
            try:
                # Gate exec until a sibling anchor joins the command's group.
                # A shared session is required by setpgid; neither child joins
                # the collector's own group. Every handle is assigned while
                # cancellation is deferred, and neither child is reaped early.
                process = subprocess.Popen(
                    [sys.executable, "-B", str(HELPER), "command", str(gate_child.fileno()), *command],
                    env=env, stdout=stdout, stderr=stderr, process_group=0, pass_fds=(gate_child.fileno(),))
                gate_child.close()
                wait_helper_ready(gate, (process,))
                anchor = subprocess.Popen(
                    [sys.executable, "-B", str(HELPER), "anchor", str(control_child.fileno())],
                    env=env, stdout=stdout, stderr=stderr, process_group=process.pid,
                    pass_fds=(control_child.fileno(),))
                control_child.close()
                wait_helper_ready(control, (process, anchor))
                deferring = False
                if deferred:
                    signal_exit(deferred[0], None)
                gate.sendall(b"G")
                gate.close()
                if cancel is not None:
                    deadline = time.monotonic() + 15
                    while not ready.exists():
                        require_live_anchor(anchor)
                        if retained_status(process) is not None or time.monotonic() >= deadline:
                            raise AssertionError("synthetic cancellation seam not reached")
                        time.sleep(0.02)
                    require_live_anchor(anchor)
                    signal_retained_group(process, cancel)
                deadline = time.monotonic() + timeout
                while True:
                    require_live_anchor(anchor)
                    status = retained_status(process)
                    if status is not None:
                        break
                    if time.monotonic() >= deadline:
                        raise subprocess.TimeoutExpired(command, timeout)
                    time.sleep(0.02)
            finally:
                deferring = True
                if process is not None:
                    # The final group signal precedes BOTH direct-child reaps.
                    # Signal errors still fail; each proved child gets a wait,
                    # even when ownership of the other child was lost.
                    propagating = sys.exc_info()[0] is not None
                    try:
                        cleanup_retained_group(process, anchor, control)
                    except BaseException as error:
                        _synthetic_cleanup_safe = False
                        if not propagating:
                            raise
                        print(f"Synthetic process cleanup also failed: {error}", file=sys.stderr)
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
        if deferred:
            signal_exit(deferred[0], None)
        stdout.seek(0)
        stderr.seek(0)
        return status, stdout.read(), stderr.read()


def collect_nested_process(command, env, owned, receipt, token, ready=None, cancel=None, timeout=20):
    global _synthetic_cleanup_safe
    previous_safe = _synthetic_cleanup_safe
    # The outer group's reap says nothing about children that started separate sessions.
    # Keep the tree on every exceptional path until the nested runner proves its own drain.
    _synthetic_cleanup_safe = False
    result = collect_owned_process(command, env, owned, ready, cancel, timeout)
    status, stdout, stderr = result
    try:
        proof = json.loads(receipt.read_text())
        if proof != {"token": token, "returncode": status, "drained": True}:
            raise ValueError("nested drain receipt does not match this invocation")
    except (OSError, ValueError) as error:
        print(f"Nested process drain unproved; preserving {owned}: {error}", file=sys.stderr)
        if status:
            raise SystemExit(status if status > 0 else 128 - status) from error
        raise RuntimeError("Nested process drain unproved") from error
    _synthetic_cleanup_safe = previous_safe
    return result


def nested_runner_main(arguments):
    runner_path, receipt, token, *runner_arguments = arguments
    spec = importlib.util.spec_from_file_location("fixture_nested_runner", runner_path)
    runner = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = runner
    spec.loader.exec_module(runner)
    sys.argv = [runner_path, *runner_arguments]
    result = runner.main()
    # main returns only after its command drain/parent-cleanup paths. An unproved
    # drain suppresses this receipt even when the original failure status survives.
    if runner._scratch_cleanup_safe:
        with Path(receipt).open("x") as output:
            json.dump({"token": token, "returncode": result, "drained": True}, output)
    return result


def executable(path, body):
    path.write_text(body)
    path.chmod(0o700)



def runner_lifecycle_cases(owned, workspace, caller):
    global _synthetic_cleanup_safe
    runner_path = workspace / "Scripts/ci_swift_test_by_suite.py"
    spec = importlib.util.spec_from_file_location("fixture_scratch_runner", runner_path)
    runner = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = runner
    spec.loader.exec_module(runner)
    ready = owned / "runner-ready"
    record = owned / "runner-parent"
    child_pid = owned / "runner-child-pid"
    fake = owned / "synthetic-swift.py"
    fake.write_text("""import os, pathlib, sys, time
parent = pathlib.Path(os.environ['CODEXBAR_TEST_SCRATCH_PARENT'])
workspace = pathlib.Path(os.environ['CODEXBAR_TEST_WORKSPACE_ROOT'])
assert workspace in parent.parents and parent.is_dir()
pathlib.Path(os.environ['RUNNER_RECORD']).write_text(str(parent))
pathlib.Path(os.environ['RUNNER_PID']).write_text(str(os.getpid()))
(parent / 'runner-marker').write_text('synthetic fixture')
mode = os.environ['RUNNER_MODE']
args = sys.argv[1:]
stage = 'discovery' if args == ['test', 'list'] else 'metadata' if args == ['build', '--show-bin-path'] else 'group'
if mode == stage + '-cancel':
    pathlib.Path(os.environ['RUNNER_READY']).touch()
    time.sleep(12)
    sys.exit(91)
if mode == stage + '-failure':
    sys.exit(37)
if stage == 'discovery':
    if mode.startswith('metadata-'):
        print('Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle', file=sys.stderr)
        print('PackageFrameworks/Sparkle.framework', file=sys.stderr)
        sys.exit(29)
    print('CodexBarTests.Synthetic/test_fixture()')
""")
    count = 0
    for supplied in (False, True):
        for mode, expected, cancellation in (
                ("success", 0, None), ("discovery-failure", 37, None), ("group-failure", 37, None),
                ("metadata-failure", 29, None),
                *((stage + "-cancel", 128 + sig, sig)
                  for stage in ("discovery", "metadata", "group") for sig in CANCELLATION_SIGNALS)):
            ready.unlink(missing_ok=True)
            record.unlink(missing_ok=True)
            child_pid.unlink(missing_ok=True)
            env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(owned / "synthetic-home"),
                   "RUNNER_RECORD": str(record), "RUNNER_READY": str(ready), "RUNNER_MODE": mode,
                   "RUNNER_PID": str(child_pid),
                   "PYTHONDONTWRITEBYTECODE": "1"}
            if supplied:
                env[KEY] = str(caller)
            token = str(time.monotonic_ns())
            receipt = owned / ("runner-drained-" + token + ".json")
            status, stdout, stderr = collect_nested_process(
                [sys.executable, "-B", str(Path(__file__).resolve()), "--nested-runner",
                 str(runner_path), str(receipt), token, "--no-retry-non-timeout-failures",
                 "--swift-command", sys.executable, "--swift-command-arg=" + str(fake)],
                env, owned, receipt, token, ready, cancellation)
            if b"Preserving" in stderr or b"Cleanup also failed" in stderr:
                _synthetic_cleanup_safe = False
            if child_pid.exists():
                observed = runner.test_process(int(child_pid.read_text()))
                if observed is not None and not observed.zombie:
                    _synthetic_cleanup_safe = False
                    raise AssertionError("Synthetic runner child still present after runner exit; preserve evidence")
            assert status == expected, (mode, status, stdout.decode(), stderr.decode())
            actual_parent = Path(record.read_text())
            if supplied:
                assert actual_parent == caller and caller.is_dir()
                assert (caller / "runner-marker").read_text() == "synthetic fixture"
                (caller / "runner-marker").unlink()
                assert (caller / "sibling").read_text() == "preserve sibling"
            else:
                if actual_parent.exists():
                    _synthetic_cleanup_safe = False
                assert actual_parent.parent == workspace and not actual_parent.exists()
                assert b"removed and absence verified" in stdout
            count += 1

    for invalid in ("", ".", str(workspace), str(caller / "missing"), str(caller / "sibling"),
                    str(workspace / "inside-link"), str(workspace / "outside-link")):
        before = set(workspace.iterdir())
        with patch.dict(os.environ, {KEY: invalid}, clear=True), patch.object(runner, "run_suites") as suites:
            assert runner.main() == 1
            suites.assert_not_called()
        assert set(workspace.iterdir()) == before
        count += 1

    # No processes exist in these fault-injection cases. Preserve the parent when drain proof is absent.
    for original_status in (0, 37):
        captured = []
        def unproved():
            captured.append(Path(os.environ[KEY]))
            runner._scratch_cleanup_safe = False
            return original_status
        with patch.dict(os.environ, {}, clear=True), patch.object(runner, "run_suites", unproved):
            assert runner.main() == (original_status or 1)
        assert captured[0].is_dir()
        shutil.rmtree(captured[0])
        count += 1

    # Cleanup failure must not replace an original command failure or turn success into a pass.
    for original_status in (0, 37):
        captured = []
        def complete():
            captured.append(Path(os.environ[KEY]))
            return original_status
        with patch.dict(os.environ, {}, clear=True), patch.object(runner, "run_suites", complete), \
                patch.object(runner.shutil, "rmtree", side_effect=OSError("synthetic cleanup failure")):
            assert runner.main() == (original_status or 1)
        assert captured[0].is_dir()
        shutil.rmtree(captured[0])
        count += 1

    with patch.dict(os.environ, {}, clear=True):
        runner._scratch_cleanup_safe = True
        first = runner.FixtureScratchParent()
        second = runner.FixtureScratchParent()
        first.prepare()
        os.environ.pop(KEY)
        second.prepare()
        assert first.path != second.path
        first.cleanup()
        assert not first.path.exists() and second.path.is_dir()
        second.cleanup()
        assert not second.path.exists()
        count += 1
    return count


def nested_cleanup_observer():
    spec = importlib.util.spec_from_file_location("fixture_nested_observer", ROOT / "Scripts/ci_swift_test_by_suite.py")
    runner = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = runner
    spec.loader.exec_module(runner)
    return runner


def nested_cleanup_child(case, owned):
    observer = nested_cleanup_observer()
    identity = observer.test_process(os.getpid())
    if identity is None:
        raise RuntimeError("Cannot capture synthetic child birth")
    (owned / "live-child-fixture").write_text("preserve while this session is live")
    (case / "child-identity.json").write_text(json.dumps({"pid": identity.pid, "birth": identity.birth}))
    (case / "child-ready").touch()
    deadline = time.monotonic() + 15
    while not (case / "stop-child").exists() and time.monotonic() < deadline:
        time.sleep(0.05)


def nested_cleanup_fixture(case):
    with owned_regression_directory(case) as name:
        owned = Path(name)
        (case / "owned-path").write_text(str(owned))
        command = [sys.executable, "-B", str(Path(__file__).resolve()),
                   "--nested-cleanup-command", str(case), str(owned)]
        original_drain = cleanup_retained_group

        def record_outer_drain(*arguments):
            original_drain(*arguments)
            (case / "outer-drained").touch()

        with patch(__name__ + ".cleanup_retained_group", side_effect=record_outer_drain):
            collect_nested_process(command, dict(os.environ), owned, owned / "no-drain-receipt", "cancellation-fixture")


def nested_cleanup_regressions(parent):
    global _synthetic_cleanup_safe
    require_wait_ownership()
    if (not parent.is_absolute() or parent.resolve(strict=True) != parent or not parent.is_dir()
            or ROOT not in parent.parents):
        raise ValueError("Nested cleanup regressions require an existing canonical workspace child")
    observer = nested_cleanup_observer()
    count = 0
    for cancellation in CANCELLATION_SIGNALS:
        previous_safe = _synthetic_cleanup_safe
        with owned_regression_directory(parent) as name:
            case = Path(name)
            worker = None
            identity = None
            _synthetic_cleanup_safe = False
            try:
                worker = subprocess.Popen(
                    [sys.executable, "-B", str(Path(__file__).resolve()), "--nested-cleanup-fixture", str(case)],
                    start_new_session=True)
                deadline = time.monotonic() + 5
                while not (case / "child-ready").exists():
                    if retained_status(worker) is not None or time.monotonic() >= deadline:
                        raise AssertionError("Nested cancellation fixture did not become ready")
                    time.sleep(0.02)
                identity = json.loads((case / "child-identity.json").read_text())
                child = observer.test_process(identity["pid"])
                assert child is not None and not child.zombie and list(child.birth) == identity["birth"]
                assert child.session == child.pid and child.session != worker.pid
                # Signal only our direct, unreaped harness. Its separate-session child stays live.
                assert retained_status(worker) is None
                os.kill(worker.pid, cancellation)
                assert worker.wait(timeout=7) == 128 + cancellation
                owned = Path((case / "owned-path").read_text())
                child = observer.test_process(identity["pid"])
                assert child is not None and not child.zombie and list(child.birth) == identity["birth"]
                assert owned.is_dir(), "harness cancellation removed a tree with a live separate-session child"
                assert (owned / "live-child-fixture").read_text() == "preserve while this session is live"
                count += 1
            finally:
                propagating = sys.exc_info()[0] is not None
                try:
                    # The private stop file and 15-second self-expiry require no descendant signal authority.
                    (case / "stop-child").touch()
                    if worker is not None and worker.returncode is None:
                        if retained_status(worker) is None:
                            os.kill(worker.pid, signal.SIGTERM)
                        worker.wait(timeout=7)
                    if not (case / "outer-drained").is_file():
                        raise RuntimeError("Outer collector drain unavailable; preserve regression tree")
                    if identity is None:
                        raise RuntimeError("Nested child identity unavailable; preserve regression tree")
                    deadline = time.monotonic() + 17
                    while True:
                        child = observer.test_process(identity["pid"])
                        if child is None or child.zombie or list(child.birth) != identity["birth"]:
                            break
                        if time.monotonic() >= deadline:
                            raise RuntimeError("Nested fixture child did not exit; preserve regression tree")
                        time.sleep(0.05)
                    _synthetic_cleanup_safe = previous_safe
                except BaseException as error:
                    if not propagating:
                        raise
                    print(f"Nested cancellation regression cleanup also failed: {error}", file=sys.stderr)
        assert not case.exists()

    # A collector exception must retain its exact original outcome with cleanup still denied.
    with owned_regression_directory(parent) as name:
        owned = Path(name)
        for original in (subprocess.TimeoutExpired("synthetic", 1), RuntimeError("synthetic collector failure")):
            previous_safe = _synthetic_cleanup_safe
            try:
                with patch(__name__ + ".collect_owned_process", side_effect=original):
                    collect_nested_process([], {}, owned, owned / "missing-receipt", "exception-fixture")
            except BaseException as error:
                assert error is original
                assert not _synthetic_cleanup_safe
            else:
                raise AssertionError("Collector exception was lost")
            # No child was launched by this injected collector.
            _synthetic_cleanup_safe = previous_safe
            count += 1
        receipt = owned / "drain-receipt.json"
        receipt.write_text(json.dumps({"token": "completed-fixture", "returncode": 37, "drained": True}))
        with patch(__name__ + ".collect_owned_process", return_value=(37, b"", b"")):
            assert collect_nested_process([], {}, owned, receipt, "completed-fixture")[0] == 37
        assert _synthetic_cleanup_safe
        count += 1
        for status in (0, 37):
            previous_safe = _synthetic_cleanup_safe
            try:
                with patch(__name__ + ".collect_owned_process", return_value=(status, b"", b"")):
                    collect_nested_process([], {}, owned, receipt, "mismatched-fixture")
            except SystemExit as error:
                assert status == 37 and error.code == 37
            except RuntimeError:
                assert status == 0
            else:
                raise AssertionError("Mismatched nested drain receipt was accepted")
            assert not _synthetic_cleanup_safe
            # The mocked collector created no process; retain no synthetic unknown after this assertion.
            _synthetic_cleanup_safe = previous_safe
            count += 1
    return count


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 Scripts/test_fixture_scratch_parent.py OWNED_WORKSPACE_PARENT")
    require_wait_ownership()
    parent = Path(sys.argv[1])
    if (not parent.is_absolute() or ".." in parent.parts
            or parent.resolve(strict=True) != parent or not parent.is_dir()
            or parent == ROOT or ROOT not in parent.parents):
        sys.exit("Expected an existing canonical directory strictly inside the workspace")
    baseline = subprocess.check_output([
        "git", "-C", str(ROOT), "show",
        "0f842d7f26edcd1a1fff886409291ef9b4f846b6:Scripts/package_app.sh"], text=True)
    with owned_regression_directory(parent) as name:
        owned = Path(name)
        workspace = owned / "workspace"
        workspace.mkdir()
        for relative in (
                f"Scripts/{IDENTITY}", f"Scripts/{PROVIDER}", f"Scripts/{CODEX}", "Scripts/package_app.sh",
                "Scripts/ci_swift_test_by_suite.py", "Scripts/test.sh",
                "Scripts/sign-and-notarize.sh", ".mac-release.jones.env.example",
                "WidgetExtension/Info.plist",
                "WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.pbxproj"):
            target = workspace / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for relative in (
                "Sources/CodexBarCore/JonesStateRoot.swift",
                "Sources/CodexBarCore/ProviderSessionStoreFile.swift",
                "Sources/CodexBarCore/KeychainSecurity.swift",
                "Sources/CodexBarCore/TestProcessSafety.swift",
                "Sources/CodexBarCore/TestFixtureScratch.swift",
                "Sources/CodexBarCore/CodexCredentialFileAccess.swift",
                "Sources/CodexBarCore/CodexPriorityDatabasePath.swift",
                "Sources/CodexBarCore/CodexHomeScope.swift",
                "Scripts/fixtures/provider_session_file_proof.swift"):
            target = workspace / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("// Synthetic compiler input; never compiled.\n")

        caller = workspace / "caller parent with spaces"
        caller.mkdir()
        sibling = caller / "sibling"
        sibling.write_text("preserve sibling")
        outside = owned / "outside"
        outside.mkdir()
        (outside / "sentinel").write_text("preserve outside")
        (workspace / "inside-link").symlink_to(caller, target_is_directory=True)
        (workspace / "outside-link").symlink_to(outside, target_is_directory=True)
        (workspace / "broken-link").symlink_to(owned / "missing", target_is_directory=True)
        identity_tools = owned / "identity-tools"
        provider_tools = owned / "provider-tools"
        identity_tools.mkdir()
        provider_tools.mkdir()
        for directory in (identity_tools, provider_tools):
            for tool in ("bash", "python3", "dirname", "mktemp", "rm", "cat"):
                target = shutil.which(tool)
                assert target, tool + " unavailable"
                (directory / tool).symlink_to(target)
        baseline_file = owned / "baseline"
        baseline_file.write_text(baseline)
        record = owned / "record"
        ready = owned / "ready"
        # Identity's own three compiler stubs remain unmodified. This git stub
        # supplies only pinned public source and the final synthetic ignore check.
        executable(identity_tools / "git", """#!/usr/bin/env python3
import os, pathlib, sys, time
if sys.argv[3] == 'show':
    sys.stdout.write(pathlib.Path(os.environ['BASELINE']).read_text())
elif sys.argv[3] == 'check-ignore':
    if os.environ['MODE'] == 'failure':
        sys.exit(53)
    if os.environ['MODE'] == 'cancel':
        pathlib.Path(os.environ['READY']).touch()
        while True:
            time.sleep(0.02)
else:
    sys.exit('Unexpected git command')
""")
        executable(provider_tools / "swiftc", """#!/usr/bin/env python3
import os, pathlib, sys, time
args = sys.argv[1:]
assert '-O' in args and '-parse-as-library' in args
assert args.count('-package-name') == 1 and args[args.index('-package-name') + 1] == 'CodexBar'
sources = [pathlib.Path(arg) for arg in args if arg.endswith('.swift')]
assert all(path.is_file() for path in sources)
expected = {'KeychainSecurity.swift', 'TestProcessSafety.swift', 'TestFixtureScratch.swift'}
if os.environ['FIXTURE_SCRIPT'] == 'test_codex_file_isolation_child.sh':
    expected |= {'CodexCredentialFileAccess.swift', 'CodexPriorityDatabasePath.swift', 'CodexHomeScope.swift', 'Proof.swift'}
else:
    expected |= {'JonesStateRoot.swift', 'ProviderSessionStoreFile.swift', 'provider_session_file_proof.swift'}
assert {path.name for path in sources} == expected, 'standalone compile source dependency missing'
output = pathlib.Path(args[args.index('-o') + 1])
assert pathlib.Path(args[args.index('-module-cache-path') + 1]).parent == output.parent
assert output.parent == pathlib.Path(os.environ['TMPDIR'])
pathlib.Path(os.environ['RECORD']).write_text(str(output.parent))
if os.environ['MODE'] == 'compile-failure':
    sys.exit(37)
if os.environ['MODE'] == 'cancel':
    pathlib.Path(os.environ['READY']).touch()
    while True:
        time.sleep(0.02)
output.write_text('#!/usr/bin/env python3\\nimport os, sys\\nsys.exit(41 if os.environ["MODE"] == "child-failure" else 0)\\n')
output.chmod(0o700)
""")

        def clean():
            assert caller.is_dir() and sibling.read_text() == "preserve sibling"
            assert set(caller.iterdir()) == {sibling}, "caller child leaked"
            assert (outside / "sentinel").read_text() == "preserve outside"
            assert set(outside.iterdir()) == {outside / "sentinel"}
            assert not list(workspace.glob(".jones-identity-fixture-*")), "default identity root leaked"
            assert not list(workspace.glob(".provider-session-child.*")), "default provider root leaked"
            assert not list(workspace.glob(".codex-file-child.*")), "default Codex root leaked"

        def run(script, override, mode="success", expected=0, cancel=None):
            for path in (record, ready):
                path.unlink(missing_ok=True)
            env = {"PATH": str(identity_tools if script == IDENTITY else provider_tools),
                   "HOME": str(owned / "synthetic-home"), "TMPDIR": str(outside),
                   "BASELINE": str(baseline_file), "RECORD": str(record),
                   "READY": str(ready), "MODE": mode, "FIXTURE_SCRIPT": script}
            if override is not None:
                env[KEY] = override
            status, stdout, stderr = collect_owned_process(
                [str(identity_tools / "bash"), str(workspace / "Scripts" / script)],
                env, owned, ready, cancel)
            assert status == expected, (script, mode, status, stderr.decode())
            if expected == 0 and script == IDENTITY:
                assert b"UNAVAILABLE: native JonesStateRoot" in stdout
                assert b"30 checks passed" in stdout
            if record.exists():
                proof = Path(record.read_text())
                expected_parent = workspace if override is None else Path(override)
                assert proof.parent == expected_parent
                assert not proof.exists(), "owned provider child leaked"
            if override is not None and expected == 1 and mode == "success":
                assert b"Invalid CODEXBAR_TEST_SCRATCH_PARENT" in stderr, (override, stderr.decode())
                assert not record.exists(), "invalid parent reached compiler"
            clean()

        invalid = (
            "", ".", str(caller) + "\n", str(workspace), str(outside), str(workspace) + "-escape",
            str(caller / "missing"), str(sibling), str(workspace / "inside-link"),
            str(workspace / "inside-link" / "missing"), str(workspace / "outside-link"),
            str(workspace / "broken-link"), str(caller / ".." / "caller parent with spaces"),
            str(workspace / ".." / "outside"),
        )
        count = 0
        for script in (IDENTITY, PROVIDER, CODEX):
            for value in invalid:
                run(script, value, expected=1)
                count += 1
            for override in (None, str(caller)):
                run(script, override)
                count += 1
                failures = (("failure", 1),) if script == IDENTITY else (
                    ("compile-failure", 37), ("child-failure", 41))
                for mode, status in failures:
                    run(script, override, mode, status)
                    count += 1
                for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                    run(script, override, "cancel", 128 + sig, sig)
                    count += 1
        count += runner_lifecycle_cases(owned, workspace, caller)
        count += nested_cleanup_regressions(owned)
        print(f"Fixture scratch parent: {count} synthetic lifecycle cases passed; no native Swift proof")
    assert not owned.exists(), "regression root leaked"
    assert parent.is_dir(), "caller parent removed"


if __name__ == "__main__":
    for sig in CANCELLATION_SIGNALS:
        signal.signal(sig, signal_exit)
    if len(sys.argv) > 1 and sys.argv[1] == "--nested-runner":
        raise SystemExit(nested_runner_main(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "--nested-cleanup-fixture":
        nested_cleanup_fixture(Path(sys.argv[2]))
    elif len(sys.argv) > 1 and sys.argv[1] == "--nested-cleanup-command":
        child = subprocess.Popen(
            [sys.executable, "-B", str(Path(__file__).resolve()), "--nested-cleanup-child", *sys.argv[2:]],
            start_new_session=True)
        child.wait(timeout=20)
    elif len(sys.argv) > 1 and sys.argv[1] == "--nested-cleanup-child":
        nested_cleanup_child(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        main()
