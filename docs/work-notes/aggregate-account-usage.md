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
source, credential, branch or worktree cleanup occurred. Local `make test` is now
running against the frozen candidate. No live provider or Keychain checks are used.

The first `make check` completed all checks and reported one new SwiftLint type
size violation in `OverviewFleetAccountsTests`. Its added helper/test moved to an
extension of that same suite; focused strict lint then passed with zero violations.
No test was removed or excluded.

## Delivery and recovery

Target `AGENTS.md` supplies the accepted canonical merge and local Jones app
update binding. Installed Jones target is `~/Applications/CodexBar Jones.app`,
bundle `com.jonessystems.codexbar`, build 135. Stock `/Applications/CodexBar.app`
is outside replacement scope. Preserve preferences and the prior Jones bundle.
Registration metadata preflight found no socket at
`~/.local/state/voice-control-plane/registry.sock`: `registration_unavailable`,
`endpoint_unavailable`, effect none. No request was sent or endpoint repaired.
Exact candidate/check/delivery evidence will be recorded here.
