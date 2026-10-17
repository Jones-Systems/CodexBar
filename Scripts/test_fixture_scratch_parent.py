#!/usr/bin/env python3
"""Synthetic shell lifecycle proof; pass one existing caller-owned workspace parent.

No Swift semantics are tested. A minimal copied workspace and stub tools keep
native compilation, packaging, and real account state outside this regression.
"""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
KEY = "CODEXBAR_TEST_SCRATCH_PARENT"
IDENTITY = "test_jones_identity_overlay.sh"
PROVIDER = "test_provider_session_file_isolation.sh"


def signal_exit(signum, _frame):
    raise SystemExit(128 + signum)


for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
    signal.signal(sig, signal_exit)


def executable(path, body):
    path.write_text(body)
    path.chmod(0o700)


def main():
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 Scripts/test_fixture_scratch_parent.py OWNED_WORKSPACE_PARENT")
    parent = Path(sys.argv[1])
    if (not parent.is_absolute() or ".." in parent.parts
            or parent.resolve(strict=True) != parent or not parent.is_dir()
            or parent == ROOT or ROOT not in parent.parents):
        sys.exit("Expected an existing canonical directory strictly inside the workspace")
    baseline = subprocess.check_output([
        "git", "-C", str(ROOT), "show",
        "0f842d7f26edcd1a1fff886409291ef9b4f846b6:Scripts/package_app.sh"], text=True)
    with tempfile.TemporaryDirectory(prefix="fixture-parent-regression-", dir=parent) as name:
        owned = Path(name)
        workspace = owned / "workspace"
        workspace.mkdir()
        for relative in (
                f"Scripts/{IDENTITY}", f"Scripts/{PROVIDER}", "Scripts/package_app.sh",
                "Scripts/sign-and-notarize.sh", ".mac-release.jones.env.example",
                "WidgetExtension/Info.plist",
                "WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.pbxproj"):
            target = workspace / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for relative in (
                "Sources/CodexBarCore/JonesStateRoot.swift",
                "Sources/CodexBarCore/ProviderSessionStoreFile.swift",
                "Sources/CodexBarCore/KeychainSecurity.swift",
                "Scripts/fixtures/provider_session_file_proof.swift"):
            target = workspace / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("// Synthetic compiler input; never compiled.\n")

        caller = workspace / "caller parent with spaces"
        caller.mkdir()
        sibling = caller / "sibling"
        sibling.write_text("preserve sibling")
        outside = owned / "outside"
        outside.mkdir()
        (outside / "sentinel").write_text("preserve outside")
        (workspace / "inside-link").symlink_to(caller, target_is_directory=True)
        (workspace / "outside-link").symlink_to(outside, target_is_directory=True)
        (workspace / "broken-link").symlink_to(owned / "missing", target_is_directory=True)
        identity_tools = owned / "identity-tools"
        provider_tools = owned / "provider-tools"
        identity_tools.mkdir()
        provider_tools.mkdir()
        for directory in (identity_tools, provider_tools):
            for tool in ("bash", "python3", "dirname", "mktemp", "rm"):
                target = shutil.which(tool)
                assert target, tool + " unavailable"
                (directory / tool).symlink_to(target)
        baseline_file = owned / "baseline"
        baseline_file.write_text(baseline)
        record = owned / "record"
        ready = owned / "ready"
        # Identity's own three compiler stubs remain unmodified. This git stub
        # supplies only pinned public source and the final synthetic ignore check.
        executable(identity_tools / "git", """#!/usr/bin/env python3
import os, pathlib, sys, time
if sys.argv[3] == 'show':
    sys.stdout.write(pathlib.Path(os.environ['BASELINE']).read_text())
elif sys.argv[3] == 'check-ignore':
    if os.environ['MODE'] == 'failure':
        sys.exit(53)
    if os.environ['MODE'] == 'cancel':
        pathlib.Path(os.environ['READY']).touch()
        while True:
            time.sleep(0.02)
else:
    sys.exit('Unexpected git command')
""")
        executable(provider_tools / "swiftc", """#!/usr/bin/env python3
import os, pathlib, sys, time
output = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
assert output.parent == pathlib.Path(os.environ['TMPDIR'])
pathlib.Path(os.environ['RECORD']).write_text(str(output.parent))
if os.environ['MODE'] == 'compile-failure':
    sys.exit(37)
if os.environ['MODE'] == 'cancel':
    pathlib.Path(os.environ['READY']).touch()
    while True:
        time.sleep(0.02)
output.write_text('#!/usr/bin/env python3\\nimport os, sys\\nsys.exit(41 if os.environ["MODE"] == "child-failure" else 0)\\n')
output.chmod(0o700)
""")

        def clean():
            assert caller.is_dir() and sibling.read_text() == "preserve sibling"
            assert set(caller.iterdir()) == {sibling}, "caller child leaked"
            assert (outside / "sentinel").read_text() == "preserve outside"
            assert set(outside.iterdir()) == {outside / "sentinel"}
            assert not list(workspace.glob(".jones-identity-fixture-*")), "default identity root leaked"
            assert not list(workspace.glob(".provider-session-child.*")), "default provider root leaked"

        def run(script, override, mode="success", expected=0, cancel=None):
            for path in (record, ready):
                path.unlink(missing_ok=True)
            env = {"PATH": str(identity_tools if script == IDENTITY else provider_tools),
                   "HOME": str(owned / "synthetic-home"), "TMPDIR": str(outside),
                   "BASELINE": str(baseline_file), "RECORD": str(record),
                   "READY": str(ready), "MODE": mode}
            if override is not None:
                env[KEY] = override
            process = subprocess.Popen(
                [str(identity_tools / "bash"), str(workspace / "Scripts" / script)],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
            try:
                if cancel is not None:
                    deadline = time.monotonic() + 15
                    while not ready.exists():
                        if process.poll() is not None or time.monotonic() >= deadline:
                            raise AssertionError("synthetic cancellation seam not reached")
                        time.sleep(0.02)
                    os.killpg(process.pid, cancel)
                stdout, stderr = process.communicate(timeout=20)
                assert process.returncode == expected, (script, mode, process.returncode, stderr.decode())
                if expected == 0 and script == IDENTITY:
                    assert b"UNAVAILABLE: native JonesStateRoot" in stdout
                    assert b"30 checks passed" in stdout
                if record.exists():
                    proof = Path(record.read_text())
                    assert proof.parent == (workspace if override is None else Path(override))
                    assert not proof.exists(), "owned provider child leaked"
                if override is not None and expected == 1 and mode == "success":
                    assert b"Invalid CODEXBAR_TEST_SCRATCH_PARENT" in stderr, (override, stderr.decode())
                    assert not record.exists(), "invalid parent reached compiler"
            finally:
                # Only this invocation's new synthetic process group is owned here.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate()
            clean()

        invalid = (
            "", ".", str(caller) + "\n", str(workspace), str(outside), str(workspace) + "-escape",
            str(caller / "missing"), str(sibling), str(workspace / "inside-link"),
            str(workspace / "inside-link" / "missing"), str(workspace / "outside-link"),
            str(workspace / "broken-link"), str(caller / ".." / "caller parent with spaces"),
            str(workspace / ".." / "outside"),
        )
        count = 0
        for script in (IDENTITY, PROVIDER):
            for value in invalid:
                run(script, value, expected=1)
                count += 1
            for override in (None, str(caller)):
                run(script, override)
                count += 1
                failures = (("failure", 1),) if script == IDENTITY else (
                    ("compile-failure", 37), ("child-failure", 41))
                for mode, status in failures:
                    run(script, override, mode, status)
                    count += 1
                for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                    run(script, override, "cancel", 128 + sig, sig)
                    count += 1
        print(f"Fixture scratch parent: {count} synthetic lifecycle cases passed; no native Swift proof")
    assert not owned.exists(), "regression root leaked"
    assert parent.is_dir(), "caller parent removed"


if __name__ == "__main__":
    main()
