#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec python3 - "$ROOT_DIR" <<'PY'
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

workspace = Path(sys.argv[1])
script = workspace / "Scripts/verify_packaged_relocation.sh"
source = script.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
spec = importlib.util.spec_from_loader("relocation_proof", loader=None)
proof = importlib.util.module_from_spec(spec)
exec(compile(source, str(script), "exec"), proof.__dict__)
active_runs = []


class RelocationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="case-", dir=invocation_parent)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.parent = self.root / "runs"
        self.parent.mkdir()
        self.checkout = self.root / 'checkout with "quotes"'
        self.checkout.mkdir()
        (self.checkout / "AGENTS.md").write_text("checkout sentinel\n")
        self.resource_input = self.checkout / "Sources/CodexBarCore/Resources/fixture.js"
        self.resource_input.parent.mkdir(parents=True)
        self.resource_input.write_text("synthetic tracked resource\n")
        self.git("init", "--quiet")
        self.git("add", "--", "AGENTS.md", str(self.resource_input.relative_to(self.checkout)))
        self.commit_source()
        self.app = self.root / "Qualified.app"
        for relative in ("Contents/MacOS/CodexBar", "Contents/Helpers/CodexBarCLI"):
            path = self.app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic executable; never launch this file\n")
            path.chmod(0o700)
        for relative in ("Contents/Helpers", "Contents/Resources", "."):
            (self.app / relative / "CodexBar_CodexBarCore.bundle").mkdir(parents=True)
        with (self.app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CodexGitCommit": self.sha[:7], "CFBundleIdentifier": "test.synthetic"}, stream)
        self.arguments = ["--app", str(self.app), "--checkout", str(self.checkout),
                          "--scratch-parent", str(self.parent), "--qualified-source-commit", self.sha,
                          "--resource-entrypoints-reviewed"]
        self.phases = []
        self.cli_mode = False
        self.original_core_present = True

    def git(self, *arguments):
        return subprocess.run(["/usr/bin/git", "-C", str(self.checkout), "-c", "core.hooksPath=/dev/null",
                               "-c", "commit.gpgsign=false", "-c", "user.name=Synthetic fixture",
                               "-c", "user.email=fixture@example.invalid", *arguments],
                              env={"PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1",
                                   "GIT_CONFIG_GLOBAL": "/dev/null"},
                              check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def commit_source(self):
        self.git("commit", "--quiet", "-m", "synthetic source qualification")
        self.sha = self.git("rev-parse", "HEAD").strip()

    def slim_source(self):
        self.git("rm", "--quiet", "--cached", "--", str(self.resource_input.relative_to(self.checkout)))
        self.commit_source()
        self.arguments[self.arguments.index("--qualified-source-commit") + 1] = self.sha
        with (self.app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CodexGitCommit": self.sha[:7], "CFBundleIdentifier": "test.synthetic"}, stream)

    def cli_arguments(self, *, remove_bundles=True):
        self.slim_source()
        self.cli_mode = True
        self.arguments[-1:] = ["--mode", "cli-relocation", "--cli-entrypoints-reviewed"]
        if remove_bundles:
            for path in self.app.rglob("CodexBar_CodexBarCore.bundle"):
                shutil.rmtree(path)
            self.original_core_present = False

    def fake_command(self, run, name, argv, environment):
        self.phases.append(name)
        self.assertEqual(argv[0], "/usr/bin/sandbox-exec")
        self.assertIn("(deny default)", argv[2])
        self.assertIn('(allow file-read-data file-read-metadata (literal "/"))', argv[2])
        self.assertNotIn('(subpath "/")', argv[2])
        self.assertNotIn("(allow mach-lookup", argv[2])
        self.assertNotIn("(allow network", argv[2])
        self.assertNotIn("(allow process-fork", argv[2])
        self.assertIn(json.dumps(str(self.checkout)), argv[2])
        if self.cli_mode:
            self.assertNotIn("CODEXBAR_RESOURCE_SMOKE", environment)
            self.assertNotIn("CODEXBAR_PLUGIN_ENGINE", environment)
        else:
            self.assertEqual(environment["CODEXBAR_RESOURCE_SMOKE"], "1")
        self.assertEqual(environment["HOME"], str(run.root / "home"))
        self.assertNotIn("CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS", environment)
        if name == "read-control":
            return 0, "owned-read-control\n"
        if name == "checkout-denial":
            return 1, "cat: Operation not permitted\n"
        if self.cli_mode:
            self.assertIn(name, ("helper-help", "symlink-help"))
            self.assertEqual(argv[-1], "--help")
            self.assertEqual(Path(argv[3]).resolve(), run.root / "CodexBar.app/Contents/Helpers/CodexBarCLI")
            return 0, "synthetic CLI help\n"
        if name.startswith("missing-"):
            self.assertFalse(list((run.root / "CodexBar.app").rglob("CodexBar_CodexBarCore.bundle")))
            return 1, proof.MISSING + "\n"
        self.assertTrue((run.root / "CodexBar.app/Contents/Helpers/CodexBar_CodexBarCore.bundle").is_dir())
        return 0, proof.MARKER + "\n"

    def invoke(self, replacement=None, arguments=None):
        output = io.StringIO()
        original = Path.is_file

        def available(path):
            return True if str(path) == "/usr/bin/sandbox-exec" else original(path)

        callback = replacement or self.fake_command
        with mock.patch.object(proof.platform, "system", return_value="Darwin"), \
                mock.patch.object(Path, "is_file", available), \
                mock.patch.object(proof.Run, "command", lambda run, *args: callback(run, *args)), \
                contextlib.redirect_stdout(output):
            status = proof.main(self.arguments if arguments is None else arguments)
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        return status, events

    def assert_clean(self, events):
        roots = [Path(event["path"]) for event in events if event["event"] == "scratch"]
        self.assertTrue(roots)
        for root in roots:
            self.assertFalse(root.exists())
        self.assertTrue(any(event["event"] == "cleanup" and event["absent"] for event in events))
        self.assertEqual((self.app / "Contents/Helpers/CodexBar_CodexBarCore.bundle").is_dir(),
                         self.original_core_present)

    def test_resources_and_negative_controls_cleanup(self):
        status, events = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(self.phases, ["read-control", "checkout-denial", "helper", "symlink", "app-resource",
                                       "missing-helper", "missing-symlink", "missing-app"])
        self.assert_clean(events)

    def test_reviewed_cli_mode_only_runs_both_help_routes_and_reports_limits(self):
        self.cli_arguments()
        status, events = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(self.phases, ["read-control", "checkout-denial", "helper-help", "symlink-help"])
        identity = next(event for event in events if event["event"] == "identity")
        self.assertEqual(identity["mode"], "cli-relocation")
        self.assertIn("app resource proof unavailable", identity["proof"])
        outcome = next(event for event in events if event["event"] == "cli-relocation")
        self.assertEqual((outcome["app_resource_proof"], outcome["app_lifetime"]), ("unavailable", "not-tested"))
        self.assertFalse(any(event["event"] == "resources" for event in events))
        self.assert_clean(events)

    def test_cli_mode_uses_tracked_source_instead_of_stale_bundles(self):
        self.cli_arguments(remove_bundles=False)
        status, events = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(self.phases, ["read-control", "checkout-denial", "helper-help", "symlink-help"])
        self.assert_clean(events)

    def test_slim_source_cannot_run_resource_entrypoints(self):
        self.slim_source()
        status, events = self.invoke()
        self.assertEqual(status, 2)
        self.assertEqual(self.phases, [])
        self.assertTrue(any("App resource proof unavailable" in event.get("message", "") for event in events))
        self.assertFalse(any(event["event"] == "scratch" for event in events))

    def test_retained_resources_cannot_downgrade_to_cli_mode(self):
        arguments = self.arguments[:-1] + ["--mode", "cli-relocation", "--cli-entrypoints-reviewed"]
        status, events = self.invoke(arguments=arguments)
        self.assertEqual(status, 2)
        self.assertEqual(self.phases, [])
        self.assertFalse(any(event["event"] == "scratch" for event in events))

    def test_cli_mode_requires_its_own_review_before_allocation_or_execution(self):
        self.cli_arguments()
        for review in ([], ["--resource-entrypoints-reviewed"],
                       ["--cli-entrypoints-reviewed", "--resource-entrypoints-reviewed"]):
            with self.subTest(review=review):
                status, events = self.invoke(arguments=self.arguments[:-1] + review)
                self.assertEqual(status, 2)
                self.assertEqual(self.phases, [])
                self.assertFalse(any(event["event"] == "scratch" for event in events))

    def test_cli_failure_keeps_status_and_does_not_run_app_or_negative_controls(self):
        self.cli_arguments()
        for phase in ("helper-help", "symlink-help"):
            with self.subTest(phase=phase):
                self.phases = []
                def command(run, name, argv, environment):
                    return (17, "synthetic help failure") if name == phase else self.fake_command(run, name, argv, environment)
                status, events = self.invoke(command)
                self.assertEqual(status, 17)
                self.assertNotIn("app-resource", self.phases)
                self.assertFalse(any(event["event"] == "cli-relocation" for event in events))
                self.assert_clean(events)

    def test_checkout_identity_and_clean_tracked_source_required_before_execution(self):
        (self.checkout / "AGENTS.md").write_text("unreviewed tracked change\n")
        status, events = self.invoke()
        self.assertEqual(status, 2)
        self.assertEqual(self.phases, [])
        self.assertFalse(any(event["event"] == "scratch" for event in events))
        self.git("add", "--", "AGENTS.md")
        self.commit_source()
        status, events = self.invoke()
        self.assertEqual(status, 2)
        self.assertTrue(any("Checkout HEAD does not match" in event.get("message", "") for event in events))
        self.assertFalse(any(event["event"] == "scratch" for event in events))

    def test_cli_denial_control_cannot_be_an_arbitrary_error(self):
        self.cli_arguments()
        def command(run, name, argv, environment):
            return (1, "No such file") if name == "checkout-denial" else self.fake_command(run, name, argv, environment)
        status, events = self.invoke(command)
        self.assertEqual(status, 1)
        self.assertNotIn("helper-help", self.phases)
        self.assert_clean(events)

    def test_failure_preserves_status_and_diagnostics(self):
        def command(run, name, argv, environment):
            return (17, "deliberate failure") if name == "helper" else self.fake_command(run, name, argv, environment)
        status, events = self.invoke(command)
        self.assertEqual(status, 17)
        self.assertTrue(any(event["event"] == "failure" and "helper" in event["message"] for event in events))
        self.assert_clean(events)

    def test_arbitrary_failure_is_not_a_missing_bundle_pass(self):
        for result in ((1, "unrelated startup failure"), (-9, proof.MISSING), (0, proof.MARKER)):
            with self.subTest(result=result):
                def command(run, name, argv, environment):
                    return result if name == "missing-helper" else self.fake_command(run, name, argv, environment)
                status, events = self.invoke(command)
                self.assertEqual(status, 1)
                self.assert_clean(events)

    def test_denial_control_cannot_be_an_arbitrary_error(self):
        def command(run, name, argv, environment):
            return (1, "No such file") if name == "checkout-denial" else self.fake_command(run, name, argv, environment)
        status, events = self.invoke(command)
        self.assertEqual(status, 1)
        self.assertNotIn("helper", self.phases)
        self.assert_clean(events)

    def test_source_review_required_before_allocation_or_execution(self):
        status, events = self.invoke(arguments=self.arguments[:-1])
        self.assertEqual(status, 2)
        self.assertEqual(self.phases, [])
        self.assertFalse(any(event["event"] == "scratch" for event in events))

    def test_source_commit_mismatch_and_escaping_symlink_rejected(self):
        with (self.app / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump({"CodexGitCommit": "bbbbbbb"}, stream)
        status, _ = self.invoke()
        self.assertEqual(status, 2)
        (self.app / "escape").symlink_to(self.checkout)
        status, _ = self.invoke()
        self.assertEqual(status, 2)
        self.assertEqual(self.phases, [])

    def test_handled_signals_cleanup_and_preserve_cancellation(self):
        for number in proof.SIGNALS:
            with self.subTest(signal=number):
                def command(run, name, argv, environment):
                    os.kill(os.getpid(), number)
                    self.fail("Signal handler did not cancel")
                status, events = self.invoke(command)
                self.assertEqual(status, 128 + number)
                self.assert_clean(events)

    def test_independent_live_roots_and_cleanup_failure_status(self):
        other = proof.Run(self.parent)
        with contextlib.redirect_stdout(io.StringIO()):
            other.allocate()
        self.addCleanup(other.cleanup)
        sentinel = other.root / "sentinel"
        sentinel.write_text("preserve")
        status, events = self.invoke()
        self.assertEqual(status, 0)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assert_clean(events)
        real_remove = shutil.rmtree
        for primary in (0, 17):
            def refuse(path, *args, **kwargs):
                if Path(path).parent == self.parent and Path(path) != other.root:
                    raise OSError("synthetic cleanup refusal")
                return real_remove(path, *args, **kwargs)
            def command(run, name, argv, environment):
                if primary and name == "helper":
                    return primary, "deliberate failure"
                return self.fake_command(run, name, argv, environment)
            with mock.patch.object(proof.shutil, "rmtree", refuse):
                status, events = self.invoke(command)
            self.assertEqual(status, primary or 1)
            self.assertTrue(any(event["event"] == "cleanup-failure" for event in events))
            for event in events:
                if event["event"] == "scratch":
                    real_remove(event["path"])
            self.assertTrue(sentinel.exists())

    def test_cancellation_drains_running_child_and_preserves_its_output(self):
        real_command = proof.Run.command
        children = []
        def command(run, name, argv, environment):
            active_runs.append(run)
            try:
                return real_command(run, "signal-child", [sys.executable, "-c",
                    "import os, signal, time; print('child-ready', flush=True); "
                    "os.kill(os.getppid(), signal.SIGTERM); time.sleep(30)"], {"PATH": "/usr/bin:/bin"})
            finally:
                children.append(run.child)
        status, events = self.invoke(command)
        # main's cleanup has drained the direct child before deleting its root.
        active_runs[:] = [run for run in active_runs if run.child is not None]
        self.assertEqual(status, 143)
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].returncode)
        self.assertTrue(any(event["event"] == "phase" and "child-ready" in event["output"] for event in events))
        self.assert_clean(events)

    def test_owned_direct_child_timeout_drains_before_cleanup(self):
        run = proof.Run(self.parent)
        active_runs.append(run)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            run.allocate()
            # Exercise the real subprocess lifecycle without a bundle, sandbox or provider.
            try:
                status, text = run.command("synthetic-exit", [sys.executable, "-c", "print('child-output')"],
                                           {"PATH": "/usr/bin:/bin"})
                self.assertEqual((status, text.strip()), (0, "child-output"))
                run.started = time.monotonic() - 179.8
                with self.assertRaises(proof.Failure) as failure:
                    run.command("synthetic-timeout", [sys.executable, "-c", "import time; time.sleep(30)"],
                                {"PATH": "/usr/bin:/bin"})
                self.assertEqual(failure.exception.status, 124)
                child = run.child
                self.assertIsNotNone(child)
            finally:
                run.cleanup()
                active_runs.remove(run)
        self.assertIsNotNone(child.returncode)
        self.assertFalse(run.root.exists())
        self.assertIn("child-output", output.getvalue())


raw_parent = os.environ.get("CODEXBAR_TEST_SCRATCH_PARENT", str(workspace))
parent = proof.canonical_directory(raw_parent)
if parent != workspace and workspace not in parent.parents:
    sys.exit("Synthetic test scratch must be inside this worktree")
invocation_parent = None
old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, proof.SIGNALS)
try:
    invocation_parent = Path(tempfile.mkdtemp(prefix=".relocation-tests-", dir=parent))
    def cancel(number, frame):
        raise KeyboardInterrupt("test cancellation signal " + str(number))
    for number in proof.SIGNALS:
        signal.signal(number, cancel)
    signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
    unittest.main(argv=[sys.argv[0]], verbosity=2)
finally:
    for number in proof.SIGNALS:
        signal.signal(number, signal.SIG_IGN)
    signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)
    for run in active_runs:
        run.cleanup()
    if invocation_parent is not None:
        shutil.rmtree(invocation_parent)
        if invocation_parent.exists():
            raise RuntimeError("Synthetic suite scratch remains: " + str(invocation_parent))
PY
