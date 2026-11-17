#!/usr/bin/env python3
"""One manual, sequential, object-cold macOS build/size observation; never a release."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time

import ci_swift_test_by_suite as processes
from cold_build_size_adapter import Adapter, BASELINE, CANDIDATE, digest
from jones_candidate_artifact import tree_manifest


DEVELOPER = "/Applications/Xcode_26.3.app/Contents/Developer"
TOOLCHAIN = "ba0d494e3bd99ca718c3b866478aecef3929bd982e54bdcc30bc90259845ac4f"
MAX_EVIDENCE = 32 * 1024**2
LOG_LIMIT = 2 * 1024**2
RESERVE = 30 * 1024**3
PEAK = 25 * 1024**3
SOURCES = (BASELINE, CANDIDATE)
INPUT_FILES = (
    "Package.swift", "Package.resolved", "Scripts/test_profiles.json", "Scripts/test.sh",
    "Scripts/package_app.sh", "Scripts/package_product_paths.sh", "Scripts/package_widget.py",
    "Scripts/build_jobs.py", "Scripts/ci_swift_test_by_suite.py", "Scripts/jones_update_metadata.py",
    "Scripts/sparkle_signing_paths.sh", "version.env",
    "WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.pbxproj",
    "WidgetExtension/Info.plist",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for data in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(data)
    return result.hexdigest()


def capture_bytes(command, cwd=None):
    result = subprocess.run([str(a) for a in command], cwd=cwd, check=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    require(len(result.stdout) <= 1024**2, "unexpectedly large read-only command output")
    return result.stdout


def capture(command, cwd=None):
    return capture_bytes(command, cwd).decode().strip()


def git(source, *args):
    return capture(["git", "--no-optional-locks", "-C", source, *args])


def validate_dispatch(environment, event, inputs, head):
    require(environment.get("GITHUB_ACTIONS") == "true"
            and environment.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and environment.get("RUNNER_OS") == "macOS" and environment.get("RUNNER_ARCH") == "ARM64",
            "measurement requires the selected hosted macOS ARM64 runner")
    require(environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch" and inputs["mode"] == "cold-build-size",
            "measurement is manual-only and must be explicitly selected")
    require(environment.get("GITHUB_REPOSITORY") == "Jones-Systems/CodexBar"
            and environment.get("GITHUB_REPOSITORY_ID") == "1425008735",
            "unexpected GitHub repository")
    repository = event.get("repository", {})
    require(repository.get("full_name") == "Jones-Systems/CodexBar" and repository.get("id") == 1425008735
            and repository.get("default_branch") == "main" and repository.get("fork") is False,
            "unexpected dispatch event repository")
    require(inputs["baseline_sha"] == BASELINE and inputs["candidate_sha"] == CANDIDATE,
            "only the reviewed pre-product/product pair is supported")
    require(bool(re.fullmatch(r"[0-9a-f]{40}", inputs["harness_sha"]))
            and inputs["harness_sha"] == inputs["expected_sha"] == head
            == environment.get("GITHUB_SHA") == environment.get("GITHUB_WORKFLOW_SHA"),
            "harness, expected branch head, checkout and workflow source must match exactly")
    ref = environment.get("GITHUB_REF", "")
    require(environment.get("GITHUB_REF_TYPE") in ("branch", "tag")
            and ref.startswith("refs/" + ("heads/" if environment["GITHUB_REF_TYPE"] == "branch" else "tags/"))
            and environment.get("GITHUB_WORKFLOW_REF")
            == "Jones-Systems/CodexBar/.github/workflows/jones-menu-candidate.yml@" + ref,
            "dispatch must select this existing workflow at an explicit branch/tag ref")
    require(all(event.get("inputs", {}).get(key) == value for key, value in inputs.items()),
            "dispatch inputs differ from the event")
    require(environment.get("GITHUB_RUN_ATTEMPT") == "1", "automatic/manual reruns are not paired observations")
    for key in ("GITHUB_RUN_ID", "ImageOS", "ImageVersion"):
        require(bool(environment.get(key)), "missing runner provenance: " + key)
    return {key: environment[key] for key in (
        "GITHUB_SHA", "GITHUB_WORKFLOW_SHA", "GITHUB_REF", "GITHUB_WORKFLOW_REF", "GITHUB_RUN_ID",
        "GITHUB_RUN_ATTEMPT", "GITHUB_REPOSITORY", "GITHUB_REPOSITORY_ID", "ImageOS", "ImageVersion",
        "RUNNER_OS", "RUNNER_ARCH", "RUNNER_ENVIRONMENT")}


def clean_source(source, revision):
    require(git(source, "rev-parse", "--show-toplevel") == str(source), "source root differs")
    require(git(source, "rev-parse", "HEAD") == revision, "source revision differs")
    require(git(source, "rev-parse", "--is-shallow-repository") == "false", "full source history is required")
    require(not git(source, "status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none"),
            "measured source is dirty/untracked")
    require(not (source / ".swiftpm/configuration").exists() and not (source / "Packages").exists(),
            "local dependency overrides are forbidden")
    return {name: sha256(source / name) for name in INPUT_FILES}


def cleanup_owned(owned, receipts):
    """A failed identity/drain check must also forbid deletion of its parent tree."""
    try:
        receipts.append(owned.cleanup(processes._scratch_cleanup_safe))
    except (OSError, ValueError) as error:
        processes._scratch_cleanup_safe = False
        receipts.append({"path": str(owned.path), "absence_verified": False, "error": str(error)})
        raise


def toolchain():
    require(sys.platform == "darwin" and platform.machine() == "arm64", "native macOS ARM64 is required")
    require(os.environ.get("DEVELOPER_DIR") == DEVELOPER and Path(DEVELOPER).is_dir(),
            "the existing exact Xcode 26.3 installation must be selected; no fallback/install")
    versions = [capture(["/usr/bin/xcodebuild", "-version"]), capture(["swift", "--version"]),
                capture(["swift", "package", "--version"])]
    require(versions[0] == "Xcode 26.3\nBuild version 17C529", "unexpected Xcode build")
    require(digest(("\n".join(versions) + "\n").encode()) == TOOLCHAIN, "toolchain fingerprint differs")
    tools = {name: capture(["/usr/bin/xcrun", "--find", name]) for name in ("swift", "clang", "ld", "strip")}
    return {"toolchain_id": TOOLCHAIN, "versions": versions, "developer_dir": DEVELOPER,
            "os": capture(["/usr/bin/sw_vers"]), "architecture": platform.machine(),
            "cpu": capture(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"]),
            "sdk_path": capture(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]),
            "sdk_version": capture(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            "sdk_build": capture(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-build-version"]),
            "tools": {name: {"path": path, "sha256": sha256(path)} for name, path in tools.items()}}


def storage(path):
    free = shutil.disk_usage(path).free
    require(free >= RESERVE + PEAK, "measurement needs 30 GiB reserve + 25 GiB estimated additional peak")
    return {"path": str(path), "available_bytes": free, "reserve_bytes": RESERVE, "additional_peak_bytes": PEAK}


class OwnedDirectory:
    def __init__(self, path, create=True):
        self.path = Path(path)
        require(self.path.is_absolute() and self.path.parent.resolve(strict=True) == self.path.parent,
                "owned output parent must already be canonical")
        if create:
            require(not os.path.lexists(self.path), "cold/owned output already exists: " + str(path))
            self.path.mkdir(mode=0o700)
        info = self.path.lstat()
        require(stat.S_ISDIR(info.st_mode) and self.path.resolve() == self.path, "noncanonical owned root")
        self.identity = (info.st_dev, info.st_ino)

    def cleanup(self, drained):
        require(drained, "process drain unproved; preserve owned outputs for runner teardown")
        info = self.path.lstat()
        require(stat.S_ISDIR(info.st_mode) and self.path.resolve() == self.path
                and (info.st_dev, info.st_ino) == self.identity, "owned output identity changed; preserve it")
        shutil.rmtree(self.path)
        require(not os.path.lexists(self.path), "owned output cleanup absence unproved")
        return {"path": str(self.path), "identity": list(self.identity), "drained": True, "absence_verified": True}


@contextmanager
def defer_cancellation():
    # Register the exact allocated path/identity before a pending cancellation can
    # run its handler. The process runner separately protects child launch windows.
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, processes.CANCELLATION_SIGNALS)
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)


class Evidence:
    def __init__(self, path):
        self.path = Path(path)
        require(not os.path.lexists(self.path), "evidence destination already exists")
        self.path.mkdir(mode=0o700)

    def write(self, name, data, final=False):
        require(Path(name).name == name and name.endswith((".json", ".log")), "invalid evidence name")
        if not isinstance(data, bytes):
            data = (json.dumps(data, indent=2, sort_keys=True) + "\n").encode()
        destination = self.path / name
        used = sum(p.stat().st_size for p in self.path.iterdir() if p != destination)
        require(used + len(data) <= MAX_EVIDENCE - (0 if final else 1024**2), "bounded evidence budget exceeded")
        destination.write_bytes(data)

    def log(self, name, path):
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - LOG_LIMIT))
            data = handle.read(LOG_LIMIT)
        self.write(name + ".log", data)
        return {"log": name + ".log", "full_log_bytes": size, "full_log_sha256": sha256(path),
                "retained_bytes": len(data), "tail_truncated": size > len(data)}


@contextmanager
def command_environment(source, state=None):
    before = dict(os.environ)
    environment = {key: value for key, value in before.items()
                   if key in ("PATH", "HOME", "LANG", "LC_ALL", "DEVELOPER_DIR", "ImageOS", "ImageVersion")
                   or key.startswith(("GITHUB_", "RUNNER_"))}
    environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_NO_REPLACE_OBJECTS="1",
                       GIT_TERMINAL_PROMPT="0", PYTHONDONTWRITEBYTECODE="1", TZ="UTC")
    if state is not None:
        environment.update(
            CFFIXED_USER_HOME=str(state / "home"), TMPDIR=str(state / "tmp"),
            XDG_CACHE_HOME=str(state / "xdg"), CLANG_MODULE_CACHE_PATH=str(state / "clang-modules"),
            SWIFTPM_MODULECACHE_OVERRIDE=str(state / "swift-modules"),
            CODEXBAR_TEST_WORKSPACE_ROOT=str(source), CODEXBAR_TEST_SCRATCH_PARENT=str(state / "fixtures"),
            CODEXBAR_TEST_PROFILE="normal", CODEXBAR_TEST_RETRY_NON_TIMEOUT_FAILURES="0",
            CODEXBAR_TEST_CODEX_FILE_ISOLATION="1", CODEXBAR_TEST_SESSION_FILE_ISOLATION="1",
            CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS="1", ROOT=str(source), MEAS_STATE=str(state),
            MEAS_OVERLAY=str(state / "identity.env"), JONES_BUILD_ORIGIN="local", JONES_BUILD_RUN="")
    previous_cwd = Path.cwd()
    try:
        os.environ.clear()
        os.environ.update(environment)
        os.chdir(source)
        yield
    finally:
        os.chdir(previous_cwd)
        os.environ.clear()
        os.environ.update(before)


def phase_state(source):
    # Absence is asserted before creating any compiler/cache output, never obtained
    # by deleting a preexisting directory. The whole .build belongs to this phase.
    owned = OwnedDirectory(source / ".build")
    try:
        state = owned.path / "measurement"
        state.mkdir()
        for name in ("home", "tmp", "fixtures", "cache", "config", "security", "xdg"):
            (state / name).mkdir()
        (state / "identity.env").write_text(
            "JONES_BUNDLE_ID=com.jonessystems.codexbar\nJONES_TEAM_ID=JONESLOCAL\n"
            "JONES_STATE_KEY=jones\nJONES_DISPLAY_NAME='CodexBar Jones'\nJONES_UPDATE_CHANNEL=none\n")
        return owned, state
    except BaseException:
        cleanup_owned(owned, [])
        raise


def swift_options(state):
    return ["--arch", "arm64", "--jobs", "2", "--cache-path", str(state / "cache"),
            "--config-path", str(state / "config"), "--security-path", str(state / "security")]


def debug_command(state):
    return ["bash", "Scripts/test.sh", "--command", "swift", "build", "--build-tests",
            "--configuration", "debug", *swift_options(state)]


def release_command(state):
    return ["bash", "Scripts/test.sh", "--command", "swift", "build", "--configuration", "release",
            *swift_options(state)]


def widget_command(source, state, version, build):
    derived = state / "DerivedData"
    return [sys.executable, str(source / "Scripts/package_widget.py"), "--log", str(state / "xcodebuild.log"),
            "--products", str(derived / "Build"), "--timeout", "4200", "--", "/usr/bin/xcodebuild",
            "-jobs", "2", "-project", str(source / "WidgetExtension/CodexBarWidgetExtension.xcodeproj"),
            "-scheme", "CodexBarWidgetExtension", "-configuration", "Release", "-destination", "generic/platform=macOS",
            "-derivedDataPath", str(derived), "-clonedSourcePackagesDirPath", str(state / "xcode-packages"),
            "-packageCachePath", str(state / "xcode-cache"), "-skipPackageUpdates",
            "-disableAutomaticPackageResolution",
            "-skipMacroValidation", "-skipPackagePluginValidation", "-showBuildTimingSummary",
            "CODEXBAR_WIDGET_BUNDLE_ID=com.jonessystems.codexbar.widget", "CODEXBAR_TEAM_ID=JONESLOCAL",
            "MARKETING_VERSION=" + version, "CURRENT_PROJECT_VERSION=" + build,
            "CODE_SIGNING_ALLOWED=NO", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", "build"]


def command(name, argv, state, evidence, commands, timeout=4500, clock=time.monotonic_ns):
    log = state / (name + ".log")
    record = {"name": name, "argv": [str(a) for a in argv], "outer_includes_resolution_planning_and_drain": True}
    commands.append(record)
    start = clock()
    try:
        with log.open("wb") as output:
            result = processes._run_command(record["argv"], timeout=timeout, stdout=output, stderr=output)
        record["exit_code"] = result
        require(result == 0, "measurement command failed: " + name)
    except BaseException as error:
        record["error_type"] = type(error).__name__
        if isinstance(error, SystemExit):
            record["exit_code"] = error.code
        raise
    finally:
        record["outer_wall_ns"] = clock() - start
        record["process_drain_proved"] = processes._scratch_cleanup_safe
        if log.exists():
            record.update(evidence.log(name, log))
            tail = (evidence.path / (name + ".log")).read_text(errors="replace")
            record["swift_internal_build_seconds"] = [float(x) for x in re.findall(
                r"Build complete! \(([0-9.]+)s\)", tail)]
            # A nested historical owner can explicitly report lost continuity even
            # if the enclosing command can drain all descendants it observed.
            if re.search(r"(?:drain is unproved|drain failed|process drain is unproved|Cannot verify cleanup)", tail):
                processes._scratch_cleanup_safe = False
                record["process_drain_proved"] = False
        require(processes._scratch_cleanup_safe, "command drain unproved; retain for runner teardown")


def signature_slice(handle, base=0):
    handle.seek(base)
    header = handle.read(32)
    if header[:4] not in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        return None
    count, size = struct.unpack_from("<II", header, 16)
    require(count <= 65536 and size <= 16 * 1024**2, "invalid Mach-O command bounds")
    handle.seek(base + (32 if header[:4] == b"\xcf\xfa\xed\xfe" else 28))
    commands = handle.read(size)
    offset = 0
    result = {"load_command_present": False, "verification": "not performed"}
    for _ in range(count):
        require(offset + 8 <= len(commands), "invalid Mach-O load commands")
        kind, length = struct.unpack_from("<II", commands, offset)
        require(length >= 8 and offset + length <= len(commands), "invalid Mach-O command length")
        if kind == 0x1D:
            require(length >= 16, "invalid signature command")
            position, byte_count = struct.unpack_from("<II", commands, offset + 8)
            result.update(load_command_present=True, blob_bytes=byte_count)
            handle.seek(base + position)
            blob = handle.read(min(byte_count, 16 * 1024**2))
            if len(blob) >= 12 and struct.unpack_from(">I", blob)[0] == 0xFADE0CC0:
                entries = struct.unpack_from(">I", blob, 8)[0]
                require(entries <= 65536 and 12 + entries * 8 <= len(blob), "invalid signature index")
                result["cms_slot_present"] = False
                for index in range(entries):
                    slot, at = struct.unpack_from(">II", blob, 12 + index * 8)
                    if slot == 0 and at + 16 <= len(blob):
                        flags = struct.unpack_from(">I", blob, at + 12)[0]
                        result.update(code_directory_flags=flags, adhoc_flag=bool(flags & 2))
                    if slot == 0x10000:
                        result["cms_slot_present"] = True
        offset += length
    return result


def signature_record(path):
    """Inspect thin/universal Mach-O signature metadata, without invoking codesign."""
    with Path(path).open("rb") as handle:
        header = handle.read(32)
        if header[:4] not in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            return signature_slice(handle)
        count = struct.unpack_from(">I", header, 4)[0]
        require(count <= 64, "invalid universal Mach-O slice count")
        handle.seek(8)
        length = 32 if header[:4] == b"\xca\xfe\xba\xbf" else 20
        entries = handle.read(length * count)
        require(len(entries) == length * count, "incomplete universal Mach-O header")
        slices = []
        for index in range(count):
            at = index * length
            cpu, subtype = struct.unpack_from(">II", entries, at)
            position = struct.unpack_from(">Q" if length == 32 else ">I", entries, at + 8)[0]
            slices.append({"cpu_type": cpu, "cpu_subtype": subtype, "signature": signature_slice(handle, position)})
        return {"format": "universal-mach-o", "slices": slices, "verification": "not performed"}


def file_record(path):
    require(path.is_file() and not path.is_symlink(), "expected regular product: " + str(path))
    return {"bytes": path.stat().st_size, "sha256": sha256(path), "signature": signature_record(path)}


def totals(manifest):
    return {"regular_file_bytes": sum(item["size"] for item in manifest.values() if item["kind"] == "file"),
            "regular_file_count": sum(item["kind"] == "file" for item in manifest.values()),
            "link_payload_bytes": sum(item["size"] for item in manifest.values() if item["kind"] == "symlink"),
            "link_count": sum(item["kind"] == "symlink" for item in manifest.values())}


def assembly_identity(app, revision):
    app_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    widget_info = plistlib.loads((app / "Contents/PlugIns/CodexBarWidget.appex/Contents/Info.plist").read_bytes())
    common = {"JonesStateKey": "jones", "JonesAppBundleID": "com.jonessystems.codexbar",
              "JonesAppGroupID": "JONESLOCAL.com.jonessystems.codexbar",
              "JonesICloudID": "iCloud.com.jonessystems.codexbar",
              "JonesSourceRevision": revision, "JonesBuildOrigin": "local", "JonesBuildRun": "",
              "JonesUpdateChannel": "none", "CodexBarTeamID": "JONESLOCAL"}
    for info, identifier in ((app_info, "com.jonessystems.codexbar"),
                             (widget_info, "com.jonessystems.codexbar.widget")):
        require(info.get("CFBundleIdentifier") == identifier
                and all(info.get(key) == value for key, value in common.items()), "assembled Jones identity differs")
    require(widget_info.get("CFBundleVersion") == app_info.get("CFBundleVersion")
            and widget_info.get("CFBundleShortVersionString") == app_info.get("CFBundleShortVersionString"),
            "assembled app/widget versions differ")
    require(all(app_info.get(key) == "" for key in ("SUFeedURL", "SUPublicEDKey"))
            and all(app_info.get(key) is False for key in (
                "SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates")),
            "channel-none assembly enabled an update path")
    require(bool(app_info.get("CodexGitCommit")) and revision.startswith(app_info["CodexGitCommit"]),
            "assembled source stamp differs")
    return {"common": common, "app_identifier": app_info["CFBundleIdentifier"],
            "widget_identifier": widget_info["CFBundleIdentifier"], "build_number": app_info["CFBundleVersion"],
            "marketing_version": app_info["CFBundleShortVersionString"], "channel_none_verified": True}


def inventory(app, raw, revision):
    require(revision in SOURCES, "unsupported inventory source")
    identity = assembly_identity(app, revision)
    core_required = revision == BASELINE
    manifest = tree_manifest(app)
    require(len(manifest) <= 40000, "bundle inventory exceeds evidence bound")
    prefix = "CodexBar.app/Contents/"
    components = {name: totals({key: item for key, item in manifest.items() if key.startswith(prefix + part)})
                  for name, part in (("frameworks", "Frameworks/"), ("widget", "PlugIns/"),
                                     ("resources", "Resources/"), ("helpers", "Helpers/"), ("main", "MacOS/"))}
    adjacent = {key: item for key, item in manifest.items()
                if key.startswith(prefix + "Helpers/CodexBar_CodexBarCore.bundle/")}
    require(bool(adjacent) == core_required, "historical CLI resource layout differs")
    expected = {"app": "MacOS/CodexBar", "cli": "Helpers/CodexBarCLI", "watchdog": "Helpers/CodexBarClaudeWatchdog",
                "widget": "PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget"}
    signatures = {}
    for name, item in manifest.items():
        if item["kind"] == "file":
            info = signature_record(app.parent / name)
            if info is not None:
                signatures[name] = info
    return {"raw_release_products": {name: file_record(path) for name, path in raw.items()},
            "stripped_staged_products": {name: file_record(app / "Contents" / part) for name, part in expected.items()},
            "expanded_bundle": totals(manifest), "components": components, "files": manifest,
            "standalone_cli_adjacent_core_payload": totals(adjacent), "component_signatures": signatures,
            "size_definition": ("logical regular-file bytes, no symlink traversal; links separate; "
                                "excludes .build/dSYMs/archive"),
            "identity": identity, "new_package_signature": False, "distributable": False}


def build_sample(source, revision, label, evidence, native):
    receipt = {"revision": revision, "profile": "normal", "phases": [], "cleanup": []}
    inputs = clean_source(source, revision)
    receipt["inputs_sha256"] = inputs
    for phase in ("debug", "release"):
        require(not os.path.lexists(source / ".build"), "phase is not cold")
        phase_receipt = {"name": phase, "owned_root": str(source / ".build"), "cold_absence_verified": True,
                         "commands": [], "storage": storage(source)}
        receipt["phases"].append(phase_receipt)
        owned = None
        try:
            with defer_cancellation():
                owned, state = phase_state(source)
            with command_environment(source, state):
                phase_receipt["native"] = toolchain()
                require(phase_receipt["native"] == native, "native toolchain/SDK/OS changed before a phase")
                if phase == "debug":
                    command(label + "-debug", debug_command(state), state, evidence, phase_receipt["commands"])
                else:
                    adapter = Adapter(source, revision)
                    prepare = state / "prepare.sh"
                    prepare.write_text(adapter.prepare())
                    command(label + "-prepare", ["bash", "Scripts/test.sh", "--command", "bash", str(prepare)],
                            state, evidence, phase_receipt["commands"])
                    utility = source / ".build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Utilities.swift"
                    lock = json.loads((source / "Package.resolved").read_text())
                    pin = next(p for p in lock["pins"] if p["identity"] == "keyboardshortcuts")
                    require(git(utility.parent, "rev-parse", "HEAD") == pin["state"]["revision"],
                            "dependency pin differs")
                    phase_receipt["dependency_preparation"] = {
                        "revision": pin["state"]["revision"], "patched_source_sha256": sha256(utility),
                        "pinned_source_sha256": digest(capture_bytes([
                            "git", "-C", utility.parent, "show", "HEAD:Sources/KeyboardShortcuts/Utilities.swift"])),
                        "patch_diff_sha256": digest(capture_bytes([
                            "git", "-C", utility.parent, "diff", "--no-ext-diff", "HEAD", "--", "Utilities.swift"])),
                        "script_sha256": sha256(prepare), "package_resolved_unchanged":
                        sha256(source / "Package.resolved") == inputs["Package.resolved"],
                    }
                    require(phase_receipt["dependency_preparation"]["package_resolved_unchanged"], "lock changed")
                    command(label + "-release", release_command(state), state, evidence, phase_receipt["commands"])
                    bin_dir = Path(capture(["swift", "build", "--show-bin-path", "--configuration", "release",
                                            *swift_options(state)]))
                    require(source / ".build" in bin_dir.resolve().parents, "product path escapes owned phase")
                    version = dict(line.split("=", 1) for line in
                                   (source / "version.env").read_text().splitlines() if "=" in line)
                    provenance = capture([sys.executable, source / "Scripts/jones_update_metadata.py", "metadata",
                                          "--repo", source, "--build-number", version["BUILD_NUMBER"],
                                          "--origin", "local",
                                          "--format", "shell"])
                    composed = re.search(r"^BUILD_NUMBER=([^\n]+)", provenance, re.M)
                    require(composed is not None, "missing historical composed build number")
                    build_number = shlex.split(composed[1])[0]
                    try:
                        command(label + "-widget", widget_command(
                            source, state, version["MARKETING_VERSION"], build_number),
                                state, evidence, phase_receipt["commands"])
                    finally:
                        if (state / "widget-build-active").exists():
                            processes._scratch_cleanup_safe = False
                        if (state / "xcodebuild.log").exists():
                            phase_receipt["widget_log"] = evidence.log(label + "-xcodebuild", state / "xcodebuild.log")
                    require(processes._scratch_cleanup_safe, "widget owner did not prove drain")
                    widget = state / "DerivedData/Build/Products/Release/CodexBarWidget.appex"
                    assembly = state / "assemble.sh"
                    assembly.write_text(adapter.assemble(bin_dir, widget, provenance))
                    phase_receipt["adapter"] = adapter.receipt()
                    phase_receipt["assembly_script_sha256"] = sha256(assembly)
                    command(label + "-assembly", ["bash", str(assembly)], state, evidence, phase_receipt["commands"])
                    app = source / ".build/package/CodexBar.app"
                    raw = {name: bin_dir / product for name, product in (
                        ("app", "CodexBar"), ("cli", "CodexBarCLI"), ("watchdog", "CodexBarClaudeWatchdog"))}
                    widget_binary = app / "Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget"
                    for path in [*raw.values(), widget_binary]:
                        require(capture(["/usr/bin/lipo", "-archs", path]) == "arm64", "product architecture differs")
                    evidence.write(label + "-inventory.json", inventory(app, raw, revision))
                require(clean_source(source, revision) == inputs, "source/package/profile bytes changed")
        finally:
            propagating = sys.exc_info()[0] is not None
            try:
                if owned is not None:
                    cleanup_owned(owned, receipt["cleanup"])
            except (OSError, ValueError):
                if not propagating:
                    raise
            finally:
                evidence.write(label + ".json", receipt)
    return receipt


def cancel(signum, _frame):
    raise SystemExit(128 + signum)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-only", action="store_true", help="bind dispatch/source without creating outputs")
    for name in ("mode", "baseline_sha", "candidate_sha", "harness_sha", "expected_sha"):
        parser.add_argument("--" + name.replace("_", "-"), required=True)
    args = parser.parse_args()
    harness = Path(__file__).resolve().parent.parent
    inputs = {key: value for key, value in vars(args).items() if key != "validate_only"}
    previous = {sig: signal.signal(sig, cancel) for sig in processes.CANCELLATION_SIGNALS}
    root = evidence = None
    result = {"schema": "codexbar.cold-build-size/v1", "status": "failed", "inputs": inputs,
              "measurement": "one baseline-first pair; object/dependency cold, OS/SDK page caches uncontrolled",
              "qualification": "advisory observation; no native compatibility, release or runtime proof",
              "started_utc": datetime.now(timezone.utc).isoformat(), "samples": []}
    exit_code = 1
    try:
        # Clear inherited compiler/Git/test overrides before even binding source.
        with command_environment(harness):
            event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
            result["provenance"] = validate_dispatch(os.environ, event, inputs, git(harness, "rev-parse", "HEAD"))
            clean_source(harness, inputs["harness_sha"])
            if args.validate_only:
                print(json.dumps(result["provenance"], sort_keys=True))
                return 0
            evidence = Evidence(harness / "cold-build-size-evidence")
            result["native"] = toolchain()
            result["storage"] = storage(harness)
            result["harness_files_sha256"] = {
                name: sha256(harness / name) for name in (
                    "Scripts/ci_cold_build_size.py", "Scripts/cold_build_size_adapter.py",
                    "Scripts/ci_swift_test_by_suite.py", "Scripts/jones_candidate_artifact.py",
                    ".github/workflows/jones-menu-candidate.yml")}
            with defer_cancellation():
                root = OwnedDirectory(Path(tempfile.mkdtemp(prefix=".cold-build-size-", dir=harness)), create=False)
            # Equal-length paths, identical cloning command, no binary/build imports.
            for name, revision in zip(("sample-a", "sample-b"), SOURCES):
                source = root.path / name
                scratch_log = root.path / (name + ".log")
                with scratch_log.open("wb") as output:
                    for argv in (["git", "clone", "--no-hardlinks", "--no-checkout", str(harness), str(source)],
                                 ["git", "-C", str(source), "checkout", "--detach", revision]):
                        require(processes._run_command(argv, timeout=120, stdout=output, stderr=output) == 0,
                                "clean historical checkout failed")
                # The .git clone is a new owned invocation tree, never another worktree.
                result["samples"].append(build_sample(source, revision, name, evidence, result["native"]))
            result["status"] = "observed"
            exit_code = 0
    except Exception as error:
        result["error"] = str(error)
        result["error_type"] = type(error).__name__
        print("Measurement failed: " + type(error).__name__ + ": " + str(error), file=sys.stderr)
    except SystemExit as error:
        result["status"] = "cancelled"
        result["exit_code"] = error.code
        exit_code = error.code if isinstance(error.code, int) and error.code else 1
    finally:
        try:
            if root is not None:
                result["cleanup"] = root.cleanup(processes._scratch_cleanup_safe)
        except (OSError, ValueError) as error:
            result["status"] = "failed"
            result["cleanup_error"] = str(error)
            result["runner_teardown_limitation"] = (
                "Unproved drain/identity: owned outputs retained for hosted VM teardown.")
            exit_code = exit_code or 1
        finally:
            if evidence is not None:
                result["finished_utc"] = datetime.now(timezone.utc).isoformat()
                evidence.write("result.json", result, final=True)
            for sig, handler in previous.items():
                signal.signal(sig, handler)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
