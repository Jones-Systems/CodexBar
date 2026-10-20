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
