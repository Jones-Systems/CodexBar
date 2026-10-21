# Engineering Spec — Idle Resource Efficiency

<!-- codex-section:begin id="spec.idle-resource-efficiency#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.idle-resource-efficiency`

Purpose: Remove redundant history calculations and closed-menu view retention without changing usage semantics.

Governing artifact: `worknote.idle-resource-efficiency`

Specification owner: M Jones

Integration owner: Codex root

Consumers: scanner and menu builders, verifier, delivery owner

Authority effect: none
<!-- codex-section:end id="spec.idle-resource-efficiency#ctx.artifact-header.001" -->

## Scope and evidence

Source inspection at `219f90407c5f3d8bc48ebe58c7e48fe6953e3586` confirms two unnecessary
costs. `PiSessionCostScanner` rebuilds all daily aggregates on unchanged-file refreshes.
Hydrated hosted submenu views remain attached to persistent menus after tracking ends.
Neither is established as the cause of the reported resource episode. Native process
measurements and their limits remain in the Work Note; no quantitative savings are promised.

<!-- codex-section:begin id="spec.idle-resource-efficiency#req.behavior.001" -->
## Requirements and design

1. Let each Pi file scan report whether its aggregate input changed. Rebuild only after
   an append, parse, removal, or invalidation changes those inputs. Every file is still
   checked; boolean short-circuiting must never skip scanning a file.
2. Persist the ordered session root paths as optional cache metadata; a missing or changed
   binding requires an aggregate rebuild. Root order controls first-wins duplicate selection
   even when every file path and modification time is unchanged. Older caches require one
   rebuild without a forced reparse; older readers may ignore the additive field safely.
   Continue persisting scan time, window, pricing key, and full cache on each refresh.
   The existing report freshness, debounce, pricing, range filtering, ordered cross-file
   deduplication, cancellation, and artifact version remain authoritative. Add no in-memory cache.
   Future aggregation/dedup semantic changes must invalidate persisted aggregates through
   the existing artifact or formula version.
3. When the complete menu tracking session ends, restore hydrated closed hosted submenus
   to their existing provider-scoped placeholders and release their render signatures.
   Preserve menu object, width, delegate, and native link-only content. Keep the hosted
   views during submenu hover/reopen while a parent menu remains open.
4. Reopening must hydrate current content normally. Releasing status view state at full
   close follows existing parent-rebuild behavior. Do not change account selection,
   preferences, provider refresh intervals, historical data, or WebView lifecycle.
<!-- codex-section:end id="spec.idle-resource-efficiency#req.behavior.001" -->

<!-- codex-section:begin id="spec.idle-resource-efficiency#ac.verification.001" -->
## Acceptance and verification

- Synthetic Pi fixtures prove zero aggregate rebuilds/parses on unchanged refresh, identical
  reports/daily totals, advancing persisted scan freshness, and correct append/deletion,
  duplicate entry/session, root-order changes, legacy missing binding, force, pricing,
  timezone, and window invalidations.
- Menu lifecycle fixtures prove retention during hover browsing, release and signature
  clearing after full close, preserved provider identity, rehydration on reopen, and
  native link preservation. Use AppKit only for the wiring being verified.
- Obtain failing-before evidence through safe synthetic seams where practical; record
  any unavailable evidence. Preserve the test harness's credential/session isolation and
  invocation-owned scratch cleanup.
- Run focused scanner/menu suites, the deduplicated affected suites, `make test`, and
  `make check`. One root owns all build/test state and takes fresh host admission.
- Deliver one non-draft PR with the current applicable repository checks; follow target
  `AGENTS.md` for merge and local app update with exact identity and rollback readback.
<!-- codex-section:end id="spec.idle-resource-efficiency#ac.verification.001" -->

## Implementation ownership and sequencing

Independent lane A owns only `Sources/CodexBarCore/PiSessionCostScanner.swift`, the optional
root binding in `Sources/CodexBarCore/PiSessionCostCache.swift`, and new
`Tests/CodexBarTests/PiSessionCostScannerRebuildTests.swift`. Lane B owns only
`Sources/CodexBar/StatusItemController+HostedSubmenus.swift`, the full-close hook in
`StatusItemController+Menu.swift`, helper visibility in `StatusItemController+MenuTracking.swift`,
and new `Tests/CodexBarTests/StatusMenuHostedSubmenuReleaseTests.swift`.
Root owns artifacts, generated/shared files, test/build/lint state, integration, and Git.
Builders first prepare regression tests, then implement after root's proving run.

## Impact and recovery

The scanner boundary remains synchronous and invocation-owned; the changed private return
value is consumed only by its caller. The menu boundary remains main-actor AppKit delegation.
Direct consumer searches identified report freshness and ordered dedup as scanner constraints,
and attached menu preparation, hover latency, and status state as lifecycle constraints.
The cache gains only optional ordered-root metadata, with backward-compatible missing-field
decoding and a one-time aggregate rebuild. No public API, new background service,
protected host operation, or destructive migration is added.
The relevant hidden-impact screen is therefore bounded to these existing state lifetimes and
their tests. Stop on changed ownership, failing monetary equivalence, lost provider identity,
live credential access, unknown installation effects, or lost rollback. Revert source normally;
retain the exact previous app bundle when performing the authorized local update.


<!-- codex-section:begin id="spec.idle-resource-efficiency#req.codex-pricing-memo.001" -->
## Captured Codex pricing work

A post-install process sample found the cost-usage worker repeatedly resolving model
names through ModelsDev while the main thread slept. This adds a concrete CPU path to
the original source-proven improvements. The Opus 5.5/high planning delta accepts a
synchronous invocation-owned `CostUsagePricing.CodexResolver`, following the existing
Claude resolver precedent. Root corrects one pseudocode ambiguity: a resolver's nil
lookup is authoritative and must never fall through a nil-coalescing static lookup.

The resolver owns a non-optional immutable catalog snapshot and caches only catalog
lookup results, including misses, by exact raw UTF-8 bytes. At most 256 entries with
keys of at most 256 bytes are retained; new keys at capacity and longer keys bypass
storage. No global, durable, actor-shared, or cross-await state is added. One project
build shares the resolver across every per-file and per-project report; one session
build shares its own resolver. Other standalone reports create their own context.
An optional trailing internal resolver argument propagates through pricing, overlay,
row pricing, report context, incomplete evidence and reconciliation helpers. When
present it is the sole catalog lookup source. Existing no-resolver callers remain valid.

Custom overlays still precede historical pricing, which precedes catalog lookup. Dates,
cutovers, nil dates, provider routing, priority model/input limits and fallback, long-
context aggregate rejection, authoritative nanos, summation and reconciliation order
remain unchanged. Final costs are recalculated per row. No refresh interval, preference,
public API, account selection or transcript parsing semantics changes.

Builder owns seven files under `Sources/CodexBarCore/Vendored/CostUsage/`:
`CostUsagePricing.swift`, `CostUsagePricing+Overlay.swift`,
`CostUsageScanner+PricingRows.swift`, `CostUsageScanner+CacheHelpers.swift`,
`CostUsageScanner+ForkCoverage.swift`, `CostUsageScanner+ReportReconciliation.swift`,
and `CostUsageScanner+Projects.swift`, plus new
`Tests/CodexBarTests/CostUsageScannerCodexPricingMemoTests.swift`.
Root owns Git, artifacts, all build/test/format state, the generated parser hash and
necessary line-only architecture-catalog anchor maintenance. Existing root catalog
snapshot boundaries are preserved; this internal per-build object has no independent
consumer, asynchronous lifecycle or externally consumed compatibility contract.

Synthetic tests must prove work scales with distinct models (two lookups across three
files and two projects, at both 40 and 80 rows/file), exact cached/uncached report and
session equivalence, changed-catalog isolation, positive and negative memoization,
capacity/long-key/exact-byte bounds, overlay precedence, dated historical/priority and
long-context costs, and authoritative-cost bypass. Preserve existing test isolation and
fixture cleanup. Count real scalar lookups at the existing no-op TaskLocal observer.
The test-only memo-disable flag is captured once at resolver creation.

Run the new suite and affected pricing, custom overlay, breakdown, Codex priority cursor,
fork split/evidence, subagent accounting, store read/view/work, fetcher, performance gate,
and Pi compatibility suites, then required `make check` and full `make test`. Regenerate
`Sources/CodexBarCore/Generated/CodexParserHash.generated.swift` through the existing script;
all changed vendored files remain hash inputs. A one-time derived Codex/Pi cache rebuild
on adoption is expected and must be separated from steady-state observations.

Deliver the focused follow-up through another ordinary PR, current CI, standing merge
policy and exact local Jones app update. Retain the original backup and the PR #13
bundle separately. First-launch resource observations include hash rebuilding; measure
a later equivalent 30-second period separately before making improvement claims. A warm
snapshot alone cannot establish elimination of every intermittent burst or a specific
memory saving. Source rollback uses an ordinary revert; local rollback retains the
exact prior app. Stop on changed monetary results, catalog leakage, unexpected paths,
private-data access, unknown installation effects or lost rollback.
<!-- codex-section:end id="spec.idle-resource-efficiency#req.codex-pricing-memo.001" -->
