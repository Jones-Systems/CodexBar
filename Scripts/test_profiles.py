#!/usr/bin/env python3
"""Offline test-profile contract, shared by validation and CI evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
from collections.abc import Mapping

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path("Scripts/test_profiles.json")


def selected_profile(environment: Mapping[str, str] | None = None) -> str:
    environment = os.environ if environment is None else environment
    profile = environment.get("CODEXBAR_TEST_PROFILE", "normal")
    if profile not in ("normal", "full"):
        raise ValueError("CODEXBAR_TEST_PROFILE must be normal or full (unset defaults to normal)")
    return profile


def manifest_digest(root: Path | None = None) -> str:
    return hashlib.sha256(((root or ROOT) / MANIFEST).read_bytes()).hexdigest()


def _source_path(root: Path, raw: str) -> Path:
    path = PurePosixPath(raw)
    if (path.is_absolute() or len(path.parts) < 2 or path.parts[0] not in ("Tests", "TestsLinux", "TestsPlugin")
            or any(part in (".", "..") for part in path.parts) or path.suffix != ".swift"
            or str(path) != raw):
        raise ValueError(f"Invalid test source path: {raw}")
    source = root / raw
    if not source.is_file() or not source.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Missing or escaped test source: {raw}")
    return source


def load_manifest(root: Path | None = None) -> dict:
    root = root or ROOT
    manifest = json.loads((root / MANIFEST).read_text())
    if (set(manifest) != {"version", "normal_providers", "full_only_groups", "mixed_full_only"}
            or manifest["version"] != 1 or manifest["normal_providers"] != ["codex", "claude"]):
        raise ValueError("Unsupported test profile manifest")
    paths: set[str] = set()
    group_ids: set[str] = set()
    for group in manifest["full_only_groups"]:
        if (set(group) != {"id", "category", "reason", "files"} or not group["id"] or not group["category"]
                or not group["reason"].strip() or not group["files"] or group["id"] in group_ids):
            raise ValueError("Invalid or duplicate full-only group")
        group_ids.add(group["id"])
        for raw in group["files"]:
            _source_path(root, raw)
            if raw in paths:
                raise ValueError(f"Duplicate test profile path: {raw}")
            paths.add(raw)
    mixed_paths: set[str] = set()
    for entry in manifest["mixed_full_only"]:
        if set(entry) != {"file", "tests", "reason"} or not entry["reason"].strip() or not entry["tests"]:
            raise ValueError("Invalid mixed test group")
        source = _source_path(root, entry["file"])
        if entry["file"] in paths or entry["file"] in mixed_paths:
            raise ValueError(f"Conflicting mixed test source: {entry['file']}")
        mixed_paths.add(entry["file"])
        if "#if CODEXBAR_FULL_TEST_PROFILE" not in source.read_text():
            raise ValueError(f"Missing full-profile guard: {entry['file']}")
        if len(set(entry["tests"])) != len(entry["tests"]):
            raise ValueError(f"Duplicate mixed test identity: {entry['file']}")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "describe"))
    args = parser.parse_args()
    profile = selected_profile()
    manifest = load_manifest()
    if args.command == "describe":
        print(json.dumps({"profile": profile, "manifest_sha256": manifest_digest(),
                          "full_only_paths": sum(len(g["files"]) for g in manifest["full_only_groups"]),
                          "mixed_full_only_tests": sum(len(g["tests"]) for g in manifest["mixed_full_only"])}))
    else:
        print(f"Test profile contract OK: {profile}; manifest {manifest_digest()}")


if __name__ == "__main__":
    main()
