#!/usr/bin/env python3
"""Create a static CI candidate, never a release or an installation attestation.

The A2 contract is spec.app-updates-codexbar#iface.lifecycle.001 at V3
634e83127f2b063bcb1caeb27aabf2437895b277. GitHub context is validated locally;
an installer must independently authenticate the run and archive hash.
"""

import argparse
import base64
import binascii
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import zipfile
import zlib
from xml.parsers.expat import ExpatError


REPOSITORY = "Jones-Systems/CodexBar"
REPOSITORY_ID = "1425008735"
BUNDLE_ID = "com.jonessystems.codexbar"
APP_GROUP = "JONESLOCAL.com.jonessystems.codexbar"
ICLOUD_ID = "iCloud.com.jonessystems.codexbar"
STABLE_FEED = "https://github.com/Jones-Systems/CodexBar/releases/latest/download/appcast.xml"
UPSTREAM_KEY = "AGCY8w5vHirVfGGDGc8Szc5iuOqupZSh9pMj/Qs67XI="
WORKFLOW_PATH = ".github/workflows/jones-app-candidate.yml"
MIB = 1024 ** 2
GIB = 1024 ** 3
MAX_ARCHIVE_BYTES = 256 * MIB
MAX_UNPACKED_BYTES = GIB
SHA = re.compile(r"[0-9a-f]{40}")
POSITIVE = re.compile(r"[1-9][0-9]*")
MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


class CandidateError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def require(condition, code, message):
    if not condition:
        raise CandidateError(code, message)


def command(arguments, *, cwd=None, environment=None, timeout=60):
    try:
        result = subprocess.run(
            [str(value) for value in arguments], cwd=cwd, env=environment,
            capture_output=True, check=False, timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CandidateError("command-unavailable", f"Cannot complete {Path(arguments[0]).name}") from error
    require(result.returncode == 0, "command-failed",
            f"{Path(arguments[0]).name} exited with status {result.returncode}")
    return result


def git(repo, *arguments):
    environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    environment.update(GIT_OPTIONAL_LOCKS="0", GIT_NO_REPLACE_OBJECTS="1")
    return command(["git", "--no-optional-locks", "-C", repo, *arguments],
                   environment=environment).stdout.decode("utf-8").strip()


def load_json(path):
    try:
        require(path.stat().st_size <= MIB, "invalid-json", "JSON input exceeds 1 MiB")
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        if isinstance(error, CandidateError):
            raise
        raise CandidateError("invalid-json", "Cannot read JSON input") from error
    require(type(value) is dict, "invalid-json", "JSON input must be an object")
    return value


def canonical_repository(value):
    return (
        type(value) is dict and value.get("full_name") == REPOSITORY
        and type(value.get("id")) is int and str(value["id"]) == REPOSITORY_ID
        and value.get("default_branch") == "main" and value.get("fork") is False
    )


@dataclass(frozen=True)
class Context:
    revision: str
    short_revision: str
    version: str
    build: str
    first_parent_count: int
    origin: str
    build_run: str
    event_name: str
    ref: str
    run_url: str
    run_id: str
    run_attempt: str
    workflow_ref: str
    workflow_sha: str


def validate_event(environment, event, revision):
    for name, expected in {
        "GITHUB_ACTIONS": "true", "GITHUB_SERVER_URL": "https://github.com",
        "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_REPOSITORY_ID": REPOSITORY_ID,
    }.items():
        require(environment.get(name) == expected, "ci-context", f"Unexpected {name}")
    require(canonical_repository(event.get("repository")), "ci-repository", "Noncanonical event repository")
    for name in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(bool(POSITIVE.fullmatch(environment.get(name, ""))), "ci-run", f"Invalid {name}")
    for name in ("GITHUB_SHA", "GITHUB_WORKFLOW_SHA"):
        require(bool(SHA.fullmatch(environment.get(name, ""))), "ci-revision", f"Invalid {name}")
    ref = environment.get("GITHUB_REF", "")
    require(environment.get("GITHUB_WORKFLOW_REF") == f"{REPOSITORY}/{WORKFLOW_PATH}@{ref}",
            "ci-workflow", "Unexpected workflow path or ref")
    event_name = environment.get("GITHUB_EVENT_NAME")
    if event_name == "push":
        require(ref == "refs/heads/main" and environment["GITHUB_SHA"] == revision
                and event.get("ref") == ref and event.get("after") == revision and event.get("deleted") is False,
                "ci-main", "ci-main requires the exact non-deleted canonical main push")
        origin = "ci-main"
    elif event_name == "pull_request":
        pr = event.get("pull_request")
        require(type(pr) is dict, "ci-pr", "Missing pull request")
        number = event.get("number")
        head, base = pr.get("head"), pr.get("base")
        require(type(number) is int and number > 0 and ref == f"refs/pull/{number}/merge"
                and pr.get("draft") is False and pr.get("state") == "open"
                and type(head) is dict and head.get("sha") == revision
                and type(head.get("ref")) is str and bool(head["ref"])
                and environment.get("GITHUB_HEAD_REF") == head["ref"]
                and type(base) is dict and base.get("ref") == "main"
                and canonical_repository(base.get("repo")) and environment.get("GITHUB_BASE_REF") == "main",
                "ci-pr", "ci-pr requires a non-draft open PR, exact head and canonical main base")
        origin = "ci-pr"
    elif event_name == "workflow_dispatch":
        require(ref.startswith("refs/heads/") and len(ref) > len("refs/heads/")
                and environment["GITHUB_SHA"] == revision, "ci-dispatch", "Dispatch requires its exact branch SHA")
        # A manual run is diagnostic. A2 reserves ci-main for push and ci-pr for PRs.
        origin = "local"
    else:
        raise CandidateError("ci-event", "Only pull_request, main push and workflow_dispatch are accepted")
    run_url = f"https://github.com/{REPOSITORY}/actions/runs/{environment['GITHUB_RUN_ID']}"
    return origin, run_url


def inspect_context(repo, environment, event=None):
    repo = repo.resolve()
    require(Path(git(repo, "rev-parse", "--show-toplevel")).resolve() == repo,
            "source-root", "Expected the source repository root")
    revision = git(repo, "rev-parse", "--verify", "HEAD^{commit}")
    require(bool(SHA.fullmatch(revision)), "source-revision", "Expected a full lowercase Git SHA")
    require(git(repo, "rev-parse", "--is-shallow-repository") == "false",
            "source-shallow", "Candidate packaging requires full history")
    require(not git(repo, "status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=none"),
            "source-dirty", "Candidate packaging requires clean source, including untracked files")
    count = git(repo, "rev-list", "--first-parent", "--count", revision)
    require(bool(POSITIVE.fullmatch(count)), "source-count", "Unknown first-parent count")
    short = git(repo, "rev-parse", "--short", revision)
    require(bool(re.fullmatch(r"[0-9a-f]{7,40}", short)) and revision.startswith(short),
            "source-short-revision", "Invalid short source revision")
    versions = {}
    for line in (repo / "version.env").read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"(MARKETING_VERSION|BUILD_NUMBER)=([0-9.]+)", line)
        if match:
            require(match[1] not in versions, "source-version", "Duplicate version field")
            versions[match[1]] = match[2]
    require(bool(POSITIVE.fullmatch(versions.get("BUILD_NUMBER", "")))
            and bool(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", versions.get("MARKETING_VERSION", ""))),
            "source-version", "Invalid version.env")
    if event is None:
        require(bool(environment.get("GITHUB_EVENT_PATH")), "ci-event", "Missing GITHUB_EVENT_PATH")
        event = load_json(Path(environment["GITHUB_EVENT_PATH"]))
    origin, run_url = validate_event(environment, event, revision)
    require(git(repo, "rev-parse", "--verify", "HEAD^{commit}") == revision,
            "source-changed", "Source revision changed while inspecting it")
    return Context(revision, short, versions["MARKETING_VERSION"], f"{versions['BUILD_NUMBER']}.{count}",
                   int(count), origin, run_url if origin != "local" else "", environment["GITHUB_EVENT_NAME"],
                   environment["GITHUB_REF"], run_url, environment["GITHUB_RUN_ID"],
                   environment["GITHUB_RUN_ATTEMPT"], environment["GITHUB_WORKFLOW_REF"],
                   environment["GITHUB_WORKFLOW_SHA"])


def exact_values(mapping, expected, code="plist-value"):
    require(type(mapping) is dict, code, "Expected a property-list dictionary")
    for name, value in expected.items():
        require(type(mapping.get(name)) is type(value) and mapping[name] == value,
                code, f"Invalid or missing {name}")


def production_plist(info):
    for name in ("JonesUpdateHarness", "JonesUpdateHarnessFixtureID", "NSAppTransportSecurity", "NSBonjourServices",
                 "NSLocalNetworkUsageDescription"):
        require(name not in info, "production-isolation", f"Production bundle must not contain {name}")


def validate_plists(info, widget, context, channel):
    shared = {
        "CFBundleShortVersionString": context.version, "CFBundleVersion": context.build,
        "JonesStateKey": "jones", "JonesAppBundleID": BUNDLE_ID,
        "JonesAppGroupID": APP_GROUP, "JonesICloudID": ICLOUD_ID,
        "JonesSourceRevision": context.revision, "JonesBuildOrigin": context.origin,
        "JonesBuildRun": context.build_run, "JonesUpdateChannel": channel,
    }
    exact_values(info, dict(shared, CFBundleIdentifier=BUNDLE_ID, CFBundleDisplayName="CodexBar Jones",
                            CFBundleExecutable="CodexBar", CFBundlePackageType="APPL", CodexBarTeamID="JONESLOCAL",
                            CodexGitCommit=context.short_revision, LSUIElement=True))
    exact_values(widget, dict(shared, CFBundleIdentifier=BUNDLE_ID + ".widget", CFBundleExecutable="CodexBarWidget"))
    production_plist(info)
    production_plist(widget)
    timestamp = info.get("CodexBuildTimestamp")
    require(type(timestamp) is str and bool(re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", timestamp)),
            "plist-timestamp", "Invalid build timestamp")
    try:
        datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise CandidateError("plist-timestamp", "Invalid build timestamp") from error
    require(channel in ("none", "stable"), "update-channel", "Unknown update channel")
    enabled = channel == "stable"
    exact_values(info, {"SUEnableAutomaticChecks": enabled, "SUAutomaticallyUpdate": enabled,
                        "SUAllowsAutomaticUpdates": enabled, "SURequireSignedFeed": True,
                        "SUVerifyUpdateBeforeExtraction": True, "SUSignedFeedFailureExpirationInterval": 0})
    if not enabled:
        exact_values(info, {"SUFeedURL": "", "SUPublicEDKey": ""})
    else:
        exact_values(info, {"SUFeedURL": STABLE_FEED})
        key = info.get("SUPublicEDKey")
        require(type(key) is str and key != UPSTREAM_KEY, "update-key", "Invalid Jones public key")
        try:
            decoded = base64.b64decode(key, validate=True)
            require(len(decoded) == 32 and base64.b64encode(decoded).decode("ascii") == key,
                    "update-key", "Expected canonical base64 for an Ed25519 public key")
        except (ValueError, binascii.Error) as error:
            if isinstance(error, CandidateError):
                raise
            raise CandidateError("update-key", "Malformed Jones public key") from error


def read_plist(path):
    try:
        require(path.stat().st_size <= MIB, "plist-size", "Oversized bundle metadata")
        with path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError) as error:
        if isinstance(error, CandidateError):
            raise
        raise CandidateError("invalid-plist", "Cannot read bundle metadata") from error
    require(type(info) is dict, "invalid-plist", "Expected a plist dictionary")
    return info


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(MIB), b""):
            result.update(block)
    return result.hexdigest()


def tree_manifest(bundle, check_quarantine=False):
    require(bundle.name == "CodexBar.app" and bundle.is_dir() and not bundle.is_symlink(),
            "bundle-root", "Expected one real CodexBar.app directory")
    root = bundle.resolve()
    manifest = {}
    pending = [bundle]
    while pending:
        path = pending.pop()
        metadata = path.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        require(not mode & (stat.S_ISUID | stat.S_ISGID), "bundle-mode", "Set-ID files are not accepted")
        if check_quarantine:
            require("com.apple.quarantine" not in os.listxattr(path, follow_symlinks=False),
                    "quarantine", "Bundle contains quarantine attributes")
        name = path.relative_to(bundle.parent).as_posix()
        if stat.S_ISLNK(metadata.st_mode):
            target = os.readlink(path)
            require(not os.path.isabs(target), "bundle-link", "Absolute bundle symlink")
            try:
                resolved = path.resolve(strict=True)
            except (OSError, RuntimeError) as error:
                raise CandidateError("bundle-link", "Dangling or cyclic bundle symlink") from error
            require(root in resolved.parents, "bundle-link", "Symlink escapes the bundle")
            manifest[name] = {"kind": "symlink", "mode": mode, "target": target, "size": len(os.fsencode(target))}
        elif stat.S_ISDIR(metadata.st_mode):
            manifest[name] = {"kind": "directory", "mode": mode, "size": 0}
            pending.extend(sorted(path.iterdir()))
        else:
            require(stat.S_ISREG(metadata.st_mode), "bundle-type", "Unexpected special file in bundle")
            manifest[name] = {"kind": "file", "mode": mode, "size": metadata.st_size, "sha256": digest(path)}
    return manifest


def validate_signature(text, identifier):
    lines = text.splitlines()
    require(lines.count("Signature=adhoc") == 1 and lines.count(f"Identifier={identifier}") == 1
            and "TeamIdentifier=not set" in lines and not any(line.startswith("Authority=") for line in lines),
            "signature-identity", "Expected the exact ad-hoc bundle identifier and no signing authority")


def inspect_bundle(bundle, context, channel):
    require(sys.platform == "darwin", "platform", "Static bundle verification requires macOS")
    manifest = tree_manifest(bundle, check_quarantine=True)
    info = read_plist(bundle / "Contents/Info.plist")
    widget = bundle / "Contents/PlugIns/CodexBarWidget.appex"
    validate_plists(info, read_plist(widget / "Contents/Info.plist"), context, channel)
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", bundle])
    entitlements = {}
    for path, identifier, expected in (
        (bundle, BUNDLE_ID, {"com.apple.security.application-groups": [APP_GROUP]}),
        (widget, BUNDLE_ID + ".widget", {"com.apple.security.application-groups": [APP_GROUP],
                                       "com.apple.security.app-sandbox": True}),
    ):
        displayed = command(["/usr/bin/codesign", "--display", "--verbose=4", path])
        validate_signature((displayed.stdout + displayed.stderr).decode("utf-8"), identifier)
        raw = command(["/usr/bin/codesign", "--display", "--entitlements", ":-", path]).stdout
        try:
            actual = plistlib.loads(raw)
        except (ValueError, plistlib.InvalidFileException, ExpatError) as error:
            raise CandidateError("entitlements", "Cannot decode signed entitlements") from error
        exact_values(actual, expected, "entitlements")
        require(set(actual) == set(expected), "entitlements", "Unexpected ad-hoc entitlements")
        entitlements[identifier] = actual
    macho = []
    macho_architectures = {}
    for name, entry in manifest.items():
        if entry["kind"] != "file":
            continue
        path = bundle.parent / name
        if path.name == "Info.plist":
            require(not any(key.startswith("JonesUpdateHarness") for key in read_plist(path)),
                    "production-isolation", "Nested harness flag")
        with path.open("rb") as handle:
            magic = handle.read(4)
        if magic in MACHO_MAGICS:
            arches = command(["/usr/bin/lipo", "-archs", path]).stdout.decode("ascii").split()
            if name.startswith("CodexBar.app/Contents/Frameworks/Sparkle.framework/"):
                # Retain the pinned vendor framework's supported slices without rewriting its binaries.
                require(len(arches) == len(set(arches)) and set(arches) in ({"arm64"}, {"arm64", "x86_64"}),
                        "architecture", "Sparkle must support arm64 with only its known optional x86_64 slice")
            else:
                require(arches == ["arm64"], "architecture", "Jones product binaries must be arm64 only")
            macho.append(name)
            macho_architectures[name] = arches
    for name in (
        "Contents/MacOS/CodexBar", "Contents/Helpers/CodexBarCLI", "Contents/Helpers/CodexBarClaudeWatchdog",
        "Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget",
    ):
        entry = manifest.get(f"CodexBar.app/{name}", {})
        require(f"CodexBar.app/{name}" in macho and entry.get("mode", 0) & 0o111,
                "executable", "Missing executable arm64 product")
    require(any("/Sparkle.framework/" in name for name in macho), "sparkle", "Missing Sparkle binary")
    return {"plist": info, "entitlements": entitlements, "macho_files": sorted(macho),
            "macho_architectures": macho_architectures}, manifest


def validate_zip(archive, manifest):
    require(0 < archive.stat().st_size <= MAX_ARCHIVE_BYTES, "archive-size", "Archive must be at most 256 MiB")
    with zipfile.ZipFile(archive) as handle:
        seen = set()
        total = 0
        for item in handle.infolist():
            name = item.filename.rstrip("/")
            parts = PurePosixPath(name).parts
            require(parts and parts[0] == "CodexBar.app" and ".." not in parts
                    and "\\" not in name and not name.startswith("/") and name == "/".join(parts)
                    and name not in seen and name in manifest, "archive-layout", "Unexpected or duplicate ZIP entry")
            seen.add(name)
            expected = manifest[name]
            mode = item.external_attr >> 16
            kind = ("directory" if stat.S_ISDIR(mode) else "symlink" if stat.S_ISLNK(mode)
                    else "file" if stat.S_ISREG(mode) else "unknown")
            require(not item.flag_bits & 1 and item.create_system == 3 and kind == expected["kind"]
                    and stat.S_IMODE(mode) == expected["mode"] and item.file_size == expected["size"],
                    "archive-metadata", "ZIP must preserve file types, modes and sizes")
            total += item.file_size
            require(total <= MAX_UNPACKED_BYTES, "unpacked-size", "Candidate exceeds 1 GiB unpacked")
            if kind == "symlink":
                require(handle.read(item) == os.fsencode(expected["target"]), "archive-link", "Changed ZIP symlink")
        require(seen == set(manifest), "archive-layout", "ZIP entries do not match the verified bundle")
        require(handle.testzip() is None, "archive-crc", "ZIP integrity check failed")
    return total


def packager_contract(repo):
    # This query must return before configuration, build, signing or launch effects.
    # Its compiler claims depend on the shared build_jobs.py wrapper at every build boundary.
    try:
        raw = command(["/bin/bash", repo / "Scripts/package_app.sh", "--jones-candidate-capabilities"],
                      cwd=repo, timeout=30).stdout
        capabilities = json.loads(raw)
    except (CandidateError, ValueError) as error:
        raise CandidateError(
            "packager-contract", "Packager lacks the bounded-jobs/resource-only capability query") from error
    expected = {
        "schema": "jones-candidate-packager/v1", "compiler_jobs_env": "CODEXBAR_BUILD_JOBS",
        "compiler_jobs_max": 6, "bounded_compilers": ["swift-build", "xcodebuild"],
        "resource_only_smoke_env": "CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY", "resource_only_smoke_value": "1",
    }
    exact_values(capabilities, expected, "packager-contract")
    return capabilities


@contextmanager
def owned_scratch(parent):
    root = Path(tempfile.mkdtemp(prefix=".jones-candidate-", dir=parent))
    original_error = None
    try:
        yield root
    except BaseException as error:
        original_error = error
        raise
    finally:
        try:
            shutil.rmtree(root)
        except OSError as error:
            if original_error is None:
                raise CandidateError("cleanup-failed", "Cannot remove owned candidate scratch") from error
            print(json.dumps({"status": "cleanup-failed", "path": str(root), "primary_error_preserved": True}),
                  file=sys.stderr)


@contextmanager
def cancellation_cleanup():
    previous = {}

    def cancel(signum, _frame):
        raise CandidateError("cancelled", f"Cancelled by signal {signum}")

    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, cancel)
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def create_artifact(bundle, output, context, channel):
    require(not output.exists() and not output.is_symlink(), "output-exists", "Artifact output must not exist")
    require(output.parent.is_dir(), "output-parent", "Artifact parent must already exist")
    require(bundle.resolve() not in output.resolve().parents, "output-location", "Artifact cannot be inside the app")
    inspected, manifest = inspect_bundle(bundle, context, channel)
    unpacked_estimate = sum(entry["size"] for entry in manifest.values())
    require(0 < unpacked_estimate <= MAX_UNPACKED_BYTES, "unpacked-size", "Candidate exceeds 1 GiB unpacked")
    available = shutil.disk_usage(output.parent).free
    require(type(available) is int and available >= 2 * unpacked_estimate + MAX_ARCHIVE_BYTES + GIB,
            "archive-storage", "Insufficient or unknown capacity for archive and round-trip scratch")
    archive_name = f"Jones-CodexBar-{context.revision}.zip"
    # One same-volume staging root is owned on success, failure and handled cancellation.
    with owned_scratch(output.parent) as root:
        delivery = root / "delivery"
        delivery.mkdir()
        archive = delivery / archive_name
        command(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", "--noqtn", bundle, archive],
                timeout=300)
        unpacked = validate_zip(archive, manifest)
        extracted = root / "extracted"
        extracted.mkdir()
        command(["/usr/bin/ditto", "-x", "-k", "--noqtn", archive, extracted], timeout=300)
        require(sorted(path.name for path in extracted.iterdir()) == ["CodexBar.app"],
                "archive-layout", "Extracted archive must contain only CodexBar.app")
        _, roundtrip = inspect_bundle(extracted / "CodexBar.app", context, channel)
        require(roundtrip == manifest, "archive-roundtrip", "Archive changed signed bytes, modes or symlinks")
        checksum = digest(archive)
        archive_size = archive.stat().st_size
        provenance = {
            "schema": "jones-app-candidate/v1", "repository": REPOSITORY, "repository_id": int(REPOSITORY_ID),
            "source": asdict(context), "channel": channel,
            "artifact": {"filename": archive_name, "sha256": checksum, "archive_size_bytes": archive_size,
                         "unpacked_size_bytes": unpacked,
                         "estimated_install_peak_bytes": archive_size + 2 * unpacked + GIB,
                         "install_peak_basis": ("archive + two unpacked bundles + 1 GiB reserve; "
                                                "prior bundle size unmeasured"),
                         "size_is_reservation": False, "root": "CodexBar.app"},
            "verification": {"signature": "adhoc", "codesign": "--verify --deep --strict",
                             "product_architectures": ["arm64"], "quarantine": "absent", "archive_roundtrip": True,
                             "signed_entitlements": inspected["entitlements"], "macho_files": inspected["macho_files"],
                             "macho_architectures": inspected["macho_architectures"]},
            "distribution": {"kind": "ci-candidate", "canonical_main_push": context.origin == "ci-main",
                             "diagnostic_only": context.origin != "ci-main", "public_release": False,
                             "installed_verification": False, "automatic_update_ready": False,
                             "installation_requires": "external run/hash authentication and root admission"},
        }
        (delivery / (archive_name + ".sha256")).write_text(f"{checksum}  {archive_name}\n", encoding="ascii")
        (delivery / "provenance.json").write_text(
            json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        require(not output.exists() and not output.is_symlink(),
                "output-exists", "Artifact output appeared during creation")
        delivery.rename(output)
    return provenance


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    context = commands.add_parser("context")
    context.add_argument("--repo", required=True, type=Path)
    context.add_argument("--github-output", type=Path)
    contract = commands.add_parser("check-packager")
    contract.add_argument("--repo", required=True, type=Path)
    create = commands.add_parser("create")
    create.add_argument("--repo", required=True, type=Path)
    create.add_argument("--app", required=True, type=Path)
    create.add_argument("--output", required=True, type=Path)
    create.add_argument("--channel", choices=("none", "stable"), default="none")
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        with cancellation_cleanup():
            if args.command == "check-packager":
                result = packager_contract(args.repo.resolve())
            else:
                context = inspect_context(args.repo, os.environ)
                if args.command == "context":
                    result = asdict(context)
                    if args.github_output:
                        with args.github_output.open("a", encoding="utf-8") as handle:
                            for name in ("revision", "origin", "build_run", "run_url"):
                                handle.write(f"{name}={getattr(context, name)}\n")
                else:
                    result = create_artifact(args.app.absolute(), args.output.absolute(), context, args.channel)
        print(json.dumps(result, sort_keys=True, indent=2))
        return 0
    except CandidateError as error:
        print(json.dumps({"status": "rejected", "code": error.code, "reason": str(error)}), file=sys.stderr)
    except (OSError, UnicodeError, ValueError, zipfile.BadZipFile, RuntimeError,
            EOFError, OverflowError, zlib.error, ExpatError) as error:
        print(json.dumps({"status": "rejected", "code": "invalid-input-or-io", "reason": type(error).__name__}),
              file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
