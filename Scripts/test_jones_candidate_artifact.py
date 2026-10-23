#!/usr/bin/env python3
"""Portable candidate/admission fixtures. Every Mac and Git command is a fake.

Affected check: python3 -B Scripts/test_jones_candidate_artifact.py
TemporaryDirectory owns the small per-test tree, including failure fixtures.
"""

import base64
from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
from dataclasses import replace
import io
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

import jones_candidate_admission as admission
import jones_candidate_artifact as candidate


REVISION = "a" * 40
MERGE_SHA = "b" * 40
RUN_URL = f"https://github.com/{candidate.REPOSITORY}/actions/runs/12345"
CONTEXT = candidate.Context(
    REVISION, "a" * 8, "0.56.4", "135.1234", 1234, "ci-main", RUN_URL, "push", "refs/heads/main",
    RUN_URL, "12345", "1", f"{candidate.REPOSITORY}/{candidate.WORKFLOW_PATH}@refs/heads/main", REVISION,
)
FIXTURE_PUBLIC_KEY = base64.b64encode(bytes(range(32))).decode("ascii")
MACHO = b"\xcf\xfa\xed\xfe" + b"synthetic-arm64-fixture"


def repository():
    return {"full_name": candidate.REPOSITORY, "id": int(candidate.REPOSITORY_ID),
            "default_branch": "main", "fork": False}


def event_fixture(event_name="push"):
    environment = {
        "GITHUB_ACTIONS": "true", "GITHUB_SERVER_URL": "https://github.com",
        "GITHUB_REPOSITORY": candidate.REPOSITORY, "GITHUB_REPOSITORY_ID": candidate.REPOSITORY_ID,
        "GITHUB_RUN_ID": "12345", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_EVENT_NAME": event_name,
        "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": REVISION, "GITHUB_WORKFLOW_SHA": REVISION,
    }
    event = {"repository": repository(), "ref": "refs/heads/main", "after": REVISION, "deleted": False}
    if event_name == "pull_request":
        environment.update(GITHUB_REF="refs/pull/21/merge", GITHUB_SHA=MERGE_SHA,
                           GITHUB_WORKFLOW_SHA=MERGE_SHA, GITHUB_HEAD_REF="work/update", GITHUB_BASE_REF="main")
        event.update(number=21, pull_request={"draft": False, "state": "open",
                                             "head": {"sha": REVISION, "ref": "work/update"},
                                             "base": {"ref": "main", "repo": repository()}})
    elif event_name == "workflow_dispatch":
        event = {"repository": repository(), "inputs": {}}
    environment["GITHUB_WORKFLOW_REF"] = f"{candidate.REPOSITORY}/{candidate.WORKFLOW_PATH}@{environment['GITHUB_REF']}"
    return environment, event


def plists(context=CONTEXT, channel="none"):
    shared = {
        "CFBundleShortVersionString": context.version, "CFBundleVersion": context.build,
        "JonesStateKey": "jones", "JonesAppBundleID": candidate.BUNDLE_ID,
        "JonesAppGroupID": candidate.APP_GROUP, "JonesICloudID": candidate.ICLOUD_ID,
        "JonesSourceRevision": context.revision, "JonesBuildOrigin": context.origin,
        "JonesBuildRun": context.build_run, "JonesUpdateChannel": channel,
    }
    app = dict(shared, CFBundleIdentifier=candidate.BUNDLE_ID, CFBundleDisplayName="CodexBar Jones",
               CFBundleExecutable="CodexBar", CFBundlePackageType="APPL", CodexBarTeamID="JONESLOCAL",
               CodexGitCommit=context.short_revision, CodexBuildTimestamp="2026-10-22T12:00:00Z", LSUIElement=True,
               SUFeedURL="", SUPublicEDKey="", SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
               SUAllowsAutomaticUpdates=False, SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
               SUSignedFeedFailureExpirationInterval=0)
    widget = dict(shared, CFBundleIdentifier=candidate.BUNDLE_ID + ".widget", CFBundleExecutable="CodexBarWidget")
    if channel == "stable":
        app.update(SUFeedURL=candidate.STABLE_FEED, SUPublicEDKey=FIXTURE_PUBLIC_KEY,
                   SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True, SUAllowsAutomaticUpdates=True)
    return app, widget


class RejectionAssertions:
    def rejects(self, code, function, *args, **kwargs):
        with self.assertRaises(candidate.CandidateError) as caught:
            function(*args, **kwargs)
        self.assertEqual(caught.exception.code, code)


class ContextTests(RejectionAssertions, unittest.TestCase):
    def test_only_exact_main_push_claims_ci_main(self):
        for event_name, origin in (("push", "ci-main"), ("pull_request", "ci-pr"), ("workflow_dispatch", "local")):
            with self.subTest(event=event_name):
                environment, event = event_fixture(event_name)
                self.assertEqual(candidate.validate_event(environment, event, REVISION), (origin, RUN_URL))

    def test_context_refuses_untrusted_repository_run_workflow_and_event(self):
        for field, value, code in (
            ("GITHUB_REPOSITORY_ID", "1", "ci-context"), ("GITHUB_REPOSITORY", "steipete/CodexBar", "ci-context"),
            ("GITHUB_SERVER_URL", "https://github.com.example.invalid", "ci-context"),
            ("GITHUB_RUN_ID", "123\nINJECTED=1", "ci-run"), ("GITHUB_RUN_ATTEMPT", "0", "ci-run"),
            ("GITHUB_SHA", "abc", "ci-revision"), ("GITHUB_WORKFLOW_SHA", "A" * 40, "ci-revision"),
            ("GITHUB_WORKFLOW_REF", "foreign/workflow.yml@refs/heads/main", "ci-workflow"),
            ("GITHUB_EVENT_NAME", "pull_request_target", "ci-event"),
        ):
            with self.subTest(field=field):
                environment, event = event_fixture()
                environment[field] = value
                self.rejects(code, candidate.validate_event, environment, event, REVISION)
        for field, value in (("id", True), ("id", "1425008735"), ("fork", True), ("default_branch", "master")):
            environment, event = event_fixture()
            event["repository"][field] = value
            self.rejects("ci-repository", candidate.validate_event, environment, event, REVISION)

    def test_pr_checks_actual_head_not_merge_commit_and_refuses_drafts(self):
        for edit in (
            lambda event: event["pull_request"].update(draft=True),
            lambda event: event["pull_request"].update(state="closed"),
            lambda event: event["pull_request"]["head"].update(sha=MERGE_SHA),
            lambda event: event["pull_request"]["base"].update(ref="work/other"),
            lambda event: event["pull_request"]["base"]["repo"].update(id=1),
            lambda event: event.update(number=True),
            lambda event: event.update(pull_request=[]),
        ):
            environment, event = event_fixture("pull_request")
            edit(event)
            self.rejects("ci-pr", candidate.validate_event, environment, event, REVISION)
        environment, event = event_fixture("pull_request")
        self.rejects("ci-pr", candidate.validate_event, environment, event, MERGE_SHA)

    def test_push_rejects_deletion_wrong_sha_and_other_branches(self):
        for field, value in (("deleted", True), ("after", MERGE_SHA), ("ref", "refs/heads/work/update")):
            environment, event = event_fixture()
            event[field] = value
            self.rejects("ci-main", candidate.validate_event, environment, event, REVISION)

    def test_dispatch_cannot_claim_push_origin_even_on_main(self):
        environment, event = event_fixture("workflow_dispatch")
        self.assertEqual(candidate.validate_event(environment, event, REVISION)[0], "local")
        environment["GITHUB_SHA"] = MERGE_SHA
        self.rejects("ci-dispatch", candidate.validate_event, environment, event, REVISION)

    def test_git_binding_rejects_dirty_shallow_and_moving_sources(self):
        with tempfile.TemporaryDirectory(prefix="jones-source-fixture-") as temporary:
            root = Path(temporary).resolve()
            (root / "version.env").write_text("MARKETING_VERSION=0.56.4\nBUILD_NUMBER=135\n", encoding="ascii")
            replies = {
                ("rev-parse", "--show-toplevel"): str(root),
                ("rev-parse", "--verify", "HEAD^{commit}"): REVISION,
                ("rev-parse", "--is-shallow-repository"): "false",
                ("status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none"): "",
                ("rev-list", "--first-parent", "--count", REVISION): "1234",
                ("rev-parse", "--short", REVISION): "a" * 8,
            }
            environment, event = event_fixture()
            with patch.object(candidate, "git", side_effect=lambda _root, *args: replies[args]):
                self.assertEqual(candidate.inspect_context(root, environment, event), CONTEXT)
                for arguments, value, code in (
                    (("rev-parse", "--is-shallow-repository"), "true", "source-shallow"),
                    (("status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none"),
                     "?? injected.swift", "source-dirty"),
                    (("rev-list", "--first-parent", "--count", REVISION), "0", "source-count"),
                ):
                    old = replies[arguments]
                    replies[arguments] = value
                    self.rejects(code, candidate.inspect_context, root, environment, event)
                    replies[arguments] = old
            heads = iter((REVISION, MERGE_SHA))
            with patch.object(candidate, "git", side_effect=lambda _root, *args:
                              next(heads) if args == ("rev-parse", "--verify", "HEAD^{commit}") else replies[args]):
                self.rejects("source-changed", candidate.inspect_context, root, environment, event)


class PlistTests(RejectionAssertions, unittest.TestCase):
    def test_bootstrap_and_stable_metadata_roundtrip(self):
        for channel in ("none", "stable"):
            app, widget = plists(channel=channel)
            candidate.validate_plists(plistlib.loads(plistlib.dumps(app)), widget, CONTEXT, channel)

    def test_every_identity_and_provenance_field_is_required_and_typed(self):
        app, widget = plists()
        for field in (
            "CFBundleIdentifier", "CFBundleDisplayName", "CFBundleVersion", "CFBundleShortVersionString",
            "JonesStateKey", "JonesAppBundleID", "JonesAppGroupID", "JonesICloudID", "CodexBarTeamID",
            "JonesSourceRevision", "JonesBuildOrigin", "JonesBuildRun", "JonesUpdateChannel", "CodexGitCommit",
        ):
            for value in (None, True, "other"):
                with self.subTest(field=field, value=value):
                    altered = dict(app, **{field: value})
                    self.rejects("plist-value", candidate.validate_plists, altered, widget, CONTEXT, "none")

    def test_boolean_and_integer_types_cannot_be_substituted(self):
        app, widget = plists()
        for field, value in (("SURequireSignedFeed", 1), ("SUVerifyUpdateBeforeExtraction", "true"),
                             ("SUEnableAutomaticChecks", 0), ("SUAutomaticallyUpdate", "false"),
                             ("SUAllowsAutomaticUpdates", None), ("SUSignedFeedFailureExpirationInterval", False)):
            with self.subTest(field=field):
                self.rejects("plist-value", candidate.validate_plists,
                             dict(app, **{field: value}), widget, CONTEXT, "none")

    def test_widget_version_source_and_identity_must_match_app(self):
        app, widget = plists()
        for field in ("CFBundleVersion", "CFBundleShortVersionString", "JonesSourceRevision", "JonesAppGroupID",
                      "JonesICloudID", "JonesBuildOrigin", "JonesBuildRun", "CFBundleIdentifier"):
            self.rejects("plist-value", candidate.validate_plists,
                         app, dict(widget, **{field: "other"}), CONTEXT, "none")

    def test_harness_flags_and_network_exceptions_rejected_even_when_false(self):
        for field in ("JonesUpdateHarness", "JonesUpdateHarnessFixtureID", "NSAppTransportSecurity",
                      "NSBonjourServices", "NSLocalNetworkUsageDescription"):
            for target in (0, 1):
                values = list(plists())
                values[target][field] = False
                self.rejects("production-isolation", candidate.validate_plists, *values, CONTEXT, "none")

    def test_stable_rejects_upstream_partial_key_and_disabled_security(self):
        app, widget = plists(channel="stable")
        for field, value, code in (
            ("SUFeedURL", "https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml", "plist-value"),
            ("SUFeedURL", "http://127.0.0.1/appcast.xml", "plist-value"),
            ("SUPublicEDKey", candidate.UPSTREAM_KEY, "update-key"),
            ("SUPublicEDKey", "", "update-key"), ("SUPublicEDKey", FIXTURE_PUBLIC_KEY + "\n", "update-key"),
            ("SUPublicEDKey", base64.b64encode(bytes(31)).decode(), "update-key"),
            ("SURequireSignedFeed", False, "plist-value"), ("SUVerifyUpdateBeforeExtraction", False, "plist-value"),
            ("SUSignedFeedFailureExpirationInterval", 1, "plist-value"),
        ):
            with self.subTest(field=field, value=value):
                self.rejects(code, candidate.validate_plists, dict(app, **{field: value}), widget, CONTEXT, "stable")

    def test_none_requires_empty_feed_and_key_and_valid_timestamp(self):
        app, widget = plists()
        for field in ("SUFeedURL", "SUPublicEDKey"):
            self.rejects("plist-value", candidate.validate_plists,
                         dict(app, **{field: "populated"}), widget, CONTEXT, "none")
        for timestamp in ("2026-02-30T12:00:00Z", "unknown", 1):
            self.rejects("plist-timestamp", candidate.validate_plists,
                         dict(app, CodexBuildTimestamp=timestamp), widget, CONTEXT, "none")


def make_bundle(root):
    bundle = root / "CodexBar.app"
    app, widget = plists()
    for relative, data in (("Contents/Info.plist", plistlib.dumps(app)),
                           ("Contents/PlugIns/CodexBarWidget.appex/Contents/Info.plist", plistlib.dumps(widget))):
        path = bundle / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for relative in (
        "Contents/MacOS/CodexBar", "Contents/Helpers/CodexBarCLI", "Contents/Helpers/CodexBarClaudeWatchdog",
        "Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget",
        "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
    ):
        path = bundle / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(MACHO)
        path.chmod(0o755)
    framework = bundle / "Contents/Frameworks/Sparkle.framework"
    (framework / "Versions/Current").symlink_to("B", target_is_directory=True)
    (framework / "Sparkle").symlink_to("Versions/Current/Sparkle")
    return bundle


def zip_bundle(bundle, archive):
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as handle:
        for path in [bundle, *sorted(bundle.rglob("*"))]:
            metadata = path.lstat()
            directory = stat.S_ISDIR(metadata.st_mode)
            name = path.relative_to(bundle.parent).as_posix() + ("/" if directory else "")
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = metadata.st_mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            content = b"" if directory else os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes()
            handle.writestr(info, content)


def extract_fixture(archive, destination):
    with zipfile.ZipFile(archive) as handle:
        for info in handle.infolist():
            path = destination / info.filename.rstrip("/")
            mode = info.external_attr >> 16
            path.parent.mkdir(parents=True, exist_ok=True)
            if stat.S_ISDIR(mode):
                path.mkdir(exist_ok=True)
            elif stat.S_ISLNK(mode):
                path.symlink_to(os.fsdecode(handle.read(info)))
                continue
            else:
                path.write_bytes(handle.read(info))
            path.chmod(stat.S_IMODE(mode))


class FakeMac:
    def __init__(self):
        self.calls = []
        self.arches = b"arm64\n"
        self.framework_arches = b"arm64\n"
        self.signature = "adhoc"
        self.entitlements_extra = {}
        self.fail_extract = False

    def __call__(self, arguments, **_kwargs):
        args = [str(value) for value in arguments]
        self.calls.append(args)
        stdout, stderr = b"", b""
        if args[0] == "/usr/bin/codesign":
            widget = args[-1].endswith(".appex")
            identifier = candidate.BUNDLE_ID + (".widget" if widget else "")
            if "--entitlements" in args:
                entitlements = {"com.apple.security.application-groups": [candidate.APP_GROUP]}
                if widget:
                    entitlements["com.apple.security.app-sandbox"] = True
                entitlements.update(self.entitlements_extra)
                stdout = plistlib.dumps(entitlements)
            elif "--display" in args:
                stderr = f"Identifier={identifier}\nSignature={self.signature}\nTeamIdentifier=not set\n".encode()
        elif args[0] == "/usr/bin/lipo":
            stdout = self.framework_arches if "/Sparkle.framework/" in args[-1] else self.arches
        elif args[0] == "/usr/bin/ditto":
            if "-c" in args:
                zip_bundle(Path(args[-2]), Path(args[-1]))
            elif self.fail_extract:
                raise candidate.CandidateError("fixture-extract", "Deliberate extraction failure")
            else:
                extract_fixture(Path(args[-2]), Path(args[-1]))
        else:
            raise AssertionError(f"Unexpected command: {args}")
        return subprocess.CompletedProcess(args, 0, stdout, stderr)


class ArtifactTests(RejectionAssertions, unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="jones-candidate-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle = make_bundle(self.root)
        self.mac = FakeMac()
        for patcher in (patch.object(candidate, "command", self.mac), patch.object(candidate.sys, "platform", "darwin"),
                        patch.object(candidate.os, "listxattr", return_value=[]),
                        patch.object(candidate.shutil, "disk_usage", return_value=Mock(free=5 * candidate.GIB))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_static_verification_checks_deep_seal_all_macho_and_entitlements(self):
        inspected, manifest = candidate.inspect_bundle(self.bundle, CONTEXT, "none")
        self.assertEqual(len(inspected["macho_files"]), 5)
        self.assertIn(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(self.bundle)],
                      self.mac.calls)
        self.assertEqual(manifest["CodexBar.app/Contents/MacOS/CodexBar"]["mode"], 0o755)
        self.mac.arches = b"arm64 x86_64\n"
        self.rejects("architecture", candidate.inspect_bundle, self.bundle, CONTEXT, "none")
        self.mac.arches = b"arm64\n"
        self.mac.framework_arches = b"arm64 x86_64\n"
        inspected, _ = candidate.inspect_bundle(self.bundle, CONTEXT, "none")
        framework = next(name for name in inspected["macho_architectures"] if "/Sparkle.framework/" in name)
        self.assertEqual(inspected["macho_architectures"][framework], ["arm64", "x86_64"])
        self.mac.framework_arches = b"x86_64\n"
        self.rejects("architecture", candidate.inspect_bundle, self.bundle, CONTEXT, "none")
        self.mac.framework_arches = b"arm64 arm64e\n"
        self.rejects("architecture", candidate.inspect_bundle, self.bundle, CONTEXT, "none")

    def test_rejects_non_adhoc_signatures_and_unexpected_entitlements(self):
        self.mac.signature = "Developer ID"
        self.rejects("signature-identity", candidate.inspect_bundle, self.bundle, CONTEXT, "none")
        self.mac.signature = "adhoc"
        self.mac.entitlements_extra = {"com.apple.security.get-task-allow": True}
        self.rejects("entitlements", candidate.inspect_bundle, self.bundle, CONTEXT, "none")

    def test_quarantine_failure_is_not_treated_as_absence(self):
        with patch.object(candidate.os, "listxattr", return_value=["com.apple.quarantine"]):
            self.rejects("quarantine", candidate.inspect_bundle, self.bundle, CONTEXT, "none")
        with patch.object(candidate.os, "listxattr", side_effect=OSError("fixture unavailable")):
            with self.assertRaises(OSError):
                candidate.inspect_bundle(self.bundle, CONTEXT, "none")

    def test_archive_roundtrip_preserves_modes_symlinks_and_exact_three_file_layout(self):
        output = self.root / "artifact"
        result = candidate.create_artifact(self.bundle, output, CONTEXT, "none")
        name = f"Jones-CodexBar-{REVISION}.zip"
        self.assertEqual(sorted(path.name for path in output.iterdir()),
                         sorted([name, name + ".sha256", "provenance.json"]))
        self.assertEqual((output / (name + ".sha256")).read_text(), f"{candidate.digest(output / name)}  {name}\n")
        self.assertEqual(json.loads((output / "provenance.json").read_text()), result)
        self.assertFalse(result["distribution"]["public_release"])
        self.assertFalse(result["distribution"]["installed_verification"])
        self.assertFalse(result["distribution"]["automatic_update_ready"])
        self.assertTrue(result["distribution"]["canonical_main_push"])
        sizes = result["artifact"]
        self.assertEqual(sizes["estimated_install_peak_bytes"],
                         sizes["archive_size_bytes"] + 2 * sizes["unpacked_size_bytes"] + candidate.GIB)
        self.assertEqual(list(self.root.glob(".jones-candidate-*")), [])

    def test_pr_and_dispatch_artifacts_are_diagnostic(self):
        for index, origin in enumerate(("ci-pr", "local")):
            context = replace(CONTEXT, origin=origin, build_run=RUN_URL if origin == "ci-pr" else "",
                              event_name="pull_request" if origin == "ci-pr" else "workflow_dispatch")
            app, widget = plists(context)
            (self.bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(app))
            widget_path = self.bundle / "Contents/PlugIns/CodexBarWidget.appex/Contents/Info.plist"
            widget_path.write_bytes(plistlib.dumps(widget))
            result = candidate.create_artifact(self.bundle, self.root / f"artifact-{index}", context, "none")
            self.assertTrue(result["distribution"]["diagnostic_only"])
            self.assertFalse(result["distribution"]["canonical_main_push"])

    def test_failure_cleans_only_its_scratch_and_preserves_original_error(self):
        sibling = self.root / ".jones-candidate-sibling"
        sibling.mkdir()
        (sibling / "keep").write_text("other invocation", encoding="ascii")
        self.mac.fail_extract = True
        self.rejects("fixture-extract", candidate.create_artifact, self.bundle, self.root / "artifact", CONTEXT, "none")
        self.assertEqual(sorted(self.root.glob(".jones-candidate-*")), [sibling])
        self.assertFalse((self.root / "artifact").exists())
        self.assertEqual((sibling / "keep").read_text(), "other invocation")

    def test_handled_cancellation_cleans_owned_scratch(self):
        previous = signal.getsignal(signal.SIGTERM)

        def cancel_extract(arguments, **kwargs):
            if arguments[0] == "/usr/bin/ditto" and "-x" in arguments:
                signal.raise_signal(signal.SIGTERM)
            return self.mac(arguments, **kwargs)

        with patch.object(candidate, "command", side_effect=cancel_extract), candidate.cancellation_cleanup():
            self.rejects("cancelled", candidate.create_artifact, self.bundle, self.root / "artifact", CONTEXT, "none")
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous)
        self.assertEqual(list(self.root.glob(".jones-candidate-*")), [])
        self.assertFalse((self.root / "artifact").exists())

    def test_foreign_output_and_bundle_symlinks_refused(self):
        output = self.root / "artifact"
        output.mkdir()
        self.rejects("output-exists", candidate.create_artifact, self.bundle, output, CONTEXT, "none")
        link_parent = self.root / "link-parent"
        link_parent.mkdir()
        alias = link_parent / "CodexBar.app"
        alias.symlink_to(self.bundle, target_is_directory=True)
        self.rejects("bundle-root", candidate.tree_manifest, alias)
        (self.bundle / "escape").symlink_to("../outside")
        (self.root / "outside").write_text("foreign", encoding="ascii")
        self.rejects("bundle-link", candidate.tree_manifest, self.bundle)

    def test_malformed_plist_is_typed(self):
        plist = self.bundle / "Contents/Info.plist"
        plist.write_bytes(b"<?xml version='1.0'?><plist><dict><key>")
        self.rejects("invalid-plist", candidate.read_plist, plist)

    def test_zip_rejects_traversal_second_root_and_mode_drift_before_extraction(self):
        manifest = candidate.tree_manifest(self.bundle)
        archive = self.root / "candidate.zip"
        for extra in ("../outside", "Other.app/file", "CodexBar.app/Contents/../../outside"):
            zip_bundle(self.bundle, archive)
            with zipfile.ZipFile(archive, "a") as handle:
                handle.writestr(extra, b"fixture")
            self.rejects("archive-layout", candidate.validate_zip, archive, manifest)
        zip_bundle(self.bundle, archive)
        altered = deepcopy(manifest)
        altered["CodexBar.app/Contents/MacOS/CodexBar"]["mode"] = 0o644
        self.rejects("archive-metadata", candidate.validate_zip, archive, altered)

    def test_oversized_and_empty_archive_are_rejected(self):
        archive = self.root / "candidate.zip"
        archive.write_bytes(b"")
        self.rejects("archive-size", candidate.validate_zip, archive, {})
        zip_bundle(self.bundle, archive)
        with patch.object(candidate, "MAX_ARCHIVE_BYTES", 1):
            self.rejects("archive-size", candidate.validate_zip, archive, candidate.tree_manifest(self.bundle))
        with patch.object(candidate, "MAX_UNPACKED_BYTES", 1):
            self.rejects("unpacked-size", candidate.validate_zip, archive, candidate.tree_manifest(self.bundle))

    def test_artifact_rechecks_storage_before_allocating_archive_scratch(self):
        with patch.object(candidate.shutil, "disk_usage", return_value=Mock(free=1)):
            self.rejects("archive-storage", candidate.create_artifact,
                         self.bundle, self.root / "artifact", CONTEXT, "none")
        self.assertFalse(any(arguments[0] == "/usr/bin/ditto" for arguments in self.mac.calls))
        self.assertEqual(list(self.root.glob(".jones-candidate-*")), [])


class CleanupAndCLITests(RejectionAssertions, unittest.TestCase):
    def test_cleanup_failure_preserves_primary_failure_and_fails_success(self):
        with tempfile.TemporaryDirectory(prefix="jones-cleanup-fixture-") as temporary:
            for fail_body in (False, True):
                stderr = io.StringIO()
                with redirect_stderr(stderr), patch.object(candidate.shutil, "rmtree", side_effect=OSError("fixture")):
                    with self.assertRaises(candidate.CandidateError) as caught:
                        with candidate.owned_scratch(Path(temporary)):
                            if fail_body:
                                raise candidate.CandidateError("primary", "original failure")
                self.assertEqual(caught.exception.code, "primary" if fail_body else "cleanup-failed")
                if fail_body:
                    self.assertTrue(json.loads(stderr.getvalue())["primary_error_preserved"])
            # TemporaryDirectory removes both deliberately retained fixture roots.

    def test_nested_invocations_own_distinct_scratch(self):
        with tempfile.TemporaryDirectory(prefix="jones-concurrent-fixture-") as temporary:
            with candidate.owned_scratch(Path(temporary)) as first:
                with candidate.owned_scratch(Path(temporary)) as second:
                    self.assertNotEqual(first, second)
                self.assertTrue(first.exists())
                self.assertFalse(second.exists())
            self.assertFalse(first.exists())

    def test_packager_missing_capabilities_is_a_typed_hold(self):
        with patch.object(candidate, "command", side_effect=candidate.CandidateError("command-failed", "baseline")):
            self.rejects("packager-contract", candidate.packager_contract, Path("/fixture"))
        valid = {
            "schema": "jones-candidate-packager/v1", "compiler_jobs_env": "CODEXBAR_BUILD_JOBS",
            "compiler_jobs_max": 6, "bounded_compilers": ["swift-build", "xcodebuild"],
            "resource_only_smoke_env": "CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY", "resource_only_smoke_value": "1",
        }
        with patch.object(candidate, "command", return_value=Mock(stdout=json.dumps(valid).encode())):
            self.assertEqual(candidate.packager_contract(Path("/fixture")), valid)
        for field, value in (("compiler_jobs_max", 7), ("bounded_compilers", ["swift-build"]),
                             ("resource_only_smoke_value", "0")):
            response = Mock(stdout=json.dumps(dict(valid, **{field: value})).encode())
            with patch.object(candidate, "command", return_value=response):
                self.rejects("packager-contract", candidate.packager_contract, Path("/fixture"))

    def test_real_packager_query_has_no_build_or_configuration_effects(self):
        repo = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="jones-packager-query-") as temporary:
            root = Path(temporary)
            scripts = root / "Scripts"
            scripts.mkdir()
            package = scripts / "package_app.sh"
            package.write_bytes((repo / "Scripts/package_app.sh").read_bytes())
            (root / "version.env").write_text("exit 91\n", encoding="ascii")
            (root / ".mac-release.jones.env").write_text("exit 92\n", encoding="ascii")
            before = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
            environment = {"PATH": str(root / "no-tools"), "CODEXBAR_SIGNING": "invalid"}
            result = subprocess.run(
                ["/bin/bash", str(package), "--jones-candidate-capabilities"],
                cwd=root, env=environment, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            capabilities = json.loads(result.stdout)
            self.assertEqual(capabilities["schema"], "jones-candidate-packager/v1")
            self.assertEqual(capabilities["compiler_jobs_max"], 6)
            self.assertEqual(capabilities["bounded_compilers"], ["swift-build", "xcodebuild"])
            self.assertEqual(capabilities["resource_only_smoke_value"], "1")
            extra = subprocess.run(
                ["/bin/bash", str(package), "--jones-candidate-capabilities", "release"],
                cwd=root, env=environment, capture_output=True, timeout=5)
            self.assertNotEqual(extra.returncode, 0)
            self.assertEqual(sorted(str(path.relative_to(root)) for path in root.rglob("*")), before)

    def test_cli_returns_json_rejection_without_traceback(self):
        stderr = io.StringIO()
        with patch.object(candidate, "inspect_context", side_effect=OSError("private path not printed")), \
                redirect_stderr(stderr):
            self.assertEqual(candidate.main(["context", "--repo", "/fixture"]), 1)
        rejection = json.loads(stderr.getvalue())
        self.assertEqual(rejection["code"], "invalid-input-or-io")
        self.assertNotIn("private path", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())


class AdmissionTests(RejectionAssertions, unittest.TestCase):
    def setUp(self):
        self.volumes = [{"available_bytes": 20 * candidate.GIB,
                         "estimated_additional_peak_bytes": 11 * candidate.GIB, "reserve_bytes": 2 * candidate.GIB}]

    def decide(self, **changes):
        values = dict(cpu=20, cores=8, total_memory=16 * candidate.GIB, available_memory=8 * candidate.GIB,
                      pressure=1, volumes=self.volumes, requested_jobs=6)
        values.update(changes)
        return admission.decide(**values)

    def test_admits_one_serial_process_with_at_most_six_jobs(self):
        result = self.decide()
        self.assertEqual(result["start_ceiling"], 1)
        self.assertEqual(result["compiler_jobs"], 6)
        self.assertEqual(result["one_core_whole_host_percent"], 12.5)
        self.assertEqual(self.decide(cores=3)["compiler_jobs"], 3)

    def test_busy_cpu_memory_pressure_and_storage_each_hold(self):
        for values in ({"cpu": 85}, {"cpu": 100}, {"pressure": 2}, {"pressure": 4},
                       {"available_memory": admission.MIN_MEMORY_BYTES - 1},
                       {"volumes": [dict(self.volumes[0], available_bytes=13 * candidate.GIB - 1)]}):
            with self.subTest(values=values):
                self.assertEqual(self.decide(**values)["start_ceiling"], 0)
        self.assertEqual(self.decide(cpu=84.99)["start_ceiling"], 1)

    def test_missing_or_malformed_evidence_never_admits(self):
        for values, code in (({"cpu": None}, "cpu-unknown"), ({"cpu": float("nan")}, "cpu-unknown"),
                             ({"cpu": True}, "cpu-unknown"), ({"cores": 0}, "cpu-unknown"),
                             ({"available_memory": None}, "memory-unknown"), ({"pressure": 0}, "pressure-unknown"),
                             ({"requested_jobs": 7}, "compiler-jobs"), ({"volumes": []}, "storage-unknown"),
                             ({"volumes": [{"available_bytes": True}]}, "storage-unknown")):
            self.rejects(code, self.decide, **values)

    def test_cpu_uses_second_interval_and_memory_excludes_speculative_claims(self):
        text = "CPU usage: 90.0% user, 5.0% sys, 5.0% idle\nCPU usage: 12.0% user, 8.0% sys, 80.0% idle\n"
        self.assertEqual(admission.parse_cpu(text), 20.0)
        self.rejects("cpu-unknown", admission.parse_cpu, "CPU usage: 0% user, 0% sys, 100% idle")
        vm = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 100.\nPages inactive: 200.\n"
        self.assertEqual(admission.parse_memory(vm, candidate.GIB), 300 * 16384)
        self.rejects("memory-unknown", admission.parse_memory, vm.replace("Pages free", "Pages unknown"), candidate.GIB)

    def test_shared_filesystem_budgets_are_added_once_with_one_reserve(self):
        with tempfile.TemporaryDirectory(prefix="jones-storage-fixture-") as temporary:
            root = Path(temporary)
            with patch.object(admission.shutil, "disk_usage", return_value=Mock(free=14 * candidate.GIB)):
                volumes = admission.storage_observations(root, root / "scratch", root / "cache")
            self.assertEqual(len(volumes), 1)
            self.assertEqual(volumes[0]["estimated_additional_peak_bytes"], 14 * candidate.GIB)
            self.assertEqual(volumes[0]["reserve_bytes"], 2 * candidate.GIB)
            self.assertEqual(len(volumes[0]["destinations"]), 3)

    def test_unknown_telemetry_cli_fails_with_numeric_zero_start_ceiling(self):
        stderr = io.StringIO()
        with patch.object(admission, "sample", side_effect=candidate.CandidateError("cpu-unknown", "unavailable")), \
                redirect_stderr(stderr):
            self.assertEqual(admission.main(["--workspace", "/fixture", "--scratch", "/fixture/scratch"]), 1)
        self.assertEqual(json.loads(stderr.getvalue())["start_ceiling"], 0)

    def test_held_admission_never_writes_jobs_output(self):
        with tempfile.TemporaryDirectory(prefix="jones-jobs-fixture-") as temporary:
            output = Path(temporary) / "jobs"
            with patch.object(admission, "sample", return_value=self.decide(cpu=85)), redirect_stdout(io.StringIO()):
                status = admission.main(
                    ["--workspace", temporary, "--scratch", temporary, "--jobs-output", str(output)])
            self.assertEqual(status, 1)
            self.assertFalse(output.exists())


class WorkflowContractTests(unittest.TestCase):
    def test_candidate_workflow_has_only_existing_pins_read_permission_and_hosted_runner(self):
        source = (Path(__file__).resolve().parent.parent / candidate.WORKFLOW_PATH).read_text(encoding="utf-8")
        uses = re.findall(r"uses:\s+(\S+)", source)
        self.assertEqual(uses, ["actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0",
                               "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
                               "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"])
        self.assertIn("permissions:\n  contents: read", source)
        self.assertIn("runs-on: macos-26", source)
        self.assertIn("fetch-depth: 0", source)
        self.assertIn("persist-credentials: false", source)
        self.assertIn("ref: ${{ github.event.pull_request.head.sha || github.sha }}", source)
        self.assertIn("retention-days: 14", source)
        self.assertIn("if-no-files-found: error", source)
        for forbidden in ("secrets.", "self-hosted", "sudo ", "pull_request_target", "continue-on-error", "gh release"):
            self.assertNotIn(forbidden, source)
        self.assertIn("CODEXBAR_SKIP_LAUNCH_SMOKE: '0'", source)
        self.assertIn("CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY: '1'", source)
        self.assertIn("CODEXBAR_RESOURCE_SMOKE: '1'", source)
        package = source.index("Scripts/package_app.sh release")
        self.assertLess(source.index("jones_candidate_artifact.py check-packager"), package)
        self.assertLess(source.index('--jobs-output "$candidate_scratch/compiler-jobs"'), package)
        self.assertIn("xcrun swiftc -j 1", source)
        self.assertIn("Scripts/jones_update_harness.py run", source)
        self.assertIn(".build/jones-update-fixture/fixture.json", source)
        self.assertIn(".com.jonessystems.codexbar.update-harness.lock", source)


if __name__ == "__main__":
    with candidate.cancellation_cleanup():
        unittest.main()
