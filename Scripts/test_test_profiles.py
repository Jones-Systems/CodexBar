#!/usr/bin/env python3
"""Profile contracts: fail closed, preserve shared compilation, explain every guard."""
import contextlib
import copy
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import ci_swift_test_by_suite as runner

import test_profiles as profiles


class ProfileContractTests(unittest.TestCase):
    def test_selection_is_explicit_and_invalid_values_fail(self):
        self.assertEqual(profiles.selected_profile({}), "normal")
        self.assertEqual(profiles.selected_profile({"CODEXBAR_TEST_PROFILE": "full"}), "full")
        for value in ("", "FULL", "typo", "normal full"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                profiles.selected_profile({"CODEXBAR_TEST_PROFILE": value})

    def test_manifest_paths_fail_closed(self):
        with tempfile.TemporaryDirectory(prefix=".test-profiles-", dir=profiles.ROOT) as temporary:
            root = Path(temporary)
            (root / "Scripts").mkdir()
            (root / "Tests").mkdir()
            (root / "Tests/Example.swift").write_text("import Testing\n")
            base = {"version": 1, "normal_providers": ["codex", "claude"], "mixed_full_only": [],
                    "full_only_groups": [{"id": "unused", "category": "unused_provider", "reason": "Unused feature",
                                          "files": ["Tests/Example.swift"]}]}
            def load(manifest):
                (root / profiles.MANIFEST).write_text(json.dumps(manifest))
                return profiles.load_manifest(root)
            self.assertEqual(load(base), base)
            empty = {**base, "full_only_groups": []}
            self.assertEqual(load(empty), empty)
            for path in ("Tests/../Sources/Example.swift", "/Tests/Example.swift", "Sources/Example.swift",
                         "Tests/Missing.swift", "Tests//Example.swift"):
                changed = copy.deepcopy(base)
                changed["full_only_groups"][0]["files"] = [path]
                with self.subTest(path=path), self.assertRaises(ValueError):
                    load(changed)
            duplicate = copy.deepcopy(base)
            duplicate["full_only_groups"][0]["files"] *= 2
            with self.assertRaisesRegex(ValueError, "Duplicate"):
                load(duplicate)
            changed = copy.deepcopy(base)
            changed["version"] = 2
            with self.assertRaises(ValueError):
                load(changed)

    def test_native_execution_receipt_keeps_function_and_method_counts_separate(self):
        output = ("Test Suite 'Selected tests' passed at 2026-10-24\n"
                  "\t Executed 7 tests, with 0 failures in 0.1 seconds\n"
                  "✔ Test run with 42 tests in 3 suites passed after 0.2 seconds.\n")
        command = ["swift", "test", "--skip-build", "--parallel"]
        completed = subprocess.CompletedProcess(command, 0, output, "")
        with patch.object(runner, "run_captured_command", return_value=completed) as invoke, \
                contextlib.redirect_stdout(io.StringIO()) as captured:
            self.assertEqual(runner.run_test_command(command, timeout=120), 0)
        invoke.assert_called_once_with(command, timeout=120)
        receipt = json.loads(captured.getvalue().split("Swift test execution counts: ")[1])
        self.assertEqual(receipt, {"swift_testing_functions": 42, "xctest_methods": 7, "exit_code": 0})

    def test_checked_in_partition_preserves_shared_inputs_and_explains_guards(self):
        manifest = profiles.load_manifest()
        excluded = {p for g in manifest["full_only_groups"] for p in g["files"]}
        for retained in ("TestsPlugin/CodexBarCoreResourcesPortableTests.swift",
                         "Tests/CodexBarTests/MiniMaxLogRedactorTests.swift",
                         "Tests/CodexBarTests/KiroStatusProbeTTYHardStopTests.swift",
                         "Tests/CodexBarTests/KiroStatusProbeTTYProcessTests.swift",
                         "Tests/CodexBarTests/OpenCodexUsageFanOutTests.swift",
                         "Tests/CodexBarTests/CLIWebFallbackTests.swift",
                         "Tests/CodexBarTests/RefreshFailureHookStatusTests.swift"):
            self.assertNotIn(retained, excluded)
        entries = {e["file"]: e for e in manifest["mixed_full_only"]}
        actual = {}
        for directory in ("Tests", "TestsLinux", "TestsPlugin"):
            for path in (profiles.ROOT / directory).rglob("*.swift"):
                if path.is_symlink():
                    continue
                stack = []
                pending = False
                guarded = []
                for line in path.read_text().splitlines():
                    stripped = line.strip()
                    if stripped.startswith("#if "):
                        stack.append(stripped == "#if CODEXBAR_FULL_TEST_PROFILE")
                    elif stripped.startswith("#endif"):
                        stack.pop()
                    elif stripped.startswith(("#else", "#elseif")) and any(stack):
                        self.fail(f"Ambiguous profile guard branch: {path}")
                    if re.match(r"\s*@Test\b", line):
                        pending = any(stack)
                    method = re.match(r"\s*(?:private |static |mutating )*func\s+(`[^`]+`|\w+)", line)
                    if method and pending:
                        guarded.append(method[1].strip("`"))
                        pending = False
                if guarded:
                    actual[str(path.relative_to(profiles.ROOT))] = guarded
        self.assertEqual(set(actual), set(entries))
        for file, tests in actual.items():
            with self.subTest(file=file):
                self.assertEqual(tests, entries[file]["tests"])
        for path in (profiles.ROOT / "Sources").rglob("*.swift"):
            self.assertNotIn("CODEXBAR_FULL_TEST_PROFILE", path.read_text(), str(path))


if __name__ == "__main__":
    unittest.main()
