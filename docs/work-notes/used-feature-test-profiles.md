# Used-feature test profile work note

Owner scope: October 24, 2026 second CodexBar pass, Frontier Max. Native goal
covers research, reversible profiles, qualification, final bulk review, merges
and quantified runner cost. Previous PRs #31–37 remain merged and unchanged.
Base: `fec59ff9e6258140126139f518f44a9cf306ed1b`.

## Research and source partition

Initial Astra/max planning, a complete source inventory, a CLI dependency lane
and a whole-file exception audit informed this pass. Graphify’s older snapshot
was used only for navigation; current source decides membership. No private
settings or installed accounts were inspected. Root owns Git and final fan-in;
the two implementation cones covered mixed test files and CI respectively.
Fresh telemetry admitted each wave/local test; local tests were serial.

The prior raw lexical baseline is 10,777. Five free TestStores helper functions
were false positives; the refined declaration baseline is **10,772** across
1,054 unique Swift sources (1,059 paths including five aliases). Lexical counts
include platform conditions and do not expand parameterized cases.

| Profile/source category | Unique files | Lexical declarations |
| --- | ---: | ---: |
| Whole-file unused-provider behavior | 281 | 3,036 |
| Whole-file unused hooks | 8 | 63 |
| Whole-file unused plugins | 11 | 111 |
| Whole-file unused iCloud | 2 | 38 |
| Mixed declarations guarded full-only | 15 modified files | 145 |
| Normal retained | 752 source files, including mixed files/helpers | 7,379 |
| Full restored | 1,054 | 10,772 |

This disables 3,393 declarations normally, with **zero deletions or rewritten
assertions**. Only 54 conditional guard lines were inserted into 15 existing
test files. The TTY support file also receives a normal-only serialized suite
declaration because its full-profile declaration lives with excluded provider
tests. Removing all added lines exactly reproduces every test file’s base bytes. Five alias paths in the manifest do not add files/cases. Product Sources,
Package.resolved, product targets, dependencies and copied fixtures are unchanged.

Whole-file classification was corrected for ten misleading names/helper owners.
Retain MiniMax LogRedactor, four OpenCodex Codex-attribution suites, and shared
parts of Antigravity publication/reader and OpenCodeGo pace invariants. Retain
Antigravity/Crof/OpenCodeGo helper definitions used by normal tests, guarding only
their unused-provider test declarations. Warp icon and OneConsole behavior are
also full-only. Shared account/menu/concurrency/cache and platform safety suites
stay normal despite representative unused-provider fixtures. Shared refresh
error privacy coverage stays normal. Final bulk review restored both Kiro-named
TTY process/hard-stop suites (seven declarations): they exercise shared process
cleanup used by Codex and Claude, including delayed discovery and pre-kill hooks. The selector and exact mixed identities,
reasons and [restoration guide](../testing-profiles.md) are checked in.

CLI research established no app module dependency, but remote Agent Sessions
invokes the bundled helper’s sessions protocol. Provider `codex`/`claude` tools
are separate. Owner terminal/remote usage remains unresolved; no dependent CLI
coverage or required CLI product builds were excluded. Package/resource,
permission, Keychain, used account/persistence and relevant regressions stay normal.

## Historical timing baseline — unpaired

Prior successful PR #36 run `40081882902`, head
`0bc0720542dabbff3fc58e279321e417882ec51b`, discovered 10,707 macOS identities.
It used the former full scope. Queue-excluded job duration sums:

| Metric | Historical result |
| --- | ---: |
| macOS jobs | 62.38 runner-min |
| Linux jobs, including lint/changes/aggregate | 13.02 runner-min |
| Total | 75.40 runner-min |
| Longest job | 2,041 s |
| Run-created to required green, including queues | 2,062 s |

Shard 0’s old combined build/discovery was 878.1 s and execution 983.5 s.
These are historical unpaired observations, not a compiler-only baseline or a
controlled causal saving. Existing first-pass broader sample medians/p90 and
measurement limits remain in [the original report](test-right-sizing.md).

## Qualification and measurement

The harness now times real test-build, no-build discovery and execution process
boundaries. Linux keeps its parallel aggregate. Native execution summary
receipts distinguish Swift Testing functions from XCTest methods; parameterized
case evidence remains separate. Build failures stop discovery/execution.
Isolation, owned scratch, child drain, strict CI retries and shard policy remain.

Local profile contract checks pass (4); campaign/evidence checks pass (71);
sharding checks, their integrated cleanup suite (95, 19 platform skips), and
isolated CI command checks (8) pass. Documentation links and shell syntax pass.
`make test` is unavailable here because Swift is absent; `make check` stops on
missing `plutil` in app-localization validation. A local tool-download guard
prevented installation; no host tools were installed. Hosted compiler/runtime
qualification is still required before merge.

Plan: qualify the normal PR candidate; use a minimal matched normal/full manual
pair on one exact source with cold Mac caches and identical campaign controls.
Manual Linux arms both use release configuration with application cache off;
PR Linux debug is reported separately. Record native manifests/outcomes, phase
durations, queue-excluded platform totals and longest job. Do not infer minutes
saved from lexical counts or call differing cache/configuration samples controlled.

The Astra/xhigh bulk review found one seven-test shared TTY restoration group
(applied) and stale development-guide profile claims (corrected). No other
supported findings were returned. Hosted outcomes and measurements remain pending. Required/advisory check
policy is unchanged; manual full is an explicit future re-enable route, with no
nightly or schedule-timing edits. No CI budget target is claimed yet.
