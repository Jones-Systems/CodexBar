#!/usr/bin/env python3
"""Portable dispatch, complete assembly, metric and lifecycle contract fixtures.

No compiler, codesign stub, app launch or hosted build is used. Native tool doubles
only model strip/rpath/architecture/xattr/plist operations inside a tiny owned tree.
"""

from copy import deepcopy
import json
import os
from pathlib import Path
import plistlib
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import ci_cold_build_size as measure
from cold_build_size_adapter import Adapter, BASELINE, CANDIDATE, PACKAGE_HASHES, digest


REPO = Path(__file__).resolve().parent.parent


def historical(revision, path="Scripts/package_app.sh"):
    return subprocess.check_output(["git", "-C", str(REPO), "show", revision + ":" + path])


class ContainedFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cold-build-fixture-", dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.enterContext(patch.object(measure.processes, "_scratch_cleanup_safe", True))

    def write(self, path, data=b"fixture"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data.encode() if isinstance(data, str) else data)


class DispatchTests(unittest.TestCase):
    def context(self):
        head = "c" * 40
        inputs = dict(mode="cold-build-size", baseline_sha=BASELINE, candidate_sha=CANDIDATE,
                      harness_sha=head, expected_sha=head)
        environment = dict(GITHUB_ACTIONS="true", RUNNER_ENVIRONMENT="github-hosted", RUNNER_OS="macOS",
                           RUNNER_ARCH="ARM64", GITHUB_EVENT_NAME="workflow_dispatch",
                           GITHUB_REPOSITORY="Jones-Systems/CodexBar", GITHUB_REPOSITORY_ID="1425008735",
                           GITHUB_SHA=head, GITHUB_WORKFLOW_SHA=head, GITHUB_REF="refs/heads/work/measurement",
                           GITHUB_REF_TYPE="branch", GITHUB_RUN_ATTEMPT="1", GITHUB_RUN_ID="123",
                           ImageOS="macos26", ImageVersion="fixture-image",
                           GITHUB_WORKFLOW_REF=("Jones-Systems/CodexBar/.github/workflows/"
                                                "jones-menu-candidate.yml@refs/heads/work/measurement"))
        event = {"repository": {"full_name": "Jones-Systems/CodexBar", "id": 1425008735,
                                "default_branch": "main", "fork": False}, "inputs": deepcopy(inputs)}
        return environment, event, inputs, head

    def test_manual_exact_pair_and_harness_binding_rejects_drift_before_any_build(self):
        env, event, inputs, head = self.context()
        self.assertEqual(measure.validate_dispatch(env, event, inputs, head)["GITHUB_SHA"], head)
        for key, value in (("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_SHA", BASELINE),
                           ("GITHUB_WORKFLOW_SHA", BASELINE), ("GITHUB_RUN_ATTEMPT", "2"),
                           ("RUNNER_ENVIRONMENT", "self-hosted"), ("RUNNER_ARCH", "X64"),
                           ("GITHUB_REPOSITORY_ID", "1"), ("GITHUB_WORKFLOW_REF", "other@refs/heads/main")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                measure.validate_dispatch(dict(env, **{key: value}), event, inputs, head)
        for key in inputs:
            changed = dict(inputs, **{key: "d" * 40})
            with self.subTest(input=key), self.assertRaises(ValueError):
                measure.validate_dispatch(env, dict(event, inputs=changed), changed, head)
        with self.assertRaises(ValueError):
            measure.validate_dispatch(env, dict(event, inputs={}), inputs, head)

    def test_workflow_is_one_manual_slot_and_keeps_ordinary_candidate_steps(self):
        current = (REPO / ".github/workflows/jones-menu-candidate.yml").read_text()
        old = historical(CANDIDATE, ".github/workflows/jones-menu-candidate.yml").decode()
        normal = current.split("  package-jones-menu:\n", 1)[1].split("\n  cold-build-size:", 1)[0]
        old_normal = old.split("  package-jones-menu:\n", 1)[1]
        self.assertEqual(normal.replace("(github.event_name == 'workflow_dispatch' && inputs.mode == 'candidate')",
                                        "github.event_name == 'workflow_dispatch'").strip(), old_normal.strip())
        job = current.split("\n  cold-build-size:\n", 1)[1]
        for required in ("github.event_name == 'workflow_dispatch' && inputs.mode == 'cold-build-size'",
                         "runs-on: macos-26", "timeout-minutes: 180", "retention-days: 7",
                         "persist-credentials: false"):
            self.assertIn(required, job)
        for forbidden in ("actions/cache", "download-artifact", "matrix:", "schedule:", "GITHUB_SHA=",
                          "package_app.sh", "codesign ", "--export-build", "swift test", "retry:"):
            self.assertNotIn(forbidden, job)
        self.assertEqual(job.count("runs-on:"), 1)
        self.assertIn("options: [candidate, cold-build-size]", current)
        self.assertIn("default: candidate", current)


class AssemblyTests(ContainedFixture):
    def source(self, revision):
        source = self.root / ("sample-a" if revision == BASELINE else "sample-b")
        source.mkdir()
        self.write(source / ".gitignore", ".build/\n")
        for path in ("Scripts/package_app.sh", "Scripts/package_product_paths.sh",
                     "Scripts/sparkle_signing_paths.sh", "version.env"):
            self.write(source / path, historical(revision, path))
        self.write(source / "Sources/CodexBar/Resources/Icon-classic.icns", "classic-icon")
        self.write(source / "Sources/CodexBar/Resources/en.lproj/Localizable.strings", "app-resource")
        self.write(source / "Icon.icns", "main-icon")
        if revision == BASELINE:
            self.write(source / "Sources/CodexBarCore/Resources/payload.txt", "core-source")
        subprocess.run(["git", "init", "--quiet", "--initial-branch=fixture", str(source)], check=True)
        subprocess.run(["git", "-C", str(source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(source), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                        "commit", "--quiet", "-m", "Fixture"], check=True)
        return source

    def tools(self):
        tools = self.root / "tools"
        tools.mkdir(exist_ok=True)
        text = '''import json, os, pathlib, plistlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["FIXTURE_CALLS"], "a") as output: output.write(json.dumps([name, *args]) + "\\n")
if name == "lipo":
    assert args[0] == "-archs"; print("arm64")
elif name == "git":
    if args == ["rev-parse", "--short", "HEAD"]: print(os.environ["FIXTURE_REVISION"][:7])
    else: os.execv("/usr/bin/git", ["/usr/bin/git", *args])
elif name == "xcrun":
    assert args[:2] == ["strip", "-x"]
    path = pathlib.Path(args[2]); path.write_bytes(path.read_bytes().replace(b"|symbols", b""))
elif name == "install_name_tool":
    assert args[:2] == ["-add_rpath", "@executable_path/../Frameworks"]
elif name == "xattr":
    assert args[0] == "-cr"
elif name == "PlistBuddy":
    assert args[0] == "-c"
    op, key, kind, value = args[1].split(" ", 3); assert op == "Add" and kind == "string"
    path = pathlib.Path(args[2]); data = plistlib.loads(path.read_bytes()); assert key[1:] not in data
    data[key[1:]] = value; path.write_bytes(plistlib.dumps(data))
else: raise AssertionError(name)
'''
        for name in ("lipo", "git", "xcrun", "install_name_tool", "xattr", "PlistBuddy"):
            path = tools / name
            self.write(path, "#!" + sys.executable + "\n" + text)
            path.chmod(0o755)
        return tools

    def assemble(self, revision):
        source = self.source(revision)
        owned, state = measure.phase_state(source)
        self.addCleanup(lambda: owned.cleanup(True) if owned.path.exists() else None)
        products = source / ".build/release"
        for name in ("CodexBar", "CodexBarCLI", "CodexBarClaudeWatchdog"):
            self.write(products / name, "binary:" + name + "|symbols")
        self.write(products / "KeyboardShortcuts_KeyboardShortcuts.bundle"
                   / "Contents/Resources/en.lproj/Localizable.strings", "shortcut")
        # Candidate deliberately carries stale output: it must not become payload.
        self.write(products / "CodexBar_CodexBarCore.bundle/Contents/Resources/core.txt", "core-resource")
        framework = products / "Sparkle.framework"
        for part in ("Autoupdate", "Sparkle", "Updater.app/Contents/MacOS/Updater",
                     "XPCServices/Downloader.xpc/Contents/MacOS/Downloader",
                     "XPCServices/Installer.xpc/Contents/MacOS/Installer"):
            self.write(framework / "Versions/B" / part, "vendor-component")
        (framework / "Versions/Current").symlink_to("B")
        (framework / "Sparkle").symlink_to("Versions/Current/Sparkle")
        widget = state / "DerivedData/Build/Products/Release/CodexBarWidget.appex"
        self.write(widget / "Contents/MacOS/CodexBarWidget", "widget|symbols")
        self.write(widget / "Contents/Resources/widget.txt", "widget-resource")
        version = dict(line.split("=", 1) for line in (source / "version.env").read_text().splitlines() if "=" in line)
        self.write(widget / "Contents/Info.plist", plistlib.dumps({
            "CFBundleIdentifier": "com.jonessystems.codexbar.widget", "CodexBarTeamID": "JONESLOCAL",
            "CFBundleVersion": "1.99", "CFBundleShortVersionString": version["MARKETING_VERSION"]}))
        adapter = Adapter(source, revision)
        provenance = ("BUILD_NUMBER=1.99\nJONES_SOURCE_REVISION=" + revision
                      + "\nJONES_BUILD_ORIGIN=local\nJONES_BUILD_RUN=''\n"
                      "JONES_PROVENANCE_METADATA='<key>JonesSourceRevision</key><string>" + revision + "</string>"
                      "<key>JonesBuildOrigin</key><string>local</string><key>JonesBuildRun</key><string></string>'")
        script = adapter.assemble(products, widget, provenance)
        for forbidden in (r"^\s*codesign\s", r"^\s*resign\s", r"^\s*.*verify_packaged_app_launch.sh", r"^\s*open\s"):
            self.assertNotRegex(script, "(?m)" + forbidden)
        tools = self.tools()
        # Only the fixture changes the absolute native PlistBuddy path.
        fixture_script = script.replace("/usr/libexec/PlistBuddy", str(tools / "PlistBuddy"))
        script_path = state / "fixture-assembly.sh"
        self.write(script_path, fixture_script)
        env = dict(os.environ, ROOT=str(source), MEAS_STATE=str(state), MEAS_OVERLAY=str(state / "identity.env"),
                   FIXTURE_CALLS=str(self.root / "calls"), FIXTURE_REVISION=revision,
                   PATH=str(tools) + os.pathsep + os.environ["PATH"])
        result = subprocess.run(["bash", str(script_path)], cwd=source, env=env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(digest((source / "Scripts/package_app.sh").read_bytes()), PACKAGE_HASHES[revision])
        self.assertEqual(measure.git(source, "status", "--porcelain=v1", "--untracked-files=all"), "")
        app = source / ".build/package/CodexBar.app"
        return source, app, products, adapter, script

    def test_complete_historical_layouts_preserve_ordinary_source_and_strip_policy(self):
        for revision in (BASELINE, CANDIDATE):
            with self.subTest(revision=revision):
                source, app, products, adapter, script = self.assemble(revision)
                info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                widget_info = app / "Contents/PlugIns/CodexBarWidget.appex/Contents/Info.plist"
                widget = plistlib.loads(widget_info.read_bytes())
                self.assertEqual(info["CFBundleIdentifier"], "com.jonessystems.codexbar")
                self.assertEqual(info["JonesUpdateChannel"], "none")
                self.assertFalse(info["SUEnableAutomaticChecks"])
                self.assertEqual(widget["JonesSourceRevision"], revision)
                self.assertEqual(widget["JonesAppGroupID"], "JONESLOCAL.com.jonessystems.codexbar")
                for relative in ("Contents/Resources/Icon.icns", "Contents/Resources/Icon-classic.icns",
                                 "Contents/Resources/en.lproj/Localizable.strings",
                                 "Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle",
                                 "Contents/PlugIns/CodexBarWidget.appex/Contents/Resources/widget.txt",
                                 "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"):
                    self.assertTrue((app / relative).exists(), relative)
                core = revision == BASELINE
                self.assertEqual((app / "Contents/Resources/CodexBar_CodexBarCore.bundle").exists(), core)
                raw = {name: products / product for name, product in (
                    ("app", "CodexBar"), ("cli", "CodexBarCLI"), ("watchdog", "CodexBarClaudeWatchdog"))}
                inventory = measure.inventory(app, raw, revision)
                self.assertGreater(inventory["expanded_bundle"]["regular_file_bytes"],
                                   inventory["stripped_staged_products"]["app"]["bytes"])
                self.assertEqual(inventory["expanded_bundle"]["link_count"], 2)
                self.assertGreater(inventory["raw_release_products"]["cli"]["bytes"],
                                   inventory["stripped_staged_products"]["cli"]["bytes"])
                self.assertEqual(bool(inventory["standalone_cli_adjacent_core_payload"]["regular_file_bytes"]), core)
                self.assertFalse(adapter.receipt()["new_package_signature"])
                altered = plistlib.loads((app / "Contents/Info.plist").read_bytes())
                altered["SUEnableAutomaticChecks"] = True
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps(altered))
                with self.assertRaisesRegex(ValueError, "enabled an update path"):
                    measure.assembly_identity(app, revision)
                self.assertIn("widget-metadata", [block["name"] for block in adapter.receipt()["blocks"]])
                calls = [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]
                self.assertEqual(sum(call[:3] == ["xcrun", "strip", "-x"] for call in calls), 4)
                self.assertEqual(sum(call[0] == "install_name_tool" for call in calls), 1)
                (self.root / "calls").unlink()

    def test_adapter_refuses_unknown_or_modified_historical_script(self):
        source = self.source(BASELINE)
        with self.assertRaises(ValueError):
            Adapter(source, "a" * 40)
        with (source / "Scripts/package_app.sh").open("a") as out:
            out.write("\n")
        with self.assertRaises(ValueError):
            Adapter(source, BASELINE)

    def test_source_binding_rejects_wrong_head_and_tracked_changes(self):
        source = self.source(BASELINE)
        head = measure.git(source, "rev-parse", "HEAD")
        with patch.object(measure, "INPUT_FILES", ("Scripts/package_app.sh",)):
            self.assertEqual(measure.clean_source(source, head)["Scripts/package_app.sh"], PACKAGE_HASHES[BASELINE])
            with self.assertRaisesRegex(ValueError, "source revision differs"):
                measure.clean_source(source, CANDIDATE)
            with (source / "Scripts/package_app.sh").open("a") as out:
                out.write("\n")
            with self.assertRaisesRegex(ValueError, "dirty/untracked"):
                measure.clean_source(source, head)

    def test_locked_preparation_has_exact_patch_and_fresh_explicit_cache_options(self):
        source = self.source(BASELINE)
        adapter = Adapter(source, BASELINE)
        script = adapter.prepare()
        self.assertIn("swift package --jobs 2 --cache-path", script)
        self.assertIn("--config-path", script)
        self.assertIn("--security-path", script)
        self.assertIn("resolve --force-resolved-versions", script)
        self.assertIn("KeyboardShortcuts checkout does not match Package.resolved", script)
        self.assertIn("Package.resolved changed during dependency preparation", script)
        self.assertIn("keyboardShortcutsSafeBundle", script)
        self.assertNotIn("swift build", script)
        original = historical(BASELINE).decode()
        before = original[original.index("patch_keyboard_shortcuts() {"):original.index("KEYBOARD_SHORTCUTS_UTIL=")]
        self.assertIn(before, script)


class LifecycleAndMetricsTests(ContainedFixture):
    def test_independent_phase_state_refuses_preexisting_roots_and_removes_only_owned_tree(self):
        source = self.root / "source"
        source.mkdir()
        other = measure.OwnedDirectory(self.root / "other")
        owned, state = measure.phase_state(source)
        (state / "old-output").write_text("must not survive into the release phase")
        with self.assertRaises(ValueError):
            measure.phase_state(source)
        records = []
        measure.cleanup_owned(owned, records)
        self.assertTrue(records[0]["absence_verified"])
        self.assertTrue(other.path.exists())
        second, second_state = measure.phase_state(source)
        self.assertFalse((second_state / "old-output").exists())
        second.cleanup(True)
        other.cleanup(True)

    def test_unknown_drain_and_changed_identity_preserve_root_and_taint_parent_cleanup(self):
        owned = measure.OwnedDirectory(self.root / "owned")
        with self.assertRaises(ValueError):
            owned.cleanup(False)
        self.assertTrue(owned.path.exists())
        owned.identity = (-1, -1)
        with self.assertRaises(ValueError):
            measure.cleanup_owned(owned, [])
        self.assertFalse(measure.processes._scratch_cleanup_safe)
        self.assertTrue(owned.path.exists())

    def test_inventory_refuses_escaping_links_and_separates_link_bytes(self):
        app = self.root / "CodexBar.app"
        self.write(app / "Contents/file", "12345")
        (app / "alias").symlink_to("Contents/file")
        totals = measure.totals(measure.tree_manifest(app))
        self.assertEqual(totals, dict(regular_file_bytes=5, regular_file_count=1, link_count=1,
                                     link_payload_bytes=len("Contents/file")))
        (app / "escape").symlink_to("../outside")
        self.write(self.root / "outside")
        with self.assertRaises(ValueError):
            measure.tree_manifest(app)

    def test_fixed_commands_build_only_with_two_jobs_and_fresh_paths(self):
        state = self.root / "state"
        for command in (measure.debug_command(state), measure.release_command(state)):
            self.assertEqual(command[:5], ["bash", "Scripts/test.sh", "--command", "swift", "build"])
            self.assertEqual(command[command.index("--jobs") + 1], "2")
            for option in ("--cache-path", "--config-path", "--security-path"):
                self.assertIn(state, Path(command[command.index(option) + 1]).parents)
            self.assertNotIn("test", command)
            self.assertNotIn("--product", command)
        widget = measure.widget_command(self.root, state, "1.0", "1.2")
        self.assertEqual(widget[widget.index("-jobs") + 1], "2")
        self.assertIn("CODE_SIGNING_ALLOWED=NO", widget)
        self.assertIn("-disableAutomaticPackageResolution", widget)

    def test_command_timing_failure_and_log_budget_are_independent(self):
        state = self.root / "state"
        state.mkdir()
        evidence = measure.Evidence(self.root / "evidence")
        for status in (0, 23):
            records = []
            argv = [sys.executable, "-c", "import sys; print('Build complete! (1.25s)'); sys.exit(" + str(status) + ")"]
            ticks = iter((10, 1010))
            if status:
                with self.assertRaisesRegex(ValueError, "command failed"):
                    measure.command("failure", argv, state, evidence, records, clock=lambda: next(ticks))
            else:
                measure.command("success", argv, state, evidence, records, clock=lambda: next(ticks))
            self.assertEqual(records[0]["outer_wall_ns"], 1000)
            self.assertEqual(records[0]["swift_internal_build_seconds"], [1.25])
            self.assertEqual(records[0]["exit_code"], status)
            self.assertTrue(records[0]["process_drain_proved"])
        self.write(state / "large", b"x" * (measure.LOG_LIMIT + 7))
        log = evidence.log("bounded", state / "large")
        self.assertEqual(log["retained_bytes"], measure.LOG_LIMIT)
        self.assertTrue(log["tail_truncated"])
        small = measure.Evidence(self.root / "bounded-evidence")
        with patch.object(measure, "MAX_EVIDENCE", 1024**2 + 16):
            small.write("fits.log", b"x" * 16)
            with self.assertRaises(ValueError):
                small.write("over-limit.log", b"x")

    def test_failed_command_preserves_primary_status_and_cleans_its_phase(self):
        source = self.root / "source"
        source.mkdir()
        owned, state = measure.phase_state(source)
        evidence = measure.Evidence(self.root / "evidence")
        records, cleanup = [], []
        with self.assertRaisesRegex(ValueError, "command failed"):
            try:
                measure.command("failed", [sys.executable, "-c", "raise SystemExit(23)"],
                                state, evidence, records)
            finally:
                measure.cleanup_owned(owned, cleanup)
        self.assertEqual(records[0]["exit_code"], 23)
        self.assertTrue(cleanup[0]["absence_verified"])
        self.assertFalse(owned.path.exists())
        self.assertTrue((evidence.path / "failed.log").exists())

    def test_phase_environment_preserves_github_identity_and_removes_live_overrides(self):
        source = self.root / "source"
        source.mkdir()
        owned, state = measure.phase_state(source)
        before_home = os.environ.get("HOME")
        with patch.dict(os.environ, GITHUB_SHA="c" * 40, SWIFT_EXEC="untrusted-compiler",
                        CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS="1", CODEXBAR_TEST_CODEX_FILE_FIXTURES="live",
                        GIT_DIR="unrelated-git-directory"):
            with measure.command_environment(source, state):
                self.assertEqual(os.environ["GITHUB_SHA"], "c" * 40)
                self.assertEqual(os.environ.get("HOME"), before_home)
                for key in ("GIT_DIR", "SWIFT_EXEC", "CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS",
                            "CODEXBAR_TEST_CODEX_FILE_FIXTURES"):
                    self.assertNotIn(key, os.environ)
                self.assertEqual(os.environ["CODEXBAR_TEST_PROFILE"], "normal")
                self.assertEqual(os.environ["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"], "1")
                self.assertEqual(os.environ["TMPDIR"], str(state / "tmp"))
        owned.cleanup(True)

    def test_allocation_registers_owned_identity_before_handled_cancellation(self):
        previous = signal.signal(signal.SIGTERM, measure.cancel)
        owned = None
        try:
            with self.assertRaises(SystemExit) as raised:
                with measure.defer_cancellation():
                    owned = measure.OwnedDirectory(self.root / "registered")
                    os.kill(os.getpid(), signal.SIGTERM)
                    self.assertTrue(owned.path.exists())
            self.assertEqual(raised.exception.code, 143)
            self.assertIsNotNone(owned)
        finally:
            if owned is not None:
                owned.cleanup(True)
            signal.signal(signal.SIGTERM, previous)
        self.assertFalse((self.root / "registered").exists())

    def test_thin_and_universal_signature_presence_is_observation_without_codesign(self):
        blob = struct.pack(">IIIII", 0xFADE0CC0, 36, 1, 0, 20) + struct.pack(">IIII", 0xFADE0C02, 16, 0, 2)
        thin = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 1, 16, 0, 0)
        thin += struct.pack("<IIII", 0x1D, 16, 48, len(blob)) + blob
        self.write(self.root / "thin", thin)
        self.assertTrue(measure.signature_record(self.root / "thin")["adhoc_flag"])
        universal = struct.pack(">IIIIIII", 0xCAFEBABE, 1, 0x0100000C, 0, 32, len(thin), 0) + b"\0" * 4 + thin
        self.write(self.root / "fat", universal)
        result = measure.signature_record(self.root / "fat")
        self.assertTrue(result["slices"][0]["signature"]["adhoc_flag"])
        self.assertEqual(result["verification"], "not performed")

    def test_handled_cancellation_drains_child_and_removes_exact_owned_output(self):
        helper = self.root / "helper.py"
        ready = self.root / "ready"
        owned_path = self.root / "owned"
        self.write(helper, '''import os, pathlib, signal, sys
sys.path.insert(0, sys.argv[1])
import ci_cold_build_size as m
base = pathlib.Path(sys.argv[2]); owned = m.OwnedDirectory(base / "owned")
evidence = m.Evidence(base / "evidence")
signal.signal(signal.SIGTERM, m.cancel)
try:
    child = "import pathlib,time; pathlib.Path(" + repr(str(base / "ready")) + ").touch(); time.sleep(60)"
    m.command("cancel", [sys.executable, "-c", child], owned.path, evidence, [])
finally:
    owned.cleanup(m.processes._scratch_cleanup_safe)
''')
        process = subprocess.Popen([sys.executable, str(helper), str(REPO / "Scripts"), str(self.root)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not ready.exists() and time.monotonic() < deadline and process.poll() is None:
                time.sleep(0.02)
            self.assertTrue(ready.exists())
            process.send_signal(signal.SIGTERM)
            _, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 143, stderr.decode())
            self.assertFalse(owned_path.exists())
            self.assertTrue((self.root / "evidence/cancel.log").exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
