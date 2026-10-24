#!/usr/bin/env python3
"""Synthetic discovery, timing, and cache contracts; no Swift toolchain required."""

import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import ci_swift_test_by_suite as runner
import ci_swift_test_campaign as campaign


ROOT = Path(__file__).resolve().parent.parent
TEST_IDS = [
    "CodexBarTests.Alpha/test_one()",
    "CodexBarTests.Alpha/test_two(argument:)",
    "CodexBarTests.Legacy/test_example",
    "CodexBarTests.`top/level works`()",
]
SHA = "a" * 40


def campaign_environment(workspace, **overrides):
    return {"GITHUB_WORKSPACE": str(workspace), "GITHUB_SHA": SHA, "GITHUB_ACTIONS": "true",
            "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_REF": "refs/heads/work/campaign",
            "RUNNER_OS": "macOS", "RUNNER_ARCH": "ARM64", "ImageVersion": "20261001.1", "ImageOS": "macos26",
            "CAMPAIGN_GROUP_SIZE": "4", "CAMPAIGN_SHARD_COUNT": "1", "CAMPAIGN_SHARD_INDEX": "0",
            "CAMPAIGN_EXPECTED_SHA": SHA, "CAMPAIGN_CACHE_MODE": "warm", "CAMPAIGN_CACHE_HIT": "true",
            "CAMPAIGN_CACHE_KEY": "swiftpm-toolchain-dependencies-" + SHA, "CAMPAIGN_TOOLCHAIN_ID": "toolchain",
            **overrides}


@contextlib.contextmanager
def capture_fixture():
    with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
        environment = campaign_environment(Path(temporary))
        root = campaign.prepare(environment, SHA)
        with patch.dict(os.environ, {"GITHUB_SHA": SHA, "GITHUB_ACTIONS": "true", **campaign.ISOLATION}):
            capture = campaign.Capture(root)
            try:
                yield capture, environment
            finally:
                capture.records.close()


def native_stream(names=("opaque/function(argument:)",), *, parameterized=True, fields=True, skipped=False):
    # Source-backed v0 capability fixture: Documentation/ABI/JSON.md at swift-6.2-RELEASE
    # requires testID, not a parameter-case ID. HumanReadableOutputRecorder supplies
    # argument messages; the raw native text must survive comparison unchanged.
    records = [{"version": 0, "kind": "test", "payload": {
        "kind": "function", "id": name, "name": "function(argument:)", "displayName": "native display",
        "sourceLocation": {"fileID": "Synthetic/Fixture.swift", "line": 7, "column": 1},
        "isParameterized": parameterized,
    }} for name in names]

    def event(kind, name=None, **extra):
        payload = {"kind": kind, "instant": {"absolute": 1, "since1970": 2}, "messages": []}
        if name:
            payload["testID"] = name
        records.append({"version": 0, "kind": "event", "payload": {**payload, **extra}})

    event("runStarted")
    for name in names:
        if skipped:
            event("testSkipped", name, messages=[{"symbol": "skip", "text": "Disabled by a synthetic trait"}])
            continue
        event("testStarted", name)
        messages = [{"symbol": "default", "text": "Test case passing 1 argument value → 7 to function started."}]
        if parameterized:
            event("testCaseStarted", name, messages=messages if fields else [])
            event("testCaseEnded", name)
        event("testEnded", name)
    event("runEnded")
    return "\n".join(campaign.encode(record) for record in records) + "\n"


def xctest_console(names=(), status="passed"):
    lines = ["Test Suite 'Selected tests' started at 2026-01-01"]
    for name in names:
        lines += [f"Test Case '{name}' started.", f"Test Case '{name}' {status} (0.001 seconds)."]
    lines += ["Test Suite 'Selected tests' passed at 2026-01-01",
              f"Executed {len(names)} tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds"]
    return "\n".join(lines) + "\n"


def completed(command, status=0, stderr=""):
    return subprocess.CompletedProcess(command, status, "\n".join(TEST_IDS) + "\n" if status == 0 else "", stderr)


def evidence_records(output):
    prefix = "Swift test evidence: "
    return [json.loads(line[len(prefix):]) for line in output.splitlines() if line.startswith(prefix)]


class DiscoveryRecoveryTests(unittest.TestCase):
    def test_sparkle_recovery_does_not_repeat_the_build(self):
        command = ["swift", "test", "list"]
        missing_library = (
            "Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle\n"
            "tried: /fixture/PackageFrameworks/Sparkle.framework/Versions/B/Sparkle"
        )
        with patch.object(runner, "run_captured_command", side_effect=[
            completed(command, 1, missing_library), completed(command),
        ]) as invoke, patch.object(runner, "repair_sparkle_test_runtime", return_value=True) as repair:
            selections = runner.swift_test_list(["swift"])
        self.assertEqual([call.args[0] for call in invoke.call_args_list], [
            command, [*command, "--skip-build"],
        ])
        repair.assert_called_once_with(["swift"])
        self.assertEqual([item.name for item in selections], [
            "CodexBarTests.Alpha", "CodexBarTests.Legacy", "CodexBarTests.`top/level works`()",
        ])

    def test_other_discovery_failures_do_not_retry_or_claim_a_manifest(self):
        with patch.object(runner, "run_captured_command", return_value=completed([], 42, "build failed")) as invoke, \
                patch.object(runner, "repair_sparkle_test_runtime") as repair, \
                contextlib.redirect_stderr(io.StringIO()) as output:
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                runner.swift_test_list(["swift"])
        self.assertEqual(failure.exception.returncode, 42)
        self.assertEqual(invoke.call_count, 1)
        repair.assert_not_called()
        self.assertNotIn('"event": "discovery"', output.getvalue())

    def test_unrepaired_sparkle_failure_does_not_skip_build(self):
        missing_library = (
            "Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle\n"
            "tried: /fixture/PackageFrameworks/Sparkle.framework/Versions/B/Sparkle"
        )
        with patch.object(runner, "run_captured_command", return_value=completed([], 1, missing_library)) as invoke, \
                patch.object(runner, "repair_sparkle_test_runtime", return_value=False):
            with self.assertRaises(subprocess.CalledProcessError):
                runner.swift_test_list(["swift"])
        self.assertEqual(invoke.call_count, 1)


class CacheContractTests(unittest.TestCase):
    def test_cache_saves_new_source_builds_with_a_toolchain_bound_fallback(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        job = re.search(r"(?ms)^  swift-test-macos:\n(.*?)(?=^  [\w-]+:|\Z)", workflow).group(1)
        cache = re.search(r"(?ms)^      - name: Restore SwiftPM build cache\n(.*?)(?=^      - |\Z)", job).group(1)
        key = re.search(r"(?m)^          key: (.+)$", cache).group(1)
        self.assertIn("${{ github.sha }}", key)
        self.assertIn("${{ steps.swift-toolchain.outputs.cache-id }}", key)
        self.assertIn("${{ runner.arch }}", key)
        self.assertIn("${{ hashFiles('Package.resolved', 'Package.swift') }}", key)
        restore = re.search(r"(?m)^          restore-keys: \|\n((?:            .+\n)+)", cache).group(1)
        self.assertEqual(restore.strip(), key.removesuffix("${{ github.sha }}"))
        self.assertLess(job.index("id: swift-toolchain"), job.index("- name: Restore SwiftPM build cache"))
        self.assertNotIn("cache-hit", job[job.index("- name: Swift Test"):])


class CampaignActivationTests(unittest.TestCase):
    def test_manual_campaign_has_explicit_validated_controls(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("  workflow_dispatch:", workflow)
        for name in ("group_size", "shard_count", "expected_sha", "cache_mode"):
            self.assertIn(f"      {name}:", workflow)
        self.assertIn("Scripts/ci_swift_test_campaign.py plan", workflow)

    def test_native_evidence_is_opt_in(self):
        source = (ROOT / "Scripts/ci_swift_test_by_suite.py").read_text()
        self.assertIn("campaign.Capture.from_environment()", source)


class CampaignPlanTests(unittest.TestCase):
    def test_ordinary_defaults_ignore_manual_inputs(self):
        for event in ("pull_request", "push"):
            plan = campaign.resolve_plan(event, "12", "3", "untrusted", SHA, "cold")
            self.assertEqual(plan["include"], [
                {"shard-index": index, "shard-count": 2, "group-size": 4,
                 "cache-mode": "ordinary", "campaign": False} for index in (0, 1)
            ])

    def test_every_manual_arm_and_invalid_input(self):
        for group in ("4", "12"):
            for count in ("1", "2", "3"):
                for mode in ("seed", "warm", "cold"):
                    with self.subTest(group=group, count=count, mode=mode):
                        arms = campaign.resolve_plan("workflow_dispatch", group, count, SHA, SHA, mode)["include"]
                        self.assertEqual([item["shard-index"] for item in arms], list(range(int(count))))
                        self.assertTrue(all(item["group-size"] == int(group) and item["campaign"] for item in arms))
        defaults = {"group_size": "4", "shard_count": "2", "expected_sha": SHA,
                    "source_sha": SHA, "cache_mode": "warm"}
        for field, value in (("group_size", "8"), ("shard_count", "4"), ("cache_mode", "unknown"),
                             ("expected_sha", "b" * 40), ("expected_sha", SHA + "\n"), ("shard_count", "2; false")):
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                campaign.resolve_plan("workflow_dispatch", **{**defaults, field: value})

    def test_workflow_preserves_caps_qualification_and_scoped_capture(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        job = workflow.split("  swift-test-macos:\n", 1)[1].split("  lint-build-test:\n", 1)[0]
        self.assertIn("timeout-minutes: 80", job)
        self.assertIn("timeout-minutes: 70", job)
        self.assertIn("CODEXBAR_TEST_SUITE_TIMEOUT=120", job)
        self.assertIn("CODEXBAR_TEST_RETRY_NON_TIMEOUT_FAILURES=0", job)
        self.assertIn("if: ${{ matrix.cache-mode != 'cold' }}", job)
        swift_step = job.split("- name: Swift Test\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("CODEXBAR_TEST_EVIDENCE_DIR:", swift_step)
        self.assertEqual(job.count("CODEXBAR_TEST_EVIDENCE_DIR:"), 1)
        for required in ("Check app locales and Swift formatting", "Provider plugin JavaScriptCore goldens",
                         "Collect crash reports on failure", "Summarize macOS shard"):
            self.assertIn(required, job)
        self.assertLess(job.index("Summarize macOS shard"), job.index("Validate campaign evidence"))
        self.assertIn("retention-days: 7", job)
        self.assertIn("steps.campaign-upload.outcome == 'success'", job)
        self.assertIn("./Scripts/test.sh --command swift test --parallel", workflow)
        self.assertIn("run: ./Scripts/test-plugin-engines.sh --jsc-only", job)
        self.assertNotIn("GITHUB_ENV", (ROOT / "Scripts/ci_swift_test_campaign.py").read_text())

    def test_prepare_refuses_unproved_warm_cold_and_storage(self):
        with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
            workspace = Path(temporary)
            environment = campaign_environment(workspace)
            for overrides in ({"CAMPAIGN_CACHE_HIT": "false"}, {"RUNNER_OS": "Linux"}, {"ImageVersion": ""}):
                with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                    campaign.prepare({**environment, **overrides}, SHA)
            (workspace / ".build").mkdir()
            with self.assertRaisesRegex(ValueError, "absent application build"):
                campaign.prepare({**environment, "CAMPAIGN_CACHE_MODE": "cold", "CAMPAIGN_CACHE_HIT": ""}, SHA)
            with patch.object(campaign.shutil, "disk_usage", return_value=SimpleNamespace(free=1)), \
                    self.assertRaisesRegex(ValueError, "insufficient storage"):
                campaign.prepare(environment, SHA)
            self.assertEqual([path.name for path in workspace.iterdir()], [".build"])

    def test_upload_cleanup_is_exact_and_preserves_unproved_roots(self):
        with capture_fixture() as (capture, environment):
            root = capture.root
            sentinel = root.parent / "unrelated"
            sentinel.write_text("keep")
            capture.finish(23, False)
            with self.assertRaisesRegex(ValueError, "drain is unproved"):
                campaign.cleanup(root, environment)
            completion = root / "completion.json"
            completion.write_text(campaign.encode({"result": 23, "cleanup_proved": True, "native_support": False}))
            with contextlib.redirect_stdout(io.StringIO()):
                campaign.cleanup(root, environment)
            self.assertFalse(root.exists())
            self.assertEqual(sentinel.read_text(), "keep")


class NativeOutcomeTests(unittest.TestCase):
    def test_v0_parameter_capability_keeps_native_fields_or_reports_unknown(self):
        complete = campaign.native_outcomes(native_stream())
        self.assertEqual(complete["limitations"], [])
        self.assertEqual(complete["functions"][0]["native_test"]["displayName"], "native display")
        self.assertEqual(complete["cases"][0]["test_id"], "opaque/function(argument:)")
        self.assertIn("value → 7", complete["cases"][0]["native_fields"]["messages"][0]["text"])
        for stream in (native_stream(fields=False), native_stream().replace("Test case passing 1 argument value → 7",
                                                                           "Generic test-start display")):
            result = campaign.native_outcomes(stream)
            self.assertIn("no comparable parameter representation", result["limitations"][0])
            self.assertEqual(result["functions"][0]["status"], "passed")
            self.assertEqual(len(result["cases"]), 1)

    def test_native_case_extension_remains_comparable_without_argument_messages(self):
        records = [json.loads(line) for line in native_stream(fields=False).splitlines()]
        native_case = {"id": "opaque-case-native-value", "displayName": "7"}
        for record in records:
            if record["payload"].get("kind") in ("testCaseStarted", "testCaseEnded"):
                record["payload"]["_testCase"] = native_case
        outcomes = campaign.native_outcomes("\n".join(map(campaign.encode, records)))
        self.assertEqual(outcomes["limitations"], [])
        self.assertEqual(outcomes["cases"][0]["native_fields"]["_testCase"], native_case)
        records[4]["payload"]["_testCase"] = {"id": "different native case"}
        with self.assertRaisesRegex(ValueError, "relationship changed"):
            campaign.native_outcomes("\n".join(map(campaign.encode, records)))

    def test_native_missing_duplicate_and_failed_outcomes(self):
        records = [json.loads(line) for line in native_stream().splitlines()]
        for kind in ("testEnded", "testCaseEnded", "runEnded"):
            incomplete = [item for item in records if item["payload"].get("kind") != kind]
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                campaign.native_outcomes("\n".join(map(campaign.encode, incomplete)))
        duplicate = records[:4] + records[3:5] + records[4:]
        with self.assertRaises(ValueError):
            campaign.native_outcomes("\n".join(map(campaign.encode, duplicate)))
        issue = {"version": 0, "kind": "event", "payload": {
            "kind": "issueRecorded", "testID": "opaque/function(argument:)",
            "issue": {"isKnown": False}, "messages": [{"symbol": "fail", "text": "expected failure"}],
        }}
        failed = campaign.native_outcomes("\n".join(map(campaign.encode, records[:4] + [issue] + records[4:])))
        self.assertEqual(failed["functions"][0]["status"], "failed")
        self.assertEqual(failed["cases"][0]["status"], "failed")
        issue["payload"]["issue"]["isKnown"] = True
        known = campaign.native_outcomes("\n".join(map(campaign.encode, records[:4] + [issue] + records[4:])))
        self.assertEqual(known["functions"][0]["status"], "passed-with-known-issue")
        self.assertEqual(len(known["issues"]), 1)

    def test_native_skips_and_ambiguous_parameter_multiplicity(self):
        skipped = campaign.native_outcomes(native_stream(skipped=True))
        self.assertEqual(skipped["functions"][0]["status"], "skipped")
        self.assertEqual(skipped["functions"][0]["skip"][0]["text"], "Disabled by a synthetic trait")
        records = [json.loads(line) for line in native_stream().splitlines()]
        duplicated_case = records[:5] + records[3:5] + records[5:]
        result = campaign.native_outcomes("\n".join(map(campaign.encode, duplicated_case)))
        self.assertEqual(len(result["cases"]), 2)
        self.assertIn("ambiguous repeated", result["limitations"][0])

    def test_xctest_retains_raw_identity_multiplicity_and_skips(self):
        name = "-[SyntheticTests.Legacy test_example]"
        outcomes = campaign.xctest_outcomes(xctest_console([name, name]))
        self.assertEqual([item["id"] for item in outcomes], [name, name])
        self.assertEqual(campaign.xctest_outcomes(xctest_console()), [])
        skipped = xctest_console([name], "skipped").replace(
            f"Test Case '{name}' skipped", "Fixture.swift:7: skipped - unavailable synthetic capability\n"
            f"Test Case '{name}' skipped")
        self.assertIn("unavailable synthetic capability", campaign.xctest_outcomes(skipped)[0]["skip"][0])
        for broken in ("", xctest_console([name]).replace("Executed 1 test", "Executed 2 test"),
                       xctest_console([name]).replace("passed (0.001 seconds).", "pending.")):
            with self.assertRaises(ValueError):
                campaign.xctest_outcomes(broken)


class CampaignCaptureTests(unittest.TestCase):
    def test_native_event_stream_command_keeps_private_destination_in_compiler_admission(self):
        selection = runner.TestSelection("CodexBarTests.Legacy", r"^CodexBarTests\.Legacy/")
        jobs = runner.build_jobs
        with capture_fixture() as (capture, _):
            def invoke(command, *, timeout, stdout, stderr):
                self.assertEqual(timeout, 120)
                self.assertEqual(command[:6], ["swift", "test", "--skip-build", "--no-parallel", "--filter",
                                              runner.filter_for([selection])])
                normalized, limit = jobs.normalize(command[1:], "swift", {})
                self.assertEqual(normalized, command[1:])
                self.assertEqual(limit, jobs.MAX_JOBS)
                output = Path(command[command.index("--event-stream-output-path") + 1])
                self.assertEqual(output.parent, capture.root / "0001-first")
                self.assertTrue(output.is_relative_to(capture.root))
                self.assertIn(output, jobs.output_destinations(normalized, "swift", {}))
                output.write_text(native_stream())
                stdout.write(xctest_console())
                return 0
            with patch.object(runner, "_campaign", capture), patch.object(runner, "run_command", side_effect=invoke), \
                    contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(runner.run_group([selection], 120, ["swift"]), 0)

    def test_native_event_stream_destination_still_requires_its_storage_reserve(self):
        jobs = runner.build_jobs
        with capture_fixture() as (capture, _):
            attempt = capture.begin_attempt("first")
            output = attempt / "swift-testing.jsonl"
            command = ["test", "--skip-build", "--no-parallel", "--filter", "^Synthetic/",
                       "--event-stream-version", "0", "--event-stream-output-path", str(output)]
            seen = []
            def counters(path):
                seen.append(path)
                return SimpleNamespace(f_bavail=jobs.RESERVE_BYTES + jobs.PEAK_BYTES - int(path == attempt),
                                       f_frsize=1)
            with patch.object(jobs, "existing_output_ancestor", side_effect=lambda path:
                              attempt if path == output else capture.root), \
                    patch.object(jobs.os, "statvfs", side_effect=counters), \
                    contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaisesRegex(jobs.AdmissionError, "insufficient storage"):
                jobs.admit_storage(command, "swift", {})
            self.assertIn(attempt, seen)
            self.assertFalse(output.exists())
            capture.end_attempt(attempt)

    def test_native_event_registration_does_not_admit_arbitrary_or_ambiguous_outputs(self):
        jobs = runner.build_jobs
        variants = [["--unknown-event-output-path", "elsewhere"], ["--event-stream-output-path", "~/outside"],
                    ["--event-stream-output-path", "$(ROOT)/output"], ["--event-stream-output-path="],
                    ["--event-stream-output-path=a", "--event-stream-output-path=b"]]
        for arguments in variants:
            with self.subTest(arguments=arguments), self.assertRaises(jobs.AdmissionError):
                jobs.output_destinations(["test", *arguments], "swift", {})

    def test_capture_rejects_partial_selection_changed_policy_and_non_native_route(self):
        with capture_fixture() as (capture, _), patch.object(sys, "argv", [
                "runner", "--group-size", "4", "--shard-count", "1", "--shard-index", "0",
                "--timeout", "120", "--no-retry-non-timeout-failures"]):
            args = runner.parse_args()
            with patch.object(sys, "platform", "darwin"):
                capture.validate_invocation(args)
                for name, value in (("limit_groups", 1), ("list_only", True), ("timeout", 180),
                                     ("retry_non_timeout_failures", True), ("command", ["true"]),
                                     ("swift_command", "other-swift")):
                    changed = copy.copy(args)
                    setattr(changed, name, value)
                    with self.subTest(name=name), self.assertRaises(ValueError):
                        capture.validate_invocation(changed)
                with patch.dict(os.environ, {"CODEXBAR_TEST_CODEX_FILE_ISOLATION": "0"}), \
                        self.assertRaisesRegex(ValueError, "isolation"):
                    capture.validate_invocation(args)
            with patch.object(sys, "platform", "linux"), self.assertRaisesRegex(ValueError, "macOS Actions"):
                capture.validate_invocation(args)

    def test_attempt_files_are_unique_and_invocation_timeout_unchanged(self):
        selection = runner.TestSelection("CodexBarTests.Legacy", r"^CodexBarTests\.Legacy/")
        handles = []
        def invoke(command, *, timeout, stdout, stderr):
            self.assertEqual(timeout, 120)
            self.assertEqual(command[:6], ["swift", "test", "--skip-build", "--no-parallel", "--filter",
                                          runner.filter_for([selection])])
            self.assertEqual(command[6:9], ["--event-stream-version", "0", "--event-stream-output-path"])
            Path(command[9]).write_text(native_stream())
            stdout.write(xctest_console())
            stderr.write("native stderr marker\n")
            handles.extend((stdout, stderr))
            return 124 if len(handles) == 2 else 0
        with capture_fixture() as (capture, _), patch.object(runner, "_campaign", capture), \
                patch.object(runner, "run_command", side_effect=invoke), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as stderr:
            self.assertEqual(runner.run_group([selection], 120, ["swift"]), 124)
            self.assertEqual(runner.run_group([selection], 120, ["swift"], attempt="selection-retry"), 0)
            self.assertTrue(all(handle.closed for handle in handles))
            self.assertIn("native stderr marker", stderr.getvalue())
            self.assertTrue((capture.root / "0001-first/swift-testing.jsonl").exists())
            self.assertTrue((capture.root / "0002-selection-retry/swift-testing.jsonl").exists())
            attempts = [item for item in campaign.read_records(capture.root / "runner.jsonl") if item["event"] == "attempt"]
            self.assertEqual([item["exit_code"] for item in attempts], [124, 0])
            self.assertIsNone(capture.attempt_id)

    def test_evidence_failure_cannot_mask_drain_failure_or_test_status(self):
        for outcome in (runner.CommandDrainError("unproved drain", 23), 23):
            with self.subTest(outcome=outcome), capture_fixture() as (capture, _), \
                    patch.object(runner, "_campaign", capture), \
                    patch.object(runner, "run_command", side_effect=outcome if isinstance(outcome, Exception) else None,
                                 return_value=23), \
                    patch.object(capture, "record", side_effect=OSError("synthetic write failure")), \
                    contextlib.redirect_stderr(io.StringIO()):
                if isinstance(outcome, Exception):
                    with self.assertRaises(runner.CommandDrainError):
                        runner.run_group([runner.TestSelection("Alpha", "Alpha")], 120, ["swift"])
                else:
                    self.assertEqual(runner.run_group([runner.TestSelection("Alpha", "Alpha")], 120, ["swift"]), 23)

    def test_native_support_probe_fails_closed(self):
        for text, status, expected in (("--event-stream-version --event-stream-output-path", 0, True),
                                       ("--event-stream-output-path", 0, False), ("", 42, False)):
            with self.subTest(text=text), capture_fixture() as (capture, _), patch.object(runner, "_campaign", capture), \
                    patch.object(runner, "run_captured_command",
                                 return_value=subprocess.CompletedProcess([], status, text, "")) as invoke, \
                    contextlib.redirect_stderr(io.StringIO()):
                if expected:
                    runner.check_native_evidence_support(["swift"])
                else:
                    with self.assertRaises(ValueError):
                        runner.check_native_evidence_support(["swift"])
                invoke.assert_called_once_with(["swift", "test", "--skip-build", "--help-hidden"])
                self.assertEqual(capture.native_support, expected)

    def test_actual_process_birth_drain_and_scratch_cleanup_receipts(self):
        with capture_fixture() as (capture, _), patch.object(runner.campaign.Capture, "from_environment", return_value=capture), \
                contextlib.redirect_stderr(io.StringIO()):
            environment = dict(os.environ)
            environment.pop(runner.SCRATCH_PARENT_KEY, None)
            environment.pop(runner.WORKSPACE_ROOT_KEY, None)
            def command():
                return runner.run_command([sys.executable, "-c", "raise SystemExit(23)"], timeout=2)
            with patch.dict(os.environ, environment, clear=True), patch.object(runner, "run_suites", side_effect=command):
                self.assertEqual(runner.main(), 23)
            records = campaign.read_records(capture.root / "runner.jsonl")
            self.assertEqual([item["event"] for item in records],
                             ["fixture-prepared", "process-start", "process-drained", "fixture-removed"])
            self.assertEqual(records[1]["birth"], records[2]["birth"])
            self.assertTrue(any(records[1]["birth"]))
            self.assertFalse(Path(records[0]["path"]).exists())
            self.assertTrue(campaign.read_json(capture.root / "completion.json")["cleanup_proved"])

    def test_capture_budget_failure_drains_the_actual_command(self):
        with capture_fixture() as (capture, _), patch.object(runner, "_campaign", capture), \
                contextlib.redirect_stderr(io.StringIO()):
            directory = capture.begin_attempt("first")
            command = [sys.executable, "-c", "import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_bytes(b'x'*4096); time.sleep(2)",
                       str(directory / "stdout.txt")]
            with patch.object(campaign, "MAX_BYTES", 2048), self.assertRaisesRegex(ValueError, "budget"):
                runner.run_command(command, timeout=2)
            records = campaign.read_records(capture.root / "runner.jsonl")
            self.assertEqual([item["event"] for item in records], ["process-start", "process-drained"])
            self.assertIsNone(runner.test_process(records[0]["pid"]))

    def test_success_and_handled_cancellation_retain_evidence_after_fixture_cleanup(self):
        for outcome in (0, SystemExit(143)):
            with self.subTest(outcome=outcome), capture_fixture() as (capture, _), \
                    patch.object(runner.campaign.Capture, "from_environment", return_value=capture), \
                    patch.object(runner, "run_suites", return_value=0,
                                 side_effect=outcome if isinstance(outcome, SystemExit) else None), \
                    contextlib.redirect_stderr(io.StringIO()):
                environment = dict(os.environ)
                environment.pop(runner.SCRATCH_PARENT_KEY, None)
                environment.pop(runner.WORKSPACE_ROOT_KEY, None)
                with patch.dict(os.environ, environment, clear=True):
                    self.assertEqual(runner.main(), 143 if isinstance(outcome, SystemExit) else 0)
                records = campaign.read_records(capture.root / "runner.jsonl")
                self.assertEqual([item["event"] for item in records], ["fixture-prepared", "fixture-removed"])
                self.assertTrue(capture.root.exists())
                self.assertFalse(Path(records[0]["path"]).exists())
                self.assertTrue(campaign.read_json(capture.root / "completion.json")["cleanup_proved"])


def receipt_fixture(workspace, group_size=4, shard_count=1, shard_index=0):
    environment = campaign_environment(workspace, CAMPAIGN_GROUP_SIZE=str(group_size),
                                       CAMPAIGN_SHARD_COUNT=str(shard_count), CAMPAIGN_SHARD_INDEX=str(shard_index))
    root = campaign.prepare(environment, SHA)
    (root / "native-help.txt").write_text("--event-stream-version --event-stream-output-path\n")
    names = [f"CodexBarTests.Suite{index:02}" for index in range(25)] + ["CodexBarTests.Legacy"]
    top = "CodexBarTests.`top/level works`()"
    discovery = sorted([name + "/function()" for name in names] + [top, "CodexBarTests.CLIEntryTests/entry()"])
    names = sorted(names + [top])
    groups = [names[offset:offset + group_size] for offset in range(0, len(names), group_size)]
    groups = [group for index, group in enumerate(groups) if index % shard_count == shard_index]
    fixture = workspace / ".test-fixtures-synthetic"
    records = []

    def record(event, **fields):
        records.append({"event": event, "source_revision": SHA, **fields})

    record("fixture-prepared", path=str(fixture), identity=[1, 2], owned=True)
    record("native-support", advertised_options=True, exit_code=0, event_stream_version=0)
    record("discovery", test_ids=discovery, sha256=campaign.digest(discovery))
    record("selection", groups=groups, shard_index=shard_index, shard_count=shard_count,
           sha256=campaign.digest(name for group in groups for name in group))
    for index, group in enumerate(groups, 1):
        attempt_id = f"{index:04}-first"
        directory = root / attempt_id
        directory.mkdir()
        native_names = ["opaque-native/" + name for name in group if name != "CodexBarTests.Legacy"]
        xctest_names = ["-[CodexBarTests.Legacy function]"] if "CodexBarTests.Legacy" in group else []
        (directory / "swift-testing.jsonl").write_text(native_stream(native_names))
        (directory / "stdout.txt").write_text(xctest_console(xctest_names))
        (directory / "stderr.txt").write_text("")
        selections = [runner.TestSelection(name, campaign.selection_pattern([name])[1:-1]) for name in group]
        pattern = runner.filter_for(selections)
        command = ["swift", "test", "--skip-build", "--no-parallel", "--filter", pattern,
                   "--event-stream-version", "0", "--event-stream-output-path", str(directory / "swift-testing.jsonl")]
        record("process-start", launch_id=index, attempt_id=attempt_id, pid=100 + index, birth=[index, 1],
               session=100 + index, command=command, environment={**campaign.ISOLATION,
               "CODEXBAR_TEST_WORKSPACE_ROOT": str(workspace), "CODEXBAR_TEST_SCRATCH_PARENT": str(fixture),
               "TMPDIR": str(fixture), "live_or_fixture_grant": False})
        record("process-drained", launch_id=index, pid=100 + index, birth=[index, 1])
        record("attempt", attempt="first", attempt_id=attempt_id, selections=group, filter_pattern=pattern,
               exit_code=0, error=None, timeout_seconds=120, elapsed_seconds=1.5)
    record("fixture-removed", path=str(fixture), identity=[1, 2])
    (root / "runner.jsonl").write_text("\n".join(map(campaign.encode, records)) + "\n")
    campaign.write_json(root / "completion.json", {"result": 0, "cleanup_proved": True, "native_support": True})
    return root


class CampaignReceiptTests(unittest.TestCase):
    def test_missing_parameter_representation_retains_functions_but_cannot_compare(self):
        with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
            root = receipt_fixture(Path(temporary))
            path = root / "0001-first/swift-testing.jsonl"
            records = campaign.read_records(path)
            for record in records:
                if record["kind"] == "test":
                    record["payload"]["isParameterized"] = True
                if record["payload"].get("kind") == "testCaseStarted":
                    record["payload"]["messages"] = []
            path.write_text("\n".join(map(campaign.encode, records)))
            receipt = campaign.verify(root)
            self.assertEqual(len(receipt["functions"]), 27)
            self.assertFalse(receipt["complete_identity"])
            with self.assertRaisesRegex(ValueError, "parameter identity"):
                campaign.compare([receipt], [receipt])

    def test_complete_same_source_campaign_compares_all_six_arms(self):
        with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
            workspace = Path(temporary)
            baseline = [campaign.verify(receipt_fixture(workspace))]
            for group in (4, 12):
                for count in (1, 2, 3):
                    with self.subTest(group=group, count=count):
                        receipts = [campaign.verify(receipt_fixture(workspace, group, count, index))
                                    for index in range(count)]
                        compared = campaign.compare(baseline, receipts)
                        self.assertTrue(compared["equivalent"])
                        self.assertEqual(compared["function_outcomes"], 27)
                        self.assertEqual(compared["case_outcomes"], 26)
                        self.assertEqual(len(receipts[0]["discovery"]), 28)
            self.assertNotIn("CodexBarTests.CLIEntryTests", baseline[0]["selections"])

    def test_incomplete_or_changed_evidence_fails_qualification(self):
        with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
            root = receipt_fixture(Path(temporary))
            records_path = root / "runner.jsonl"
            records = campaign.read_records(records_path)
            mutations = []
            for event in ("process-drained", "fixture-removed", "native-support", "attempt"):
                changed = copy.deepcopy(records)
                changed.pop(next(index for index, item in enumerate(changed) if item["event"] == event))
                mutations.append(changed)
            for event, key, value in (("process-start", "birth", [0, 0]), ("process-start", "session", 999),
                                      ("process-drained", "birth", [999, 1]), ("attempt", "exit_code", 124),
                                      ("attempt", "attempt", "selection-retry"), ("attempt", "timeout_seconds", 121),
                                      ("attempt", "filter_pattern", ".*"), ("selection", "groups", [])):
                changed = copy.deepcopy(records)
                next(item for item in changed if item["event"] == event)[key] = value
                mutations.append(changed)
            changed = copy.deepcopy(records)
            next(item for item in changed if item["event"] == "process-start")["environment"]["TMPDIR"] = "/tmp"
            mutations.append(changed)
            for index, changed in enumerate(mutations):
                records_path.write_text("\n".join(map(campaign.encode, changed)))
                with self.subTest(mutation=index), self.assertRaises(ValueError):
                    campaign.verify(root)

    def test_comparison_rejects_missing_shards_changed_outcomes_and_unknown_case_identity(self):
        with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
            workspace = Path(temporary)
            baseline = [campaign.verify(receipt_fixture(workspace))]
            candidate = [campaign.verify(receipt_fixture(workspace, 12, 2, index)) for index in (0, 1)]
            with self.assertRaisesRegex(ValueError, "every shard"):
                campaign.compare(baseline, candidate[:1])
            for mutation in ("identity", "outcome", "multiplicity", "source", "cache", "unknown"):
                changed = copy.deepcopy(candidate)
                if mutation == "identity":
                    changed[0]["functions"][0]["id"] = "other native ID"
                elif mutation == "outcome":
                    changed[0]["functions"][0]["status"] = "skipped"
                elif mutation == "multiplicity":
                    changed[0]["functions"].append(copy.deepcopy(changed[0]["functions"][0]))
                elif mutation == "source":
                    changed[0]["context"]["source_revision"] = "b" * 40
                elif mutation == "cache":
                    changed[0]["context"]["cache_hit"] = "false"
                else:
                    changed[0]["complete_identity"] = False
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    campaign.compare(baseline, changed)

    def test_known_compiler_admission_tail_is_preserved_but_filter_override_rejected(self):
        with tempfile.TemporaryDirectory(prefix=".test-campaign-", dir=ROOT) as temporary:
            root = receipt_fixture(Path(temporary))
            path = root / "runner.jsonl"
            records = campaign.read_records(path)
            commands = [item["command"] for item in records if item["event"] == "process-start"]
            for command in commands:
                command.extend(["--jobs", "4", "-Xswiftc", "-num-threads", "-Xswiftc", "1"])
            path.write_text("\n".join(map(campaign.encode, records)))
            self.assertTrue(campaign.verify(root)["complete_identity"])
            commands[0].extend(["--filter", ".*"])
            path.write_text("\n".join(map(campaign.encode, records)))
            with self.assertRaisesRegex(ValueError, "invocation"):
                campaign.verify(root)


class LinuxStorageObservationTests(unittest.TestCase):
    def test_storage_walk_stops_at_its_time_bound_without_changing_files(self):
        with tempfile.TemporaryDirectory(prefix=".test-storage-", dir=ROOT) as temporary:
            workspace = Path(temporary)
            build = workspace / ".build"
            build.mkdir()
            (build / "object").write_bytes(b"unchanged")
            with patch.object(campaign.time, "monotonic", side_effect=[0, 11, 12]):
                receipt = campaign.measure_linux(campaign_environment(workspace, RUNNER_OS="Linux"), "after-release")
            self.assertEqual(receipt["status"], "unavailable")
            self.assertIn("entry/time bound", receipt["reason"])
            self.assertEqual((build / "object").read_bytes(), b"unchanged")

    def test_storage_receipt_counts_metadata_without_following_links_or_reading_files(self):
        with tempfile.TemporaryDirectory(prefix=".test-storage-", dir=ROOT) as temporary:
            workspace = Path(temporary)
            build = workspace / ".build"
            build.mkdir()
            (build / "release").mkdir()
            (build / "release/app").write_bytes(b"x" * 7)
            (build / "debug").mkdir()
            (build / "debug/tests").write_bytes(b"x" * 11)
            (workspace / "outside").write_bytes(b"x" * 19)
            (build / "reference").symlink_to(workspace / "outside")
            environment = campaign_environment(workspace, RUNNER_OS="Linux", SWIFT_VERSION="6.3.3")
            with patch.object(Path, "read_text", side_effect=AssertionError("must not read file contents")), \
                    patch.object(Path, "read_bytes", side_effect=AssertionError("must not read file contents")):
                receipt = campaign.measure_linux(environment, "after-tests")
            self.assertEqual(receipt["status"], "observed")
            self.assertEqual(receipt["regular_files"], 2)
            self.assertEqual(receipt["logical_bytes"], 18)
            self.assertEqual(receipt["symlinks"], 1)
            self.assertEqual(receipt["cache_path_manifest"], [".build"])
            self.assertFalse(receipt["cache_enabled"])
            self.assertTrue(receipt["fixture_parents_absent"])
            self.assertGreater(receipt["available_bytes"], 0)
            (workspace / ".test-fixtures-owned").mkdir()
            (build / "fixture-link").symlink_to(workspace / ".test-fixtures-owned")
            observed = campaign.measure_linux(environment, "after-tests")
            self.assertFalse(observed["fixture_parents_absent"])
            self.assertEqual(observed["fixture_paths_in_build"], 1)
            self.assertTrue((workspace / ".test-fixtures-owned").exists())

    def test_missing_build_and_unavailable_measurements_never_change_command_status(self):
        with tempfile.TemporaryDirectory(prefix=".test-storage-", dir=ROOT) as temporary:
            environment = campaign_environment(Path(temporary), RUNNER_OS="Linux")
            receipt = campaign.measure_linux(environment, "before-release")
            self.assertEqual(receipt["status"], "observed")
            self.assertFalse(receipt["build_exists"])
            self.assertEqual(receipt["logical_bytes"], 0)
            with patch.object(campaign.shutil, "disk_usage", side_effect=OSError(5, "synthetic failure")), \
                    patch.dict(os.environ, environment), \
                    patch.object(sys, "argv", ["campaign", "measure-linux", "--phase", "after-release"]), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(campaign.main(), 0)
            self.assertEqual(json.loads(output.getvalue())["status"], "unavailable")
            self.assertEqual(json.loads(output.getvalue())["error_errno"], 5)

    def test_workflow_measurements_surround_existing_builds(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        linux = workflow.split("  build-linux-cli:\n", 1)[1]
        steps = ("measure-linux --phase before-release", 'swift build "${build_args[@]}"',
                 "measure-linux --phase after-release", "./Scripts/test.sh --command swift test --parallel",
                 "measure-linux --phase after-tests", "- name: Smoke test CodexBarCLI")
        positions = [linux.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(linux.count("uses: actions/cache@"), 1)
        self.assertIn("path: ~/.local/share/swiftly", linux)
        for name in ("Observe Linux build storage after release", "Observe Linux build storage after tests"):
            step = linux.split(f"- name: {name}\n", 1)[1].split("      - name:", 1)[0]
            self.assertIn("if: ${{ always() }}", step)


@contextlib.contextmanager
def linux_cache_fixture(mode="auto"):
    parent = Path(os.environ.get(runner.SCRATCH_PARENT_KEY, ROOT))
    with tempfile.TemporaryDirectory(prefix=".test-linux-cache-", dir=parent) as temporary:
        workspace = Path(temporary) / "workspace"
        staging = Path(temporary) / "staging"
        workspace.mkdir()
        staging.mkdir()
        (workspace / "Package.swift").write_text("// synthetic package identity\n")
        (workspace / "Package.resolved").write_text('{"pins":[]}\n')
        env = campaign_environment(workspace, RUNNER_OS="Linux", RUNNER_ARCH="X64", ImageOS="ubuntu24",
            ImageVersion="20261001.1", RUNNER_TEMP=str(staging), LINUX_RUNNER_LABEL="ubuntu-24.04",
            GITHUB_REPOSITORY="Jones-Systems/CodexBar",
            GITHUB_EVENT_NAME="push" if mode == "auto" else "workflow_dispatch",
            LINUX_CACHE_MODE=mode, LINUX_DEFAULT_BRANCH="main")
        context = campaign.linux_cache_source(env, SHA)
        context = campaign.linux_cache_plan(context, env, lambda command: "native " + " ".join(command) + "\n")
        yield workspace, env, context


def cache_metadata(context, key=None, **changes):
    entry = {"id": 42, "key": key or context["requested_key"], "version": "native-cache-version",
             "ref": context["ref"], "size_in_bytes": 1024, "created_at": "2026-10-23T00:00:00Z", **changes}
    return {"total_count": 1, "actions_caches": [entry]}


class LinuxCacheTests(unittest.TestCase):
    def test_source_controls_are_independent_and_manual_sha_is_checked_even_when_off(self):
        with linux_cache_fixture("off") as (_, env, context):
            self.assertFalse(context["enabled"])
            self.assertEqual(context["macos_cache_mode"], "warm")
            self.assertEqual(context["linux_cache_mode"], "off")
            self.assertEqual(context["actual_sha"], context["event_sha"])
            for field, value in (("CAMPAIGN_EXPECTED_SHA", "b" * 40), ("GITHUB_SHA", "b" * 40),
                                 ("LINUX_CACHE_MODE", "cold"), ("CAMPAIGN_GROUP_SIZE", "8")):
                with self.subTest(field=field), self.assertRaises(ValueError):
                    campaign.linux_cache_source({**env, field: value}, SHA)
            ordinary = campaign.linux_cache_source({**env, "GITHUB_EVENT_NAME": "pull_request",
                                                   "LINUX_CACHE_MODE": "untrusted"}, SHA)
            self.assertEqual((ordinary["linux_cache_mode"], ordinary["group_size"], ordinary["shard_count"]),
                             ("auto", 4, 2))

    def test_identity_key_changes_only_with_its_bound_family_or_actual_source(self):
        with linux_cache_fixture() as (workspace, env, context):
            self.assertTrue(context["enabled"])
            self.assertTrue(context["requested_key"].endswith("-" + SHA))
            self.assertEqual(context["requested_key"], context["restore_prefix"] + SHA)
            self.assertEqual(context["toolchain"]["swiftpm"], "native swift package --version\n")
            for field, value in (("RUNNER_ARCH", "ARM64"), ("LINUX_RUNNER_LABEL", "ubuntu-24.04-arm"),
                                 ("ImageOS", "ubuntu-next"), ("ImageVersion", "20261002.1")):
                changed = campaign.linux_cache_plan(copy.deepcopy(context), {**env, field: value},
                                                   lambda command: "native " + " ".join(command) + "\n")
                self.assertNotEqual(changed["restore_prefix"], context["restore_prefix"])
            toolchain = campaign.linux_cache_plan(copy.deepcopy(context), env, lambda _: "changed compiler")
            self.assertNotEqual(toolchain["identity_hashes"]["toolchain"], context["identity_hashes"]["toolchain"])
            self.assertEqual(toolchain["identity_hashes"]["image"], context["identity_hashes"]["image"])
            newer = {**env, "GITHUB_SHA": "b" * 40}
            changed = campaign.linux_cache_plan(campaign.linux_cache_source(newer, "b" * 40), newer,
                                               lambda command: "native " + " ".join(command) + "\n")
            self.assertEqual(changed["restore_prefix"], context["restore_prefix"])
            self.assertNotEqual(changed["requested_key"], context["requested_key"])
            (workspace / "Package.resolved").write_text('{"pins":["changed"]}\n')
            changed = campaign.linux_cache_plan(copy.deepcopy(context), env, lambda _: "same version")
            self.assertNotEqual(changed["identity_hashes"]["dependencies"], context["identity_hashes"]["dependencies"])

    def test_missing_identities_disable_ordinary_cache_and_fail_warm(self):
        for mode in ("auto", "warm"):
            with linux_cache_fixture(mode) as (_, env, original):
                for field in ("RUNNER_ARCH", "LINUX_RUNNER_LABEL", "ImageOS", "ImageVersion"):
                    with self.subTest(mode=mode, field=field):
                        context = campaign.linux_cache_plan(copy.deepcopy(original), {**env, field: ""},
                                                           lambda _: "version")
                        self.assertFalse(context["enabled"])
                        self.assertEqual(context["fatal"], mode == "warm")
                context = campaign.linux_cache_plan(copy.deepcopy(original), env, lambda _: "")
                self.assertFalse(context["enabled"])
                self.assertEqual(context["fatal"], mode == "warm")

    def test_complete_scan_checks_containment_fixtures_special_files_and_limits(self):
        for kind in ("valid", "root-link", "escape-link", "dangling-link", "fixture", "cache-fixture", "parent", "fifo",
                     "bytes", "entries", "time"):
            with self.subTest(kind=kind), linux_cache_fixture() as (workspace, _, _):
                build = workspace / ".build"
                outside = workspace / "outside"
                outside.mkdir()
                (outside / "sentinel").write_text("preserved")
                if kind == "root-link":
                    build.symlink_to(outside)
                else:
                    build.mkdir()
                    (build / "object").write_bytes(b"1234")
                if kind == "valid":
                    (build / "reference").symlink_to("object")
                elif kind in ("escape-link", "dangling-link"):
                    (build / "reference").symlink_to(outside if kind == "escape-link" else "missing")
                elif kind == "fixture":
                    (build / ".swift-test-evidence-owned").mkdir()
                elif kind == "cache-fixture":
                    (build / ".test-linux-cache-owned").mkdir()
                elif kind == "parent":
                    (workspace / ".test-fixtures-owned").mkdir()
                elif kind == "fifo":
                    os.mkfifo(build / "pipe")
                with contextlib.ExitStack() as stack:
                    if kind == "bytes":
                        stack.enter_context(patch.object(campaign, "LINUX_CACHE_BYTES", 3))
                    if kind == "entries":
                        stack.enter_context(patch.object(campaign, "LINUX_SCAN_ENTRIES", 1))
                    if kind == "time":
                        stack.enter_context(patch.object(campaign.time, "monotonic", side_effect=[0, 11, 12]))
                    scanned = campaign.linux_build_scan(workspace)
                self.assertEqual(scanned["complete"], kind == "valid")
                self.assertEqual((outside / "sentinel").read_text(), "preserved")
                if kind == "valid":
                    self.assertEqual((scanned["logical_bytes"], scanned["regular_files"], scanned["symlinks"]),
                                     (4, 1, 1))

    def test_space_admission_uses_both_actual_filesystems(self):
        gib = 1024 ** 3
        for same, available, allowed in ((True, (8, 8), True), (True, (8, 7), False),
                                         (False, (6, 4), True), (False, (5, 4), False), (False, (6, 3), False)):
            with self.subTest(same=same, available=available), \
                    patch.object(Path, "stat", side_effect=[SimpleNamespace(st_dev=1),
                                                           SimpleNamespace(st_dev=1 if same else 2)]), \
                    patch.object(campaign.shutil, "disk_usage", side_effect=[
                        SimpleNamespace(free=value * gib) for value in available]):
                self.assertEqual(campaign.linux_storage(Path("/workspace"), Path("/staging"))["eligible"], allowed)
        self.assertEqual(campaign.LINUX_CACHE_BYTES, 2 * gib)

    def test_exact_and_compatible_prefix_hits_are_approved_but_warm_needs_exact(self):
        for mode in ("auto", "seed", "warm"):
            with linux_cache_fixture(mode) as (_, env, original):
                for suffix in (SHA, "b" * 40):
                    context = copy.deepcopy(original)
                    matched = context["restore_prefix"] + suffix
                    approved = campaign.linux_approve_restore(context,
                        {**env, "LINUX_LOOKUP_OUTCOME": "success", "LINUX_MATCHED_KEY": matched},
                        lambda _env, key: cache_metadata(context, key))
                    allowed = mode != "warm" or suffix == SHA
                    self.assertEqual(approved["restore"], allowed)
                    self.assertEqual(approved.get("fatal", False), not allowed)
                    if allowed:
                        self.assertEqual(approved["producer_source"], suffix)

    def test_metadata_ambiguity_truncation_size_ref_and_family_refuse_before_restore(self):
        with linux_cache_fixture() as (_, env, original):
            valid = cache_metadata(original)
            documents = [None, {}, {"total_count": 2, "actions_caches": valid["actions_caches"]},
                         {"total_count": 2, "actions_caches": valid["actions_caches"] * 2},
                         {"total_count": 1, "actions_caches": [None]}]
            documents += [cache_metadata(original, **changes) for changes in (
                {"size_in_bytes": campaign.LINUX_CACHE_BYTES + 1}, {"size_in_bytes": -1},
                {"version": ""}, {"ref": "refs/heads/unrelated"}, {"id": None})]
            for document in documents:
                context = copy.deepcopy(original)
                result = campaign.linux_approve_restore(context,
                    {**env, "LINUX_LOOKUP_OUTCOME": "success", "LINUX_MATCHED_KEY": context["requested_key"]},
                    lambda *_args: document)
                self.assertFalse(result["restore"])
                self.assertFalse(result["fatal"])
            with patch.object(campaign, "linux_cache_metadata") as metadata:
                result = campaign.linux_approve_restore(copy.deepcopy(original),
                    {**env, "LINUX_LOOKUP_OUTCOME": "success", "LINUX_MATCHED_KEY": "other-family-" + SHA})
                self.assertFalse(result["restore"])
                metadata.assert_not_called()

    def test_metadata_http_read_is_bounded_and_rejects_pagination(self):
        with linux_cache_fixture() as (_, env, context):
            for body, headers, allowed in ((campaign.encode(cache_metadata(context)).encode(), {}, True),
                                           (b"x" * (campaign.LINUX_METADATA_BYTES + 1), {}, False),
                                           (b"{}", {"Link": "next page"}, False)):
                response = io.BytesIO(body)
                response.headers = headers
                requests = []
                def open_request(request, timeout):
                    requests.append((request, timeout))
                    return response
                with patch.object(campaign.urllib.request, "build_opener",
                                  return_value=SimpleNamespace(open=open_request)):
                    if allowed:
                        self.assertEqual(campaign.linux_cache_metadata(
                            {**env, "GH_TOKEN": "synthetic"}, context["requested_key"]),
                                         cache_metadata(context))
                    else:
                        with self.assertRaises(ValueError):
                            campaign.linux_cache_metadata({**env, "GH_TOKEN": "synthetic"}, context["requested_key"])
                self.assertEqual(requests[0][1], 10)
                self.assertIn("/repos/Jones-Systems/CodexBar/actions/caches?", requests[0][0].full_url)

    def test_failed_or_changed_restore_never_becomes_a_cold_success(self):
        for fault in ("none", "action", "matched", "absent", "symlink", "version"):
            with self.subTest(fault=fault), linux_cache_fixture("warm") as (workspace, env, context):
                metadata = lambda _env, key: cache_metadata(context, key)
                context = campaign.linux_approve_restore(context,
                    {**env, "LINUX_LOOKUP_OUTCOME": "success", "LINUX_MATCHED_KEY": context["requested_key"]}, metadata)
                if fault != "absent":
                    (workspace / ".build").mkdir()
                    (workspace / ".build/object").write_text("retained")
                if fault == "symlink":
                    (workspace / ".build/escape").symlink_to(workspace)
                restored_env = {**env, "LINUX_RESTORE_OUTCOME": "failure" if fault == "action" else "success",
                                "LINUX_RESTORED_KEY": "wrong-key" if fault == "matched" else context["requested_key"]}
                observed = lambda _env, key: cache_metadata(
                    context, key, version="changed" if fault == "version" else "native-cache-version")
                result = campaign.linux_after_restore(context, restored_env, observed)
                self.assertEqual(result.get("fatal", False), fault != "none")
                self.assertEqual(result.get("restored_exact", False), fault == "none")
                if fault != "absent":
                    self.assertEqual((workspace / ".build/object").read_text(), "retained")

    def test_save_requires_all_commands_final_scan_storage_and_a_new_key(self):
        with linux_cache_fixture("seed") as (workspace, env, original):
            (workspace / ".build").mkdir()
            (workspace / ".build/object").write_text("compiled")
            passing = {**env, **{"LINUX_" + name + "_OUTCOME": "success" for name in ("RELEASE", "TESTS", "SMOKE")}}
            self.assertTrue(campaign.linux_before_save(copy.deepcopy(original), passing)["save"])
            for name in ("RELEASE", "TESTS", "SMOKE"):
                self.assertFalse(campaign.linux_before_save(copy.deepcopy(original),
                    {**passing, "LINUX_" + name + "_OUTCOME": "failure"})["save"])
            self.assertFalse(campaign.linux_before_save(
                {**copy.deepcopy(original), "restored_exact": True}, passing)["save"])
            with patch.object(campaign, "linux_storage", return_value={"eligible": False}):
                self.assertFalse(campaign.linux_before_save(copy.deepcopy(original), passing)["save"])
            (workspace / ".test-fixtures-live").mkdir()
            self.assertFalse(campaign.linux_before_save(copy.deepcopy(original), passing)["save"])

    def test_save_success_requires_exact_metadata_readback_to_claim_availability(self):
        with linux_cache_fixture("seed") as (_, env, original):
            for outcome, available in (("success", True), ("success", False), ("failure", True)):
                context = {**copy.deepcopy(original), "save": True}
                result = campaign.linux_after_save(context, {**env, "LINUX_SAVE_OUTCOME": outcome},
                    lambda *_args: cache_metadata(context) if available else {"total_count": 0, "actions_caches": []})
                self.assertEqual(result["publication"], "exact-entry-observed; producer-run-unproved"
                                 if available and outcome == "success" else "unavailable")

    def test_cli_phase_receipts_round_trip_through_actual_step_outputs(self):
        with linux_cache_fixture("warm") as (workspace, env, context):
            output = workspace / "step-output"
            env = {**env, "GITHUB_OUTPUT": str(output), "LINUX_LOOKUP_OUTCOME": "success",
                   "LINUX_RESTORE_OUTCOME": "success", "LINUX_SAVE_OUTCOME": "skipped",
                   **{"LINUX_" + name + "_OUTCOME": "success" for name in ("RELEASE", "TESTS", "SMOKE")}}
            for phase in ("source", "plan", "approve-restore", "after-restore", "before-save", "after-save"):
                if phase == "after-restore":
                    (workspace / ".build").mkdir()
                    (workspace / ".build/object").write_text("synthetic build")
                command = ["campaign", "linux-cache", phase]
                if phase == "source":
                    command += ["--checkout-sha", SHA]
                env.update(LINUX_CACHE_CONTEXT=campaign.encode(context),
                           LINUX_MATCHED_KEY=context.get("requested_key", ""),
                           LINUX_RESTORED_KEY=context.get("requested_key", ""))
                with patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", command), \
                        patch.object(campaign, "linux_version", return_value="native compiler identity\n"), \
                        patch.object(campaign, "linux_cache_metadata", side_effect=lambda _env, key:
                                     cache_metadata(context, key)), \
                        contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(campaign.main(), 0, phase)
                values = dict(line.split("=", 1) for line in output.read_text().splitlines())
                context = json.loads(values["context"])
                self.assertEqual(context["phase"], phase)
                self.assertEqual(context["expected_sha"], SHA)
                self.assertFalse(context["hard_extraction_byte_limit"])
            self.assertTrue(context["restored_exact"])
            self.assertEqual(context["save_disposition"], "exact-key-already-restored")
            self.assertEqual(context["publication"], "not-attempted")

    def test_workflow_preserves_commands_and_controls_manual_concurrency_and_cache_limits(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("group: ${{ github.event_name == 'workflow_dispatch' && "
                      "format('ci-manual-{0}-{1}-{2}-{3}', github.workflow, github.ref, "
                      "github.run_id, github.run_attempt) || format('ci-{0}-{1}', github.workflow, github.ref) }}",
                      workflow)
        self.assertIn("cancel-in-progress: ${{ github.event_name != 'workflow_dispatch' }}", workflow)
        linux = workflow.split("  build-linux-cli:\n", 1)[1]
        self.assertIn("actions: read", linux)
        self.assertLess(linux.index("Validate Linux campaign source"), linux.index("Restore Swift toolchain cache"))
        self.assertIn("lookup-only: true", linux)
        for name in ("Restore approved Linux application cache", "Save admitted Linux application cache"):
            step = linux.split("- name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            self.assertIn("timeout-minutes: 2", step)
            self.assertIn("SEGMENT_DOWNLOAD_TIMEOUT_MINS: '1'", step)
            self.assertIn("path: .build", step)
            self.assertIn("@55cc8345863c7cc4c66a329aec7e433d2d1c52a9", step)
        for name in ("Build CodexBarCLI (PR debug; main/manual release with static Swift stdlib)", "Swift Test (Linux only)",
                     "Smoke test CodexBarCLI"):
            step = linux.split("- name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            self.assertNotIn("if:", step)
            self.assertNotIn("cache-hit", step)
        self.assertIn("LINUX_BUILD_CONFIGURATION: ${{ github.event_name == 'pull_request' && 'debug' || 'release' }}", linux)
        self.assertIn('build_args=(-c "$LINUX_BUILD_CONFIGURATION" --product CodexBarCLI)', linux)
        self.assertIn('if [[ "$LINUX_BUILD_CONFIGURATION" == release ]]; then', linux)
        self.assertIn('build_args+=(--static-swift-stdlib)', linux)
        self.assertIn('swift build "${build_args[@]}"', linux)
        self.assertIn("run: ./Scripts/test.sh --command swift test --parallel", linux)
        self.assertIn("steps.linux-cache-restore.outcome", linux)
        self.assertIn("linux-cache after-save", linux)


class LinuxCacheFamilyTests(unittest.TestCase):
    def test_ordinary_push_and_pull_request_keep_the_complete_existing_key(self):
        with linux_cache_fixture() as (_, env, original):
            hashes = original["identity_hashes"]
            prefix = ("codexbar-linux-glibc-build-v1-X64-" + hashes["image"] + "-"
                      + hashes["toolchain"] + "-" + hashes["dependencies"] + "-")
            for event in ("push", "pull_request"):
                options = {**env, "GITHUB_EVENT_NAME": event, "LINUX_CACHE_MODE": "warm",
                           "LINUX_TIMESTAMP_MODE": "replay", "GITHUB_RUN_ID": "456", "GITHUB_RUN_ATTEMPT": "3"}
                context = campaign.linux_cache_plan(campaign.linux_cache_source(options, SHA), options,
                                                   lambda command: "native " + " ".join(command) + "\n")
                self.assertTrue(context["enabled"])
                self.assertEqual(context["restore_prefix"], prefix)
                self.assertEqual(context["requested_key"], prefix + SHA)
                self.assertEqual(context["requested_key"], original["requested_key"])
                self.assertEqual((context["linux_cache_mode"], context["linux_timestamp_mode"]), ("auto", "off"))

    def test_manual_treatments_share_one_key_independent_of_modes_and_run_attempt(self):
        with linux_cache_fixture() as (_, env, ordinary):
            prefix = ordinary["restore_prefix"].replace("glibc-build-v1-", "glibc-campaign-v1-", 1)
            for mode, treatment, run_id, attempt in (("seed", "record", "101", "1"),
                                                    ("warm", "off", "202", "2"),
                                                    ("warm", "replay", "303", "3")):
                options = {**env, "GITHUB_EVENT_NAME": "workflow_dispatch", "LINUX_CACHE_MODE": mode,
                           "LINUX_TIMESTAMP_MODE": treatment, "GITHUB_RUN_ID": run_id, "GITHUB_RUN_ATTEMPT": attempt}
                source = campaign.linux_cache_source(options, SHA)
                context = campaign.linux_cache_plan(source, options,
                                                   lambda command: "native " + " ".join(command) + "\n")
                self.assertTrue(context["enabled"])
                self.assertEqual(context["restore_prefix"], prefix)
                self.assertEqual(context["requested_key"], prefix + SHA)
                self.assertEqual(context["identity_hashes"], ordinary["identity_hashes"])
                self.assertEqual((context["run_id"], context["run_attempt"]), (run_id, attempt))
                rebound = campaign.linux_cache_plan(copy.deepcopy(context), {**options, "GITHUB_EVENT_NAME": "push"},
                                                   lambda command: "native " + " ".join(command) + "\n")
                self.assertEqual(rebound["requested_key"], context["requested_key"])

    def test_cross_family_hits_are_refused_before_metadata_and_warm_stays_fatal(self):
        with linux_cache_fixture() as (_, env, ordinary), linux_cache_fixture("seed") as (_, manual_env, manual):
            for original, options, foreign, fatal in (
                (ordinary, env, manual["requested_key"], False),
                (manual, manual_env, ordinary["requested_key"], False),
                ({**manual, "linux_cache_mode": "warm"}, manual_env, ordinary["requested_key"], True),
            ):
                with self.subTest(event=original["event"], mode=original["linux_cache_mode"]), \
                        patch.object(campaign, "linux_cache_metadata", return_value=cache_metadata(original, foreign)) as metadata:
                    result = campaign.linux_approve_restore(copy.deepcopy(original),
                        {**options, "LINUX_LOOKUP_OUTCOME": "success", "LINUX_MATCHED_KEY": foreign})
                    self.assertFalse(result["restore"])
                    self.assertEqual(result["fatal"], fatal)
                    metadata.assert_not_called()

    def test_manual_seed_is_reusable_by_warm_and_retains_all_identity_and_record_guards(self):
        with linux_cache_fixture("seed") as (seed_workspace, seed_env, seed), \
                linux_cache_fixture("warm") as (workspace, env, original):
            self.assertTrue(seed["requested_key"].startswith("codexbar-linux-glibc-campaign-v1-"))
            options = {**env, "GITHUB_RUN_ID": "456", "GITHUB_RUN_ATTEMPT": "2"}
            versions = lambda command: "native " + " ".join(command) + "\n"
            warm = campaign.linux_cache_plan(campaign.linux_cache_source(options, SHA), options, versions)
            self.assertEqual((warm["requested_key"], warm["restore_prefix"]),
                             (seed["requested_key"], seed["restore_prefix"]))
            metadata = cache_metadata(seed)
            approved = campaign.linux_approve_restore(warm,
                {**options, "LINUX_LOOKUP_OUTCOME": "success", "LINUX_MATCHED_KEY": seed["requested_key"]},
                lambda *_: metadata)
            self.assertTrue(approved["restore"])
            (workspace / ".build").mkdir()
            (workspace / ".build/restored-object").write_bytes(b"synthetic cached output")
            restored = campaign.linux_after_restore(approved,
                {**options, "LINUX_RESTORE_OUTCOME": "success", "LINUX_RESTORED_KEY": seed["requested_key"]},
                lambda *_: metadata)
            self.assertTrue(restored["restored_exact"])
            self.assertEqual(restored["approved_entry"]["version"], "native-cache-version")
            record = {**restored, "linux_cache_mode": "seed", "linux_timestamp_mode": "record"}
            self.assertTrue(campaign.linux_input_timestamps(record, options)["fatal"])
            self.assertEqual(record["input_timestamps"]["attempted"], 0)
            for field, value in (("RUNNER_ARCH", "ARM64"), ("LINUX_RUNNER_LABEL", "ubuntu-24.04-arm"),
                                 ("ImageOS", "ubuntu-next"), ("ImageVersion", "20261002.1")):
                changed = campaign.linux_cache_plan(copy.deepcopy(seed), {**seed_env, field: value}, versions)
                self.assertNotEqual(changed["restore_prefix"], seed["restore_prefix"])
            toolchain = campaign.linux_cache_plan(copy.deepcopy(seed), seed_env, lambda _: "changed compiler")
            self.assertNotEqual(toolchain["restore_prefix"], seed["restore_prefix"])
            newer = {**seed_env, "GITHUB_SHA": "b" * 40, "CAMPAIGN_EXPECTED_SHA": "b" * 40}
            changed = campaign.linux_cache_plan(campaign.linux_cache_source(newer, "b" * 40), newer, versions)
            self.assertEqual(changed["restore_prefix"], seed["restore_prefix"])
            self.assertNotEqual(changed["requested_key"], seed["requested_key"])
            (seed_workspace / "Package.resolved").write_text('{"pins":["changed"]}\n')
            changed = campaign.linux_cache_plan(copy.deepcopy(seed), seed_env, versions)
            self.assertNotEqual(changed["restore_prefix"], seed["restore_prefix"])


@contextlib.contextmanager
def linux_timestamp_fixture(qualify=True):
    with linux_cache_fixture("seed") as (workspace, env, context):
        (workspace / "Sources").mkdir()
        (workspace / "Sources/A.swift").write_bytes(b"let a = 1\n")
        (workspace / "Sources/B.swift").write_bytes(b"let b = 2\n")
        (workspace / "Sources/link.swift").symlink_to("A.swift")
        inventory = []
        for index, path in enumerate(("Package.resolved", "Package.swift", "Sources/A.swift",
                                      "Sources/B.swift", "Sources/link.swift")):
            target = workspace / path
            symlink = target.is_symlink()
            data = os.fsencode(os.readlink(target)) if symlink else target.read_bytes()
            inventory.append({"path": path, "git_mode": "120000" if symlink else "100644",
                              "git_oid": hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()})
            stamp = 1700000000123456789 + index
            os.utime(target, ns=(stamp, stamp), follow_symlinks=False)
        reader = lambda *_args: copy.deepcopy(inventory)
        context["linux_timestamp_mode"] = "record"
        campaign.linux_input_timestamps(context, env, reader)
        if context.get("fatal"):
            raise AssertionError(context["input_timestamps"])
        if qualify:
            campaign.linux_input_after_build(context, env, reader)
        yield workspace, env, context, inventory, reader


def linux_timestamp_warm(workspace, context):
    warm = {**copy.deepcopy(context), "linux_cache_mode": "warm", "linux_timestamp_mode": "replay",
            "restored": True, "restored_exact": True, "producer_source": SHA}
    manifest, _, _ = campaign.linux_input_manifest(workspace)
    for item in manifest["entries"]:
        path = workspace / item["path"]
        stamp = item["mtime_ns"] + 5000000007
        os.utime(path, ns=(stamp, stamp), follow_symlinks=False)
    return warm, manifest


@contextlib.contextmanager
def linux_timestamp_read_race(workspace, snapshot_index):
    path = workspace / "Sources/A.swift"
    identity = path.stat()
    real_read = os.read
    real_fingerprint = campaign.linux_input_fingerprint
    snapshot = campaign.linux_input_snapshot
    evidence = {"changed": False, "snapshot": 0, "read_ordinal": 0, "reads_by_snapshot": {}}

    def fingerprint(info):
        value = real_fingerprint(info)
        if (info.st_dev, info.st_ino) == (identity.st_dev, identity.st_ino):
            # Model coarse ctime observation only; all other identity/content checks stay real.
            return (*value[:-1], identity.st_ctime_ns)
        return value

    def observed_snapshot(*args, **kwargs):
        evidence["snapshot"] += 1
        return snapshot(*args, **kwargs)

    def raced_read(descriptor, amount):
        before = os.fstat(descriptor)
        data = real_read(descriptor, amount)
        if (before.st_dev, before.st_ino) == (identity.st_dev, identity.st_ino):
            evidence["read_ordinal"] += 1
            phase = evidence["snapshot"]
            evidence["reads_by_snapshot"][phase] = evidence["reads_by_snapshot"].get(phase, 0) + 1
            if not evidence["changed"] and phase == snapshot_index:
                evidence["changed"] = True
                path.write_bytes(b"let a = 9\n")
                os.utime(path, ns=(identity.st_atime_ns, identity.st_mtime_ns))
                after = os.fstat(descriptor)
                evidence["injection"] = {"snapshot": phase, "read_ordinal": evidence["read_ordinal"],
                    "snapshot_read_ordinal": evidence["reads_by_snapshot"][phase],
                    "real_before": real_fingerprint(before), "real_after": real_fingerprint(after),
                    "observed_before": fingerprint(before), "observed_after": fingerprint(after)}
        return data

    with patch.object(campaign, "linux_input_snapshot", side_effect=observed_snapshot), \
            patch.object(campaign, "linux_input_fingerprint", side_effect=fingerprint), \
            patch.object(campaign.os, "read", side_effect=raced_read):
        yield evidence


class LinuxTimestampTests(unittest.TestCase):
    def test_controls_are_default_off_and_only_admit_manual_record_seed_or_replay_warm(self):
        with linux_cache_fixture("off") as (_, env, context):
            self.assertEqual(context["linux_timestamp_mode"], "off")
            for timestamp, cache, allowed in (("record", "seed", True), ("replay", "warm", True),
                                              ("record", "warm", False), ("replay", "seed", False),
                                              ("replay", "off", False), ("unknown", "seed", False)):
                options = {**env, "LINUX_TIMESTAMP_MODE": timestamp, "LINUX_CACHE_MODE": cache}
                if allowed:
                    self.assertEqual(campaign.linux_cache_source(options, SHA)["linux_timestamp_mode"], timestamp)
                else:
                    with self.assertRaises(ValueError):
                        campaign.linux_cache_source(options, SHA)
            ordinary = campaign.linux_cache_source({**env, "GITHUB_EVENT_NAME": "push",
                                                    "LINUX_TIMESTAMP_MODE": "replay"}, SHA)
            self.assertEqual(ordinary["linux_timestamp_mode"], "off")
            with patch.object(campaign, "linux_input_update") as update:
                self.assertIs(campaign.linux_input_timestamps(ordinary, {}), ordinary)
                campaign.linux_input_after_build(ordinary, {})
                update.assert_not_called()

    def test_record_binds_complete_inputs_and_qualifies_only_unchanged_producer_inputs(self):
        with linux_timestamp_fixture(qualify=False) as (workspace, env, context, _, reader):
            manifest, before_hash, _ = campaign.linux_input_manifest(workspace)
            self.assertEqual(manifest["state"], "before-build")
            self.assertEqual(manifest["binding"], campaign.linux_input_binding(context))
            self.assertEqual(manifest["roots"], list(campaign.LINUX_INPUT_ROOTS))
            self.assertEqual(len(manifest["entries"]), 5)
            self.assertEqual(manifest["entries"][0]["mtime_ns"], 1700000000123456789)
            campaign.linux_input_after_build(context, env, reader)
            qualified, after_hash, size = campaign.linux_input_manifest(workspace)
            self.assertEqual(qualified["state"], "qualified")
            self.assertNotEqual(before_hash, after_hash)
            self.assertEqual(context["input_timestamps"]["manifest_sha256"], after_hash)
            self.assertLess(size, campaign.LINUX_INPUT_METADATA_BYTES)
            self.assertEqual(list((workspace / ".build").iterdir()),
                             [workspace / ".build" / campaign.LINUX_INPUT_MANIFEST])

    def test_replay_preserves_nanoseconds_and_symlink_target_while_matching_all_inputs(self):
        with linux_timestamp_fixture() as (workspace, env, context, _, reader):
            warm, manifest = linux_timestamp_warm(workspace, context)
            result = campaign.linux_input_timestamps(warm, env, reader)
            self.assertFalse(result.get("fatal", False))
            receipt = result["input_timestamps"]
            self.assertEqual((receipt["before_matching"], receipt["after_matching"], receipt["applied"]), (0, 5, 5))
            for entry in manifest["entries"]:
                self.assertEqual((workspace / entry["path"]).lstat().st_mtime_ns, entry["mtime_ns"])
            self.assertEqual(os.readlink(workspace / "Sources/link.swift"), "A.swift")
            self.assertEqual((workspace / "Sources/A.swift").read_bytes(), b"let a = 1\n")
            campaign.linux_input_after_build(result, env, reader)
            self.assertEqual(result["input_timestamps"]["after_build_matching"], 5)

    def test_same_size_edit_is_rejected_before_any_timestamp_changes(self):
        with linux_timestamp_fixture() as (workspace, env, context, _, reader):
            warm, _ = linux_timestamp_warm(workspace, context)
            (workspace / "Sources/A.swift").write_bytes(b"let a = 9\n")
            with patch.object(campaign, "linux_input_update") as update:
                result = campaign.linux_input_timestamps(warm, env, reader)
                self.assertTrue(result["fatal"])
                self.assertIn("content differs", result["input_timestamps"]["reason"])
                update.assert_not_called()

    def test_missing_new_mode_and_source_mismatches_refuse_the_complete_manifest(self):
        for fault in ("missing", "new", "mode", "source", "pending", "exact"):
            with self.subTest(fault=fault), linux_timestamp_fixture() as (workspace, env, context, inventory, reader):
                warm, manifest = linux_timestamp_warm(workspace, context)
                if fault == "missing":
                    (workspace / "Sources/B.swift").unlink()
                elif fault == "new":
                    (workspace / "Sources/new.swift").write_bytes(b"new")
                    inventory.append({"path": "Sources/new.swift", "git_mode": "100644",
                                      "git_oid": hashlib.sha1(b"blob 3\0new").hexdigest()})
                elif fault == "mode":
                    (workspace / "Sources/B.swift").chmod(0o755)
                elif fault == "source":
                    warm["actual_sha"] = "b" * 40
                    warm["producer_source"] = "b" * 40
                elif fault == "pending":
                    manifest["state"] = "before-build"
                    campaign.linux_input_manifest(workspace, manifest)
                else:
                    warm["restored_exact"] = False
                with patch.object(campaign, "linux_input_update") as update:
                    self.assertTrue(campaign.linux_input_timestamps(warm, env, reader)["fatal"])
                    update.assert_not_called()

    def test_git_inventory_rejects_new_untracked_and_staged_inputs(self):
        with linux_timestamp_fixture() as (workspace, _, _, inventory, _):
            tree = b"".join(f"{item['git_mode']} blob {item['git_oid']}\t{item['path']}\0".encode()
                            for item in inventory)
            index = b"".join(f"{item['git_mode']} {item['git_oid']} 0\t{item['path']}\0".encode()
                             for item in inventory)
            for raw, allowed in ((index, True), (index + b"Sources/new.swift\0", False),
                                  (index.replace(b"Sources/B.swift", b"Sources/C.swift"), False)):
                with patch.object(campaign, "linux_input_git", side_effect=[(SHA + "\n").encode(), tree, raw]) as read:
                    if allowed:
                        self.assertEqual(campaign.linux_input_inventory(workspace, SHA, 1), inventory)
                    else:
                        with self.assertRaises(ValueError):
                            campaign.linux_input_inventory(workspace, SHA, 1)
                    self.assertNotIn("--exclude-standard", read.call_args.args[1])

    def test_symlink_escape_ancestry_chain_and_special_files_are_rejected_without_updates(self):
        for fault in ("escape", "ancestor", "chain", "fifo"):
            with self.subTest(fault=fault), linux_timestamp_fixture() as (workspace, env, context, _, reader):
                warm, _ = linux_timestamp_warm(workspace, context)
                sentinel = workspace.parent / "outside.swift"
                sentinel.write_text("outside remains unchanged")
                stamp = sentinel.stat().st_mtime_ns
                if fault == "ancestor":
                    (workspace / "Sources").rename(workspace / "elsewhere")
                    (workspace / "Sources").symlink_to("elsewhere")
                elif fault == "fifo":
                    (workspace / "Sources/B.swift").unlink()
                    os.mkfifo(workspace / "Sources/B.swift")
                else:
                    link = workspace / "Sources/link.swift"
                    link.unlink()
                    if fault == "chain":
                        (workspace / "Sources/second").symlink_to("A.swift")
                    link.symlink_to("second" if fault == "chain" else "../../outside.swift")
                with patch.object(campaign, "linux_input_update") as update:
                    self.assertTrue(campaign.linux_input_timestamps(warm, env, reader)["fatal"])
                    update.assert_not_called()
                self.assertEqual(sentinel.stat().st_mtime_ns, stamp)

    def test_hashing_race_fails_even_when_size_and_mtime_are_restored(self):
        with linux_timestamp_fixture() as (workspace, env, context, _, reader):
            warm, _ = linux_timestamp_warm(workspace, context)
            with linux_timestamp_read_race(workspace, 1) as race:
                result = campaign.linux_input_timestamps(warm, env, reader)
            print("Timestamp race fixture: " + campaign.encode({"race": race, "receipt": result["input_timestamps"]}))
            self.assertTrue(race["changed"])
            injection = race["injection"]
            self.assertEqual((injection["snapshot"], injection["read_ordinal"],
                              injection["snapshot_read_ordinal"]), (1, 1, 1))
            self.assertEqual(injection["observed_before"], injection["observed_after"])
            self.assertEqual(injection["real_before"][:-1], injection["real_after"][:-1])
            self.assertTrue(result["fatal"])
            self.assertEqual(result["input_timestamps"]["attempted"], 0)

    def test_second_scan_race_reports_exact_partial_replay_without_timestamping_changed_input(self):
        with linux_timestamp_fixture() as (workspace, env, context, _, reader):
            warm, manifest = linux_timestamp_warm(workspace, context)
            original_manifest = campaign.linux_input_manifest(workspace)
            path = workspace / "Sources/A.swift"
            warm_mtime = path.stat().st_mtime_ns
            with linux_timestamp_read_race(workspace, 2) as race:
                result = campaign.linux_input_timestamps(warm, env, reader)
            receipt = result["input_timestamps"]
            print("Timestamp race fixture: " + campaign.encode({"race": race, "receipt": receipt}))
            self.assertTrue(race["changed"])
            self.assertEqual((race["injection"]["snapshot"], race["injection"]["snapshot_read_ordinal"]), (2, 1))
            self.assertEqual(race["injection"]["observed_before"], race["injection"]["observed_after"])
            self.assertTrue(result["fatal"])
            self.assertEqual((receipt["attempted"], receipt["applied"]), (2, 2))
            self.assertTrue(receipt["partial_replay_possible"])
            updated = [entry["path"] for entry in manifest["entries"]
                       if (workspace / entry["path"]).lstat().st_mtime_ns == entry["mtime_ns"]]
            self.assertEqual(updated, ["Package.resolved", "Package.swift"])
            self.assertEqual(path.stat().st_mtime_ns, warm_mtime)
            self.assertEqual(path.read_bytes(), b"let a = 9\n")
            self.assertEqual(campaign.linux_input_manifest(workspace), original_manifest)

    def test_change_between_complete_verification_and_replay_is_detected(self):
        with linux_timestamp_fixture() as (workspace, env, context, _, reader):
            warm, _ = linux_timestamp_warm(workspace, context)
            snapshot = campaign.linux_input_snapshot
            def changed_after_scan(*args):
                result = snapshot(*args)
                (workspace / "Package.resolved").write_bytes(b"changed")
                return result
            with patch.object(campaign, "linux_input_snapshot", side_effect=changed_after_scan), \
                    patch.object(campaign, "linux_input_update") as update:
                result = campaign.linux_input_timestamps(warm, env, reader)
                self.assertTrue(result["fatal"])
                update.assert_not_called()

    def test_partial_update_failure_is_explicit_and_retains_manifest_diagnostics(self):
        with linux_timestamp_fixture() as (workspace, env, context, _, reader):
            warm, manifest = linux_timestamp_warm(workspace, context)
            real_update = campaign.linux_input_update
            calls = 0
            def fail_second(*args, **kwargs):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("synthetic partial replay failure")
                return real_update(*args, **kwargs)
            with patch.object(campaign, "linux_input_update", side_effect=fail_second):
                result = campaign.linux_input_timestamps(warm, env, reader)
            receipt = result["input_timestamps"]
            self.assertTrue(result["fatal"])
            self.assertEqual((receipt["attempted"], receipt["applied"]), (2, 1))
            self.assertTrue(receipt["partial_replay_possible"])
            self.assertEqual((workspace / manifest["entries"][0]["path"]).stat().st_mtime_ns,
                             manifest["entries"][0]["mtime_ns"])
            self.assertTrue((workspace / ".build" / campaign.LINUX_INPUT_MANIFEST).is_file())

    def test_producer_changes_fail_save_and_preserve_pending_manifest(self):
        with linux_timestamp_fixture(qualify=False) as (workspace, env, context, _, reader):
            (workspace / "Sources/A.swift").write_bytes(b"let a = 9\n")
            passing = {**env, **{"LINUX_" + name + "_OUTCOME": "success" for name in ("RELEASE", "TESTS", "SMOKE")}}
            with patch.object(campaign, "linux_input_inventory", side_effect=reader):
                result = campaign.linux_before_save(context, passing)
            self.assertFalse(result["save"])
            self.assertTrue(result["fatal"])
            self.assertEqual(campaign.linux_input_manifest(workspace)[0]["state"], "before-build")

    def test_input_byte_path_time_and_metadata_limits_refuse_without_large_allocations(self):
        for field, limit in (("LINUX_INPUT_BYTES", 1), ("LINUX_INPUT_PATHS", 1),
                             ("LINUX_INPUT_SECONDS", -1), ("LINUX_INPUT_METADATA_BYTES", 1)):
            with self.subTest(field=field), linux_timestamp_fixture() as (workspace, env, context, _, reader):
                warm, _ = linux_timestamp_warm(workspace, context)
                with patch.object(campaign, field, limit):
                    result = campaign.linux_input_timestamps(warm, env, reader)
                self.assertTrue(result["fatal"])
                self.assertEqual(result["input_timestamps"]["attempted"], 0)
        self.assertEqual(campaign.LINUX_CACHE_BYTES, 2 * 1024 ** 3)

    def test_workflow_experiment_preserves_default_off_commands_and_cache_guards(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        options = workflow.split("      linux_timestamp_mode:\n", 1)[1].split("\nconcurrency:", 1)[0]
        self.assertIn("options: ['off', record, replay]", options)
        self.assertIn("default: 'off'", options)
        linux = workflow.split("  build-linux-cli:\n", 1)[1]
        self.assertIn("github.event_name == 'workflow_dispatch' && inputs.linux_timestamp_mode || 'off'", linux)
        self.assertLess(linux.index("linux-cache after-restore"), linux.index("linux-cache input-timestamps"))
        self.assertLess(linux.index("linux-cache input-timestamps"), linux.index('swift build "${build_args[@]}"'))
        self.assertIn("steps.linux-input-timestamps.outputs.context ||", linux)
        for name in ("Build CodexBarCLI (PR debug; main/manual release with static Swift stdlib)", "Swift Test (Linux only)",
                     "Smoke test CodexBarCLI"):
            step = linux.split("- name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            self.assertNotIn("if:", step)
            self.assertNotIn("--skip-build", step)
        for name in ("Restore approved Linux application cache", "Save admitted Linux application cache"):
            step = linux.split("- name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            self.assertIn("timeout-minutes: 2", step)
            self.assertIn("SEGMENT_DOWNLOAD_TIMEOUT_MINS: '1'", step)


class EvidenceTests(unittest.TestCase):
    def test_discovery_retains_every_test_identity_and_stable_digest(self):
        stats = runner.RunStats()
        with patch.object(runner, "run_captured_command", return_value=completed([])), \
                patch.dict(runner.os.environ, {"GITHUB_SHA": "candidate-revision"}), \
                contextlib.redirect_stderr(io.StringIO()) as output:
            selections = runner.swift_test_list(["swift"], stats)
        record, = evidence_records(output.getvalue())
        self.assertEqual(record["schema"], "codexbar.swift-test-evidence/v1")
        self.assertEqual(record["event"], "discovery")
        self.assertEqual(record["source_revision"], "candidate-revision")
        self.assertEqual(record["test_ids"], sorted(TEST_IDS))
        digest = hashlib.sha256(("\n".join(sorted(TEST_IDS)) + "\n").encode()).hexdigest()
        self.assertEqual(record["sha256"], digest)
        self.assertEqual(stats.discovered_tests, len(TEST_IDS))
        self.assertEqual(stats.discovery_manifest_sha256, digest)
        self.assertEqual(len(selections), 3)

    def test_list_only_stdout_and_shard_union_stay_exact(self):
        all_names = []
        for shard in range(2):
            with patch.object(sys, "argv", ["runner", "--group-size", "2", "--shard-index", str(shard),
                                            "--shard-count", "2", "--list-only"]), \
                    patch.object(runner, "run_captured_command", return_value=completed([])), \
                    contextlib.redirect_stdout(io.StringIO()) as stdout, \
                    contextlib.redirect_stderr(io.StringIO()) as stderr:
                self.assertEqual(runner.run_suites(), 0)
            names = stdout.getvalue().splitlines()
            selection, = [item for item in evidence_records(stderr.getvalue()) if item["event"] == "selection"]
            self.assertEqual(selection["shard_index"], shard)
            self.assertEqual(selection["shard_count"], 2)
            self.assertEqual([name for group in selection["groups"] for name in group], names)
            all_names.extend(names)
        self.assertEqual(sorted(all_names), [
            "CodexBarTests.Alpha", "CodexBarTests.Legacy", "CodexBarTests.`top/level works`()",
        ])

    def test_attempt_timing_includes_the_unchanged_command_and_result(self):
        selection = runner.TestSelection("CodexBarTests.Legacy", r"^CodexBarTests\.Legacy/")
        for status in (0, 23, 124):
            with self.subTest(status=status), \
                    patch.object(runner, "run_command", return_value=status) as invoke, \
                    patch.object(runner.time, "monotonic", side_effect=[10.0, 11.25]), \
                    contextlib.redirect_stderr(io.StringIO()) as output:
                self.assertEqual(runner.run_group([selection], 120, ["swift"], attempt="group-retry"), status)
            invoke.assert_called_once_with([
                "swift", "test", "--skip-build", "--no-parallel", "--filter", runner.filter_for([selection]),
            ], timeout=120)
            record, = evidence_records(output.getvalue())
            self.assertEqual(record["event"], "attempt")
            self.assertEqual(record["attempt"], "group-retry")
            self.assertEqual(record["selections"], [selection.name])
            self.assertEqual(record["exit_code"], status)
            self.assertEqual(record["elapsed_seconds"], 1.25)
            self.assertEqual(record["timeout_seconds"], 120)

    def test_unproved_drain_is_reported_and_still_raises(self):
        with patch.object(runner, "run_command", side_effect=runner.CommandDrainError("unproved drain", 23)), \
                contextlib.redirect_stderr(io.StringIO()) as output:
            with self.assertRaises(runner.CommandDrainError):
                runner.run_group([runner.TestSelection("Alpha", "Alpha")], 120, ["swift"])
        record, = evidence_records(output.getvalue())
        self.assertIsNone(record["exit_code"])
        self.assertEqual(record["error"], "CommandDrainError")


if __name__ == "__main__":
    unittest.main()
