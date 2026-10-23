#!/usr/bin/env python3
"""Synthetic discovery, timing, and cache contracts; no Swift toolchain required."""

import contextlib
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest
from unittest.mock import patch

import ci_swift_test_by_suite as runner


ROOT = Path(__file__).resolve().parent.parent
TEST_IDS = [
    "CodexBarTests.Alpha/test_one()",
    "CodexBarTests.Alpha/test_two(argument:)",
    "CodexBarTests.Legacy/test_example",
    "CodexBarTests.`top/level works`()",
]


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
