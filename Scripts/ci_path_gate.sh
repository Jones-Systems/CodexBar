#!/usr/bin/env bash

set -euo pipefail

# One classifier owns all platform partitions, including rename and deletion evidence.
python3 - "$@" <<'PY'
import os
import pathlib
import re
import sys

if len(sys.argv) != 3 or sys.argv[1] not in {"macos", "linux", "musl"}:
    sys.exit("Usage: ci_path_gate.sh <macos|linux|musl> <changed-paths-file>")
platform, filename = sys.argv[1:]
try:
    rows = pathlib.Path(filename).read_text(encoding="utf-8").splitlines()
except (OSError, UnicodeError) as error:
    sys.exit(f"Cannot read changed paths; refusing to skip compilation: {error}")

draft = os.environ.get("CI_PULL_REQUEST_DRAFT", "false")
if draft not in {"true", "false"}:
    sys.exit("CI_PULL_REQUEST_DRAFT must be true or false.")

paths = []
for row in rows:
    if not row:
        continue
    fields = row.split("\t")
    status = fields[0]
    rename = re.fullmatch(r"[RC]([0-9]{1,3})", status)
    valid = ((rename is not None and int(rename[1]) <= 100 and len(fields) == 3)
             or (status in {"A", "D", "M", "T", "U", "X", "B"} and len(fields) == 2))
    if not valid or any(not path or "\x00" in path for path in fields[1:]):
        sys.exit("Invalid git name-status row; refusing to skip compilation.")
    paths.extend(fields[1:])

all_platforms = {"macos", "linux", "musl"}
native_prefixes = (
    "Sources/CodexBar/", "Sources/CodexBarWidget/", "Sources/CodexBarClaudeWatchdog/",
    "Sources/CodexBarClaudeWebProbe/", "WidgetExtension/", "Tests/CodexBarTests/", "Icon.icon/",
)
portable_test_prefixes = (
    "TestsLinux/", "TestsPlugin/", "Tests/AdaptiveReplayCLITests/", "Tests/AdaptiveReplayKitTests/",
)
# TestsPlugin compiles these sources through checked-in symlinks.
portable_source_paths = {
    "Tests/CodexBarTests/ProviderPluginDetailsParityTests.swift",
    "Tests/CodexBarTests/ProviderPluginExtensionParityTests.swift",
    "Tests/CodexBarTests/ProviderPluginParityTests.swift",
    "Tests/CodexBarTests/ProviderPluginRuntimeTests.swift",
    "Tests/CodexBarTests/Sub2APIPluginGoldenTests.swift",
}
portable_paths = {
    "docs/.nojekyll", "docs/CNAME", "docs/index.html", "docs/llms.txt", "docs/site-locales.mjs",
    "docs/site.css", "docs/site.js", "docs/social.html", "docs/social.png",
    "Scripts/build-site-css.sh", "Scripts/site-tailwind.input.css", "Scripts/tailwind.site.config.cjs",
    "Scripts/check-site-locales.mjs", "Scripts/check-documentation-links.mjs", "Scripts/docs-list.mjs",
    "Scripts/generate-llms.mjs", "Scripts/check_repository_size.sh", "Scripts/check_upstreams.sh",
    ".github/workflows/upstream-monitor.yml", ".github/workflows/jones-app-candidate.yml",
    ".github/workflows/jones-menu-candidate.yml", ".oxfmtrc.json", ".oxlintrc.json", "tsconfig.plugins.json",
}


def classify(path):
    if (path in {"AGENTS.md", "CLAUDE.md", "docs/configuration.md", "docs/DEVELOPMENT.md",
                 "docs/compiler-resource-limits.md"}
            or path.endswith(("/AGENTS.md", "/CLAUDE.md")) or path.startswith(".agents/")):
        return all_platforms, "changes contributor or runtime configuration contracts"
    if path in portable_source_paths:
        return {"macos", "linux"}, "changes a source shared through TestsPlugin symlinks"
    if path.startswith(native_prefixes) or path == "Icon.icns":
        return {"macos"}, "changes macOS app, widget, resources or native tests"
    if path.startswith(portable_test_prefixes):
        return {"macos", "linux"}, "changes test targets supported on macOS and Linux"
    if path.startswith("Sources/") or path in {"Package.swift", "Package.resolved"}:
        return all_platforms, "changes shared source, C modules or package dependencies"
    if path in portable_paths or path.endswith(".md"):
        return set(), "covered by portable checks"
    if path.startswith("docs/") and pathlib.PurePosixPath(path).suffix in {
        ".png", ".jpg", ".jpeg", ".webp", ".ico", ".svg",
    }:
        return set(), "covered by portable checks"
    return all_platforms, "unknown path or global build, test or policy surface"


required = False
reason = "changes covered by portable checks or another platform"
for path in paths:
    platforms, path_reason = classify(path)
    if platform in platforms and not required:
        required = True
        reason = f"{path}: {path_reason}"
if not paths:
    required = True
    reason = "no changed paths reported; full platform coverage required"

deferred = platform == "macos" and required and draft == "true"
if deferred:
    reason = "draft pull request: macOS Swift tests deferred until ready for review"
key = {"macos": "macos-tests", "linux": "linux-tests", "musl": "linux-musl-build"}[platform]
outputs = {key: str(required).lower(), f"{key}-reason": reason}
if platform == "macos":
    outputs.update({"macos-tests-deferred": str(deferred).lower(), "changed-path-count": str(len(paths))})
if os.environ.get("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        for name, value in outputs.items():
            output.write(f"{name}={value}\n")
print(f"{key}: required={str(required).lower()}, deferred={str(deferred).lower()}; {reason}")
PY
