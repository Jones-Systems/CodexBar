# Test execution profiles

The shipped product and offline tests cover Codex, Claude and shared behavior.
Unused providers, provider plugins and QuickJS, hooks and iCloud synchronization
have been removed from source. Both `normal` and `full` remain valid profile
names for existing SwiftPM, CLI and CI callers. The owner uses the visual menu
bar app without intentional repository CLI terminal or remote Agent Sessions use.
`normal` excludes four owner-terminal-only suites from test compilation and
execution: `CLICacheTests.swift`, `CLIToonSnapshotTests.swift`,
`ToonFormatterTests.swift` and `CLIUnificationGoldenTests.swift`. `full` retains
all current offline test sources, methods, assertions and fixtures. The mixed
full-only partition remains empty.

## Commands and restoration

```sh
make test
CODEXBAR_TEST_PROFILE=normal make test
CODEXBAR_TEST_PROFILE=full make test
python3 Scripts/test_profiles.py describe
```

An invalid explicit profile still fails. Profile and manifest digest remain part
of campaign/cache identity. Selecting `full` does not restore deleted code.
For deliberate restoration, recover the relevant implementation, tests and
package membership from Git revision
`91bd5fb4af704da9181212bea636d527a058e615`, then qualify the restored behavior.
See the [product spec](engineering-specs/slim-codex-claude-product.md).

In the CI workflow’s manual dispatch, select `test_profile: full` and provide the
exact `expected_sha` and the existing campaign controls. PR, push and daily
scheduled events always select normal. Full is offline: it does not grant live
provider, Keychain, browser-cookie, private-account, signing or packaging access.
The native journey cap and advisory label/manual placement remain unchanged.

The CI workflow runs the normal used-feature profile daily at **05:00
America/New_York (EST/EDT)**, following daylight saving time automatically. It uses
the default branch's latest commit and selects the macOS build producer, both
existing macOS shards, both Linux test architectures and the musl CLI build. Its
concurrency group is separate from push/PR runs. GitHub may delay or drop
scheduled events under runner/service load; this is a requested trigger time,
not a guaranteed start time.

Results use the existing Actions job/step logs and path-gate/aggregate summaries.
The producer and both macOS shards must pass; failure or skipped selected jobs
fail the aggregate. Compiled artifacts expire after one day. Synthetic reset-timing
artifacts upload on macOS success or failure when setup succeeded and are retained
for seven days. Failure includes existing crash diagnostics; no issue is created
automatically. Campaign receipts remain specific to manual measurement runs.
See GitHub's [schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

## Retained boundaries

Codex/Claude account switching, credential isolation, quota/reset tracking,
persistence, local usage/spend history, cache integrity and scanner scale
regressions remain covered. No high-limit scanner or persistence fixture was
reduced for this removal. OpenAI dashboard/web parsing remains Codex coverage;
OpenCodex ingestion remains an optional spend source. Claude offline quota
fallback and widget quota fields remain.

MiniMax-named LogRedactor tests cover shared redaction. Kiro-named TTY process
and hard-stop suites protect shared process cleanup used by Codex and Claude.
Local fleet/account identity is retained independently of removed iCloud
transport. Tests with arbitrary retired-provider IDs use retained provider or
account scopes when their subject is shared behavior. Removed-provider adapters
and UI inventories have no retained product route.

The CLI and supported-platform build checks remain enabled. Offline tests do
not authorize Keychain, browser-cookie, private-account, live provider, signing
or packaging access. Native journey placement remains advisory and opt-in.

All other CLI suites, shared safety and shipped regression coverage remain normal,
including external Codex/Claude executable, session, login, probe and fallback paths.
Local/adaptive Agent Sessions, scheduling, shared session JSON and Tailscale security
coverage remain normal; no remote-only group is excluded.
