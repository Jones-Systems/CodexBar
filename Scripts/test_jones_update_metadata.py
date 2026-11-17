#!/usr/bin/env python3
"""Portable public-metadata fixtures, including one small owned local Git repository."""

import base64
from copy import deepcopy
from dataclasses import replace
import io
import hashlib
from datetime import datetime, timezone
from types import SimpleNamespace
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import jones_update_metadata as metadata
import jones_signing as signing
import jones_sign_and_notarize as signing_operation


REVISION = "a" * 40
MERGE_REVISION = "b" * 40
FIXTURE_KEY = base64.b64encode(bytes(range(32))).decode("ascii")
SOURCE = metadata.SourceRevision(REVISION, "1234")
ROOT = Path(__file__).resolve().parent.parent


def repository():
    return {"full_name": metadata.REPOSITORY, "id": int(metadata.REPOSITORY_ID),
            "default_branch": "main", "fork": False}


def ci_fixture(origin="ci-main"):
    environment = {
        "GITHUB_ACTIONS": "true", "GITHUB_SERVER_URL": "https://github.com",
        "GITHUB_REPOSITORY": metadata.REPOSITORY, "GITHUB_REPOSITORY_ID": metadata.REPOSITORY_ID,
        "GITHUB_RUN_ID": "12345", "GITHUB_EVENT_NAME": "push",
        "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": REVISION,
    }
    event = {"repository": repository(), "ref": "refs/heads/main", "after": REVISION, "deleted": False}
    if origin == "ci-pr":
        environment.update(GITHUB_EVENT_NAME="pull_request", GITHUB_REF="refs/pull/21/merge",
                           GITHUB_SHA=MERGE_REVISION, GITHUB_HEAD_REF="work/update", GITHUB_BASE_REF="main")
        event = {
            "repository": repository(), "number": 21,
            "pull_request": {
                "head": {"sha": REVISION, "ref": "work/update"},
                "base": {"ref": "main", "repo": repository()},
            },
        }
    return environment, event


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.stable = metadata.UpdateConfiguration("stable", metadata.STABLE_FEED_URL, FIXTURE_KEY)

    def test_bootstrap_disables_every_automatic_control_with_typed_values(self):
        result = metadata.UpdateConfiguration().metadata()
        self.assertEqual(result["JonesUpdateChannel"], "none")
        self.assertEqual(result["SUFeedURL"], "")
        self.assertEqual(result["SUPublicEDKey"], "")
        for key in ("SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates"):
            self.assertIs(result[key], False)
        self.assertIs(result["SURequireSignedFeed"], True)
        self.assertIs(result["SUVerifyUpdateBeforeExtraction"], True)
        self.assertEqual(result["SUSignedFeedFailureExpirationInterval"], 0)
        self.assertIs(type(result["SUSignedFeedFailureExpirationInterval"]), int)

    def test_stable_requires_both_authenticated_feed_and_archive_verification(self):
        result = self.stable.metadata()
        self.assertEqual(result["SUFeedURL"], metadata.STABLE_FEED_URL)
        self.assertEqual(result["SUPublicEDKey"], FIXTURE_KEY)
        for key in ("SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates",
                    "SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
            self.assertIs(result[key], True)
        self.assertEqual(result["SUSignedFeedFailureExpirationInterval"], 0)

    def test_no_partial_or_unknown_channel_configuration(self):
        invalid = (
            metadata.UpdateConfiguration("none", metadata.STABLE_FEED_URL, ""),
            metadata.UpdateConfiguration("none", "", FIXTURE_KEY),
            metadata.UpdateConfiguration("none", metadata.STABLE_FEED_URL, FIXTURE_KEY),
            metadata.UpdateConfiguration("stable"),
            replace(self.stable, feed_url=""), replace(self.stable, public_ed_key=""),
            replace(self.stable, channel="beta"), replace(self.stable, channel=""),
        )
        for configuration in invalid:
            with self.subTest(configuration=configuration), self.assertRaises(metadata.MetadataError):
                configuration.metadata()

    def test_stable_feed_is_exact_canonical_https_release_location(self):
        invalid = (
            "https://raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml",
            "https://github.com/steipete/CodexBar/releases/latest/download/appcast.xml",
            "https://steipete.me/appcast.xml", "https://example.com/Jones-Systems/CodexBar/appcast.xml",
            "http://127.0.0.1:1234/appcast.xml", "https://localhost/appcast.xml",
            metadata.STABLE_FEED_URL.replace("https:", "http:"),
            metadata.STABLE_FEED_URL.replace("github.com", "github.com.example.com"),
            metadata.STABLE_FEED_URL.replace("github.com", "user@github.com"),
            metadata.STABLE_FEED_URL.replace("github.com", "github.com:443"),
            metadata.STABLE_FEED_URL.replace("Jones-Systems", "%4Aones-Systems"),
            metadata.STABLE_FEED_URL.replace("/CodexBar/", "/CodexBar-other/"),
            metadata.STABLE_FEED_URL + "?feed=other", metadata.STABLE_FEED_URL + "#other",
            metadata.STABLE_FEED_URL + "/", " " + metadata.STABLE_FEED_URL,
            metadata.STABLE_FEED_URL.replace("/latest/", "/download/v1/"),
        )
        for feed_url in invalid:
            with self.subTest(feed_url=feed_url), self.assertRaises(metadata.MetadataError):
                replace(self.stable, feed_url=feed_url).validate()

    def test_public_key_rejects_upstream_wrong_lengths_and_noncanonical_base64(self):
        invalid = (
            metadata.UPSTREAM_PUBLIC_ED_KEY, "AGCY...", "", "not-a-key",
            base64.b64encode(bytes(31)).decode(), base64.b64encode(bytes(33)).decode(),
            FIXTURE_KEY.rstrip("="), FIXTURE_KEY + "=", FIXTURE_KEY + "\n", " " + FIXTURE_KEY,
            FIXTURE_KEY[:-2] + "9=", "é" * 43 + "=", "_" * 43 + "=",
        )
        for public_ed_key in invalid:
            with self.subTest(public_ed_key=public_ed_key), self.assertRaises(metadata.MetadataError):
                replace(self.stable, public_ed_key=public_ed_key).validate()

    def test_exact_production_identity_and_derived_state_contract(self):
        for key, value in (
            ("bundle_id", "com.steipete.codexbar"), ("bundle_id", metadata.BUNDLE_ID + ".update-harness"),
            ("team_id", "Y5PE65HELJ"), ("team_id", "REPLACE_WITH_YOUR_TEAM"),
            ("state_key", "unknown"), ("state_key", ""), ("display_name", "CodexBar"),
            ("app_group_id", "OTHER." + metadata.BUNDLE_ID), ("icloud_id", "iCloud.com.steipete.codexbar"),
        ):
            with self.subTest(key=key, value=value), self.assertRaises(metadata.MetadataError):
                replace(self.stable, **{key: value}).validate()
        result = self.stable.metadata()
        self.assertEqual(result["JonesAppGroupID"], "JONESLOCAL.com.jonessystems.codexbar")
        self.assertEqual(result["JonesICloudID"], "iCloud.com.jonessystems.codexbar")

    def test_plist_roundtrip_preserves_boolean_types_and_has_no_harness_or_network_exception(self):
        for configuration in (metadata.UpdateConfiguration(), self.stable):
            with self.subTest(channel=configuration.channel):
                result = configuration.metadata()
                rendered = plistlib.dumps(result)
                self.assertEqual(plistlib.loads(rendered), result)
                for forbidden in (b"JonesUpdateHarness", b"NSAppTransportSecurity", b"localhost", b"127.0.0.1"):
                    self.assertNotIn(forbidden, rendered)


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.outputs = {
            ("rev-parse", "--show-toplevel"): str(ROOT),
            ("rev-parse", "--verify", "HEAD^{commit}"): REVISION,
            ("rev-parse", "--is-shallow-repository"): "false",
            ("status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none"): "",
            ("rev-list", "--first-parent", "--count", REVISION): "1234",
        }
        self.git = Mock(side_effect=lambda repo, *args: self.outputs[args])

    def inspect(self):
        with patch.object(metadata, "git_output", self.git):
            return metadata.inspect_source(ROOT)

    def test_clean_full_source_uses_first_parent_count_and_checks_head_again(self):
        self.assertEqual(self.inspect(), SOURCE)
        revisions = [call for call in self.git.call_args_list if call.args[1:] == (
            "rev-parse", "--verify", "HEAD^{commit}")]
        self.assertEqual(len(revisions), 2)
        self.git.assert_any_call(ROOT, "rev-list", "--first-parent", "--count", REVISION)

    def test_shallow_or_unknown_history_is_refused_before_count(self):
        for value in ("true", "", "unknown"):
            with self.subTest(value=value):
                self.outputs[("rev-parse", "--is-shallow-repository")] = value
                self.git.reset_mock()
                with self.assertRaisesRegex(metadata.MetadataError, "full Git history"):
                    self.inspect()
                self.assertFalse(any(call.args[1] == "rev-list" for call in self.git.call_args_list))

    def test_dirty_index_worktree_or_submodule_is_refused(self):
        status_args = ("status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none")
        for status in (" M tracked.swift", "M  tracked.swift", " D tracked.swift", " M submodule", "?? Extra.swift"):
            with self.subTest(status=status):
                self.outputs[status_args] = status
                with self.assertRaisesRegex(metadata.MetadataError, "dirty or untracked"):
                    self.inspect()

    def test_real_git_rejects_untracked_source_without_rejecting_ignored_build_output(self):
        scratch = Path(os.environ.get("CODEXBAR_TEST_SCRATCH_PARENT", str(ROOT / ".build")))
        self.assertTrue(scratch.is_absolute() and ROOT in scratch.parents and scratch.resolve() == scratch)
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".jones-provenance-fixture-", dir=scratch) as temporary:
            repo = Path(temporary)

            def git(*arguments):
                return subprocess.run(
                    ["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                     "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                     "-C", str(repo), *arguments],
                    check=True, capture_output=True, text=True, timeout=15,
                ).stdout.strip()

            git("init", "--quiet", "--initial-branch=fixture")
            (repo / ".gitignore").write_text(".build/\n")
            (repo / "Sources").mkdir()
            (repo / "Sources/Tracked.swift").write_text("let tracked = 1\n")
            git("add", ".gitignore", "Sources/Tracked.swift")
            git("commit", "--quiet", "-m", "fixture")
            expected = git("rev-parse", "HEAD")
            (repo / ".build").mkdir()
            (repo / ".build/artifact").write_bytes(b"owned fixture")
            self.assertEqual(metadata.inspect_source(repo), metadata.SourceRevision(expected, "1"))
            (repo / "Sources/Extra.swift").write_text("let untracked = 2\n")
            with self.assertRaisesRegex(metadata.MetadataError, "dirty or untracked"):
                metadata.inspect_source(repo)

    def test_non_root_repository_or_abbreviated_revision_is_refused(self):
        self.outputs[("rev-parse", "--show-toplevel")] = str(ROOT.parent)
        with self.assertRaisesRegex(metadata.MetadataError, "repository root"):
            self.inspect()
        self.outputs[("rev-parse", "--show-toplevel")] = str(ROOT)
        for revision in ("abc1234", "A" * 40, "g" * 40):
            with self.subTest(revision=revision):
                self.outputs[("rev-parse", "--verify", "HEAD^{commit}")] = revision
                with self.assertRaisesRegex(metadata.MetadataError, "complete lowercase"):
                    self.inspect()

    def test_unknown_or_invalid_count_is_refused(self):
        for count in ("", "0", "01", "-1", "1.2", "12\n13"):
            with self.subTest(count=count):
                self.outputs[("rev-list", "--first-parent", "--count", REVISION)] = count
                with self.assertRaisesRegex(metadata.MetadataError, "positive integer"):
                    self.inspect()

    def test_changed_head_during_snapshot_is_refused(self):
        heads = iter((REVISION, MERGE_REVISION))

        def git(repo, *arguments):
            if arguments == ("rev-parse", "--verify", "HEAD^{commit}"):
                return next(heads)
            return self.outputs[arguments]

        with patch.object(metadata, "git_output", side_effect=git):
            with self.assertRaisesRegex(metadata.MetadataError, "changed while"):
                metadata.inspect_source(ROOT)

    def test_git_reader_does_not_follow_inherited_repository_or_replacement_environment(self):
        with patch.dict(metadata.os.environ, {"GIT_DIR": "/synthetic/foreign", "GIT_INDEX_FILE": "foreign",
                                             "GIT_REPLACE_REF_BASE": "foreign"}):
            with patch.object(metadata.subprocess, "run", return_value=Mock(stdout=REVISION + "\n")) as run:
                self.assertEqual(metadata.git_output(ROOT, "rev-parse", "HEAD"), REVISION)
        command = run.call_args.args[0]
        self.assertEqual(command, ["git", "--no-optional-locks", "-C", str(ROOT), "rev-parse", "HEAD"])
        environment = run.call_args.kwargs["env"]
        self.assertNotIn("GIT_DIR", environment)
        self.assertNotIn("GIT_INDEX_FILE", environment)
        self.assertNotIn("GIT_REPLACE_REF_BASE", environment)
        self.assertEqual(environment["GIT_NO_REPLACE_OBJECTS"], "1")
        self.assertEqual(environment["GIT_OPTIONAL_LOCKS"], "0")

    def test_git_failure_becomes_bounded_diagnostic(self):
        for error in (OSError("unavailable"), subprocess.CalledProcessError(1, "git", stderr="private path")):
            with self.subTest(error=type(error)), patch.object(metadata.subprocess, "run", side_effect=error):
                with self.assertRaisesRegex(metadata.MetadataError, "Cannot read Jones source") as caught:
                    metadata.git_output(ROOT, "rev-parse", "HEAD")
                self.assertNotIn("private path", str(caught.exception))


class ProvenanceTests(unittest.TestCase):
    def test_local_default_uses_full_revision_empty_run_and_monotonic_base_count(self):
        result = metadata.provenance_metadata(SOURCE, "135", environment=ci_fixture()[0])
        self.assertEqual(result, {"CFBundleVersion": "135.1234", "JonesSourceRevision": REVISION,
                                  "JonesBuildOrigin": "local", "JonesBuildRun": ""})
        following = metadata.provenance_metadata(replace(SOURCE, first_parent_count="1235"), "135")
        self.assertGreater(tuple(map(int, following["CFBundleVersion"].split("."))),
                           tuple(map(int, result["CFBundleVersion"].split("."))))
        self.assertGreater(tuple(map(int, result["CFBundleVersion"].split("."))), (135,))

    def test_local_run_claim_and_unknown_origin_are_refused(self):
        with self.assertRaisesRegex(metadata.MetadataError, "empty build run"):
            metadata.provenance_metadata(SOURCE, "135", build_run="https://example.com/run")
        for origin in ("ci", "main", "", "CI-main"):
            with self.subTest(origin=origin), self.assertRaises(metadata.MetadataError):
                metadata.provenance_metadata(SOURCE, "135", origin)

    def test_invalid_build_inputs_are_refused(self):
        for build_number in ("0", "01", "-1", "135.1", "135\n", ""):
            with self.subTest(build_number=build_number), self.assertRaises(metadata.MetadataError):
                metadata.provenance_metadata(SOURCE, build_number)
        for source in (replace(SOURCE, revision="a" * 7), replace(SOURCE, first_parent_count="0")):
            with self.subTest(source=source), self.assertRaises(metadata.MetadataError):
                metadata.provenance_metadata(source, "135")

    def test_ci_main_records_exact_canonical_push_and_derived_run(self):
        environment, event = ci_fixture()
        result = metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)
        self.assertEqual(result["JonesBuildOrigin"], "ci-main")
        self.assertEqual(result["JonesBuildRun"], "https://github.com/Jones-Systems/CodexBar/actions/runs/12345")

    def test_ci_context_cannot_be_claimed_with_origin_flag_alone(self):
        with self.assertRaisesRegex(metadata.MetadataError, "repository context"):
            metadata.provenance_metadata(SOURCE, "135", "ci-main")
        for key in ("GITHUB_ACTIONS", "GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_REPOSITORY_ID"):
            with self.subTest(key=key):
                environment, event = ci_fixture()
                environment[key] = "foreign"
                with self.assertRaisesRegex(metadata.MetadataError, "repository context"):
                    metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)

    def test_ci_main_rejects_non_main_non_push_or_mismatched_revision(self):
        for key, value in (("GITHUB_EVENT_NAME", "pull_request_target"), ("GITHUB_EVENT_NAME", "workflow_dispatch"),
                           ("GITHUB_REF", "refs/heads/work/update"), ("GITHUB_SHA", MERGE_REVISION)):
            with self.subTest(key=key, value=value):
                environment, event = ci_fixture()
                environment[key] = value
                with self.assertRaisesRegex(metadata.MetadataError, "canonical main push"):
                    metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)
        for key, value in (("after", MERGE_REVISION), ("ref", "refs/tags/v1"), ("deleted", True), ("deleted", None)):
            with self.subTest(key=key, value=value):
                environment, event = ci_fixture()
                event[key] = value
                with self.assertRaisesRegex(metadata.MetadataError, "canonical main push"):
                    metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)

    def test_ci_pr_uses_the_pr_head_not_the_synthetic_merge_revision(self):
        environment, event = ci_fixture("ci-pr")
        result = metadata.provenance_metadata(SOURCE, "135", "ci-pr", environment=environment, event=event)
        self.assertEqual(result["JonesSourceRevision"], REVISION)
        self.assertEqual(result["JonesBuildOrigin"], "ci-pr")
        with self.assertRaisesRegex(metadata.MetadataError, "exact PR head"):
            metadata.provenance_metadata(replace(SOURCE, revision=MERGE_REVISION), "135", "ci-pr",
                                         environment=environment, event=event)

    def test_ci_pr_rejects_wrong_event_ref_head_or_base(self):
        for key, value in (("GITHUB_EVENT_NAME", "pull_request_target"), ("GITHUB_REF", "refs/heads/main"),
                           ("GITHUB_HEAD_REF", "foreign"), ("GITHUB_BASE_REF", "foreign")):
            with self.subTest(key=key):
                environment, event = ci_fixture("ci-pr")
                environment[key] = value
                with self.assertRaises(metadata.MetadataError):
                    metadata.provenance_metadata(SOURCE, "135", "ci-pr", environment=environment, event=event)
        environment, original = ci_fixture("ci-pr")
        for mutation in (lambda e: e.update(number=True), lambda e: e.update(number=22),
                         lambda e: e["pull_request"].update(head=None),
                         lambda e: e["pull_request"]["base"].update(ref="foreign"),
                         lambda e: e["pull_request"]["base"]["repo"].update(id=1)):
            event = deepcopy(original)
            mutation(event)
            with self.subTest(event=event), self.assertRaises(metadata.MetadataError):
                metadata.provenance_metadata(SOURCE, "135", "ci-pr", environment=environment, event=event)

    def test_ci_requires_canonical_event_repository_and_run(self):
        for key, value in (("full_name", "steipete/CodexBar"), ("id", 1), ("default_branch", "other"), ("fork", True)):
            with self.subTest(key=key):
                environment, event = ci_fixture()
                event["repository"][key] = value
                with self.assertRaises(metadata.MetadataError):
                    metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)
        for run_id in ("", "0", "01", "123/attempts/2", "123\n"):
            with self.subTest(run_id=run_id):
                environment, event = ci_fixture()
                environment["GITHUB_RUN_ID"] = run_id
                with self.assertRaises(metadata.MetadataError):
                    metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)
        environment, event = ci_fixture()
        with self.assertRaisesRegex(metadata.MetadataError, "does not match"):
            metadata.provenance_metadata(SOURCE, "135", "ci-main", "https://github.com/other/run",
                                         environment, event)

    def test_missing_unreadable_or_malformed_ci_event_is_refused(self):
        with self.assertRaises(metadata.MetadataError):
            metadata.load_ci_event({})
        for content in ("{", "[]", "null"):
            with self.subTest(content=content), patch.object(Path, "read_text", return_value=content):
                with self.assertRaises(metadata.MetadataError):
                    metadata.load_ci_event({"GITHUB_EVENT_PATH": "/synthetic/event.json"})
        with patch.object(Path, "read_text", side_effect=OSError("missing")):
            with self.assertRaises(metadata.MetadataError):
                metadata.load_ci_event({"GITHUB_EVENT_PATH": "/synthetic/event.json"})


class CLITests(unittest.TestCase):
    def invoke(self, arguments, environment=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        status = metadata.main(arguments, environment={} if environment is None else environment,
                               stdout=stdout, stderr=stderr)
        return status, stdout.getvalue(), stderr.getvalue()

    def test_validate_is_pure_and_json_is_the_default(self):
        with patch.object(metadata, "inspect_source") as inspect:
            status, output, error = self.invoke(["validate"])
        inspect.assert_not_called()
        self.assertEqual((status, error), (0, ""))
        self.assertEqual(json.loads(output), metadata.UpdateConfiguration().metadata())

    def test_invalid_configuration_has_no_metadata_output_or_git_reads(self):
        with patch.object(metadata, "inspect_source") as inspect:
            status, output, error = self.invoke(["metadata", "--repo", str(ROOT), "--build-number", "135",
                                                 "--channel", "stable"])
        inspect.assert_not_called()
        self.assertEqual((status, output), (1, ""))
        self.assertTrue(error.startswith("ERROR: "))

    def test_metadata_outputs_json_plist_and_safe_shell_assignments(self):
        arguments = ["metadata", "--repo", str(ROOT), "--build-number", "135"]
        with patch.object(metadata, "inspect_source", return_value=SOURCE):
            for output_format in ("json", "plist", "shell"):
                with self.subTest(output_format=output_format):
                    status, output, error = self.invoke(arguments + ["--format", output_format])
                    self.assertEqual((status, error), (0, ""))
                    if output_format == "shell":
                        values = dict(assignment.split("=", 1) for assignment in shlex.split(output))
                        self.assertEqual(set(values), {"BUILD_NUMBER", "JONES_SOURCE_REVISION", "JONES_BUILD_ORIGIN",
                                                       "JONES_BUILD_RUN", "JONES_PROVENANCE_METADATA"})
                        self.assertEqual(values["BUILD_NUMBER"], "135.1234")
                        self.assertEqual(values["JONES_SOURCE_REVISION"], REVISION)
                        fragment = "<plist><dict>" + values["JONES_PROVENANCE_METADATA"] + "</dict></plist>"
                        self.assertEqual(plistlib.loads(fragment.encode()), {
                            "JonesSourceRevision": REVISION, "JonesBuildOrigin": "local", "JonesBuildRun": ""})
                    else:
                        values = json.loads(output) if output_format == "json" else plistlib.loads(output.encode())
                        self.assertEqual(values["CFBundleVersion"], "135.1234")
                        self.assertEqual(values["JonesSourceRevision"], REVISION)
                        self.assertIs(values["SUAutomaticallyUpdate"], False)

    def test_source_refusal_has_no_partial_stdout(self):
        with patch.object(metadata, "inspect_source", side_effect=metadata.MetadataError("dirty tracked source")):
            status, output, error = self.invoke(["metadata", "--repo", str(ROOT), "--build-number", "135"])
        self.assertEqual((status, output), (1, ""))
        self.assertIn("dirty tracked", error)

    def test_ci_metadata_reads_only_the_supplied_event_fixture(self):
        environment, event = ci_fixture()
        environment["GITHUB_EVENT_PATH"] = "/synthetic/event.json"
        with patch.object(metadata, "inspect_source", return_value=SOURCE):
            with patch.object(Path, "read_text", return_value=json.dumps(event)) as read:
                status, output, error = self.invoke(
                    ["metadata", "--repo", str(ROOT), "--build-number", "135", "--origin", "ci-main"], environment)
        self.assertEqual((status, error), (0, ""))
        read.assert_called_once_with(encoding="utf-8")
        self.assertEqual(json.loads(output)["JonesBuildOrigin"], "ci-main")

    def test_package_preflight_precedes_build_effects_and_app_widget_share_version(self):
        source = (ROOT / "Scripts/package_app.sh").read_text()
        preflight = source.index("\nprepare_jones_update_metadata #")
        for effect in ("\n# Clean build", "\npatch_keyboard_shortcuts\n", "\nPRODUCT_STAGE_ROOT=", "\nAPP_FINAL="):
            self.assertLess(preflight, source.index(effect))
        self.assertIn('<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>', source)
        self.assertIn('CURRENT_PROJECT_VERSION="$BUILD_NUMBER"', source)


class PreparationHookTests(unittest.TestCase):
    def invoke(self, helper_body, overlay="1"):
        source = (ROOT / "Scripts/package_app.sh").read_text()
        function = re.search(r"^prepare_jones_update_metadata\(\) \{\n.*?^\}", source, re.M | re.S).group()
        variables = {
            "ROOT": "/synthetic/jones-package", "JONES_OVERLAY": overlay, "BUILD_NUMBER": "135",
            "BUNDLE_ID": metadata.BUNDLE_ID, "APP_TEAM_ID": metadata.TEAM_ID, "JONES_STATE_KEY": "jones",
            "DISPLAY_NAME": metadata.DISPLAY_NAME, "APP_GROUP_ID": metadata.APP_GROUP_ID,
            "ICLOUD_ID": metadata.ICLOUD_ID, "JONES_UPDATE_CHANNEL": "none", "FEED_URL": "", "PUBLIC_ED_KEY": "",
            "JONES_METADATA": "<key>JonesStateKey</key><string>jones</string>",
        }
        script = "set -euo pipefail\n" + "\n".join(f"{key}={shlex.quote(value)}" for key, value in variables.items())
        script += "\n" + function + "\npython3() {\n" + helper_body + "\n}\n"
        script += "prepare_jones_update_metadata\nprintf '%s\\0' \"$BUILD_NUMBER\" \"$JONES_METADATA\"\n"
        return subprocess.run(["bash", "-c", script], env={"PATH": "/usr/bin:/bin"}, capture_output=True, check=False)

    def test_hook_appends_full_provenance_and_composes_version_without_executing_helper(self):
        output = metadata.shell_metadata(metadata.provenance_metadata(SOURCE, "135"))
        result = self.invoke("printf '%s' " + shlex.quote(output))
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        version, fragment, _ = result.stdout.decode().split("\0")
        self.assertEqual(version, "135.1234")
        parsed = plistlib.loads(("<plist><dict>" + fragment + "</dict></plist>").encode())
        self.assertEqual(parsed, {"JonesStateKey": "jones", "JonesSourceRevision": REVISION,
                                  "JonesBuildOrigin": "local", "JonesBuildRun": ""})

    def test_failed_preflight_does_not_reach_the_following_shell_effect(self):
        result = self.invoke("return 37")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_no_overlay_never_invokes_helper_or_changes_version(self):
        result = self.invoke("printf 'unexpected helper invocation'; return 37", overlay="0")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, b"135\0<key>JonesStateKey</key><string>jones</string>\0")



class DeveloperIDTests(unittest.TestCase):
    def profile(self, identifier=signing.BUNDLE):
        return {"TeamIdentifier": [signing.TEAM], "ApplicationIdentifierPrefix": [signing.TEAM],
                "ExpirationDate": datetime(2099, 1, 1), "ProvisionsAllDevices": True,
                "DeveloperCertificates": [b"public synthetic certificate"],
                "Entitlements": signing.entitlements(identifier)}

    @property
    def certificate(self):
        return hashlib.sha1(b"public synthetic certificate").hexdigest()

    def test_exact_production_identity_preserves_cloudkit_and_holds_updates(self):
        configuration = replace(metadata.UpdateConfiguration(), signing_mode="developer-id",
                                team_id=signing.TEAM, app_group_id=signing.GROUP)
        info = configuration.metadata()
        self.assertEqual(info["JonesSigningMode"], "developer-id")
        self.assertEqual(info["JonesStateKey"], "jones")
        self.assertFalse(info["SUAutomaticallyUpdate"])
        for invalid in (replace(configuration, signing_mode="identity"),
                        replace(configuration, team_id="JONESLOCAL"),
                        replace(configuration, app_group_id=metadata.APP_GROUP_ID),
                        replace(configuration, channel="stable", feed_url=metadata.STABLE_FEED_URL,
                                public_ed_key=FIXTURE_KEY)):
            with self.assertRaises(metadata.MetadataError):
                invalid.validate()
        self.assertEqual(signing.entitlements(signing.BUNDLE)["com.apple.developer.icloud-container-identifiers"],
                         ["iCloud.com.jonessystems.codexbar"])

    def test_profiles_require_exact_team_certificate_expiry_and_entitlement_grants(self):
        for identifier in (signing.BUNDLE, signing.BUNDLE + ".widget"):
            profile = self.profile(identifier)
            signing.validate_profile(profile, identifier, self.certificate)
            mutations = [{"TeamIdentifier": ["OTHERTEAM1"]}, {"ApplicationIdentifierPrefix": ["OTHERTEAM1"]},
                         {"ExpirationDate": datetime(2000, 1, 1)}, {"ExpirationDate": "2099"},
                         {"ProvisionsAllDevices": False}, {"ProvisionedDevices": ["device"]},
                         {"DeveloperCertificates": [b"another certificate"]}, {"Entitlements": {}},
                         {"Entitlements": dict(profile["Entitlements"], **{"get-task-allow": True})}]
            for key in signing.entitlements(identifier):
                if key != "com.apple.security.app-sandbox":
                    bad = dict(profile["Entitlements"])
                    bad[key] = "*"
                    mutations.append({"Entitlements": bad})
            for mutation in mutations:
                with self.subTest(mutation=mutation), self.assertRaises(signing.SigningError):
                    signing.validate_profile(dict(profile, **mutation), identifier, self.certificate)

    def test_team_wildcard_profile_authorizes_exact_group_but_never_changes_signed_entitlements(self):
        for identifier in (signing.BUNDLE, signing.BUNDLE + ".widget"):
            for groups in ([signing.TEAM + ".*"], [signing.GROUP, signing.TEAM + ".*"]):
                profile = self.profile(identifier)
                profile["Entitlements"]["com.apple.security.application-groups"] = groups
                signing.validate_profile(profile, identifier, self.certificate)
                self.assertEqual(signing.entitlements(identifier)["com.apple.security.application-groups"], [signing.GROUP])
            for groups in (["*"], ["OTHERTEAM1.*"], [signing.TEAM + ".com.*"], [], [signing.GROUP, "*"]):
                profile = self.profile(identifier)
                profile["Entitlements"]["com.apple.security.application-groups"] = groups
                with self.subTest(groups=groups), self.assertRaises(signing.SigningError):
                    signing.validate_profile(profile, identifier, self.certificate)

    def test_production_signature_requires_team_runtime_timestamp_resources_and_chain(self):
        text = "\n".join([
            "Identifier=" + signing.BUNDLE, "TeamIdentifier=" + signing.TEAM,
            "Authority=Developer ID Application: Fixture (2CUPSQS986)",
            "Authority=Developer ID Certification Authority", "Authority=Apple Root CA",
            "Timestamp=Oct 22, 2026", "CodeDirectory v=20500 size=500 flags=0x10000(runtime) hashes=1+2",
            "CDHash=" + "a" * 40, "Sealed Resources version=2 rules=13 files=18"])
        self.assertEqual(signing.validate_signature(text, signing.BUNDLE), "a" * 40)
        for row in text.splitlines():
            with self.subTest(row=row), self.assertRaises(signing.SigningError):
                signing.validate_signature(text.replace(row, ""), signing.BUNDLE)
        for altered in (text + "\nSignature=adhoc", text.replace("2CUPSQS986", "Y5PE65HELJ"),
                        text + "\nTeamIdentifier=" + signing.TEAM):
            with self.assertRaises(signing.SigningError):
                signing.validate_signature(altered, signing.BUNDLE)

    def test_only_exact_main_signing_dispatch_can_claim_ci_main(self):
        environment, event = ci_fixture()
        environment.update(GITHUB_EVENT_NAME="workflow_dispatch", GITHUB_WORKFLOW_SHA=REVISION,
                           GITHUB_WORKFLOW_REF=f"{metadata.REPOSITORY}/{signing.WORKFLOW}@refs/heads/main")
        event = {"repository": repository(), "inputs": {}}
        result = metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment,
                                              event=event, signing_mode="developer-id")
        self.assertEqual(result["JonesBuildOrigin"], "ci-main")
        for mutation in ({"GITHUB_REF": "refs/heads/topic"}, {"GITHUB_WORKFLOW_SHA": MERGE_REVISION},
                         {"GITHUB_EVENT_NAME": "pull_request_target"}, {"GITHUB_WORKFLOW_REF": "foreign"}):
            with self.assertRaises(metadata.MetadataError):
                metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=dict(environment, **mutation),
                                             event=event, signing_mode="developer-id")
        with self.assertRaises(metadata.MetadataError):
            metadata.provenance_metadata(SOURCE, "135", "ci-main", environment=environment, event=event)

    def test_command_timeout_drains_owned_group_and_reports_unknown_descendants(self):
        process = Mock(pid=12345, returncode=0)
        process.communicate.side_effect = [subprocess.TimeoutExpired("fixture", 1), (b"", b"")]
        with patch.object(signing_operation.subprocess, "Popen", return_value=process) as launch, \
                patch.object(signing_operation.os, "killpg") as kill, \
                patch.object(signing_operation, "group_exists", return_value=False):
            with self.assertRaises(subprocess.TimeoutExpired):
                signing_operation.run(["fixture"], {}, timeout=1)
            kill.assert_called_once_with(12345, signal.SIGTERM)
            self.assertTrue(launch.call_args.kwargs["start_new_session"])
        process.communicate.side_effect = None
        process.communicate.return_value = (b"", b"")
        with patch.object(signing_operation.subprocess, "Popen", return_value=process), \
                patch.object(signing_operation, "group_exists", return_value=True):
            with self.assertRaises(signing_operation.ProcessDrainUnknown):
                signing_operation.run(["fixture"], {})

    def test_secret_free_argv_and_owned_cleanup_on_success_failure_and_cancellation(self):
        for failure in (None, "partition", "notary", "cancel"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory(prefix=".jones-signing-test-", dir=ROOT) as name:
                root = Path(name)
                script = root / "Scripts/jones_sign_and_notarize.py"
                script.parent.mkdir()
                (root / ".build").mkdir()
                (root / ".build/jones-import-identity").write_text("synthetic importer")
                fixture_environment = {"PATH": os.environ.get("PATH", ""), "RUNNER_ENVIRONMENT": "github-hosted",
                                       "MACOS_SIGNING_CERTIFICATE_PASSWORD": "synthetic-password-only",
                                       "APPLE_NOTARY_KEY_ID": "AAAAAAAAAA",
                                       "APPLE_NOTARY_ISSUER_ID": "00000000-0000-0000-0000-000000000000"}
                for key in ("MACOS_SIGNING_CERTIFICATE_P12_BASE64", "APPLE_NOTARY_API_KEY_P8_BASE64",
                            "JONES_APP_PROVISIONING_PROFILE_BASE64", "JONES_WIDGET_PROVISIONING_PROFILE_BASE64"):
                    fixture_environment[key] = base64.b64encode(b"synthetic input").decode()
                commands = []

                def fake_run(args, environment, timeout=120):
                    args = [str(arg) for arg in args]
                    commands.append(args)
                    self.assertNotIn("synthetic-password-only", args)
                    if Path(args[0]).name == "jones-import-identity":
                        self.assertEqual(environment["MACOS_SIGNING_CERTIFICATE_PASSWORD"], "synthetic-password-only")
                        return self.certificate.upper().encode()
                    self.assertFalse(set(signing_operation.SECRETS) & set(environment))
                    if "create-keychain" in args:
                        Path(args[-1]).touch()
                    if "list-keychains" in args and "-s" not in args:
                        return b'"/synthetic/login.keychain-db"\n'
                    if "set-key-partition-list" in args:
                        if failure == "partition":
                            raise signing.SigningError("fixture partition failure")
                        if failure == "cancel":
                            raise SystemExit(143)
                    if "notarytool" in args:
                        return json.dumps({"status": "Invalid" if failure == "notary" else "Accepted"}).encode()
                    return b""

                with patch.dict(os.environ, fixture_environment, clear=True), \
                        patch.object(signing_operation, "__file__", str(script)), \
                        patch.object(signing_operation.candidate, "inspect_context", return_value=SimpleNamespace(origin="ci-main")), \
                        patch.object(signing_operation.candidate, "create_artifact") as artifact, \
                        patch.object(signing_operation, "run", side_effect=fake_run), \
                        patch.object(signing, "profile_from_file", side_effect=lambda path: self.profile(
                            signing.BUNDLE + ".widget" if path.name.startswith("widget") else signing.BUNDLE)), \
                        patch.object(signing, "verify_bundle"):
                    if failure:
                        with self.assertRaises((signing.SigningError, SystemExit)):
                            signing_operation.main()
                        artifact.assert_not_called()
                    else:
                        signing_operation.main()
                        artifact.assert_called_once()
                self.assertFalse((root / ".mac-release.jones.env").exists())
                self.assertEqual([path.name for path in (root / ".build").iterdir()], ["jones-import-identity"])
                self.assertTrue(any("delete-keychain" in args for args in commands))
                self.assertTrue(any("list-keychains" in args and "-s" in args for args in commands))


if __name__ == "__main__":
    def cancelled(signum, _frame):
        raise SystemExit(128 + signum)

    for caught_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(caught_signal, cancelled)
    unittest.main()
