#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROOF_DIR="$(mktemp -d "$ROOT_DIR/.provider-session-child.XXXXXX")"
trap 'rm -rf "$PROOF_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
export TMPDIR="$PROOF_DIR"

# Compile the real path policy and runtime detector without DEBUG; only unrelated Keychain linkage is stubbed.
swiftc -O -parse-as-library -module-cache-path "$PROOF_DIR/modules" \
  "$ROOT_DIR/Sources/CodexBarCore/JonesStateRoot.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/ProviderSessionStoreFile.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/KeychainSecurity.swift" \
  "$ROOT_DIR/Scripts/fixtures/provider_session_file_proof.swift" \
  -o "$PROOF_DIR/provider-session-file-child"
"$PROOF_DIR/provider-session-file-child" launch "$PROOF_DIR/fixtures"
