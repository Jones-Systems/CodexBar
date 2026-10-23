#!/usr/bin/env python3
"""Exercise package preparation and widget deadlines using only owned synthetic fixtures."""

from contextlib import contextmanager, redirect_stderr
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import package_widget as widget
import test_swift_test_process_cleanup as processes


ROOT = Path(__file__).resolve().parent.parent
PACKAGE_SOURCE = (ROOT / "Scripts/package_app.sh").read_text()
UTILITY = ('extension String {\n'
           '    var localized: String { NSLocalizedString(self, bundle: .module, comment: self) }\n'
           '}\n\n\nextension Data {\n}\n')
REVISION = "a" * 40


class DependencyPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="codexbar-package-build-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Scripts").mkdir()
        (self.root / "tools").mkdir()
        self.utility = self.root / ".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
        (self.root / "Package.resolved").write_text(json.dumps({
            "pins": [{"identity": "keyboardshortcuts", "state": {"revision": REVISION}}]}))
        (self.root / "utility-source").write_text(UTILITY)
        (self.root / "Scripts/build_jobs.py").write_text('''
import json, os, sys
from pathlib import Path
root = Path(os.environ["ROOT"])
args = sys.argv[1:]
with (root / "calls").open("a") as out:
    out.write(json.dumps(args) + "\\n")
utility = root / ".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
mode = os.environ.get("FIXTURE_MODE", "success")
if args == ["--", "swift", "package", "resolve", "--force-resolved-versions"]:
    if mode == "resolver-failure":
        sys.exit(31)
    if mode == "missing-checkout":
        sys.exit(0)
    utility.parent.mkdir(parents=True, exist_ok=True)
    utility.write_text((root / "utility-source").read_text())
    if mode == "changed-pins":
        with (root / "Package.resolved").open("a") as out:
            out.write(" ")
else:
    assert args[:5] == ["--", "swift", "build", "-c", "release"], args
    assert "bundle: .keyboardShortcutsSafeBundle" in utility.read_text()
''')
        git = self.root / "tools/git"
        git.write_text('#!/bin/sh\nprintf "%s\\n" "$FIXTURE_REVISION"\n')
        git.chmod(0o755)

    def prepare(self, mode="success", revision=REVISION):
        start = PACKAGE_SOURCE.index("patch_keyboard_shortcuts() {")
        end = PACKAGE_SOURCE.index("# Resolve SwiftPM's current output path", start)
        loop = PACKAGE_SOURCE.index('for ARCH in "${ARCH_LIST[@]}"; do', end)
        loop_end = PACKAGE_SOURCE.index('\nAPP_FINAL=', loop)
        script = ('set -euo pipefail\nCONF=release\nARCH_LIST=(arm64 x86_64)\n' +
                  PACKAGE_SOURCE[start:end] + '\nstage_build_products() { :; }\n' +
                  PACKAGE_SOURCE[loop:loop_end])
        environment = dict(os.environ, ROOT=str(self.root), FIXTURE_MODE=mode, FIXTURE_REVISION=revision,
                           PATH=str(self.root / "tools") + os.pathsep + os.environ["PATH"])
        return subprocess.run(["bash", "-c", script], env=environment,
                              capture_output=True, text=True, timeout=15)

    def calls(self):
        return [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]

    def test_cold_resolve_patches_before_exactly_two_product_builds(self):
        original_pins = (self.root / "Package.resolved").read_bytes()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            ["--", "swift", "package", "resolve", "--force-resolved-versions"],
            ["--", "swift", "build", "-c", "release", "--arch", "arm64"],
            ["--", "swift", "build", "-c", "release", "--arch", "x86_64"]])
        self.assertEqual((self.root / "Package.resolved").read_bytes(), original_pins)
        self.assertIn('"revision": "' + REVISION + '"', result.stdout)
        self.assertIn('"patched_source_sha256":', result.stdout)

    def test_warm_patch_is_idempotent_and_never_resolves_again(self):
        self.assertEqual(self.prepare().returncode, 0)
        patched = self.utility.read_bytes()
        (self.root / "calls").unlink()
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.utility.read_bytes(), patched)
        self.assertEqual(len(self.calls()), 2)
        self.assertTrue(all(call[2] == "build" for call in self.calls()))

    def test_resolver_failure_or_missing_checkout_prevents_product_builds(self):
        for mode, expected in (("resolver-failure", 31), ("missing-checkout", 1)):
            with self.subTest(mode=mode):
                if (self.root / "calls").exists():
                    (self.root / "calls").unlink()
                result = self.prepare(mode)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(len(self.calls()), 1)
                self.assertFalse(self.utility.exists())

    def test_patch_preimage_or_insertion_drift_prevents_product_builds(self):
        for source in (UTILITY.replace("bundle: .module", "bundle: .main"),
                       UTILITY.replace("extension Data", "extension Array")):
            with self.subTest(source=source):
                (self.root / "utility-source").write_text(source)
                if self.utility.exists():
                    self.utility.unlink()
                if (self.root / "calls").exists():
                    (self.root / "calls").unlink()
                result = self.prepare()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(self.calls()), 1)
                self.assertEqual(self.utility.read_text(), source)

    def test_changed_pins_or_wrong_checkout_prevents_product_builds(self):
        result = self.prepare("changed-pins")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Package.resolved changed", result.stderr)
        self.assertEqual(len(self.calls()), 1)
        (self.root / "calls").unlink()
        result = self.prepare(revision="b" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match Package.resolved", result.stderr)
        self.assertFalse((self.root / "calls").exists())


@contextmanager
def synthetic_admission(command, kind, *, cleanup_proved):
    if kind != "xcode":
        raise AssertionError("widget admission must request Xcode limits")
    yield command
    if not cleanup_proved():
        raise AssertionError("successful command left unknown cleanup")


class WidgetBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="codexbar-widget-build-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log = self.root / "xcodebuild.log"
        self.products = self.root / "Build"
        self.products.mkdir()
        self.stderr = io.StringIO()
        self.enterContext(redirect_stderr(self.stderr))
        self.enterContext(patch.object(widget.build_jobs, "admission", synthetic_admission))
        self.enterContext(patch.object(widget.runner, "_scratch_cleanup_safe", True))

    def run_widget(self, command, timeout=5):
        return widget.run(command, self.log, self.products, timeout, interval=0.05)

    def result(self):
        return json.loads(self.log.with_name("widget-build-result.json").read_text())

    def assert_stopped(self):
        self.assertFalse(self.log.with_name("widget-build-active").exists())
        self.assertFalse(any(thread.name == "widget-build-progress" for thread in threading.enumerate()))

    def test_success_and_failure_preserve_result_and_bounded_diagnostics(self):
        for status in (0, 23):
            with self.subTest(status=status):
                command = [sys.executable, "-c",
                           "import sys; print('x' * 100000); print('CompileSwift normal arm64'); "
                           f"sys.exit({status})"]
                self.assertEqual(self.run_widget(command), status)
                report = self.result()
                self.assertEqual(report["exit_code"], status)
                self.assertEqual(report["completed"], status == 0)
                self.assertTrue(report["cleanup_proved"])
                self.assertEqual(self.log.with_name("xcodebuild-tail.log").stat().st_size, widget.TAIL_BYTES)
                self.assertEqual(report["latest_progress"]["latest_observed_phase"], "CompileSwift normal arm64")
                self.assert_stopped()

    def contained_command(self, cancel=False):
        original_refresh = widget.runner.TestProcessOwnership.refresh
        sent = False
        def refresh(ownership, **kwargs):
            nonlocal sent
            owned = original_refresh(ownership, **kwargs)
            if processes.release_observed_fixture(self.root, owned) and cancel and not sent:
                sent = True
                os.kill(os.getpid(), signal.SIGTERM)
            return owned
        self.enterContext(patch.object(widget.runner.TestProcessOwnership, "refresh", refresh))
        return [sys.executable, str(Path(processes.__file__)), "--fixture", "timeout-session", str(self.root)]

    def assert_child_drained(self):
        identity = json.loads((self.root / "ready").read_text())
        current = widget.runner.test_process(identity["pid"])
        self.assertTrue(current is None or current.zombie or current.birth != tuple(identity["birth"]))
        self.assert_stopped()

    def test_execution_timeout_drains_descendants_before_releasing_marker(self):
        try:
            self.assertEqual(self.run_widget(self.contained_command(), timeout=2), 124)
            self.assertEqual(self.result()["exit_code"], 124)
            self.assert_child_drained()
        finally:
            (self.root / "stop").touch()

    def test_cancellation_drains_descendants_and_stops_progress_observer(self):
        try:
            with self.assertRaises(SystemExit) as caught:
                self.run_widget(self.contained_command(cancel=True))
            self.assertEqual(caught.exception.code, 143)
            self.assertEqual(self.result()["exit_code"], 143)
            self.assertFalse(self.result()["completed"])
            self.assert_child_drained()
        finally:
            (self.root / "stop").touch()

    def test_admission_failure_never_starts_a_command(self):
        with patch.object(widget.build_jobs, "admission", side_effect=widget.build_jobs.AdmissionError("held")), \
                patch.object(widget.runner, "_run_command") as command:
            with self.assertRaises(widget.build_jobs.AdmissionError):
                self.run_widget(["synthetic-unused"])
            command.assert_not_called()
        self.assert_stopped()

    def test_existing_execution_marker_is_preserved_without_starting(self):
        marker = self.log.with_name("widget-build-active")
        marker.write_text("Prior execution is unresolved.\n")
        with patch.object(widget.runner, "_run_command") as command:
            with self.assertRaises(FileExistsError):
                self.run_widget(["synthetic-unused"])
            command.assert_not_called()
        self.assertEqual(marker.read_text(), "Prior execution is unresolved.\n")

    def test_unproved_drain_retains_marker_and_reports_failure(self):
        def fail(*_args, **_kwargs):
            widget.runner._scratch_cleanup_safe = False
            raise widget.runner.CommandDrainError("synthetic unknown drain", 23)
        with patch.object(widget.runner, "_run_command", side_effect=fail):
            with self.assertRaises(widget.runner.CommandDrainError):
                self.run_widget(["synthetic-unused"])
        self.assertTrue(self.log.with_name("widget-build-active").exists())
        self.assertFalse(self.result()["cleanup_proved"])
        self.assertFalse(self.result()["completed"])
        self.assertEqual(self.result()["exit_code"], 23)

    def test_diagnostic_failure_preserves_command_failure_and_fails_success(self):
        for status in (23, 0):
            with self.subTest(status=status), patch.object(widget.runner, "_run_command", return_value=status), \
                    patch.object(Path, "write_bytes", side_effect=OSError("synthetic diagnostic failure")):
                if status == 0:
                    with self.assertRaises(OSError):
                        self.run_widget(["synthetic-unused"])
                else:
                    self.assertEqual(self.run_widget(["synthetic-unused"]), status)
                self.assert_stopped()

    def test_progress_distinguishes_output_growth_from_elapsed_time(self):
        self.log.write_text("CompileSwift normal arm64\n")
        (self.products / "core.o").write_bytes(b"object")
        events = io.StringIO()
        with patch.object(widget.time, "monotonic", side_effect=[0, 1, 31]):
            progress = widget.Progress(self.log, self.products, events)
            progress.sample()
            progress.sample()
        first, second = map(json.loads, events.getvalue().splitlines())
        self.assertGreater(first["log_growth_bytes"], 0)
        self.assertEqual(second["log_growth_bytes"], 0)
        self.assertEqual(second["seconds_since_output"], 30)
        self.assertEqual(second["compiler_outputs"]["files"], 1)
        self.assertEqual(second["compiler_outputs"]["bytes"], 6)

    def test_output_census_is_bounded_and_does_not_follow_symlinks(self):
        (self.products / "core.o").write_bytes(b"object")
        (self.root / "outside.o").write_bytes(b"outside")
        (self.products / "linked.o").symlink_to(self.root / "outside.o")
        (self.products / "loop").symlink_to(self.products, target_is_directory=True)
        self.assertEqual(widget.compiler_outputs(self.products)["files"], 1)
        self.assertFalse(widget.compiler_outputs(self.products, limit=1)["complete"])

    def test_invalid_execution_budgets_are_rejected(self):
        for value in ("0", "-1", "7201", "inf", "1.5", ""):
            with self.subTest(value=value), self.assertRaises(ValueError):
                widget.timeout_value(value)


if __name__ == "__main__":
    unittest.main()
