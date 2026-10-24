#!/usr/bin/env python3
"""Same-run, same-path SwiftPM test build handoff; never execute archive metadata."""

from __future__ import annotations

import hashlib
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import platform
import posixpath
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import time

from test_profiles import manifest_digest, selected_profile


SCHEMA = "codexbar.swift-test-build/v1"
NATIVE_SCHEMA = "codexbar.swift-test-build/v2"
# Root reviews the complete native proof before this is activated/published.
ENABLE_NATIVE_COMPATIBILITY = False
MANIFEST = "manifest.json"
ARCHIVE = "build.tar.gz"
MAX_ENTRIES = 200000
MAX_PAYLOAD_BYTES = 12 * 1024 ** 3
MAX_ARCHIVE_BYTES = 4 * 1024 ** 3
MAX_MANIFEST_BYTES = 16 * 1024 ** 2
RESERVE_BYTES = 2 * 1024 ** 3
# upload-artifact excludes hidden ancestors by default. Keep this owned root visible;
# the workflow uploads only the two named payload files, never the whole workspace.
ROOT_PREFIX = "swift-test-build-"
IDENTITY_FIELDS = frozenset({
    "repository", "source_revision", "run_id", "run_attempt", "workflow_ref", "workspace", "profile",
    "profile_manifest_sha256", "package_sha256", "resolved_sha256", "toolchain_id", "runner_os",
    "runner_arch", "image_os", "image_version",
})


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def identity(workspace, environment, swift_command, capture):
    require(environment.get("GITHUB_ACTIONS") == "true"
            and environment.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and environment.get("RUNNER_OS") == "macOS" and platform.system() == "Darwin",
            "compiled test handoff requires a GitHub-hosted macOS runner")
    require(environment.get("GITHUB_REPOSITORY") == "Jones-Systems/CodexBar", "unexpected repository")
    require(environment.get("RUNNER_ARCH") == "ARM64" and platform.machine() == "arm64",
            "compiled test handoff requires the selected ARM64 runner")
    workspace = Path(workspace)
    require(workspace.is_absolute() and workspace.resolve(strict=True) == workspace,
            "workspace must be canonical")
    require(str(workspace) == environment.get("GITHUB_WORKSPACE"), "workspace identity differs")
    fields = ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_WORKFLOW_REF",
              "ImageOS", "ImageVersion")
    for key in fields:
        require(environment.get(key) and not any(c in environment[key] for c in "\r\n\0"),
                f"missing or invalid {key}")
    require(re.fullmatch(r"[0-9a-f]{40}", environment["GITHUB_SHA"]), "invalid source revision")
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", environment[key]), f"invalid {key}")

    def output(command):
        result = capture(command, timeout=30)
        result.check_returncode()
        return result.stdout.strip()

    source = output(["git", "--no-optional-locks", "rev-parse", "HEAD"])
    require(source == environment["GITHUB_SHA"], "checkout differs from workflow source")
    output(["git", "--no-optional-locks", "diff", "--quiet", "HEAD", "--"])
    versions = [output(["/usr/bin/xcodebuild", "-version"]),
                output([*swift_command, "--version"]), output([*swift_command, "package", "--version"])]
    toolchain = hashlib.sha256(("\n".join(versions) + "\n").encode()).hexdigest()
    require(toolchain == environment.get("CODEXBAR_TEST_TOOLCHAIN_ID"), "toolchain fingerprint differs")
    return {
        "repository": environment["GITHUB_REPOSITORY"], "source_revision": source,
        "run_id": environment["GITHUB_RUN_ID"], "run_attempt": environment["GITHUB_RUN_ATTEMPT"],
        "workflow_ref": environment["GITHUB_WORKFLOW_REF"], "workspace": str(workspace),
        "profile": selected_profile(environment), "profile_manifest_sha256": manifest_digest(workspace),
        "package_sha256": sha256(workspace / "Package.swift"),
        "resolved_sha256": sha256(workspace / "Package.resolved"), "toolchain_id": toolchain,
        "runner_os": environment["RUNNER_OS"], "runner_arch": environment["RUNNER_ARCH"],
        "image_os": environment["ImageOS"], "image_version": environment["ImageVersion"],
    }


def transfer_root(workspace, raw):
    root = Path(raw)
    require(root.parent == workspace and root.name.startswith(ROOT_PREFIX)
            and root.is_dir() and not root.is_symlink() and root.resolve(strict=True) == root,
            "build transfer root must be a canonical owned workspace directory")
    return root


def test_manifest(test_ids):
    require(isinstance(test_ids, list) and test_ids and len(test_ids) <= MAX_ENTRIES
            and all(isinstance(name, str) and name and not any(c in name for c in "\r\n\0")
                    for name in test_ids), "invalid or empty discovery manifest")
    require(test_ids == sorted(set(test_ids)), "discovery manifest must be sorted and unique")
    return hashlib.sha256(("\n".join(test_ids) + "\n").encode()).hexdigest()


def member_path(raw):
    path = PurePosixPath(raw)
    require(path.parts and path.parts[0] == ".build" and str(path) == raw
            and not any(part in (".", "..") for part in path.parts)
            and not any(c in raw for c in "\\\r\n\0"), "unsafe archive member path")
    return path


def link_target(name, raw):
    require(raw and not raw.startswith("/") and not any(c in raw for c in "\\\r\n\0"),
            "unsafe archive symlink")
    target = posixpath.normpath(posixpath.join(posixpath.dirname(name), raw))
    require(target == ".build" or target.startswith(".build/"), "archive symlink escapes build tree")
    return target


def inventory(build):
    require(build.is_dir() and not build.is_symlink(), "producer build tree is absent or symlinked")
    entries = [build]
    pending = [build]
    total = 0
    while pending:
        directory = pending.pop()
        for path in sorted(directory.iterdir()):
            info = path.lstat()
            require(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode),
                    "unsupported producer build entry")
            entries.append(path)
            require(len(entries) <= MAX_ENTRIES, "build tree entry budget exceeded")
            if stat.S_ISREG(info.st_mode):
                total += info.st_size
                require(total <= MAX_PAYLOAD_BYTES, "build tree byte budget exceeded")
            elif stat.S_ISDIR(info.st_mode):
                pending.append(path)
            else:
                require(path.resolve(strict=True).is_relative_to(build), "producer symlink escapes build tree")
    require(any(path.name.endswith(".xctest") and path.is_dir() for path in entries),
            "producer has no built XCTest bundle")
    require(any(path.name == "description.json" for path in entries), "SwiftPM build description is absent")
    return entries, total


def export_build(workspace, root, current, test_ids, native_runtime=None):
    root = transfer_root(workspace, str(root))
    require(not any(root.iterdir()), "build transfer output must be empty")
    discovery = test_manifest(test_ids)
    entries, total = inventory(workspace / ".build")
    # gzip can slightly expand incompressible input; include tar headers and its worst-case overhead.
    estimate = total + total // 100 + len(entries) * 2048 + 1024 ** 2
    require(shutil.disk_usage(root).free >= RESERVE_BYTES + min(estimate, MAX_ARCHIVE_BYTES),
            "insufficient storage for build archive and residual reserve")
    try:
        with tarfile.open(root / ARCHIVE, "w:gz", compresslevel=1) as archive:
            for path in entries:
                name = path.relative_to(workspace).as_posix()
                member_path(name)
                info = archive.gettarinfo(str(path), arcname=name)
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mode &= 0o777
                if path.is_symlink():
                    # SwiftPM can cache absolute links; the same build-tree target is portable within this archive.
                    info.linkname = os.path.relpath(path.resolve(strict=True), path.parent)
                    link_target(name, info.linkname)
                    archive.addfile(info)
                elif path.is_file():
                    info.type, info.linkname = tarfile.REGTYPE, ""
                    info.size = path.stat().st_size
                    with path.open("rb") as content:
                        archive.addfile(info, content)
                else:
                    archive.addfile(info)
                require((root / ARCHIVE).stat().st_size <= MAX_ARCHIVE_BYTES, "compressed build budget exceeded")
        manifest = {
            "schema": SCHEMA, "identity": current, "archive_sha256": sha256(root / ARCHIVE),
            "archive_bytes": (root / ARCHIVE).stat().st_size, "payload_bytes": total,
            "entries": len(entries), "test_ids": test_ids, "discovery_sha256": discovery,
        }
        if native_runtime is not None:
            manifest["schema"] = NATIVE_SCHEMA
            manifest["native_runtime"] = native_runtime
        encoded = (json.dumps(manifest, sort_keys=True) + "\n").encode()
        require(len(encoded) <= MAX_MANIFEST_BYTES, "build manifest budget exceeded")
        with (root / MANIFEST).open("xb") as output:
            output.write(encoded)
        return manifest, sha256(root / MANIFEST)
    except BaseException:
        for name in (MANIFEST, ARCHIVE):
            (root / name).unlink(missing_ok=True)
        raise


def require_identity(producer, current):
    if producer == current:
        return

    def public_value(value):
        # Identity contains public CI identifiers, never arbitrary manifest metadata.
        if not isinstance(value, str):
            return "<non-string>"
        return value if len(value) <= 256 else "<oversized>"

    differences = {}
    if isinstance(producer, dict) and isinstance(current, dict):
        for key in sorted(IDENTITY_FIELDS):
            if (key in producer) != (key in current) or producer.get(key) != current.get(key):
                differences[key] = {
                    "producer": public_value(producer[key]) if key in producer else "<missing>",
                    "worker": public_value(current[key]) if key in current else "<missing>",
                }
        if set(producer) - IDENTITY_FIELDS or set(current) - IDENTITY_FIELDS:
            differences["schema"] = "unrecognized identity fields (values omitted)"
    else:
        differences["schema"] = "identity must be an object (value omitted)"
    raise ValueError("build identity differs from this source/profile/run/toolchain/runner; mismatches="
                     + json.dumps(differences, sort_keys=True, ensure_ascii=True))


def native_precheck(workspace, capture, swift_command=None):
    if not ENABLE_NATIVE_COMPATIBILITY:
        return None
    import ci_swift_test_native as native
    started = time.monotonic()
    state = {"host": None, "reason": None, "host_seconds": 0.0}
    try:
        state["host"] = native.Host(workspace, workspace / ".build", dict(os.environ), capture,
                                    swift_command=swift_command)
    except native.UnsupportedRuntime as error:
        state["reason"] = str(error)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        state["reason"] = "native-host-evidence-unavailable"
    state["host_seconds"] = time.monotonic() - started
    return state


def native_finish(state, build):
    import ci_swift_test_native as native
    if state["host"] is None:
        return {"status": "unavailable", "reason": state["reason"]}, 0.0
    state["host"].build = build
    started = time.monotonic()
    try:
        payload = {"status": "complete", "fingerprint": state["host"].closure()}
    except native.UnsupportedRuntime as error:
        payload = {"status": "unavailable", "reason": str(error)}
    except OSError:
        payload = {"status": "unavailable", "reason": "native-runtime-file-unavailable"}
    return payload, time.monotonic() - started


def native_payload(value):
    require(isinstance(value, dict), "invalid native runtime proof")
    if value.get("status") == "unavailable":
        require(set(value) == {"status", "reason"}
                and isinstance(value["reason"], str)
                and re.fullmatch(r"[a-z0-9-]{1,80}", value["reason"]), "invalid native unavailability reason")
    else:
        require(set(value) == {"status", "fingerprint"} and value["status"] == "complete",
                "invalid native runtime proof status")
        fingerprint = value["fingerprint"]
        require(isinstance(fingerprint, dict) and set(fingerprint) == {"schema", "context", "entries", "edges"}
                and fingerprint["schema"] == "codexbar.swift-test-native/v1"
                and all(isinstance(fingerprint[key], dict) for key in ("context", "entries", "edges")),
                "incomplete native runtime proof")
    return value


def read_manifest(root, expected_sha256, current, native_state=None):
    require(re.fullmatch(r"[0-9a-f]{64}", expected_sha256 or ""), "producer manifest hash is required")
    path = root / MANIFEST
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_MANIFEST_BYTES,
            "build manifest is absent or oversized")
    require(sha256(path) == expected_sha256, "build manifest integrity mismatch")
    manifest = json.loads(path.read_bytes())
    fields = {"schema", "identity", "archive_sha256", "archive_bytes", "payload_bytes",
              "entries", "test_ids", "discovery_sha256"}
    modern = manifest.get("schema") == NATIVE_SCHEMA
    require(set(manifest) == fields | ({"native_runtime"} if modern else set())
            and (modern and ENABLE_NATIVE_COMPATIBILITY or manifest["schema"] == SCHEMA),
            "unsupported build manifest")
    proof = native_payload(manifest["native_runtime"]) if modern else None
    ready = (proof is not None and proof["status"] == "complete" and native_state is not None
             and native_state["host"] is not None)
    if ready:
        # Image revision alone is provenance; every other original field stays exact.
        require(isinstance(manifest["identity"], dict) and set(manifest["identity"]) == set(current),
                "invalid build identity fields")
        version = manifest["identity"]["image_version"]
        require(isinstance(version, str) and 0 < len(version) <= 256
                and not any(c in version for c in "\r\n\0"), "invalid producer image provenance")
        require_identity({key: value for key, value in manifest["identity"].items() if key != "image_version"},
                         {key: value for key, value in current.items() if key != "image_version"})
        require(proof["fingerprint"]["context"] == native_state["host"].context,
                "native host identity differs before restore")
    else:
        require_identity(manifest["identity"], current)
    for key, ceiling in (("archive_bytes", MAX_ARCHIVE_BYTES), ("payload_bytes", MAX_PAYLOAD_BYTES),
                         ("entries", MAX_ENTRIES)):
        require(type(manifest[key]) is int and 0 < manifest[key] <= ceiling, f"invalid {key}")
    require(test_manifest(manifest["test_ids"]) == manifest["discovery_sha256"], "discovery integrity mismatch")
    require(re.fullmatch(r"[0-9a-f]{64}", manifest["archive_sha256"] or ""), "invalid build archive hash")
    archive = root / ARCHIVE
    require(archive.is_file() and not archive.is_symlink()
            and archive.stat().st_size == manifest["archive_bytes"], "build archive size mismatch")
    require(sha256(archive) == manifest["archive_sha256"], "build archive integrity mismatch")
    return manifest


def extract_build(archive_path, destination, manifest):
    seen = {}
    links = []
    total = 0
    with tarfile.open(archive_path, "r:gz") as archive:
        # Inspect before creating files; tarfile.extract/extractall are deliberately never used.
        for info in archive:
            path = member_path(info.name)
            require(info.name not in seen, "duplicate archive member")
            require(info.isdir() or info.isreg() or info.issym(), "unsupported archive member type")
            require(info.mode & ~0o777 == 0, "unsafe archive mode")
            require(info.size >= 0 and (info.isreg() or info.size == 0), "invalid archive member size")
            total += info.size
            seen[info.name] = info
            require(len(seen) <= manifest["entries"] and total <= manifest["payload_bytes"],
                    "archive exceeds declared budget")
            if info.issym():
                links.append((path, link_target(info.name, info.linkname)))
        require(len(seen) == manifest["entries"] and total == manifest["payload_bytes"],
                "archive differs from declared inventory")
        require(".build" in seen and seen[".build"].isdir(), "archive build root is absent")
        for name in seen:
            for parent in PurePosixPath(name).parents:
                if str(parent) in seen:
                    require(seen[str(parent)].isdir(), "archive member has a non-directory ancestor")
        for _, target in links:
            require(target in seen, "archive symlink target is absent")
        for info in seen.values():
            path = destination / info.name
            if info.isdir():
                path.mkdir(parents=True, exist_ok=True)
            elif info.isreg():
                path.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(info) as content, path.open("xb") as output:
                    shutil.copyfileobj(content, output, 1024 ** 2)
                os.chmod(path, info.mode)
        for path, _ in links:
            (destination / path).parent.mkdir(parents=True, exist_ok=True)
            (destination / path).symlink_to(seen[str(path)].linkname)
        for path, _ in links:
            require((destination / path).resolve(strict=True).is_relative_to(destination / ".build"),
                    "archive symlink chain escapes build tree")


def restore_build(workspace, root, expected_sha256, current, native_state=None, native_observer=None):
    root = transfer_root(workspace, str(root))
    require(not os.path.lexists(workspace / ".build"), "worker build tree already exists; refusing replacement")
    manifest = read_manifest(root, expected_sha256, current, native_state)
    require(shutil.disk_usage(workspace).free >= RESERVE_BYTES + manifest["payload_bytes"],
            "insufficient storage for build restore and residual reserve")
    with tempfile.TemporaryDirectory(prefix=".swift-test-restore-", dir=workspace) as temporary:
        stage = Path(temporary)
        extract_build(root / ARCHIVE, stage, manifest)
        if native_state is not None:
            actual, seconds = native_finish(native_state, stage / ".build")
            expected = manifest.get("native_runtime", {"status": "unavailable", "reason": "legacy-manifest"})
            complete = expected["status"] == actual["status"] == "complete"
            status = "rejected"
            try:
                if complete:
                    import ci_swift_test_native as native
                    native.same_native_fingerprint(expected["fingerprint"], actual["fingerprint"])
                else:
                    # Missing API/SDK/closure evidence never permits a different image.
                    require_identity(manifest["identity"], current)
                status = "verified"
            finally:
                if native_observer is not None:
                    native_observer(mode="complete-fingerprint" if complete else "exact-image-fallback",
                                    status=status, producer_image=manifest["identity"]["image_version"],
                                    worker_image=current["image_version"], host_seconds=native_state["host_seconds"],
                                    closure_seconds=seconds,
                                    reason=None if complete else actual.get("reason", expected.get("reason")))
        require(not os.path.lexists(workspace / ".build"), "worker build tree appeared during restore")
        (stage / ".build").rename(workspace / ".build")
    return manifest


def cleanup_restored_build(workspace, identity, cleanup_safe):
    build = workspace / ".build"
    require(cleanup_safe, "preserving restored build after unproved process drain")
    info = build.lstat()
    require(build.is_dir() and not build.is_symlink() and (info.st_dev, info.st_ino) == identity,
            "preserving restored build after directory identity changed")
    shutil.rmtree(build)
    require(not os.path.lexists(build), "restored build cleanup failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare-transfer", "cleanup-transfer"))
    args = parser.parse_args()
    workspace = Path(os.environ["GITHUB_WORKSPACE"])
    require(workspace.resolve(strict=True) == workspace, "workspace must be canonical")
    if args.command == "prepare-transfer":
        root = Path(tempfile.mkdtemp(prefix=ROOT_PREFIX, dir=workspace))
        info = root.stat()
        try:
            with open(os.environ["GITHUB_ENV"], "a") as output:
                output.write(f"CODEXBAR_TEST_BUILD_ROOT={root}\n")
                output.write(f"CODEXBAR_TEST_BUILD_ROOT_ID={info.st_dev}:{info.st_ino}\n")
        except BaseException:
            root.rmdir()
            raise
    else:
        root = transfer_root(workspace, os.environ["CODEXBAR_TEST_BUILD_ROOT"])
        info = root.stat()
        require(f"{info.st_dev}:{info.st_ino}" == os.environ["CODEXBAR_TEST_BUILD_ROOT_ID"],
                "preserving transfer root after directory identity changed")
        shutil.rmtree(root)
        require(not os.path.lexists(root), "build transfer cleanup failed")


if __name__ == "__main__":
    main()
