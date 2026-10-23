#!/usr/bin/env python3
"""Exercise the real launch-smoke script with owned executable fixtures, never an app."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import textwrap
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
        self.checkout = self.root / "checkout"
        (self.checkout / "Scripts").mkdir(parents=True)
        (self.checkout / ".build").mkdir()
        self.script = self.checkout / "Scripts/verify_packaged_app_launch.sh"
        self.write_executable(self.script, SCRIPT.read_text(encoding="utf-8"))
        self.app = self.checkout / "Fixture.app"
        executable = self.app / "Contents/MacOS/CodexBar"
        cli = self.app / "Contents/Helpers/CodexBarCLI"
        (self.app / "Contents/Helpers/CodexBar_CodexBarCore.bundle").mkdir(parents=True)
        executable.parent.mkdir(parents=True)
        self.write_executable(self.tools / "launchctl", "#!/bin/sh\nprintf 'Aqua\\n'\n")
        # Emulate the profile's path denial; this is not native sandbox proof.
        self.write_executable(self.tools / "sandbox-exec", f"#!{sys.executable}\n" + '''
import os
from pathlib import Path
import re
import sys
assert sys.argv[1] == "-p"
denied = Path(re.search(r'\\(subpath "([^"]+)"\\)', sys.argv[2])[1]).resolve()
assert denied == Path(os.environ["FIXTURE_CHECKOUT"]).resolve()
executable = Path(sys.argv[3]).resolve()
if executable == denied or denied in executable.parents:
    sys.exit(133)
os.execv(sys.argv[3], sys.argv[3:])
''')
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

    def environment(self, *, resource_only=False, probe_failure=False, scratch=None):
        environment = {
            "PATH": f"{self.tools}:/usr/bin:/bin",
            "HOME": str(self.root),
            "TMPDIR": str(scratch or self.scratch),
            "FIXTURE_RECORD": str(self.record),
            "FIXTURE_CHECKOUT": str(self.checkout),
            "CODEXBAR_LAUNCH_SMOKE_SECONDS": "1",
        }
        if resource_only:
            environment["CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY"] = "1"
        if probe_failure:
            environment["FIXTURE_PROBE_FAILURE"] = "1"
        return environment

    def run_process(self, command, environment):
        process = subprocess.Popen(
            command, env=environment, cwd=self.checkout,
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

    def run_smoke(self, *, resource_only=False, probe_failure=False, scratch=None):
        return self.run_process(
            ["/bin/bash", str(self.script), str(self.app)],
            self.environment(resource_only=resource_only, probe_failure=probe_failure, scratch=scratch),
        )

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

    def test_scratch_inside_denied_checkout_fails_before_any_probe_and_cleans_up(self):
        scratch = self.checkout / ".build"
        result, stdout, stderr = self.run_smoke(resource_only=True, scratch=scratch)
        self.assertNotEqual(result, 0, stdout)
        self.assertIn("outside the checkout", stderr)
        self.assertFalse(self.record.exists())
        self.assertEqual(list(scratch.iterdir()), [])

    def test_candidate_workflow_probes_outside_checkout_and_cleans_on_success_and_failure(self):
        workflow = (ROOT / ".github/workflows/jones-app-candidate.yml").read_text(encoding="utf-8")
        step = workflow.split("      - name: Admit, package and statically verify the candidate\n", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        command = textwrap.dedent(step.split("        run: |\n", 1)[1])
        self.write_executable(self.tools / "git", '#!/bin/sh\n[ "$1" = check-ignore ]\n')
        # Keep the actual workflow shell and smoke checker; replace only build/admission producers.
        self.write_executable(self.tools / "python3", f"#!{sys.executable}\n" + '''
from pathlib import Path
import sys
if sys.argv[2] == "Scripts/jones_candidate_admission.py":
    Path(sys.argv[sys.argv.index("--jobs-output") + 1]).write_text("1\\n")
elif sys.argv[2:4] != ["Scripts/jones_candidate_artifact.py", "create"]:
    sys.exit(98)
''')
        self.write_executable(self.checkout / "Scripts/package_app.sh", '''#!/bin/bash
set -euo pipefail
[[ "$1" == release && "$CODEXBAR_BUILD_JOBS" == 1 ]]
exec /bin/bash Scripts/verify_packaged_app_launch.sh "$FIXTURE_APP"
''')
        for probe_failure in (False, True):
            with self.subTest(probe_failure=probe_failure):
                if self.record.exists():
                    self.record.unlink()
                environment = self.environment(resource_only=True, probe_failure=probe_failure)
                environment.update(GITHUB_WORKSPACE=str(self.checkout), RUNNER_TEMP=str(self.scratch),
                                   FIXTURE_APP=str(self.app))
                result, stdout, stderr = self.run_process(["/bin/bash", "-c", command], environment)
                if probe_failure:
                    self.assertNotEqual(result, 0, stdout)
                    self.assertEqual(self.record.read_text().splitlines(), ["probe"])
                    self.assertIn("cannot load CodexBarCore resources", stderr)
                else:
                    self.assertEqual(result, 0, stderr)
                    self.assertEqual(self.record.read_text().splitlines(), ["probe"] * 3)
                self.assertEqual(list((self.checkout / ".build").iterdir()), [])
                self.assertFalse((self.checkout / ".mac-release.jones.env").exists())


if __name__ == "__main__":
    def cancelled(signum, _frame):
        raise SystemExit(128 + signum)

    for caught_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(caught_signal, cancelled)
    unittest.main()
