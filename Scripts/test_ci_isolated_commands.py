#!/usr/bin/env python3
"""Exercise CI entry points with synthetic Swift commands and contained fixtures."""

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import ci_swift_test_by_suite as runner


ROOT = Path(__file__).resolve().parent.parent
FILTER = (
    "ProviderPluginRuntimeTests|ProviderPluginParityTests|ProviderPluginDetailsParityTests|"
    "ProviderPluginExtensionParityTests|Sub2APIPluginGoldenTests|UserProviderPluginPortableTests"
)


class IsolatedCICommandsTests(unittest.TestCase):
    def setUp(self):
        parent = runner.fixture_scratch_parent(dict(os.environ))
        self.root = Path(tempfile.mkdtemp(prefix="ci-command-proof-", dir=parent))
        self.addCleanup(self.cleanup_fixture)
        self.workspace = self.root / "workspace"
        scripts = self.workspace / "Scripts"
        scripts.mkdir(parents=True)
        for name in ("test.sh", "test-plugin-engines.sh", "ci_swift_test_by_suite.py", "build_jobs.py"):
            shutil.copy2(ROOT / "Scripts" / name, scripts / name)
        helper = scripts / "build_jobs.py"
        helper.write_text(helper.read_text().replace(
            'PLATFORM = sys.platform', 'PLATFORM = "linux"'))
        tools = self.root / "tools"
        tools.mkdir()
        swift = tools / "swift"
        swift.write_text(f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
parent = pathlib.Path(os.environ["CODEXBAR_TEST_SCRATCH_PARENT"])
workspace = pathlib.Path(os.environ["CODEXBAR_TEST_WORKSPACE_ROOT"])
assert parent.is_dir() and workspace in parent.parents
assert os.environ["TMPDIR"] == str(parent)
for key in ("CODEXBAR_TEST_CODEX_FILE_ISOLATION", "CODEXBAR_TEST_SESSION_FILE_ISOLATION",
            "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"):
    assert os.environ[key] == "1", key
assert "CODEXBAR_TEST_CODEX_FILE_FIXTURES" not in os.environ
(parent / "synthetic-fixture").write_text("fixture")
with open(os.environ["CI_COMMAND_RECORD"], "a") as output:
    output.write(json.dumps({"args": sys.argv[1:], "engine": os.environ.get("CODEXBAR_PLUGIN_ENGINE"),
                             "parent": str(parent)}) + "\\n")
sys.exit(int(os.environ.get("CI_COMMAND_EXIT", "0")))
''')
        swift.chmod(0o700)
        self.record = self.root / "commands.jsonl"
        self.env = {
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "HOME": str(self.root / "synthetic-home"),
            "PYTHONDONTWRITEBYTECODE": "1",
            "CI_COMMAND_RECORD": str(self.record),
            "CODEXBAR_TEST_CODEX_FILE_FIXTURES": "inherited grant must be removed",
            "CODEXBAR_PLUGIN_ENGINE": "inherited engine must be replaced",
        }

    def cleanup_fixture(self):
        if not runner._scratch_cleanup_safe:
            raise RuntimeError(f"Preserving CI command proof after unproved drain: {self.root}")
        shutil.rmtree(self.root)
        self.assertFalse(self.root.exists())

    def invoke(self, command):
        with (self.root / "output.log").open("w+") as output:
            with patch.dict(os.environ, self.env, clear=True):
                status = runner.run_command(command, timeout=20, stdout=output, stderr=output)
            output.seek(0)
            self.output = output.read()
        return status

    def records(self):
        return [json.loads(line) for line in self.record.read_text().splitlines()]

    def assert_owned_cleanup(self, records):
        parents = {item["parent"] for item in records}
        self.assertEqual(len(parents), 1)
        for parent in parents:
            self.assertFalse(Path(parent).exists())
        self.assertIn("removed and absence verified", self.output)
        self.assertEqual(list(self.workspace.glob(".test-fixtures-*")), [])

    def test_linux_command_retains_parallel_selection_and_cleanup(self):
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("run: ./Scripts/test.sh --command swift test --parallel", workflow)
        status = self.invoke([str(self.workspace / "Scripts/test.sh"), "--command", "swift", "test", "--parallel"])
        self.assertEqual(status, 0, self.output)
        records = self.records()
        self.assertEqual([item["args"] for item in records], [["test", "--parallel"]])
        self.assert_owned_cleanup(records)

    def test_focused_command_caps_explicit_twelve_on_macos(self):
        helper = self.workspace / "Scripts/build_jobs.py"
        helper.write_text(helper.read_text().replace('PLATFORM = "linux"', 'PLATFORM = "darwin"') +
                          '\nlock_directory = lambda: Path(' + repr(str(self.root / "lock")) + ')\n' +
                          'sample_window = lambda deadline: (Fraction(1, 5), Fraction(1, 5), 30)\n' +
                          'os.cpu_count = lambda: 12\n')
        status = self.invoke([str(self.workspace / "Scripts/test.sh"), "--command", "swift", "test",
                              "--filter", "FocusedTests", "-j12"])
        self.assertEqual(status, 0, self.output)
        records = self.records()
        self.assertEqual(records[0]["args"], ["test", "--filter", "FocusedTests", "--jobs", "6"])
        self.assert_owned_cleanup(records)

    def test_plugin_passes_share_parent_and_preserve_filters(self):
        status = self.invoke([str(self.workspace / "Scripts/test-plugin-engines.sh")])
        self.assertEqual(status, 0, self.output)
        records = self.records()
        self.assertEqual([item["engine"] for item in records], [None, "jsc"])
        self.assertEqual([item["args"] for item in records], [
            ["test", "--filter", FILTER], ["test", "--skip-build", "--filter", FILTER],
        ])
        self.assert_owned_cleanup(records)

    def test_plugin_failure_keeps_status_and_does_not_run_second_engine(self):
        self.env["CI_COMMAND_EXIT"] = "37"
        status = self.invoke([str(self.workspace / "Scripts/test-plugin-engines.sh")])
        self.assertEqual(status, 37, self.output)
        records = self.records()
        self.assertEqual(len(records), 1)
        self.assert_owned_cleanup(records)

    def test_borrowed_parent_is_retained_on_command_failure(self):
        parent = self.workspace / "borrowed"
        parent.mkdir()
        sibling = parent / "caller-owned"
        sibling.write_text("retain")
        self.env["CODEXBAR_TEST_SCRATCH_PARENT"] = str(parent)
        self.env["CI_COMMAND_EXIT"] = "37"
        status = self.invoke([str(self.workspace / "Scripts/test.sh"), "--command", "swift", "test", "--parallel"])
        self.assertEqual(status, 37, self.output)
        self.assertEqual(sibling.read_text(), "retain")
        self.assertEqual(self.records()[0]["parent"], str(parent))

    def test_command_rejects_sharding_without_launch(self):
        status = self.invoke([
            str(self.workspace / "Scripts/test.sh"), "--shard-index", "0", "--shard-count", "2",
            "--command", "swift", "test", "--parallel",
        ])
        self.assertEqual(status, 2, self.output)
        self.assertFalse(self.record.exists())
        self.assertEqual(list(self.workspace.glob(".test-fixtures-*")), [])


if __name__ == "__main__":
    unittest.main()
