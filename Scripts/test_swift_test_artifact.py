#!/usr/bin/env python3
"""Exercise the build handoff boundary with contained runtime trees and hostile archives."""

import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import ci_swift_test_artifact as artifact
import ci_swift_test_by_suite as runner


ROOT = Path(__file__).resolve().parent.parent
TEST_IDS = ["CodexBarTests.Alpha/test_one()", "CodexBarTests.Beta/test_two()"]


class BuildArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix=".test-build-artifact-", dir=ROOT)
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        self.root = self.workspace / (artifact.ROOT_PREFIX + "transfer")
        self.root.mkdir()
        self.current = {
            "source_revision": "a" * 40, "profile": "normal", "profile_manifest_sha256": "b" * 64,
            "run_id": "123", "run_attempt": "1", "toolchain_id": "c" * 64, "runner_arch": "ARM64",
            "workspace": str(self.workspace), "image_version": "20261024.1",
        }

    def runtime(self):
        debug = self.workspace / ".build/arm64-apple-macosx/debug"
        binary = debug / "CodexBarPackageTests.xctest/Contents/MacOS/CodexBarPackageTests"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"synthetic XCTest executable")
        binary.chmod(0o755)
        (debug / "description.json").write_text('{"builtTestProducts": []}')
        (debug / "CodexBarCLI").write_bytes(b"synthetic CLI")
        (debug / "CodexBarCLI").chmod(0o755)
        os.link(debug / "CodexBarCLI", debug / "CLI-hardlink")
        resources = debug / "CodexBar_CodexBarCore.bundle"
        resources.mkdir()
        (resources / "fixture.json").write_text('{"fixture": true}')
        framework = self.workspace / ".build/artifacts/sparkle/Sparkle.framework/Versions/B"
        framework.mkdir(parents=True)
        (framework / "Sparkle").write_bytes(b"synthetic framework")
        (framework.parent / "Current").symlink_to("B", target_is_directory=True)
        (debug / "Sparkle.framework").symlink_to(framework.parent.parent, target_is_directory=True)
        (debug / "PackageFrameworks").mkdir()
        (debug / "PackageFrameworks/Sparkle.framework").symlink_to("../Sparkle.framework")
        (self.workspace / ".build/debug").symlink_to("arm64-apple-macosx/debug")

    def export(self):
        self.runtime()
        manifest, digest = artifact.export_build(self.workspace, self.root, self.current, TEST_IDS)
        shutil.rmtree(self.workspace / ".build")
        return manifest, digest

    def assert_no_restore(self):
        self.assertFalse((self.workspace / ".build").exists())
        self.assertEqual(list(self.workspace.glob(".swift-test-restore-*")), [])

    def test_upload_selects_only_visible_owned_manifest_and_archive_before_cleanup(self):
        environment_file = self.workspace / "github-environment"
        with patch.dict(os.environ, {"GITHUB_WORKSPACE": str(self.workspace),
                                     "GITHUB_ENV": str(environment_file)}, clear=True), \
                patch.object(sys, "argv", ["artifact", "prepare-transfer"]):
            artifact.main()
        environment = dict(line.split("=", 1) for line in environment_file.read_text().splitlines())
        root = Path(environment["CODEXBAR_TEST_BUILD_ROOT"])
        self.assertEqual(root.parent, self.workspace)
        self.assertFalse(root.name.startswith("."), "upload-artifact excludes hidden staging ancestors")
        self.runtime()
        artifact.export_build(self.workspace, root, self.current, TEST_IDS)
        (root / ".unrelated-metadata").write_text("must not be uploaded")
        (self.workspace / "unrelated-workspace-file").write_text("must not be uploaded")
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        upload = workflow.split("      - name: Upload compiled macOS tests\n", 1)[1].split("\n      - name:", 1)[0]
        selected = upload.split("          path: |\n", 1)[1].split("          include-hidden-files:", 1)[0]
        paths = [Path(line.strip().replace("${{ env.CODEXBAR_TEST_BUILD_ROOT }}", str(root)))
                 for line in selected.splitlines() if line.strip()]
        self.assertEqual(set(paths), {root / artifact.MANIFEST, root / artifact.ARCHIVE})
        self.assertTrue(all(path.is_file() and not path.is_symlink() for path in paths))
        self.assertIn("include-hidden-files: false", upload)
        self.assertIn("if-no-files-found: error", upload)
        self.assertLess(workflow.index("Upload compiled macOS tests"),
                        workflow.index("Remove runner-local compiled test transfer"))
        with patch.dict(os.environ, {"GITHUB_WORKSPACE": str(self.workspace), **environment}, clear=True), \
                patch.object(sys, "argv", ["artifact", "cleanup-transfer"]):
            artifact.main()
        self.assertFalse(root.exists())

    def test_runtime_roundtrip_preserves_tools_resources_frameworks_and_executable_modes(self):
        manifest, digest = self.export()
        restored = artifact.restore_build(self.workspace, self.root, digest, self.current)
        self.assertEqual(restored, manifest)
        debug = self.workspace / ".build/debug"
        self.assertEqual((debug / "CodexBarCLI").read_bytes(), b"synthetic CLI")
        self.assertEqual((debug / "CLI-hardlink").read_bytes(), b"synthetic CLI")
        self.assertEqual((debug / "CodexBarCLI").stat().st_mode & 0o777, 0o755)
        self.assertTrue((debug / "CodexBar_CodexBarCore.bundle/fixture.json").is_file())
        sparkle = debug / "PackageFrameworks/Sparkle.framework/Versions/Current/Sparkle"
        self.assertEqual(sparkle.read_bytes(), b"synthetic framework")
        self.assertFalse(os.path.isabs(os.readlink(debug / "Sparkle.framework")))
        info = (self.workspace / ".build").stat()
        artifact.cleanup_restored_build(self.workspace, (info.st_dev, info.st_ino), True)
        self.assert_no_restore()
        self.assertTrue((self.root / artifact.ARCHIVE).is_file())

    def test_identity_mismatch_and_missing_producer_hash_fail_before_restore(self):
        _, digest = self.export()
        for key in self.current:
            changed = {**self.current, key: "different"}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "identity differs"):
                artifact.restore_build(self.workspace, self.root, digest, changed)
            self.assert_no_restore()
        for value in (None, "", "0" * 64):
            with self.subTest(hash=value), self.assertRaises(ValueError):
                artifact.restore_build(self.workspace, self.root, value, self.current)
            self.assert_no_restore()

    def test_current_identity_requires_real_checkout_and_toolchain_evidence(self):
        (self.workspace / "Scripts").mkdir()
        (self.workspace / "Scripts/test_profiles.json").write_text("{}")
        for name in ("Package.swift", "Package.resolved"):
            (self.workspace / name).write_text(name)
        versions = ["Xcode 26.3\nBuild version synthetic", "Swift version synthetic", "SwiftPM synthetic"]
        toolchain = artifact.hashlib.sha256(("\n".join(versions) + "\n").encode()).hexdigest()
        environment = {
            "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_OS": "macOS",
            "RUNNER_ARCH": "ARM64", "GITHUB_REPOSITORY": "Jones-Systems/CodexBar",
            "GITHUB_WORKSPACE": str(self.workspace), "GITHUB_SHA": "a" * 40,
            "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKFLOW_REF": "repo/ci@ref",
            "ImageOS": "macos26", "ImageVersion": "synthetic", "CODEXBAR_TEST_TOOLCHAIN_ID": toolchain,
        }
        def capture(command, **_):
            output = {("git", "--no-optional-locks", "rev-parse", "HEAD"): "a" * 40,
                      ("git", "--no-optional-locks", "diff", "--quiet", "HEAD", "--"): "",
                      ("/usr/bin/xcodebuild", "-version"): versions[0],
                      ("swift", "--version"): versions[1], ("swift", "package", "--version"): versions[2]}[tuple(command)]
            return subprocess.CompletedProcess(command, 0, output + "\n", "")
        with patch.object(artifact.platform, "system", return_value="Darwin"), \
                patch.object(artifact.platform, "machine", return_value="arm64"):
            result = artifact.identity(self.workspace, environment, ["swift"], capture)
            self.assertEqual(result["toolchain_id"], toolchain)
            self.assertEqual(result["profile"], "normal")
            for key, changed in (("GITHUB_REPOSITORY", "other/repo"), ("GITHUB_RUN_ATTEMPT", "0"),
                                 ("GITHUB_SHA", "b" * 40), ("CODEXBAR_TEST_TOOLCHAIN_ID", "0" * 64),
                                 ("RUNNER_ENVIRONMENT", "self-hosted"), ("CODEXBAR_TEST_PROFILE", "typo")):
                with self.subTest(key=key), self.assertRaises(ValueError):
                    artifact.identity(self.workspace, {**environment, key: changed}, ["swift"], capture)
            def dirty(command, **kwargs):
                if "diff" in command:
                    return subprocess.CompletedProcess(command, 1, "", "")
                return capture(command, **kwargs)
            with self.assertRaises(subprocess.CalledProcessError):
                artifact.identity(self.workspace, environment, ["swift"], dirty)

    def test_manifest_and_archive_corruption_fail_closed(self):
        _, digest = self.export()
        manifest_path = self.root / artifact.MANIFEST
        original = manifest_path.read_bytes()
        manifest_path.write_bytes(original + b" ")
        with self.assertRaisesRegex(ValueError, "manifest integrity"):
            artifact.restore_build(self.workspace, self.root, digest, self.current)
        manifest_path.write_bytes(original)
        archive = self.root / artifact.ARCHIVE
        data = archive.read_bytes()
        archive.write_bytes(bytes([data[0] ^ 1]) + data[1:])
        with self.assertRaisesRegex(ValueError, "archive integrity"):
            artifact.restore_build(self.workspace, self.root, digest, self.current)
        self.assert_no_restore()

    def hostile_archive(self, members):
        with tarfile.open(self.root / artifact.ARCHIVE, "w:gz") as archive:
            for member in members:
                archive.addfile(member, io.BytesIO(b"x" * member.size) if member.isreg() else None)
        manifest = {
            "schema": artifact.SCHEMA, "identity": self.current,
            "archive_sha256": artifact.sha256(self.root / artifact.ARCHIVE),
            "archive_bytes": (self.root / artifact.ARCHIVE).stat().st_size,
            "payload_bytes": sum(member.size for member in members), "entries": len(members),
            "test_ids": TEST_IDS, "discovery_sha256": artifact.test_manifest(TEST_IDS),
        }
        (self.root / artifact.MANIFEST).write_text(json.dumps(manifest))
        return artifact.sha256(self.root / artifact.MANIFEST)

    def test_hostile_archives_leave_no_build_or_staging_tree(self):
        def member(name, kind=tarfile.REGTYPE, link="", mode=0o755):
            info = tarfile.TarInfo(name)
            info.type, info.linkname, info.mode = kind, link, mode
            info.size = 1 if info.isreg() else 0
            return info

        cases = {
            "absolute": [member("/outside")],
            "traversal": [member(".build/../../outside")],
            "alternate spelling": [member(".build//outside")],
            "backslash": [member(".build/a\\b")],
            "duplicate": [member(".build/file"), member(".build/file")],
            "escaping link": [member(".build/link", tarfile.SYMTYPE, "../../outside")],
            "absolute link": [member(".build/link", tarfile.SYMTYPE, "/outside")],
            "hardlink": [member(".build/link", tarfile.LNKTYPE, ".build/file")],
            "device": [member(".build/device", tarfile.CHRTYPE)],
            "setuid": [member(".build/file", mode=0o4755)],
            "symlink ancestor": [member(".build/real", tarfile.DIRTYPE),
                                 member(".build/link", tarfile.SYMTYPE, "real"), member(".build/link/file")],
            "missing link target": [member(".build/link", tarfile.SYMTYPE, "missing")],
            "link cycle": [member(".build/a", tarfile.SYMTYPE, "b"),
                           member(".build/b", tarfile.SYMTYPE, "a")],
        }
        for name, members in cases.items():
            with self.subTest(case=name):
                members = [member(".build", tarfile.DIRTYPE), member(".build/payload"), *members]
                digest = self.hostile_archive(members)
                with self.assertRaises((ValueError, RuntimeError, OSError)):
                    artifact.restore_build(self.workspace, self.root, digest, self.current)
                self.assert_no_restore()

    def test_budget_failure_and_cancelled_extraction_clean_owned_staging(self):
        _, digest = self.export()
        with patch.object(artifact.shutil, "disk_usage", return_value=SimpleNamespace(free=0)):
            with self.assertRaisesRegex(ValueError, "storage"):
                artifact.restore_build(self.workspace, self.root, digest, self.current)
        self.assert_no_restore()
        with patch.object(artifact, "extract_build", side_effect=SystemExit(143)):
            with self.assertRaises(SystemExit):
                artifact.restore_build(self.workspace, self.root, digest, self.current)
        self.assert_no_restore()

    def test_cancelled_export_removes_partial_files_and_rejects_external_links(self):
        self.runtime()
        with patch.object(tarfile.TarFile, "addfile", side_effect=SystemExit(143)):
            with self.assertRaises(SystemExit):
                artifact.export_build(self.workspace, self.root, self.current, TEST_IDS)
        self.assertEqual(list(self.root.iterdir()), [])
        (self.workspace / ".build/external").symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            artifact.export_build(self.workspace, self.root, self.current, TEST_IDS)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_refuses_existing_build_and_cleanup_without_proved_ownership(self):
        _, digest = self.export()
        artifact.restore_build(self.workspace, self.root, digest, self.current)
        with self.assertRaisesRegex(ValueError, "already exists"):
            artifact.restore_build(self.workspace, self.root, digest, self.current)
        info = (self.workspace / ".build").stat()
        for identity, safe in (((info.st_dev, info.st_ino), False), ((info.st_dev, info.st_ino + 1), True)):
            with self.assertRaisesRegex(ValueError, "preserving"):
                artifact.cleanup_restored_build(self.workspace, identity, safe)
        self.assertTrue((self.workspace / ".build").is_dir())

    @contextlib.contextmanager
    def harness(self, args, *, discovery=TEST_IDS, status=0):
        previous = Path.cwd()
        os.chdir(self.workspace)
        self.addCleanup(os.chdir, previous)
        result = subprocess.CompletedProcess([], status, "\n".join(discovery) + "\n", "")
        with patch.object(sys, "argv", ["runner", *args]), \
                patch.object(artifact, "identity", return_value=self.current), \
                patch.object(runner, "run_captured_command", return_value=result) as captured, \
                patch.object(runner, "run_test_command", return_value=0) as execute, \
                patch.object(runner, "_campaign", None), \
                patch.dict(os.environ, {"GITHUB_OUTPUT": "", "GITHUB_STEP_SUMMARY": ""}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            yield captured, execute
        os.chdir(previous)

    def test_both_shards_restore_same_build_and_never_compile(self):
        _, digest = self.export()
        commands = []
        for index in (0, 1):
            with self.harness(["--use-build", str(self.root), "--group-size", "1",
                               "--shard-count", "2", "--shard-index", str(index)]) as (captured, execute), \
                    patch.dict(os.environ, {"CODEXBAR_TEST_BUILD_MANIFEST_SHA256": digest}):
                self.assertEqual(runner.run_suites(), 0)
                self.assertEqual([call.args[0] for call in captured.call_args_list],
                                 [["swift", "test", "list", "--skip-build"]])
                commands.extend(call.args[0] for call in execute.call_args_list)
            self.assert_no_restore()
        self.assertEqual(len(commands), 2)
        self.assertTrue(all(command[:4] == ["swift", "test", "--skip-build", "--no-parallel"]
                            for command in commands))
        self.assertIn("Alpha", commands[0][-1])
        self.assertIn("Beta", commands[1][-1])

    def test_worker_discovery_failure_or_drift_never_repairs_or_compiles(self):
        _, digest = self.export()
        for discovery, status in ((["CodexBarTests.Other/test_changed()"], 0), (TEST_IDS, 1)):
            with self.harness(["--use-build", str(self.root)], discovery=discovery, status=status) as (captured, execute), \
                    patch.dict(os.environ, {"CODEXBAR_TEST_BUILD_MANIFEST_SHA256": digest}), \
                    patch.object(runner, "repair_sparkle_test_runtime") as repair:
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    runner.run_suites()
                self.assertEqual(captured.call_count, 1)
                execute.assert_not_called()
                repair.assert_not_called()
            self.assert_no_restore()

    def test_bad_handoff_does_not_invoke_swift(self):
        self.export()
        with self.harness(["--use-build", str(self.root)]) as (captured, execute), \
                patch.dict(os.environ, {"CODEXBAR_TEST_BUILD_MANIFEST_SHA256": "0" * 64}):
            with self.assertRaisesRegex(ValueError, "integrity"):
                runner.run_suites()
            captured.assert_not_called()
            execute.assert_not_called()
        self.assert_no_restore()

    def test_producer_compiles_once_without_running_test_groups(self):
        self.runtime()
        with self.harness(["--export-build", str(self.root)]) as (captured, execute):
            self.assertEqual(runner.run_suites(), 0)
            self.assertEqual([call.args[0] for call in captured.call_args_list], [
                ["swift", "build", "--build-tests"], ["swift", "test", "list", "--skip-build"],
            ])
            execute.assert_not_called()
        self.assertTrue((self.root / artifact.MANIFEST).is_file())

    def test_full_profile_jsc_uses_shared_build_before_cleanup(self):
        self.current["profile"] = "full"
        _, digest = self.export()
        with self.harness(["--use-build", str(self.root), "--jsc-goldens"]) as (captured, execute), \
                patch.dict(os.environ, {"CODEXBAR_TEST_BUILD_MANIFEST_SHA256": digest,
                                        "CODEXBAR_TEST_PROFILE": "full"}):
            self.assertEqual(runner.run_suites(), 0)
            self.assertEqual(captured.call_count, 1)
            commands = [call.args[0] for call in execute.call_args_list]
            self.assertEqual(len(commands), 2)
            self.assertIn("ProviderPluginRuntimeTests", commands[-1][-1])
            self.assertTrue(all("--skip-build" in command for command in commands))
            self.assertNotIn("CODEXBAR_PLUGIN_ENGINE", os.environ)
        self.assert_no_restore()

    def test_failed_execution_status_survives_build_cleanup_failure(self):
        _, digest = self.export()
        with self.harness(["--use-build", str(self.root), "--no-retry-non-timeout-failures"]) as (_, execute), \
                patch.dict(os.environ, {"CODEXBAR_TEST_BUILD_MANIFEST_SHA256": digest}), \
                patch.object(artifact, "cleanup_restored_build", side_effect=ValueError("cleanup failure")):
            execute.return_value = 37
            self.assertEqual(runner.run_suites(), 37)


if __name__ == "__main__":
    unittest.main()
