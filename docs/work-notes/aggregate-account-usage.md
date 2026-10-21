# Work Note — Aggregate Account Usage

<!-- codex-section:begin id="worknote.aggregate-account-usage#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.aggregate-account-usage`

Purpose: Preserve selected-account aggregate delivery and pacing mock scope.

Governing artifact: `spec.aggregate-account-usage`

Continuity owner: Codex root, Jones Code thread `8b4b042f-1785-4ce2-8a42-58a1692e197b`

Consumers: M Jones and CodexBar delivery owner

Authority effect: none
<!-- codex-section:end id="worknote.aggregate-account-usage#ctx.artifact-header.001" -->

## Accepted scope and binding

The owner selected A and authorized baseline implementation, while requesting a
new mock of a small red aggregate pacing tick. The tick remains review-only.
Canonical repository `Jones-Systems/CodexBar`; verified initial base `main`
at `6b0cb33408653c0755d6527eb82615d2d082b314`. No open PRs were found.
Task worktree `/Users/malcolmjones/.t3/worktrees/CodexBar/aggregate-account-usage-8b4b042f`,
branch `work/aggregate-account-usage-8b4b042f`; root is sole Git owner.
The original V3 worktree retains owned local HTML artifacts only.

## Research and decisions

Two independent read-only lanes completed: Opus 5.5/high technical framing and
Sol/medium existing-pacing source inspection. Inherited mode `claude_frontier`,
personal temporary preference revision 1. Claude routing chose the verified
Malcolm provider binding with allowance unavailable under the standing fallback.
No live usage or credential reads were performed by the research lanes.
Frontend guidance main resolved to `9a01d7131a057aee382c78485a2610eeba689b54`.

The aggregate uses fixed owner-selected rosters, not all future enrollment.
Codex combines normalized workspace ID and email to avoid merging Team seats.
Existing compact percentages reflect the limiting usage window, not reliably
Weekly. Reported errors with retained usage must not count as fresh contributions.

Existing `UsagePace` calculates each window separately; remaining-oriented pacing
uses 100 minus expected consumed. The mock sums expected remaining independently
across each account's own reset. Its illustrative weekly example uses actual
357% / 500%, target 400% / 500%, fill 71.4%, red marker 80%. Missing timing hides
the exact marker. Mock source is the original worktree's
`artifacts/codexbar-aggregate-usage-mockups/pacing.html`; HTML checks at 728px and
360px passed marker counts, missing-state behavior and horizontal overflow checks.
This is browser concept evidence, not native implementation evidence.

## Execution and verification

Source model/view, adapters and synthetic tests are complete. Root accepted the
builder checkpoint, aligned the second line and Overview divider with selected A,
and froze source for verification. One bounded builder owns source/tests; root owns documents, build/test
state and publication. Parent-only core compilation passed with
`swift build --target CodexBarCore -j 2` (76.14 seconds). `swift package resolve` completed
against the existing lock without a tracked change. Swift 6.3 is available.
Declared lint tools bootstrap through the repository's pinned scripts; no new
dependency is introduced. Initial disk free space was 7.5 GiB, so no duplicate
parallel builds or unowned cache cleanup will be used. The pinned lint tools are
ready. The ambient Homebrew Node failed its dynamic-library load; the existing
NVM Node 20.19.2 runs the repository tools successfully, without a global repair.

Affected-check group: `JonesAccountAggregateTests`,
`CodexVisibleAccountProjectionRuntimeIdentityTests`, `OverviewFleetAccountsTests`,
`StatusMenuClaudeNativeProfileAccountsTests`, `StatusMenuCompactAccountLayoutTests`,
`JonesCompactAccountPresentationTests`, `JonesGroupedCompactAccountPresentationTests`,
and `ProviderArchitectureGatekeeperTests`. No target affected-check manifest exists;
this note records the bounded group. Pure synthetic arithmetic/identity fixtures add
no I/O. Menu fixtures retain their contained scratch lifecycle and cleanup assertions.
No performance optimization or test scope reduction is included.

The first focused build failed because root changed layout source during compilation;
the fixture runner drained and verified scratch removal. A fresh frozen-source rerun used `Scripts/test.sh --command swift test -j 2 --filter` with the affected group.
Admission for the rerun: CPU 14.1%, one core 8.33%, warning pressure, swap 0.62 MiB/s;
one serial process allowed. That cold build was deliberately stopped (143) as
shared disk free space fell below 700 MiB. The runner drained and verified fixture
removal. Only task-generated `.dSYM` folders were then removed from this worktree's
new `.build/arm64-apple-macosx/debug` to recover roughly 0.5 GiB; no shared cache,
source, credential, branch or worktree cleanup occurred. The required local `make test` was also safely stopped during discovery (make
exit 2, inner command 143) as free space fell to 280 MiB. It ran no test groups;
no passing local suite is claimed. After verified drain and scratch removal,
root removed this task's newly generated debug directory only. Build/test logs
remain in the owned `.build` root. Shared free space remained below 1 GiB, so
no further local compilation or Jones app replacement was attempted in that first pass. No live provider or Keychain checks are used.

The first `make check` completed all checks and reported one new SwiftLint type
size violation in `OverviewFleetAccountsTests`. Its added helper/test moved to an
extension of that same suite; focused strict lint then passed with zero violations.
No test was removed or excluded. The final full `make check` passed (exit 0),
including SwiftFormat and strict SwiftLint with zero violations across 2,166 files.
Repository tooling used the already-installed NVM Node 20.19.2.

## Delivery and recovery

Target `AGENTS.md` supplies the accepted canonical merge and local Jones app
update binding. Installed Jones target is `~/Applications/CodexBar Jones.app`,
bundle `com.jonessystems.codexbar`, build 135. Stock `/Applications/CodexBar.app`
is outside replacement scope. Preserve preferences and the prior Jones bundle.
Registration metadata preflight found no socket at
`~/.local/state/voice-control-plane/registry.sock`: `registration_unavailable`,
`endpoint_unavailable`, effect none. No request was sent or endpoint repaired.
Source checkpoint `e36c89c9aa670c626a7c08c42b7c76ab719dc14e` was pushed to the
canonical `standalone` remote with direct OID readback. Ordinary non-draft
[PR #15](https://github.com/Jones-Systems/CodexBar/pull/15) is linked to this Jones
Code thread. GitHub's full macOS/Linux CI qualifies the final PR head. The PR's
delivery record owns subsequent exact-head CI, merge and local-installation
postconditions; a pending CI run is not a pass. Local replacement was initially
blocked by disk space; a later sample recovered to 13 GiB, permitting validation
and a subsequent tested Jones-identity build. The prior
installed bundle remains untouched; no unrelated cleanup is authorized.


## CI repair

At PR head `0dfb210838e2c3cd75f58210af4d9adfc9fae89d`, GitHub run
`39541901280` passed Linux glibc x64/ARM64, musl, lint, and macOS shard 1.
macOS shard 0 failed the new aggregate placement fixture at the required Codex
display (`nil`); the overall `lint-build-test` job then correctly failed its
macOS result gate. The aggregate arithmetic and identity tests passed in that run.

The fixture seeded Codex's menu projection before changing Claude's profile
selection. Config revision changes intentionally invalidate cached Codex routing,
including when another provider changes. The repair seeds Claude configuration
first, then the synthetic Codex projection. All placement/order/refresh assertions
remain present; no production code changes and no retries or exclusions mask the
failure. Direct failing-before evidence is the exact-head CI log retained under
the owned `.build` directory. CPU admission before local validation: 28.9%, one
core 8.33%, normal pressure and zero sampled swap; one serial test process.


The first local affected-group run completed its cold build in 632.74 seconds.
The repaired placement fixture and all feature checks passed. Its one remaining
failure was the architecture gate: edits shifted existing absolute-line anchors
in four touched source files. Root updated 31 location integers by mapping each
unchanged baseline source line to its current position. Anchor text, provider sets,
reasons, occurrence fingerprints and scanner behavior remain unchanged. No new
allowlist or suppression was added. The affected-group rerun now includes that
exact gate as well as the original feature checks.


The final local affected group passed: 97 Swift Testing cases in seven suites
and four XCTest cases, zero failures; fixture cleanup verified absence. This
includes the repaired aggregate placement fixture and architecture gate. Final
full `make check`, full `make test`, current-head CI and local packaging follow
under the existing delivery binding.
