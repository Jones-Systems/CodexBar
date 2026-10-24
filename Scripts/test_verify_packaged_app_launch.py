#!/usr/bin/env python3
"""Exercise packaging resource contracts with owned executables, never a real app."""

import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
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
        self.resource_input = self.checkout / "Sources/CodexBarCore/Resources/fixture.js"
        self.resource_input.parent.mkdir(parents=True)
        self.resource_input.write_text("synthetic tracked resource\n")
        self.git("init", "--quiet")
        self.git("add", "--", str(self.resource_input.relative_to(self.checkout)))
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
if [ "${1:-}" = --help ]; then
  case "$0" in */codexbar) printf 'symlink-help\\n' >> "$FIXTURE_RECORD" ;;
    *) printf 'helper-help\\n' >> "$FIXTURE_RECORD" ;; esac
  if [ "${FIXTURE_PROBE_FAILURE:-0}" = 1 ]; then exit 17; fi
  printf 'fixture help\\n'
  exit 0
fi
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

    def git(self, *arguments):
        return subprocess.run(["/usr/bin/git", "-C", str(self.checkout), *arguments],
                              env={"PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1",
                                   "GIT_CONFIG_GLOBAL": "/dev/null"},
                              check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def slim_source(self):
        # Keep untracked source/output leftovers to prove the index selects the contract.
        self.git("rm", "--quiet", "--cached", "--", str(self.resource_input.relative_to(self.checkout)))

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

    def test_tracked_resources_require_bundle_before_launch(self):
        shutil.rmtree(self.app / "Contents/Helpers/CodexBar_CodexBarCore.bundle")
        result, stdout, stderr = self.run_smoke(resource_only=True)
        self.assertNotEqual(result, 0, stdout)
        self.assertIn("missing CodexBarCore resource bundle", stderr)
        self.assertFalse(self.record.exists())

    def test_coreless_resource_only_proves_both_cli_routes_without_app_startup(self):
        self.slim_source()
        result, stdout, stderr = self.run_smoke(resource_only=True)
        self.assertEqual(result, 0, stderr)
        self.assertEqual(self.record.read_text().splitlines(), ["helper-help", "symlink-help"])
        self.assertIn("app forced resource-load proof unavailable", stdout)
        self.assertIn("application lifetime was not tested", stdout)
        self.assertNotIn("resource probe OK", stdout)

    def test_coreless_default_keeps_app_liveness_separate(self):
        self.slim_source()
        result, stdout, stderr = self.run_smoke()
        self.assertEqual(result, 0, stderr)
        self.assertEqual(self.record.read_text().splitlines(), ["helper-help", "symlink-help", "application"])
        self.assertIn("app forced resource-load proof unavailable", stdout)
        self.assertIn("Launch smoke check OK", stdout)

    def test_coreless_cli_failure_cannot_start_the_app(self):
        self.slim_source()
        result, stdout, stderr = self.run_smoke(probe_failure=True)
        self.assertNotEqual(result, 0, stdout)
        self.assertEqual(self.record.read_text().splitlines(), ["helper-help"])
        self.assertIn("CLI --help failed", stderr)

    def test_unverifiable_source_cannot_silently_select_coreless_contract(self):
        (self.checkout / ".git").rename(self.checkout / ".git-unavailable")
        result, stdout, _ = self.run_smoke(resource_only=True)
        self.assertNotEqual(result, 0, stdout)
        self.assertFalse(self.record.exists())

    def stage_app_resources(self, *, core_bundle=True):
        build = self.root / "build-products"
        build.mkdir()
        for bundle in ("KeyboardShortcuts_KeyboardShortcuts.bundle", "Retained.bundle"):
            (build / bundle).mkdir()
        if core_bundle:
            (build / "CodexBar_CodexBarCore.bundle").mkdir()
        stage = self.root / "staged.app"
        (stage / "Contents/Resources").mkdir(parents=True)
        (stage / "Contents/Helpers").mkdir()
        source = (ROOT / "Scripts/package_app.sh").read_text()
        block = source.split("# SwiftPM resource bundles (", 1)[1].split("# Ensure contents are writable", 1)[0]
        # Execute only the real resource-copy block, never build, signing, or launch.
        block = "# SwiftPM resource bundles (" + block
        environment = self.environment()
        environment.update(ROOT=str(self.checkout), PREFERRED_BUILD_DIR=str(build), APP=str(stage))
        result, stdout, stderr = self.run_process(["/bin/bash", "-euc", block], environment)
        return stage, result, stdout, stderr

    def test_app_staging_retains_required_and_non_core_bundles(self):
        stage, result, _, stderr = self.stage_app_resources()
        self.assertEqual(result, 0, stderr)
        for relative in ("Resources/CodexBar_CodexBarCore.bundle", "Helpers/CodexBar_CodexBarCore.bundle",
                         "Resources/KeyboardShortcuts_KeyboardShortcuts.bundle", "Resources/Retained.bundle"):
            self.assertTrue((stage / "Contents" / relative).is_dir(), relative)

    def test_app_staging_does_not_accept_missing_required_core_bundle(self):
        _, result, stdout, stderr = self.stage_app_resources(core_bundle=False)
        self.assertNotEqual(result, 0, stdout)
        self.assertIn("Missing CodexBarCore SwiftPM resource bundle", stderr)

    def test_app_staging_excludes_stale_core_bundle_after_source_removal(self):
        self.slim_source()
        stage, result, _, stderr = self.stage_app_resources()
        self.assertEqual(result, 0, stderr)
        self.assertFalse(list(stage.rglob("CodexBar_CodexBarCore.bundle")))
        self.assertTrue((stage / "Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle").is_dir())
        self.assertTrue((stage / "Contents/Resources/Retained.bundle").is_dir())

    @staticmethod
    def workflow_command(name):
        workflow = (ROOT / ".github/workflows/release-cli.yml").read_text()
        step = workflow.split(f"      - name: {name}\n", 1)[1].split("\n      - name:", 1)[0]
        lines = []
        for line in step.split("        run: |\n", 1)[1].splitlines():
            if line and not line.startswith("          "):
                break
            lines.append(line[10:])
        return "\n".join(lines) + "\n"

    def package_cli_resources(self, *, core_bundle=True):
        build = self.root / "cli-products"
        build.mkdir()
        shutil.copy2(self.app / "Contents/Helpers/CodexBarCLI", build / "CodexBarCLI")
        if core_bundle:
            (build / "CodexBar_CodexBarCore.resources").mkdir()
        shutil.copy2(ROOT / "Scripts/generate_release_checksum.sh", self.checkout / "Scripts")
        output = self.root / "package-output"
        environment = self.environment()
        environment.update(GITHUB_WORKSPACE=str(self.checkout), GITHUB_OUTPUT=str(output),
                           RELEASE_TAG="v0.0.0", FIXTURE_BIN_DIR=str(build))
        command = self.workflow_command("Package")
        command = command.replace("${{ steps.build.outputs.bin_dir }}", "$FIXTURE_BIN_DIR")
        command = command.replace("${{ matrix.asset-platform }}", "fixture")
        command = command.replace("${{ matrix.asset-arch }}", "fixture")
        members = []
        try:
            result, stdout, stderr = self.run_process(["/bin/bash", "-c", command], environment)
            values = dict(line.split("=", 1) for line in output.read_text().splitlines())
            stage = Path(values["out_dir"])
            self.assertFalse(stage.name.startswith("."), "manual artifact uploads exclude hidden ancestors")
            if result == 0:
                with tarfile.open(stage / values["asset"]) as archive:
                    members = archive.getnames()
                self.assertTrue((stage / (values["asset"] + ".sha256")).is_file())
        finally:
            values = dict(line.split("=", 1) for line in output.read_text().splitlines())
            environment.update(CLI_PACKAGE_ROOT=values["out_dir"], CLI_PACKAGE_IDENTITY=values["out_dir_identity"])
            cleanup, _, error = self.run_process(
                ["/bin/bash", "-euc", self.workflow_command("Clean CLI package scratch")], environment)
            self.assertEqual(cleanup, 0, error)
            self.assertEqual(list(self.checkout.glob("cli-package-*")), [])
        return result, stdout, stderr, members

    def test_cli_archive_keeps_required_resources_and_both_forced_probes(self):
        result, _, stderr, members = self.package_cli_resources()
        self.assertEqual(result, 0, stderr)
        self.assertIn("CodexBar_CodexBarCore.bundle", members)
        self.assertEqual(self.record.read_text().splitlines(), ["probe", "probe"])

    def test_cli_archive_rejects_missing_required_resources_and_cleans_failure(self):
        result, stdout, stderr, _ = self.package_cli_resources(core_bundle=False)
        self.assertNotEqual(result, 0, stdout)
        self.assertIn("Missing CodexBarCore resource bundle", stderr)
        self.assertFalse(self.record.exists())

    def test_coreless_cli_archive_excludes_stale_resources_and_checks_help_routes(self):
        self.slim_source()
        result, stdout, stderr, members = self.package_cli_resources()
        self.assertEqual(result, 0, stderr)
        self.assertEqual(members, ["CodexBarCLI", "codexbar", "VERSION"])
        self.assertEqual(self.record.read_text().splitlines(), ["helper-help", "symlink-help"])
        self.assertIn("forced resource-load proof unavailable", stdout)

    def test_cli_staging_cleanup_rejects_changed_identity(self):
        stage = self.checkout / "cli-package-fixture"
        stage.mkdir()
        environment = self.environment()
        environment.update(GITHUB_WORKSPACE=str(self.checkout), CLI_PACKAGE_ROOT=str(stage),
                           CLI_PACKAGE_IDENTITY="0:0")
        command = ["/bin/bash", "-euc", self.workflow_command("Clean CLI package scratch")]
        result, stdout, stderr = self.run_process(command, environment)
        self.assertNotEqual(result, 0, stdout)
        self.assertIn("identity changed", stderr)
        self.assertTrue(stage.is_dir())
        info = stage.stat()
        environment["CLI_PACKAGE_IDENTITY"] = f"{info.st_dev}:{info.st_ino}"
        result, _, stderr = self.run_process(command, environment)
        self.assertEqual(result, 0, stderr)
        self.assertFalse(stage.exists())

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
        self.write_executable(self.tools / "git", '#!/bin/sh\n'
                              'if [ "$1" = check-ignore ]; then exit 0; fi\n'
                              f'exec {shlex.quote(shutil.which("git"))} "$@"\n')
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
