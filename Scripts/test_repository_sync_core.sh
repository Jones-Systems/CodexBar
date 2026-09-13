#!/usr/bin/env bash
# Offline source-closure verification only; this does not replace repository make test/check or native CI.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codexbar-sync-closure.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/Sources" "$scratch/Tests"
cp "$root"/Sources/CodexBarCore/RepositorySync/*.swift "$scratch/Sources/"
cp "$root"/TestsLinux/RepositorySync*.swift "$scratch/Tests/"
cat > "$scratch/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "RepositorySyncClosure",
    products: [.library(name: "CodexBarCore", targets: ["CodexBarCore"])],
    targets: [
        .target(name: "CodexBarCore", path: "Sources"),
        .testTarget(name: "RepositorySyncTests", dependencies: ["CodexBarCore"], path: "Tests")
    ])
PACKAGE
swift test --package-path "$scratch" "$@"
