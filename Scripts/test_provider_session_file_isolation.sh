#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Optional CODEXBAR_TEST_SCRATCH_PARENT must be a canonical absolute workspace descendant.
# The caller owns this existing parent; only our unique proof child is disposable.
SCRATCH_PARENT="$ROOT_DIR"
if [[ ${CODEXBAR_TEST_SCRATCH_PARENT+x} ]]; then
  SCRATCH_PARENT="$(python3 - "$ROOT_DIR" <<'PYVALIDATE'
import os
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
raw_parent = os.environ["CODEXBAR_TEST_SCRATCH_PARENT"]
parent = Path(raw_parent)
try:
    if (not raw_parent or "\n" in raw_parent or not parent.is_absolute() or ".." in parent.parts
            or parent == root or root not in parent.parents
            or parent.resolve(strict=True) != parent or not parent.is_dir()):
        raise ValueError("expected an existing canonical directory strictly inside the workspace")
except (OSError, RuntimeError, ValueError) as error:
    sys.exit(f"Invalid CODEXBAR_TEST_SCRATCH_PARENT: {error}")
print(parent)
PYVALIDATE
)"
fi
PROOF_DIR="$(mktemp -d "$SCRATCH_PARENT/.provider-session-child.XXXXXX")"
trap 'rm -rf "$PROOF_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
export TMPDIR="$PROOF_DIR"

# Compile the real path policy and runtime detector without DEBUG; only unrelated Keychain linkage is stubbed.
swiftc -O -parse-as-library -package-name CodexBar -module-cache-path "$PROOF_DIR/modules" \
  "$ROOT_DIR/Sources/CodexBarCore/JonesStateRoot.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/ProviderSessionStoreFile.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/KeychainSecurity.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/TestProcessSafety.swift" \
  "$ROOT_DIR/Scripts/fixtures/provider_session_file_proof.swift" \
  -o "$PROOF_DIR/provider-session-file-child"
"$PROOF_DIR/provider-session-file-child" launch "$PROOF_DIR/fixtures"
