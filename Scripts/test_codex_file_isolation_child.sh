#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
    if (not raw_parent or "\n" in raw_parent or "\r" in raw_parent or str(parent) != raw_parent
            or not parent.is_absolute() or ".." in parent.parts
            or parent == root or root not in parent.parents
            or parent.resolve(strict=True) != parent or not parent.is_dir()):
        raise ValueError("expected an existing canonical directory strictly inside the workspace")
except (OSError, RuntimeError, ValueError) as error:
    sys.exit(f"Invalid CODEXBAR_TEST_SCRATCH_PARENT: {error}")
print(parent)
PYVALIDATE
)"
fi
PROOF_DIR="$(mktemp -d "$SCRATCH_PARENT/.codex-file-child.XXXXXX")"
trap 'rm -rf "$PROOF_DIR"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
export TMPDIR="$PROOF_DIR"
export CODEXBAR_TEST_WORKSPACE_ROOT="$ROOT_DIR"
export CODEXBAR_TEST_SCRATCH_PARENT="$PROOF_DIR"

# Compile the actual policy and detector without DEBUG. Only unrelated link dependencies are stubbed;
# this is policy/child proof, not a release build of the entire app or credential store.
cat > "$PROOF_DIR/Proof.swift" <<'SWIFT'
import Foundation

enum CodexOAuthCredentialsError: Error { case notFound }
enum KeychainAccessGate {
    static let disableAccessEnvironmentKey = "CODEXBAR_DISABLE_KEYCHAIN_ACCESS"
    static var isDisabled: Bool { fatalError("The file policy must not consult Keychain state") }
}

@main
struct Proof {
    static func main() throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[2])
        let childRoot = root.appendingPathComponent("child")
        let childFile = childRoot.appendingPathComponent("auth.json")
        let parentFile = root.appendingPathComponent("parent-auth.json")
        if args[1] == "launch" {
            try FileManager.default.createDirectory(at: childRoot, withIntermediateDirectories: true)
            try Data("synthetic-child".utf8).write(to: childFile)
            try Data("synthetic-parent".utf8).write(to: parentFile)
            let inherited = [CodexCredentialFileAccess.isolationEnvironmentKey: "1",
                             "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
                             "CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS": "1",
                             "CODEX_HOME": root.path,
                             TestFixtureScratch.parentEnvironmentKey: TestFixtureScratch.root.path,
                             TestFixtureScratch.workspaceEnvironmentKey: ProcessInfo.processInfo.environment[
                                 TestFixtureScratch.workspaceEnvironmentKey]!]
            for mode in ["deny", "fixture", "production"] {
                let child = Process()
                child.executableURL = URL(fileURLWithPath: args[0])
                child.arguments = [mode, root.path]
                if mode == "fixture" {
                    let parentScope = CodexCredentialFileAccess.FixtureScope(files: [parentFile])
                    let base = try parentScope.childEnvironment(base: inherited)
                    child.environment = try CodexCredentialFileAccess.FixtureScope(roots: [childRoot])
                        .childEnvironment(base: base)
                } else {
                    child.environment = mode == "production" ? [:] : inherited
                }
                try child.run()
                child.waitUntilExit()
                precondition(child.terminationStatus == 0, "Child policy proof failed")
            }
            print("Optimized policy child: deny, scoped fixture, parent-grant replacement, and pure non-test decision passed")
            return
        }
        if args[1] == "production" {
            precondition(!CodexCredentialFileAccess.isTestContext)
            precondition(CodexCredentialFileAccess.permits(URL(fileURLWithPath: "/fictitious/auth.json")))
            precondition(CodexPriorityDatabasePath.defaultURL(codexHome: { root })
                == root.appendingPathComponent("logs_2.sqlite"))
            return
        }
        let allowed = args[1] != "deny"
        precondition(CodexCredentialFileAccess.isTestContext)
        let trace = CodexPriorityDatabasePath.defaultURL(codexHome: {
            fatalError("Isolated trace resolution consulted the user home")
        })
        precondition(trace.deletingLastPathComponent().lastPathComponent.hasPrefix("codexbar-cost-trace-tests-"))
        precondition(trace.lastPathComponent == "logs_2.sqlite")
        precondition(CodexPriorityDatabasePath.defaultURL() == trace)
        precondition(CodexCredentialFileAccess.fileExists(at: childFile) == allowed)
        if allowed {
            let data = try CodexCredentialFileAccess.read(at: childFile)
            precondition(data == Data("synthetic-child".utf8))
        } else {
            do {
                _ = try CodexCredentialFileAccess.read(at: childFile)
                fatalError("An existing but unregistered fixture was read")
            } catch CodexOAuthCredentialsError.notFound {}
        }
        precondition(!CodexCredentialFileAccess.permits(parentFile))
    }
}
SWIFT

swiftc -O -parse-as-library -package-name CodexBar -module-cache-path "$PROOF_DIR/modules" \
  "$ROOT_DIR/Sources/CodexBarCore/CodexCredentialFileAccess.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/CodexPriorityDatabasePath.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/CodexHomeScope.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/KeychainSecurity.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/TestProcessSafety.swift" \
  "$ROOT_DIR/Sources/CodexBarCore/TestFixtureScratch.swift" \
  "$PROOF_DIR/Proof.swift" -o "$PROOF_DIR/codex-file-child"
"$PROOF_DIR/codex-file-child" launch "$PROOF_DIR/fixtures"
