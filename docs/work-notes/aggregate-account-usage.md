# Work Note — Aggregate Account Usage

<!-- codex-section:begin id="worknote.aggregate-account-usage#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.aggregate-account-usage`

Purpose: Preserve selected-account aggregate delivery, pacing, and account presentation repairs.

Governing artifact: `spec.aggregate-account-usage`

Continuity owner: Codex root, Jones Code thread `8b4b042f-1785-4ce2-8a42-58a1692e197b`

Consumers: M Jones and CodexBar delivery owner

Authority effect: none
<!-- codex-section:end id="worknote.aggregate-account-usage#ctx.artifact-header.001" -->

## Original accepted scope and binding

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

## Owner follow-up: pacing and account presentation

PR #15 merged as `1c28608feaacfa17eaa86d2d06322b5335ba37ca`; its delivery
record verifies all eight required checks, full local tests (1,044 selections,
87 first-pass successful groups), lint and the installed Jones app's executable.
The previous installed bundle is retained for rollback. No readiness mark was
created because this runtime reported unavailable Darwin process containment.

The owner now authorizes production pacing with the red marker reduced from
the mock's 12-point height to 8 points, keeping its center aligned with the
meter. The summary's text and overall row height are not the requested target.
The owner also supplied native screenshots showing a visible Codex `default`
row, provider names instead of account names in minimized Overview, and several
workspace sections. Required follow-up: never display Codex `default`; show the
selected account names in Overview; display Malcolm, Jace, Umich, Steven and
Wallace together in one Personal section without workspace headings or IDs.
Internal verified quota identities remain necessary for deduplication and routing.
The delivery finish line remains merged changes and the updated local Jones app.

Root owns Git, documentation, shared build/test/package state and installation
in the existing isolated worktree. The follow-up branch is
`work/aggregate-pacing-overview-repair-8b4b042f`, based on canonical `main` at
`1c28608feaacfa17eaa86d2d06322b5335ba37ca`; no overlapping open PRs were found.
Two read-only lanes cover pacing technical framing and account presentation
evidence. Inherited mode remains `claude_frontier`, temporary preference revision
1. Fresh account routing selected Malcolm's verified fleet binding with allowance
unavailable under its standing fallback; no model access or quota is inferred.

The follow-up registration preflight again found no socket at
`~/.local/state/voice-control-plane/registry.sock`: `registration_unavailable`,
`endpoint_unavailable`, effect none. No request was sent and no endpoint repaired.

Source evidence found independent presentation causes: the shared Codex account
display consumed every visible projection row, the minimized Overview summary
explicitly used the provider name, and workspace metadata determined account
sections. The read-only follow-up also established that hidden live sources
need a unique verified named counterpart; percentages alone are not identity.
Opus technical framing completed and is retained at
`.build/pacing-overview-opus-framing-v2.md`. Its limiting-window timing, additive
core selection helper, stable readiness fingerprint and 8-point overlay decisions
are encoded in the evolving Engineering Spec. One Astra builder owns all source
and affected tests; root owns documentation, architecture anchors and shared
verification state. No independent review is required by target policy.

Before production changes, the isolated Overview fixture file had SHA-256
`25c393df76795456468966e5d63851118925ba07b01e78b62c194e076ebe9364`.
The first slash/name filter built successfully but selected zero tests, so it
provides no behavioral evidence. The corrected isolated command was
`Scripts/test.sh --command swift test --skip-build --no-parallel --filter OverviewFleetAccountsTests`.
It ran 18 tests: the two new regression cases failed with 19 issues, while all
16 existing tests passed. Failures independently prove visible default count,
missing Personal grouping, live-vs-named active identity, duplicate account rows
and the Codex-vs-Jace summary label. One ordering assertion also assumed raw
projection order; it will be corrected to preserve existing sort preferences.
Logs are `.build/pacing-overview-v2-red-suite.log`; runner exit 1 and fixture
scratch removal/absence were verified. Production source stayed at the base
revision through that run. Source writes were then released to the builder.

### Follow-up component render and verification correction

Rendered the actual aggregate SwiftUI view with synthetic model values in dark
and highlighted states. The marker and marker-free render both measure
310 × 39 points at 2× scale; the centered marker remains red when highlighted.
Evidence lives in `.build/pacing-native-render/` (source hashes, PNGs and probe).
This verifies the component, not a live menu or installed-account screenshot.
The first affected run compiled app sources but failed test compilation on a
nested Swift Testing `#require`; split that binding before the next run.
Self-review also narrowed the unresolved-default summary omission to a cached
projection containing actual hidden sources, preserving absent/empty projection
overviews; added isolated regressions. No live credentials or provider probes.

### Follow-up resumed after interrupted verification

Recovered the affected-suite result: 247 tests ran; four issues across three
tests. The default-row fixture had opened a single-provider Codex page instead
of merged Overview, and the cold-cache fixture expected reconciliation not to
populate an empty projection. Corrected both fixture assumptions while retaining
the account counts, names and raw-identity assertions. The architecture inventory
tracks moved existing anchors, retires the removed default fallback, and retains
explicit local reasons for the new provider identity display branches.
The interrupted runner no longer existed; no process held its exact fixture
parent. Preserved the log and recovery manifest, then removed only that owned
fixture root and verified absence. Full verification is pending.
Native render pixel bounds are 4 × 16 pixels at 2× scale (2 × 8 points),
identical in normal/highlighted states; both rows remain 310 × 39 points.

Final `make check` passes with zero violations across 2166 Swift files. The
new argument layouts were corrected without changing test values, and the
hidden-source predicate moved to the existing presentation projection to stay
within the menu controller file-length limit. No lint suppression was added.
The final full `make test` is running with frozen source and test files.

The first full run discovered 1044 selections and completed 48 groups before
stopping at group 49 on an existing selected-source custom-label regression.
The failing test was unchanged; its one full-group retry also failed. Preserved
the existing custom name when no named account resolves by reading only the
explicit saved override. Missing/blank overrides still do not synthesize default.
Added that boundary coverage. The runner removed its fixture root and verified
absence. All later full-suite groups remain unverified until the final rerun.

The next validation passed 70 focused tests (labels, Overview and architecture),
then passed 63 full-suite groups before the new distinct-default Overview
fixture failed when grouped with its normal peers. Both full-group attempts
reported missing rendered rows. Menu refresh freshness uses object identifiers;
releasing and recreating a menu inside the fixture loop can reuse a fresh ID.
That is a source-grounded explanation, not a live runtime defect diagnosis.
The fixture now invokes production Overview content with an explicit context,
retaining exact row counts, both layouts, no-default and raw-identity checks.
No production change was needed. The failed run drained and verified scratch
removal. Next verification begins with its exact full-suite group before the
required unchanged full suite; no test selection is removed.

The exact formerly failing Overview peer group passed (114 tests/11 suites).
The next full run passed groups 1–76 before an existing height fixture failed
at group 77 because it selected an unmatched live/default source and expected
a Codex summary. Migrated that fixture to a named active profile and seeded
Claude first; all geometry, toggle and row assertions remain unchanged. No
production source changed. The failed group retry repeated the same issue,
and the runner verified cleanup. Rather than repeat 76 unchanged groups, the
final local continuation discovers the same 1044 selections, verifies the
height group is still 77, and executes original groups 77–87 with the existing
runner helpers and owned fixture lifecycle. The earlier full-run evidence is
preserved; this is a coverage union, not a claim of one all-green local
`make test` invocation. Exact final-head full CI remains mandatory for merge.

Final local validation: `make check` passed with zero violations in 2166 Swift
files. Original groups 77–87 passed without test issues or retries after the
height-fixture migration; together with the unchanged production run's first
76 successful groups, all 1044 discovered selections are covered locally.
The tail command used the existing runner's discovery/group/filter helpers,
checked the original group mapping, and verified owned scratch removal. Its
first safety assertion used the file name rather than the suite name and ran
no tests; corrected it, then reused the completed build. Logs and exact
selection coverage remain under `.build/pacing-*`. Production source hashes
match the earlier full run. No claim of one final all-green local full-suite
invocation is made; final-head complete CI remains the merge gate.

## Expanded pacing and production-identity follow-up

The owner supplied installed-menu screenshots after PR #16 and requested a
clickable aggregate with a signed pacing difference measured against 500% or
200%, an estimated exhaustion time, green reserve/red deficit semantics, the
Claude Personal heading, a working Claude total, and exactly the five named
Codex fleet profiles. The current 2 × 8 point marker extension is acceptable.
The accepted finish line remains merge and local Jones-app installation.

This follow-up starts from canonical main `2fdc905b8aa55a2900a3f5907ad7daebe0b5bbc4`
in `/Users/malcolmjones/.t3/worktrees/CodexBar/aggregate-details-8b4b042f`, branch
`work/aggregate-details-8b4b042f`. Root alone owns Git, documents, checks,
packaging and delivery. No open PR overlapped at intake. The prior task worktree
and installation rollback bundles remain retained.

Two bounded Sol/medium source investigations completed at that exact base.
The Codex filter excluded live/default rows but admitted managed and nonfleet
profile rows, which can receive the `Account · <digest>` label. The screenshot
cannot identify which of those sources produced the particular row. A strict
presentation-only roster applies when a recognized enrolled fleet home exists;
generic nonfleet behavior remains outside that integration. Missing usage must
not hide a named enrolled profile or change authentication selection.

Claude native row IDs already use the expected aliases. Production OAuth usage
contains no email/organization, and its snapshot conversion supplies no account
ID; the aggregate consequently rejects valid usage as unidentified. Existing
fixtures supplied synthetic email or IDs and missed this transport shape. The
bounded repair attaches an unchanged selected-profile Claude UUID at the fetch
boundary, preserving identity deduplication instead of counting display labels.
The native Claude caller also supplies no section metadata to the shared renderer.

The new pacing disclosure is framed by an Opus 5.5/high read-only child under
inherited `claude_frontier`, personal temporary revision 1. Its account route
returned `start` for Malcolm's `claudeAgent`; both companion allowances were
unavailable (`account_authentication_unverified`, fleet-managed unsupported),
so allowance remains unknown under the existing fallback. The first T3 launch
was rejected with `No task was created` because the target worktree belongs to
a different repository; the corrected read-only child uses the parent binding
and explicit source path. No unknown creation effect exists.

Current frontend guidance was resolved and read at
`9a01d7131a057aee382c78485a2610eeba689b54`; affected map entries remain in `docs/ui.md`.
The gallery export route covers public website/iOS presentation exports; this
private account-backed macOS application update produces no such export.
No web search is needed: owner screenshots, current native code and synthetic
fixtures provide the bounded research basis. The native Voice registry socket
is absent, so registration is unavailable with no submitted effect; no endpoint
repair or identity guess is attempted.

Independent builders own disjoint roster-presentation and Claude-fetch source
and tests. Root owns the shared build state. An APFS copy-on-write clone of the
prior owned build cache limits disk duplication; retained logs and binaries
inside it are historical and do not establish candidate verification. CPU was
24.3%, one core 8.33% across 12 cores, memory pressure warning with zero sampled
swap traffic at builder admission. No test/build process was started concurrently.

Opus framing completed and was accepted for in-place expansion, raw signed
balance, pooled current-rate estimate bounded by the first reset, existing
workday behavior, native green/red/selection colors and session-scoped state.
Its full result is retained in task-owned `.build/aggregate-details-opus-v3.md`.
The Engineering Spec now records those semantics and the shared-core compatibility
and verification boundary. One Astra/high writer owns that connected source/test
slice; the two defect writers have frozen their scopes. Root checkpointed their
six paths as `18512e9b`. No independent reviewer is selected by default.

Failing-before execution was not cheap at this new physical worktree: compiling
new app assertions required a rebuild while independent writers were active.
Root did not freeze sibling lanes solely to manufacture red evidence. The exact
pre-fix counterexamples and production-shaped assertions are retained; frozen
candidate execution remains required and no unrun test is reported as passing.

The first make-check run completed its harness checks but stopped on formatting
in eight changed files. Root ran the repository-pinned SwiftFormat only on the
17 changed Swift paths and replaced two forced fixture UUID unwraps with
throwing requirements. The first focused compile could not reuse cloned Clang
modules because their cache recorded the prior absolute worktree path; its
runner drained and removed the fixture parent. Root retained the incompatible
cloned debug/release ModuleCache directories under exact task-owned names,
leaving the old worktree untouched, then restarted against fresh cache paths.
The second compile has built the core and application and is building tests;
no behavioral pass is claimed before execution finishes.
