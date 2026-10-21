# Work Note — Idle Resource Efficiency

<!-- codex-section:begin id="worknote.idle-resource-efficiency#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.idle-resource-efficiency`

Purpose: Preserve the diagnosis, implementation boundaries, and verification of idle resource reductions.

Governing artifact: owner request to diagnose and reduce CodexBar Jones idle memory and CPU use

Continuity owner: Codex root, Jones Code thread `318adfde-f888-4f6a-be12-2b0035b760ed`

Consumers: CodexBar maintainers and delivery owner

Authority effect: none
<!-- codex-section:end id="worknote.idle-resource-efficiency#ctx.artifact-header.001" -->

## Binding and scope

The owner explicitly confirmed the observed Activity Monitor target is CodexBar Jones,
the menu bar app, during the baseline/regression verification phase.

The canonical repository is `Jones-Systems/CodexBar`, base `main`, initial revision
`219f90407c5f3d8bc48ebe58c7e48fe6953e3586`. Work occurs in dedicated linked worktree
`idle-resources-318adfde`, branch `work/reduce-idle-resources-318adfde`.
The root is the sole Git owner.
Initial open-PR inspection found no open PRs. The starting Codex-V3 worktree is read-only.

Research uses source and bounded process metadata/stack/VM summaries. It does not read
account credentials, transcript contents, usage datasets, or private application logs.
Installed app: `~/Applications/CodexBar Jones.app`, bundle `com.jonessystems.codexbar`,
version `0.56.4 (135)`, source `4eea84c4`. Its app/core source matches the initial revision.
Local installation follows the exact standing authorization in target `AGENTS.md`.

## Observations and limits

At 7:03–7:04 PM EDT on October 20, 2026, PID 65153 had a 131.2 MiB physical footprint
and a recorded lifetime peak of 486.2 MiB. Twelve seconds of `top` samples showed
0–0.5% CPU. A three-second stack sample found sleeping run loops and worker threads.
VM summary reported approximately 56.6 MiB allocated malloc bytes and 59 MiB of
dirty/swapped allocator fragmentation. Shared libraries and reserved virtual addresses
are not additional private physical footprint.

The process had accumulated approximately 43 minutes 49 seconds of CPU time over
four hours. This supports substantial past work but does not establish its source,
whether the UI was idle throughout, or an infinite loop. A bounded 180-second
process-only observation completed without capturing the reported spike.

Source research identified two specific mechanisms to evaluate: Pi/OMP refreshes
rebuild daily aggregates even when every session file is unchanged, and closed
hydrated submenus retain attached hosted views through persistent parent menus.
Neither mechanism is yet proven to account for the reported footprint or CPU spike.
Existing token TTL, catch-up duty-cycle bounds, and WebView eviction are retained.

## Ownership and next step

Two read-only Sol/medium investigators completed independent refresh and memory lanes.
Initial planning was delegated to Opus 5.5/high under inherited `claude_frontier`,
personal temporary preference revision 1. The root retains artifact, scheduling,
test/build, and Git ownership.
The completed plan is `spec.idle-resource-efficiency`; the Opus result narrowed the scanner
change to skipping aggregation while retaining the freshness save, and placed menu release
at complete tracking close to preserve hover/reopen latency.

Initial registration `codexbar-idle-initial-318adfde`, expected revision zero, returned
`registration_unavailable`, `effect: none`, `endpoint_unavailable`. No endpoint repair occurred.
The Work Note bytes supplied to that request preceded this update; no registration is claimed.

The 180-second observation finished: average CPU 0.42%, maximum two-second sample 7.95%,
RSS 25,856–96,416 KiB. No 20% trigger fired, so no incident stack was captured. RSS is
not physical footprint. Another unconditional idle sample has low information value.
The `.test-fixtures-*` path observed during baseline compilation is owned by the existing
root-started isolated test runner and is removed by that runner; this Work Note is root-owned.

The initial planner omitted ordered-root invalidation: identical cached file paths can change
first-wins duplicate precedence when the two configured roots are reversed. Lane A verified
that no prior binding existed. The accepted bounded correction persists only the two ordered
root paths as optional metadata, with a one-time rebuild for older caches. This adds no full
reparse, persistent in-memory cache, or per-file fingerprint collection.

Both builders prepared regression tests while the baseline's already-enumerated test inputs
compiled. Production behavior remains unchanged; lane A added only the TaskLocal rebuild
observer and callback. Root is the only test/build writer. Native baseline compilation is a
shared-state dependency before the failing-before invocation; no duplicate suite is running.

Plan registration `codexbar-idle-plan-318adfde`, expected revision zero, submitted spec digest
`edb639af5b74334a4af97bd9d86cbf8d346908f5486a1e5fe68cc50a40099242` and returned
`registration_unavailable`, `effect: none`, `endpoint_unavailable`. The root-order correction
postdates that digest and will receive a distinct registration request. No receipt proves enrollment.

The revised plan digest `79ac4d7f0b9f166104708d1d2823f7614654b2a7d38ce45394874b2cfa23598a`
was submitted as `codexbar-idle-root-binding-318adfde`, expected revision zero, and returned
the same unavailable endpoint, `effect: none`.

The original focused baseline passed: 30 tests in two suites, with behavior unchanged.
Cold compilation took 677.82 seconds; test execution took 3.669 seconds. The runner verified
removal of its exact scratch root.

The new two-suite failing-before run failed as expected on three unchanged-refresh rebuild
assertions and two retained cost-view/signature assertions. Its status-view fixture also
failed before closing: disabled status checks suppressed the synthetic components. That
fixture was corrected by enabling status checks only in that test; its original failure is
not defect evidence. Native-only row preservation passed before the change. Both builders
then implemented their declared scopes and released their writer cones. Lane A's optional
cache field was explicitly assigned by root; no ownership collision occurred.

The owner's later screenshot shows 136.8 MB, consistent with the measured low footprint.
It does not identify the source of the earlier peak. The fixes remove source-proven work
and menu ownership; actual AppKit deallocation and incident-level resource savings remain
unmeasured. Focused green verification passed: eight tests in two suites in 1.450 seconds;
the runner removed its exact scratch parent and verified absence. SwiftFormat changed
only the final blank line in the new menu test. At the source checkpoint, the mandatory
full `make test` is running. Final verification and delivery receipts belong to the PR.

The initial `make check` invocation could not start its JavaScript checks: the default
Homebrew Node 24.9.0 executable references missing `libsimdjson.27.dylib`. Existing
`/opt/homebrew/opt/node@22/bin/node` reports version 22.23.2; the check will be retried
with that existing runtime selected only through invocation-local PATH. No host repair
or new host tool installation is part of this work.

The canonical repository has disabled GitHub issues. Outstanding diagnosis of the
intermittent CPU episode therefore remains here: no spike was reproduced and no causal
stack was captured. If it recurs, capture bounded process-only CPU deltas and a stack
during the episode before choosing further changes. No issue setting was modified.

One independent Astra/high correctness review (`/root/idle_correctness_review`,
`codex-v3-code-reviewer`) found no supported defects. It verified all five source hashes
before and after inspecting cache/dedup/freshness consumers and the close/rehydration
callers. It ran no tests. Its source review does not establish native AppKit event ordering,
framework deallocation timing, causal resource savings, or delivery readiness.

PR #13's initial lint job reported 13 `multiline_arguments` violations, all in the two
new tests. The repair expands only those argument lists to one argument per line.
Targeted SwiftLint reports zero violations and SwiftFormat reports no changes.
Production source bytes remain identical to the independently reviewed candidate.
The root-owned full test run is still executing its previously compiled candidate;
the repair does not change test semantics. The new CI head will compile the formatted tests.

The first full local test invocation stopped after 65 successful groups at the architecture
gatekeeper group; its retry failed identically. The failure was nine exact-line catalog
entries shifted by additions in the three changed source files. Root verified each old
anchor line against the new source line byte for byte, then changed only those nine line
numbers. Reasons, provider sets, occurrence fingerprints, suppression semantics, and
gatekeeper logic are unchanged. The run took 639.9 seconds, had no timeouts, and removed
its owned fixture root with absence verified. Remaining groups were not executed in that
invocation; a corrected full run is required. Root owns this added test-catalog write scope.

The full `make check` retry using invocation-local Node 22 passed, including portable
script checks, JavaScript/TypeScript checks, SwiftFormat, and strict SwiftLint with zero
violations across 2,162 Swift files. No host runtime was repaired or replaced.

The corrected architecture gatekeeper and both new regression suites passed together:
49 tests in three suites, 5.757 seconds of execution. The runner removed its owned fixture
root and verified absence. Production source remains unchanged from the reviewed candidate.

## Delivered slice and captured follow-up

PR #13 delivered the two original source fixes. The final full local test run passed all
1,042 discovered selections in 87 groups with zero retries, failures, or timeouts (839.1
seconds). All eight applicable CI checks passed on `fa73bf996cc643d21fd6bcfc98066b5990f842e7`
from Actions app 15368, workflow 388934113, run 39517025490. The expected-head merge produced
`203a15e9a6a23a53dc15f2845497cbcfccb8956b`; parents and canonical-main inclusion were verified.
The native PR watch was stopped. The release arm64 Jones bundle passed strict ad-hoc
signature verification and was installed after graceful quit of the exact original app.
The prior bundle is retained for rollback; installation did not change preferences or
account files. The new PID and exact mapped executable path were verified.

The post-launch check captured the reported class of resource burst: 96.26% average
process CPU over 30.02 seconds, later 100.1% at 1 minute 37 seconds after launch. The app
returned to 0% CPU around 3 minutes after launch. This is a post-launch observation, not
an equivalent idle-baseline comparison or a claim that PR #13 caused the burst.

A three-second process-only sample at 10 ms intervals found the main thread sleeping
in every sample and the serial cost-usage queue active in every sample. Matching dSYM
symbolication identified `buildCodexProjectBreakdownsFromCache` through per-project
`buildCodexReportFromCache`, `codexRowCostBreakdown`, `resolvedCodexPricing`, and
`ModelsDevProvider.pricing` / `ModelsDevModelIDNormalizer.candidates`, with regex name
matching on the hot stack. Sample-native physical footprint was 220.9M, recorded peak
286.8M; this is distinct from RSS. No transcript, account/cache data, or private app log
was read to obtain this evidence.

The same owner request and isolated worktree remain active for this concrete CPU path.
Root fast-forwarded the owned task branch to the verified merge commit; source tree
bytes were identical. No worktree was retired or repurposed. Initial open-PR inspection
for the follow-up found none. A read-only Astra/high debugger now owns the bounded
source diagnosis; root retains Git, artifacts, and all build/test state. Further source
changes await that diagnosis and its safe synthetic verification seam.


The independent debugger returned a fix-ready diagnosis: repeated ModelsDev model lookup
is shared neither across reconciliation passes nor across per-file/project reports.
An invocation-owned catalog-lookup memo is the bounded candidate; final monetary costs
must still be calculated per row. The existing Claude resolver provides a local precedent.
Builder phase 1 prepared only synthetic regression tests and a no-op lookup observer;
root started the isolated failing-before run, whose retained log is
`/var/tmp/codexbar-idle-318adfde-pricing-red.log`. No functional memo has been applied.

Because the captured burst materially extends the accepted plan, Claude Frontier's
Opus 5.5/high planning delta is pending as task
`codexbar-idle-pricing-plan-delta-318adfde-v1` in this thread's native task lineage.
The initial explicit target-worktree binding was rejected with “No task was created”
because that worktree is not registered to the supplied project. The corrected launch
is read-only in the parent workspace and reads the exact target path; it grants no
writer scope. Fresh account routing selected Malcolm Claude with unknown allowance
(`fleet_managed_allowance_unsupported`, companion authentication unverified), following
the nonblocking quota fallback. The original planner's accepted result remains in the
specification and completed PR. Functional implementation waits for the planning delta
and the regression run. Host admission was CPU 41.97%, one core 8.33% of 12-core capacity,
warning memory pressure and zero swap traffic; one serial test process remains active.


The native Opus planning task completed with `plan ready, nothing blocking`. Root encoded
its bounded seven-source-file memo design in
`spec.idle-resource-efficiency#req.codex-pricing-memo.001`, including exact UTF-8 positive
and negative caching, 256-entry/256-byte limits, per-build catalog ownership and monetary
invariants. The planner's optional-lookup pseudocode used nil coalescing; root explicitly
corrected it to an if-resolver branch so negative results cannot fall back and repeat
work. No functional implementation is authorized until the active failing-before run
finishes. Its cold compilation remains in progress; no second build/test process starts.

Plan registration request `codexbar-idle-pricing-plan-318adfde-v2`, expected revision 0,
plan SHA-256 `c6cadd168f7b11d3a144093ddb258ec323f30462b211220264e044d0f935e238`, returned
`registration_unavailable`, `effect: none`, `endpoint_unavailable`. No registry repair attempted.

A separate warm measurement of the still-installed PR #13 app (PID 71656) recorded
0.0% CPU from cumulative process time over 30.127 seconds. RSS ranged 42,448–56,384 KiB;
RSS is not physical footprint and no memory-saving claim follows. Raw process-only
observations are retained in the rollback directory's diagnostics/pr13-warm-30s.json.

The failing-before run completed: 616.26 seconds cold compilation, 0.110 seconds of
test execution. Two tests (one parameterized at 40/80 rows per file) produced four
work-count issues only: 485 and 965 scalar lookups instead of two, and 485 for each
changed-catalog build. Exact report equality, monetary and token assertions passed.
The runner drained its children and verified removal of `.test-fixtures-njtjt8yh`.
Phase-1 hashes matched the builder's frozen candidate before execution. Root granted
the accepted functional memo implementation to the existing builder, within the seven
source files and new test file. Fresh admission: CPU 36.80%, 12 cores (8.33% each),
warning pressure and swap 0.061 MiB/s; one agent start, no active test process.

The builder froze the seven-source-file implementation and new test, returning ownership
to root. The per-report pricing context requires a resolver; optional trailing helper
arguments retain existing callers. Root formatted the writer cone and regenerated parser
hash `7a0850a29b8965de`. Eight architecture-catalog line numbers moved; old and new anchor
bytes were verified through an unchanged-line mapping, with every provider set, reference
count, fingerprint, reason and enforcement rule intact. The isolated focused green run
is active in `/var/tmp/codexbar-idle-318adfde-pricing-green.log` (owned command session
31169), rebuilding dependants of the changed internal helper signatures. Production
source is frozen. Targeted SwiftLint found only argument-layout issues in the new test;
root will repair those after the current command drains, then rerun the final test
candidate with the affected suites. No final green result is claimed yet.

The first implementation-focused run passed all seven tests in one suite (0.116 seconds
execution), proving the original 485/965 lookup fixtures now require two lookups with
identical report/monetary/token outputs. Session reuse, missing-catalog isolation, memo
capacity, long keys, exact Unicode bytes, dated/priority/aggregate parity, overlays and
authoritative-cost bypass all passed. The runner verified its owned scratch removal.
Root expanded argument layout in the new test. Targeted lint then identified eight
closure-layout violations; these remain a formatting-only repair before publication.
The final affected-suite run is active; production source remains frozen.

The affected union passed 428 tests in 15 suites (22.472 seconds execution), including
pricing/history/report compatibility and the unchanged architecture gatekeeper. The
runner verified removal of its owned scratch. Root repaired eight new-test closure
layouts with explicit local Sendable observer values; targeted strict SwiftLint now
reports zero violations. This test-only syntactic repair is included in the final
full-suite candidate; production source remains unchanged from the focused/affected runs.
Required `make check` is active with the existing Node 22 runtime selected only for the
invocation. Fresh admission: CPU 9.15%, one core 8.33%, warning pressure, swap 0.124 MiB/s;
one serial check invocation. Full `make test`, focused correctness review, CI and local
installation are required before delivery; their final receipts belong to the native PR
and retained local installation record. No interface appearance changes require screenshots.
