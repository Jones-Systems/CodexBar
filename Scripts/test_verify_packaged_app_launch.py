#!/usr/bin/env python3
"""Exercise the real launch-smoke script with owned executable fixtures, never an app."""

import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "Scripts/verify_packaged_app_launch.sh"


class LaunchSmokeTests(unittest.TestCase):
    def setUp(self):
        scratch = Path(os.environ.get("CODEXBAR_TEST_SCRATCH_PARENT", str(ROOT / ".build")))
        self.assertTrue(scratch.is_absolute() and ROOT in scratch.parents and scratch.resolve() == scratch)
        scratch.mkdir(exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(prefix=".launch-smoke-fixture-", dir=scratch)
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.scratch = self.root / "scratch"
        self.scratch.mkdir()
        self.app = self.root / "Fixture.app"
        executable = self.app / "Contents/MacOS/CodexBar"
        cli = self.app / "Contents/Helpers/CodexBarCLI"
        (self.app / "Contents/Helpers/CodexBar_CodexBarCore.bundle").mkdir(parents=True)
        executable.parent.mkdir(parents=True)
        self.write_executable(self.tools / "launchctl", "#!/bin/sh\nprintf 'Aqua\\n'\n")
        self.write_executable(self.tools / "sandbox-exec", "#!/bin/sh\nshift 2\nexec \"$@\"\n")
        fixture = '''#!/bin/sh
if [ "${CODEXBAR_RESOURCE_SMOKE:-0}" = 1 ]; then
  printf 'probe\\n' >> "$FIXTURE_RECORD"
  if [ "${FIXTURE_PROBE_FAILURE:-0}" = 1 ]; then exit 17; fi
  printf 'CODEXBAR_RESOURCE_SMOKE_OK\\n'
  exit 0
fi
printf 'application\\n' >> "$FIXTURE_RECORD"
exec sleep 300
'''
        self.write_executable(executable, fixture)
        self.write_executable(cli, fixture)
        self.record = self.root / "record"

    @staticmethod
    def write_executable(path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o700)

    def run_smoke(self, *, resource_only=False, probe_failure=False):
        environment = {
            "PATH": f"{self.tools}:/usr/bin:/bin",
            "HOME": str(self.root),
            "TMPDIR": str(self.scratch),
            "FIXTURE_RECORD": str(self.record),
            "CODEXBAR_LAUNCH_SMOKE_SECONDS": "1",
        }
        if resource_only:
            environment["CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY"] = "1"
        if probe_failure:
            environment["FIXTURE_PROBE_FAILURE"] = "1"
        process = subprocess.Popen(
            ["/bin/bash", str(SCRIPT), str(self.app)], env=environment,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=30)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        self.assertEqual(list(self.scratch.iterdir()), [], "smoke scratch survived the command")
        return process.returncode, stdout, stderr

    def test_resource_only_requires_all_probes_and_never_starts_application(self):
        result, stdout, stderr = self.run_smoke(resource_only=True)
        self.assertEqual(result, 0, stderr)
        self.assertEqual(self.record.read_text().splitlines(), ["probe"] * 3)
        self.assertIn("application lifetime was not tested", stdout)

    def test_default_still_runs_application_lifetime_check(self):
        result, stdout, stderr = self.run_smoke()
        self.assertEqual(result, 0, stderr)
        self.assertEqual(self.record.read_text().splitlines(), ["probe"] * 3 + ["application"])
        self.assertIn("Launch smoke check OK", stdout)

    def test_resource_only_cannot_hide_a_failed_probe(self):
        result, stdout, stderr = self.run_smoke(resource_only=True, probe_failure=True)
        self.assertNotEqual(result, 0, stdout)
        self.assertEqual(self.record.read_text().splitlines(), ["probe"])
        self.assertIn("cannot load CodexBarCore resources", stderr)


if __name__ == "__main__":
    def cancelled(signum, _frame):
        raise SystemExit(128 + signum)

    for caught_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(caught_signal, cancelled)
    unittest.main()
