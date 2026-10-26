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
# The existing portable artifact-suite entrypoint owns these affected contract checks.
from test_swift_test_native import NativeTests, image


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
            "repository": "Jones-Systems/CodexBar", "workflow_ref": "Jones-Systems/CodexBar/.github/workflows/ci.yml@refs/pull/40/merge",
            "source_revision": "a" * 40, "profile": "normal", "profile_manifest_sha256": "b" * 64,
            "run_id": "123", "run_attempt": "1", "toolchain_id": "c" * 64, "runner_arch": "ARM64",
            "workspace": str(self.workspace), "image_version": "20261024.1", "image_os": "macos26",
            "runner_os": "macOS", "package_sha256": "d" * 64, "resolved_sha256": "e" * 64,
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
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "identity differs") as error:
                artifact.restore_build(self.workspace, self.root, digest, changed)
            self.assertIn(key, str(error.exception))
            self.assert_no_restore()
        for value in (None, "", "0" * 64):
            with self.subTest(hash=value), self.assertRaises(ValueError):
                artifact.restore_build(self.workspace, self.root, value, self.current)
            self.assert_no_restore()

    def test_hosted_image_rollout_mismatch_reports_versions_and_rejects_before_extraction(self):
        self.current["image_version"] = "20261013.0424.1"
        _, digest = self.export()
        worker = {**self.current, "image_version": "20261021.0445.8"}
        with patch.object(artifact, "extract_build") as extract, \
                self.assertRaisesRegex(ValueError, "identity differs") as error:
            artifact.restore_build(self.workspace, self.root, digest, worker)
        extract.assert_not_called()
        details = json.loads(str(error.exception).split("mismatches=", 1)[1])
        self.assertEqual(details, {"image_version": {"producer": "20261013.0424.1",
                                                   "worker": "20261021.0445.8"}})
        self.assert_no_restore()

    def test_identity_diagnostics_omit_unknown_metadata_and_structured_or_oversized_values(self):
        producer = {**self.current, "unexpected_secret": "must-never-appear",
                    "profile": {"secret": "must-never-appear"}, "workspace": "x" * 257}
        with self.assertRaisesRegex(ValueError, "identity differs") as error:
            artifact.require_identity(producer, self.current)
        message = str(error.exception)
        self.assertNotIn("must-never-appear", message)
        self.assertNotIn("unexpected_secret", message)
        self.assertNotIn("x" * 257, message)
        details = json.loads(message.split("mismatches=", 1)[1])
        self.assertEqual(details["profile"]["producer"], "<non-string>")
        self.assertEqual(details["workspace"]["producer"], "<oversized>")
        self.assertIn("schema", details)

    def test_identity_diagnostics_escape_controls_and_report_missing_fields(self):
        producer = {**self.current, "profile": "full\n::error::injected"}
        del producer["image_version"]
        with self.assertRaisesRegex(ValueError, "identity differs") as error:
            artifact.require_identity(producer, self.current)
        self.assertNotIn("\n", str(error.exception))
        details = json.loads(str(error.exception).split("mismatches=", 1)[1])
        self.assertEqual(details["image_version"]["producer"], "<missing>")
        self.assertEqual(details["profile"]["producer"], "full\n::error::injected")
        with self.assertRaisesRegex(ValueError, "value omitted") as malformed:
            artifact.require_identity(["must-never-appear"], self.current)
        self.assertNotIn("must-never-appear", str(malformed.exception))

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

    def native_export(self, complete=True, diagnostic=None):
        fingerprint = {"schema": "codexbar.swift-test-native/v1", "context": {"os_build":"25G83"},
                       "entries": {"runtime": {"sha256":"a" * 64}}, "edges": {}}
        self.runtime()
        payload = {"status":"complete", "fingerprint":fingerprint} if complete else {
            "status":"unavailable", "reason":"native-cache-api-unavailable"}
        if diagnostic is not None:
            payload["diagnostic"] = diagnostic
        manifest, digest = artifact.export_build(self.workspace, self.root, self.current, TEST_IDS,
                                                 native_runtime=payload)
        shutil.rmtree(self.workspace / ".build")
        return manifest, digest, fingerprint

    def test_complete_native_identity_allows_image_rollout_only_after_staged_closure(self):
        manifest, digest, fingerprint = self.native_export()
        worker = {**self.current, "image_version":"20261021.0445.8"}
        def staged():
            self.assertFalse((self.workspace / ".build").exists())
            self.assertTrue((host.build / "debug/CodexBarCLI").is_file())
            return fingerprint
        work = {"images":1, "attempted_edges":2, "resolved_edges":2,
                "memo_hits":0, "memo_misses":1, "processes":1}
        host = SimpleNamespace(context=fingerprint["context"], closure=staged, closure_work=work)
        state = {"host":host, "reason":None, "host_seconds":0.25}
        observed = []
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True):
            restored = artifact.restore_build(self.workspace, self.root, digest, worker, state,
                                               lambda **fields: observed.append(fields))
        self.assertEqual(restored, manifest)
        self.assertEqual(observed[0]["mode"], "complete-fingerprint")
        self.assertEqual(observed[0]["status"], "verified")
        self.assertEqual(observed[0]["worker_image"], worker["image_version"])
        self.assertEqual(observed[0]["host_seconds"], 0.25)
        self.assertEqual(observed[0]["work"], work)
        self.assertNotIn("work", restored["native_runtime"])

    def test_native_work_observations_never_change_payload_or_admission(self):
        import ci_swift_test_native as native
        fingerprint = {"schema":native.SCHEMA, "context":{}, "entries":{}, "edges":{}}
        for work in (None, {"command":"untrusted"}, {
                "images":1, "attempted_edges":1, "resolved_edges":1,
                "memo_hits":0, "memo_misses":1, "processes":1}):
            with self.subTest(work=work):
                state = {"host":SimpleNamespace(closure=lambda: fingerprint, closure_work=work)}
                payload, _seconds = artifact.native_finish(state, self.workspace / ".build")
                self.assertEqual(payload, {"status":"complete", "fingerprint":fingerprint})
                self.assertEqual(state["closure_work"], work if work and "images" in work else None)

    def test_actual_shared_dag_work_is_emitted_before_build_without_entering_manifest_identity(self):
        self.runtime()
        fixtures = NativeTests()
        fixtures.setUp()
        self.addCleanup(fixtures.doCleanups)
        host, _nodes = fixtures.shared_dag(levels=2, width=2, leaf_count=2)
        state = {"host":host, "reason":None, "host_seconds":0.1}
        unavailable = {"host":None, "reason":"native-cache-api-unavailable", "host_seconds":0.1}
        with self.harness(["--export-build", str(self.root)]) as (_, execute), \
                patch.object(artifact, "native_precheck", side_effect=[state, unavailable]), \
                patch.object(runner, "emit_evidence") as evidence:
            self.assertEqual(runner.run_suites(), 0)
        execute.assert_not_called()
        preflight = next(call.kwargs for call in evidence.call_args_list if call.args == ("native-tool-preflight",))
        self.assertTrue(preflight["build_allowed"])
        self.assertEqual(preflight["work"], host.closure_work)
        self.assertGreater(preflight["work"]["memo_hits"], 0)
        manifest = json.loads((self.root / artifact.MANIFEST).read_text())
        self.assertNotIn("work", manifest["identity"])
        self.assertEqual(manifest["native_runtime"], {
            "status":"unavailable", "reason":"native-cache-api-unavailable"})

    def test_native_host_mismatch_fails_before_extraction_even_with_identical_image(self):
        _, digest, _ = self.native_export()
        state = {"host":SimpleNamespace(context={"os_build":"different"}), "reason":None, "host_seconds":0}
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True), \
                patch.object(artifact, "extract_build") as extract, \
                self.assertRaisesRegex(ValueError, "before restore"):
            artifact.restore_build(self.workspace, self.root, digest, self.current, state)
        extract.assert_not_called()
        self.assert_no_restore()

    def test_incomplete_native_identity_uses_only_strict_exact_image_fallback(self):
        _, digest, _ = self.native_export(complete=False)
        state = {"host":None, "reason":"native-cache-api-unavailable", "host_seconds":0.1}
        observed = []
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True):
            with patch.object(artifact, "extract_build") as extract, self.assertRaisesRegex(ValueError, "identity differs"):
                artifact.restore_build(self.workspace, self.root, digest,
                                       {**self.current, "image_version":"different"}, state)
            extract.assert_not_called()
            self.assert_no_restore()
            artifact.restore_build(self.workspace, self.root, digest, self.current, state,
                                   lambda **fields: observed.append(fields))
        self.assertEqual(observed[0]["mode"], "exact-image-fallback")
        self.assertEqual(observed[0]["reason"], "native-cache-api-unavailable")

    def test_unavailable_file_diagnostics_are_data_only_and_never_relax_exact_image_fallback(self):
        import ci_swift_test_native as native
        diagnostic = {"path":"/Applications/Xcode.app/Contents/Developer/usr/bin/swift-package",
                      "file_bytes":512, "header_sha256":"a" * 64, "fat_slices":[{
                          "cpu":native.ARM64, "subtype":0x81000002, "offset":64,
                          "bytes":128, "alignment":6, "hidden":False}]}
        _, digest, _ = self.native_export(complete=False, diagnostic=diagnostic)
        state = {"host":None, "reason":"native-cache-api-unavailable", "host_seconds":0.1}
        observed = []
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True):
            with patch.object(artifact, "extract_build") as extract, self.assertRaisesRegex(ValueError, "identity differs"):
                artifact.restore_build(self.workspace, self.root, digest,
                                       {**self.current, "image_version":"different"}, state)
            extract.assert_not_called()
            artifact.restore_build(self.workspace, self.root, digest, self.current, state,
                                   lambda **fields: observed.append(fields))
        self.assertEqual(observed[0]["diagnostic"], diagnostic)
        self.assertEqual(observed[0]["mode"], "exact-image-fallback")
        for payload in ({"status":"unavailable", "reason":"unsupported-fat-layout",
                         "diagnostic":{**diagnostic, "command":"untrusted"}},
                        {"status":"complete", "fingerprint":{}, "diagnostic":diagnostic}):
            with self.assertRaises(ValueError):
                artifact.native_payload(payload)

    def test_native_file_diagnostic_survives_collection_and_producer_evidence(self):
        import ci_swift_test_native as native
        diagnostic = {"path":"/Applications/Xcode.app/Contents/runtime", "file_bytes":64,
                      "header_sha256":"b" * 64, "fat_slices":[]}
        failure = native.UnsupportedRuntime("unsupported-arm64-subtype-abi")
        failure.diagnostic = diagnostic
        def unavailable(**kwargs):
            if kwargs == {"include_build":False}:
                return {"schema":native.SCHEMA, "context":{}, "entries":{}, "edges":{}}
            raise failure
        state = {"host":SimpleNamespace(closure=unavailable), "reason":None, "host_seconds":0.1}
        payload, seconds = artifact.native_finish(state, self.workspace / ".build")
        self.assertEqual(payload, {"status":"unavailable", "reason":str(failure), "diagnostic":diagnostic})
        self.assertGreaterEqual(seconds, 0)
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True), \
                patch.object(native, "Host", side_effect=failure):
            precheck = artifact.native_precheck(self.workspace, None)
        self.assertIsNone(precheck["host"])
        self.assertEqual(artifact.native_finish(precheck, self.workspace / ".build")[0], payload)
        self.runtime()
        with self.harness(["--export-build", str(self.root)]) as (_, execute), \
                patch.object(artifact, "native_precheck", return_value=state), \
                patch.object(runner, "emit_evidence") as evidence:
            self.assertEqual(runner.run_suites(), 0)
        produced = [call.kwargs for call in evidence.call_args_list
                    if call.args == ("native-compatibility-produced",)]
        self.assertEqual(produced[0]["diagnostic"], diagnostic)
        self.assertEqual(produced[0]["status"], "unavailable")
        self.assertEqual(json.loads((self.root / artifact.MANIFEST).read_text())["native_runtime"], payload)
        execute.assert_not_called()

    def test_resolver_diagnostics_round_trip_as_bounded_data_with_strict_fallback(self):
        diagnostic = {"type":"resolver", "loader":"<xcode>/Developer/usr/bin/swift-package",
                      "executable":"<xcode>/Developer/usr/bin/swift-package", "mode":"plain",
                      "install_name":"@rpath/Absent.dylib", "chain":[{
                          "path":"<xcode>/Developer/usr/bin/swift-package", "subtype":0}],
                      "unapproved_declarations":[{
                          "loader":"<xcode>/Developer/usr/bin/swift-package", "loader_sha256":"b" * 64,
                          "subtype":0, "install_name":"<outside-approved-roots:" + "c" * 64 + ">",
                          "weak":False, "dylinker":False}],
                      "location":{"path":"/System/Library/PrivateFrameworks/Example.framework/Versions/A/Example",
                                  "root":"/System/Library/PrivateFrameworks",
                                  "root_canonical":"/System/Library/PrivateFrameworks",
                                  "canonical":"<outside-approved-roots:" + "d" * 64 + ">", "status":"first-link",
                                  "first_symlink":{"path":"/System/Library/PrivateFrameworks/Example.framework",
                                                   "target":"<outside-approved-roots:" + "e" * 64 + ">",
                                                   "raw_target_sha256":"f" * 64, "relative":False}},
                      "rpaths":[{"loader":"<xcode>/Developer/usr/bin/swift-package",
                                 "raw":"@loader_path", "expanded":"<xcode>/Developer/usr/bin"}],
                      "candidates":[{"path":"<xcode>/Developer/usr/bin/Absent.dylib", "canonical":None,
                                     "kind":"missing", "sha256":None}], "truncated":False}
        _, digest, _ = self.native_export(complete=False, diagnostic=diagnostic)
        state = {"host":None, "reason":"native-cache-api-unavailable", "host_seconds":0.1}
        observed = []
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True):
            with patch.object(artifact, "extract_build") as extract, self.assertRaisesRegex(ValueError, "identity differs"):
                artifact.restore_build(self.workspace, self.root, digest,
                                       {**self.current, "image_version":"different"}, state)
            extract.assert_not_called()
            artifact.restore_build(self.workspace, self.root, digest, self.current, state,
                                   lambda **fields: observed.append(fields))
        self.assertEqual(observed[0]["diagnostic"], diagnostic)
        self.assertEqual(observed[0]["mode"], "exact-image-fallback")
        for field in ("mode", "loader", "candidates", "truncated"):
            invalid = {**diagnostic, field:{"command":"untrusted"}}
            with self.subTest(field=field), self.assertRaises(ValueError):
                artifact.native_payload({"status":"unavailable", "reason":"unsupported-runtime", "diagnostic":invalid})

    def test_complete_native_proof_never_relaxes_other_identity_or_integrity_boundaries(self):
        _, digest, fingerprint = self.native_export()
        state = {"host":SimpleNamespace(context=fingerprint["context"]), "reason":None, "host_seconds":0}
        self.assertEqual(set(self.current), artifact.IDENTITY_FIELDS)
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True), \
                patch.object(artifact, "extract_build") as extract:
            for key in sorted(artifact.IDENTITY_FIELDS - {"image_version"}):
                with self.subTest(key=key), self.assertRaisesRegex(ValueError, "identity differs"):
                    artifact.restore_build(self.workspace, self.root, digest, {**self.current, key:"changed"}, state)
                self.assert_no_restore()
            with self.assertRaisesRegex(ValueError, "manifest integrity"):
                artifact.restore_build(self.workspace, self.root, "f" * 64, self.current, state)
            archive = self.root / artifact.ARCHIVE
            archive.write_bytes(archive.read_bytes() + b"corruption")
            with self.assertRaisesRegex(ValueError, "archive (size|integrity)"):
                artifact.restore_build(self.workspace, self.root, digest, self.current, state)
        extract.assert_not_called()
        self.assert_no_restore()

    def test_incomplete_staged_closure_cannot_admit_a_different_image(self):
        import ci_swift_test_native as native
        _, digest, fingerprint = self.native_export()
        def unsupported():
            raise native.UnsupportedRuntime("unresolved-runtime-dependency")
        state = {"host":SimpleNamespace(context=fingerprint["context"], closure=unsupported),
                 "reason":None, "host_seconds":0}
        observed = []
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True), \
                self.assertRaisesRegex(ValueError, "identity differs"):
            artifact.restore_build(self.workspace, self.root, digest,
                                   {**self.current, "image_version":"different"}, state,
                                   lambda **fields: observed.append(fields))
        self.assertEqual(observed[0]["mode"], "exact-image-fallback")
        self.assertEqual(observed[0]["status"], "rejected")
        self.assertEqual(observed[0]["reason"], "unresolved-runtime-dependency")
        self.assert_no_restore()

    def test_complete_staged_dependency_mismatch_fails_before_install(self):
        import ci_swift_test_native as native
        _, digest, fingerprint = self.native_export()
        changed = {**fingerprint, "entries":{"runtime":{"sha256":"b" * 64}}}
        state = {"host":SimpleNamespace(context=fingerprint["context"], closure=lambda:changed),
                 "reason":None, "host_seconds":0}
        with patch.object(artifact, "ENABLE_NATIVE_COMPATIBILITY", True), \
                self.assertRaisesRegex(native.UnsupportedRuntime, "differs"):
            artifact.restore_build(self.workspace, self.root, digest, self.current, state)
        self.assert_no_restore()

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

    def test_tool_preflight_precedes_build_and_never_substitutes_for_fresh_product_closure(self):
        self.runtime()
        order = []
        def precheck(*_args):
            order.append("host")
            def closure(**kwargs):
                order.append("tools" if kwargs == {"include_build":False} else "products")
                if kwargs == {"include_build":False}:
                    return {"schema":artifact_native.SCHEMA, "context":{}, "entries":{}, "edges":{}}
                raise artifact_native.UnsupportedRuntime("unresolved-runtime-dependency")
            return {"host":SimpleNamespace(closure=closure), "reason":None, "host_seconds":0.1}
        import ci_swift_test_native as artifact_native
        with self.harness(["--export-build", str(self.root)]) as (captured, execute), \
                patch.object(artifact, "native_precheck", side_effect=precheck), \
                patch.object(runner, "emit_evidence") as evidence:
            result = captured.return_value
            def capture(command, **_kwargs):
                order.append("build" if "build" in command else "discovery")
                return result
            captured.side_effect = capture
            self.assertEqual(runner.run_suites(), 0)
        self.assertEqual(order, ["host", "tools", "build", "discovery", "host", "products"])
        self.assertEqual([call.args[0] for call in captured.call_args_list], [
            ["swift", "build", "--build-tests"], ["swift", "test", "list", "--skip-build"]])
        execute.assert_not_called()
        preflight = [call.kwargs for call in evidence.call_args_list if call.args == ("native-tool-preflight",)]
        self.assertEqual(preflight[0]["status"], "complete")
        self.assertEqual(preflight[0]["host_status"], "complete")
        self.assertTrue(preflight[0]["build_allowed"])
        self.assertGreaterEqual(preflight[0]["closure_seconds"], 0)
        self.assertEqual(json.loads((self.root / artifact.MANIFEST).read_text())["native_runtime"], {
            "status":"unavailable", "reason":"unresolved-runtime-dependency"})

    def test_complete_host_with_unsupported_tools_fails_before_compiler_sentinel(self):
        import ci_swift_test_native as artifact_native
        diagnostic = {"path":"<xcode>/Developer/runtime", "file_bytes":64,
                      "header_sha256":"b" * 64, "fat_slices":[]}
        def unsupported(**_kwargs):
            failure = artifact_native.UnsupportedRuntime("runtime-path-outside-approved-roots")
            failure.diagnostic = diagnostic
            raise failure
        state = {"host":SimpleNamespace(closure=unsupported), "reason":None, "host_seconds":0.1}
        with self.harness(["--export-build", str(self.root)]) as (captured, execute), \
                patch.object(artifact, "native_precheck", return_value=state), \
                patch.object(runner, "emit_evidence") as evidence:
            captured.side_effect = AssertionError("compiler/discovery sentinel must not run")
            with self.assertRaisesRegex(ValueError, "incomplete before compilation: runtime-path-outside-approved-roots"):
                runner.run_suites()
        captured.assert_not_called()
        execute.assert_not_called()
        self.assertFalse((self.root / artifact.MANIFEST).exists())
        preflight = next(call.kwargs for call in evidence.call_args_list if call.args == ("native-tool-preflight",))
        self.assertEqual(preflight["status"], "unavailable")
        self.assertEqual(preflight["host_status"], "complete")
        self.assertFalse(preflight["build_allowed"])
        self.assertEqual(preflight["reason"], "runtime-path-outside-approved-roots")
        self.assertEqual(preflight["diagnostic"], diagnostic)

    def test_unavailable_native_host_retains_producer_exact_image_fallback(self):
        self.runtime()
        state = {"host":None, "reason":"native-cache-api-unavailable", "host_seconds":0.1}
        with self.harness(["--export-build", str(self.root)]) as (captured, execute), \
                patch.object(artifact, "native_precheck", return_value=state), \
                patch.object(runner, "emit_evidence") as evidence:
            self.assertEqual(runner.run_suites(), 0)
        self.assertEqual([call.args[0] for call in captured.call_args_list], [
            ["swift", "build", "--build-tests"], ["swift", "test", "list", "--skip-build"]])
        execute.assert_not_called()
        preflight = next(call.kwargs for call in evidence.call_args_list if call.args == ("native-tool-preflight",))
        self.assertEqual(preflight["host_status"], "unavailable")
        self.assertTrue(preflight["build_allowed"])
        self.assertEqual(preflight["closure_seconds"], 0)
        self.assertEqual(json.loads((self.root / artifact.MANIFEST).read_text())["native_runtime"], {
            "status":"unavailable", "reason":"native-cache-api-unavailable"})

    def test_invalid_actual_mobiledevice_alias_stops_before_compiler_or_discovery(self):
        import ci_swift_test_native as artifact_native
        fixtures = NativeTests()
        fixtures.setUp()
        self.addCleanup(fixtures.doCleanups)
        layout = fixtures.mobiledevice_layout()
        with fixtures.mobiledevice_policy(layout):
            host = fixtures.host()
            host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
            layout["source"].unlink()
            layout["source"].symlink_to(layout["target"], target_is_directory=True)
            state = {"host":host, "reason":None, "host_seconds":0.1}
            with self.harness(["--export-build", str(self.root)]) as (captured, execute), \
                    patch.object(artifact, "native_precheck", return_value=state), \
                    patch.object(runner, "emit_evidence") as evidence:
                captured.side_effect = AssertionError("compiler/discovery sentinel must not run")
                with self.assertRaisesRegex(ValueError, "incomplete before compilation: runtime-framework-alias-target-differs"):
                    runner.run_suites()
            captured.assert_not_called()
            execute.assert_not_called()
            self.assertFalse((self.root / artifact.MANIFEST).exists())
            preflight = next(call.kwargs for call in evidence.call_args_list if call.args == ("native-tool-preflight",))
            self.assertFalse(preflight["build_allowed"])
            self.assertEqual(preflight["host_status"], "complete")
            self.assertEqual(preflight["reason"], "runtime-framework-alias-target-differs")
            self.assertEqual(preflight["diagnostic"]["install_name"], str(layout["logical"]))
            artifact_native.validate_diagnostic(preflight["diagnostic"])

    def test_actual_mobiledevice_unsupported_weak_imports_stop_before_compiler_or_discovery(self):
        import ci_swift_test_native as artifact_native
        for scenario, reason in (("cache-only", "runtime-cache-only-dependency-unproven"),
                                 ("third-import", "runtime-path-outside-approved-roots")):
            with self.subTest(scenario=scenario):
                fixtures = NativeTests()
                fixtures.setUp()
                self.addCleanup(fixtures.doCleanups)
                layout = fixtures.weak_mobiledevice_layout(present=(True, scenario != "cache-only"))
                with fixtures.weak_mobiledevice_policy(layout):
                    host = fixtures.host()
                    host.tools["xctest"].write_bytes(image(dependencies=[(0xC, str(layout["logical"]))]))
                    if scenario == "cache-only":
                        host.cache_membership[str(layout["extension"])] = True
                    else:
                        layout["binary"].write_bytes(image(kind=6, subtype=0x80000002, dependencies=[
                            (artifact_native.WEAK, str(layout["device"])),
                            (artifact_native.WEAK, str(layout["extension"])),
                            (artifact_native.WEAK, str(layout["extension"].with_name("Unreviewed.dylib")))]))
                    state = {"host":host, "reason":None, "host_seconds":0.1}
                    with self.harness(["--export-build", str(self.root)]) as (captured, execute), \
                            patch.object(artifact, "native_precheck", return_value=state), \
                            patch.object(runner, "emit_evidence") as evidence:
                        captured.side_effect = AssertionError("compiler/discovery sentinel must not run")
                        with self.assertRaisesRegex(ValueError, "incomplete before compilation: " + reason):
                            runner.run_suites()
                    captured.assert_not_called()
                    execute.assert_not_called()
                    self.assertFalse((self.root / artifact.MANIFEST).exists())
                    preflight = next(call.kwargs for call in evidence.call_args_list
                                     if call.args == ("native-tool-preflight",))
                    self.assertFalse(preflight["build_allowed"])
                    self.assertEqual(preflight["host_status"], "complete")
                    self.assertEqual(preflight["reason"], reason)
                    artifact_native.validate_diagnostic(preflight["diagnostic"])

    def test_actual_internal_parent_escape_or_strong_miss_stops_before_compiler_and_discovery(self):
        import ci_swift_test_native as artifact_native
        for scenario, reason in (("escape", "runtime-rpath-link-escapes-root"),
                                 ("missing", "unresolved-runtime-dependency")):
            with self.subTest(scenario=scenario):
                fixtures = NativeTests()
                fixtures.setUp()
                self.addCleanup(fixtures.doCleanups)
                host, paths = fixtures.compiler_parent_suffix_layout()
                name = paths["base"] / "XcodeDefault"
                name.rmdir()
                if scenario == "escape":
                    name.symlink_to(fixtures.root / "private-user/secret", target_is_directory=True)
                state = {"host":host, "reason":None, "host_seconds":0.1}
                with self.harness(["--export-build", str(self.root)]) as (captured, execute), \
                        patch.object(artifact, "native_precheck", return_value=state), \
                        patch.object(runner, "emit_evidence") as evidence:
                    captured.side_effect = AssertionError("compiler/discovery sentinel must not run")
                    with self.assertRaisesRegex(ValueError, "incomplete before compilation: " + reason):
                        runner.run_suites()
                captured.assert_not_called()
                execute.assert_not_called()
                self.assertFalse((self.root / artifact.MANIFEST).exists())
                preflight = next(call.kwargs for call in evidence.call_args_list
                                 if call.args == ("native-tool-preflight",))
                self.assertFalse(preflight["build_allowed"])
                self.assertEqual(preflight["host_status"], "complete")
                self.assertEqual(preflight["reason"], reason)
                diagnostic = preflight["diagnostic"]
                self.assertTrue(diagnostic["rpath_join"]["path"].endswith("/" + paths["suffix"]))
                self.assertNotIn("private-user", json.dumps(diagnostic))
                artifact_native.validate_diagnostic(diagnostic)

    def test_full_profile_uses_same_skip_build_contract_before_cleanup(self):
        self.current["profile"] = "full"
        _, digest = self.export()
        with self.harness(["--use-build", str(self.root)]) as (captured, execute), \
                patch.dict(os.environ, {"CODEXBAR_TEST_BUILD_MANIFEST_SHA256": digest,
                                        "CODEXBAR_TEST_PROFILE": "full"}):
            self.assertEqual(runner.run_suites(), 0)
            self.assertEqual([call.args[0] for call in captured.call_args_list],
                             [["swift", "test", "list", "--skip-build"]])
            self.assertEqual(execute.call_count, 1)
            self.assertIn("--skip-build", execute.call_args.args[0])
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
