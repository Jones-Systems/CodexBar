# Used-feature test profile measurements

October 24, 2026. This report records the test-selection change in
[PR #38](https://github.com/Jones-Systems/CodexBar/pull/38), qualified at
`515334773b60c8ff278710d96738d6055ed1a2b0` and merged as
`7c7acb59f2c49e7a217ce01455df80fb236ca602`. The earlier
[PR #31–37 results](test-right-sizing.md) remain separate.

Normal testing now covers the owner's Codex/Claude app use and relevant shared
behavior. The measured full profile preserves unused provider, plugin, hook and
iCloud tests as explicit offline manual opt-in. Product sources, dependencies,
resources and test assertions were unchanged in this revision. Later owner-authorized
product slimming and the independent seven-function deletion stack are outside
these measurements; do not subtract their changes from this revision or attribute
runtime savings to them.

## Result and measurement limit

The same-revision full and normal runs both succeeded. Normal selected 3,349
fewer native functions/methods, all mapped to the reviewed full-only groups.
Their observed aggregate runner time was **94.50 → 73.00 minutes**, excluding
queues: **21.50 minutes (22.75%) lower**. This is an observed comparison, **not a
controlled causal estimate**: GitHub assigned different macOS image revisions.
Only one sequential sample per profile was taken; no redundant rerun was made.

| Control | Normal | Full |
| --- | --- | --- |
| Run | [40114138442](https://github.com/Jones-Systems/CodexBar/actions/runs/40114138442) | [40117297355](https://github.com/Jones-Systems/CodexBar/actions/runs/40117297355) |
| Source | `515334773b60c8ff278710d96738d6055ed1a2b0` | same |
| macOS topology | one shard, group size 4 | same |
| Application cache | cold; absence verified | same |
| Toolchain identity | `ba0d494e3bd99ca718c3b866478aecef3929bd982e54bdcc30bc90259845ac4f` | same |
| Runner | macOS 26 / ARM64 | same |
| macOS image revision | `20261021.0445.8` | `20261013.0424.1` |
| Linux configuration | release, application cache off, input timestamp replay off | same |

Ordinary PRs use two macOS shards and Linux debug builds. These one-shard manual
release measurements do not estimate PR median/p90 or directly compare with
ordinary PR runner minutes. No hosted runner multiplier, billing discount or
queue time is included in the aggregate runner-minute totals.

## Source and native coverage

The earlier raw lexical count of 10,777 included five free TestStores helper
functions. The refined full declaration count is 10,772, across 1,054 unique
Swift sources (1,059 paths including five aliases). Lexical declarations do not
expand parameter cases and include platform-conditional declarations.

| Metric at the measured revision | Full | Normal | Difference |
| --- | ---: | ---: | ---: |
| Refined source declarations | 10,772 | 7,379 | 3,393 |
| Unique test-source inventory files, including helpers/mixed files | 1,054 | 752 | 302 |
| macOS native discovery identities | 10,707 | 7,358 | 3,349 |
| Selected suite/top-level-function selections | 1,052 | 697 | 355 |
| Function/method outcomes | 10,665 | 7,316 | 3,349 |
| Passed function/method outcomes | 10,632 | 7,285 | 3,347 |
| Existing skipped function/method outcomes | 33 | 31 | 2 |
| Passed parameterized Swift Testing functions | 452 | 329 | 123 |
| Passed parameter case outcomes | 1,909 | 1,361 | 548 |
| Passed invocations after expanding parameters | 12,089 | 8,317 | 3,772 |
| Each Linux architecture: discovered/executed function summaries | 565 | 341 | 224 |

Full function outcomes comprise 10,551 passed and seven skipped Swift Testing
functions, plus 81 passed and 26 skipped XCTest methods. Normal comprises 7,219
passed and five skipped Swift Testing functions, plus 66 passed and 26 skipped
XCTest methods. Expanded passed invocation counts replace each parameterized
function with its case outcomes: full `10099 + 1909 + 81 = 12089`; normal
`6890 + 1361 + 66 = 8317`. Do not add cases to all function outcomes twice.

Both macOS profiles preserve the existing runner exclusion of 42 discovered
`CLIEntryTests` identities for the pre-existing executable-target SwiftPM hang
exception. The existing conditional test skips above are separate from that
runner exclusion. This pass introduced no failure-hiding skip or retry.

| Disabled normally | Source declarations | macOS native outcomes | Reason |
| --- | ---: | ---: | --- |
| Unused providers | 3,160 | 3,116 | Outside Codex/Claude app use; shared exceptions retained. |
| Hooks | 66 | 66 | Owner does not use hooks. |
| Plugins/engine | 111 | 111 | Owner does not use plugins. |
| iCloud | 56 | 56 | Owner does not use iCloud sync. |
| Total | 3,393 | 3,349 | Preserved in explicit full profile at this revision. |

The [selector manifest](https://github.com/Jones-Systems/CodexBar/blob/515334773b60c8ff278710d96738d6055ed1a2b0/Scripts/test_profiles.json) and
[restoration guide](../testing-profiles.md) carry a reason per group and exact
mixed declarations. Whole-file exclusions remove test sources from SwiftPM's
compile/discovery inputs, rather than only filtering execution. Fifteen mixed
files retain shared tests with 54 inserted conditional guard lines. A normal-only
serialized suite declaration adds eight lines to the shared TTY helper. Removing
these inserted lines reproduces the original test-file bytes; no assertion/body
was rewritten. Five plugin aliases do not add unique source declarations, though
native identities retain their module/location identities.

Both arms passed the existing strict single-arm verifier with complete native
parameter identity and zero issues. All normal discovery/function identities
are a subset of full; retained function IDs, statuses and skip dispositions match,
as do all 1,361 retained native case IDs, statuses and issue records. Every one
of the 3,349 full-only outcomes maps to an approved full-only source or exact
mixed declaration. Source locations resolve the five reviewed plugin aliases.

The raw native payloads differ in one presentation field: dictionary key order
in the argument display for `TailscaleSessionTests`'s CLI-environment fixture.
The seven original opaque case IDs and outcomes for that function are identical.
Raw receipts were preserved. The existing strict same-profile/same-image campaign
comparer was neither changed nor represented as passing across these profiles.
A historical console mask also shortened one unused Devin test name, explaining
an earlier projection of 7,359 normal identities; actual artifacts prove 7,358.

Shared used-provider account switching, persistence, privacy/security/permissions,
quota/reset, cost/spend and shipped-regression coverage remain normal. CLI research
found that remote Agent Sessions invokes the bundled `codexbar` helper; the owner’s
terminal/remote usage question remains unresolved. All dependent CLI coverage and
platform CLI builds were retained. No installed private settings were inspected.

## Time spent: build, discovery, execution and jobs

All values below exclude queue time. Harness phase durations are actual process
boundaries. Aggregate runner minutes sum job start-to-completion durations,
including setup/cleanup and every Linux job in this workflow.

| macOS single-shard metric | Full | Normal | Observed reduction |
| --- | ---: | ---: | ---: |
| Test build | 1,096.6 s | 848.5 s | 248.1 s (22.62%) |
| No-build discovery | 13.9 s | 9.5 s | 4.4 s (31.65%) |
| Test execution | 2,268.4 s | 1,305.3 s | 963.1 s (42.46%) |
| Harness total | 3,379.7 s | 2,163.8 s | 1,215.9 s (35.98%) |
| Mac job / runner minutes | 58.95 min | 38.17 min | 20.78 min (35.26%) |
| All Linux jobs / runner minutes | 35.55 min | 34.83 min | 0.72 min (2.02%) |
| Total runner minutes | 94.50 min | 73.00 min | 21.50 min (22.75%) |

The image-version difference applies to every causal interpretation of the
macOS reductions. Product targets still compile all provider/product code at
this revision; their compilation and dependencies remain after test source selection; these
measurements do not break down time by product target. Test-build time still dominates the six-minute-thirty-second
job budget. The separate compile-once and product-slimming lanes address further
work; their savings are not included here.

| Linux test phase | Full x64 | Normal x64 | Full ARM64 | Normal ARM64 |
| --- | ---: | ---: | ---: | ---: |
| Build | 193.5 s | 156.2 s | 119.1 s | 109.5 s |
| Discovery | 1.5 s | 1.5 s | 1.5 s | 1.5 s |
| Execution | 14.3 s | 13.2 s | 11.1 s | 9.6 s |
| Harness total | 209.3 s | 170.9 s | 131.8 s | 120.6 s |

Full Linux job durations were x64 733 s, ARM64 595 s, musl 667 s, lint 117 s,
changes 14 s and aggregate 7 s. Normal durations were x64 638 s, ARM64 575 s,
musl 720 s, lint 140 s, changes 10 s and aggregate 7 s. Musl compiles product
code only, which this pass did not change; its variation is not test-profile
execution savings. Linux setup/CLI release builds dominate its job totals.

The slowest reported **individual test function** was Claude PTY keepalive
relaunch on account/environment changes: **29.009 s full**, **28.681 s normal**.
These are rounded console durations; display names need not be globally unique.
The longest measured **test-suite step** was full macOS `Swift Test`, **3,405 s**;
its separate JavaScriptCore golden step took 26 s. The longest **CI job** was
full macOS, **3,537 s**; normal's longest job was **2,290 s**. GitHub's Jobs API
left the normal `Swift Test` step marked in progress with no completion timestamp
under a completed successful job. Therefore its exact API step duration is
unavailable; the verified native receipt and 2,163.8 s harness total provide
completion and harness timing without inventing a step timestamp.

## PR timing and remaining budget

The required normal PR run
[40111837084](https://github.com/Jones-Systems/CodexBar/actions/runs/40111837084)
used two macOS shards. Native discovery was 7,358, with 7,316 function/method
summary outcomes before expanding parameter cases. Queue-excluded macOS jobs
summed to 49.63 runner-minutes; all Linux jobs to 11.25, total 60.88. Its longest
job was 1,587 s (26m27s). Run creation to required green was **1,665 s (27m45s)**,
including queues. PR creation to first qualified green was **3,505 s (58m25s)**,
including diagnosis of an earlier formatting failure and SDK-installer crash.
The formatting defect was fixed; the unchanged installer passed on the new head.
No failing test was removed, skipped, retried or weakened.

The prior full PR #36 sample used 62.38 macOS and 13.02 Linux runner-minutes,
75.40 total; its longest job was 2,041 s and run-created-to-green 2,062 s. This
is a **historical unpaired sample**, with different source/cache/configuration;
its difference from the normal PR sample is not a causal saving. Neither this
single PR nor the one-shard comparison establishes new PR median/p90. The previous
broader sample remains in the first-pass report.

The 390-second required-job limit and ten-minute median/twenty-minute p90 goal
remain unmet at this revision: normal test compilation alone took 848.5 s and
ordinary PR shards executed for 661.9/509.9 s. Increasing shard count would
replicate compilation and hosted cost. Required jobs were not reclassified as
advisory to claim compliance. [AGENTS.md](https://github.com/Jones-Systems/CodexBar/blob/515334773b60c8ff278710d96738d6055ed1a2b0/AGENTS.md) declares always-required
`changes`, `lint`, `lint-build-test`, path-selected macOS/Linux jobs, and advisory
packaging/native/manual performance work. Packaging stays opt-in; native workflow
proofs retain the three-to-five critical-journey cap and advisory label/manual
placement. No additional native E2E journeys were added.

## Review, delivery and evidence

One final Astra/xhigh source bulk review identified seven shared TTY regressions
that must remain normal. Both TTY suites were restored; the same reviewer confirmed
an empty remaining restore list and no new findings at `404ef3b77ed2`. The final
`515334773` change only corrected a SwiftFormat documentation comment. Stale
profile claims in the development guide were also corrected. No new test was
added to raise counts. Earlier first-pass PR #35's three ineffective assertions
were repaired separately and are not new gaps added by this second pass.

Local profile contracts (4), campaign/evidence checks (71), isolated command
checks (8), sharding/cleanup checks (95 with 19 platform skips), path gates,
documentation links and shell syntax passed during implementation. `make test`
is unavailable on this Linux host because Swift is absent; `make check` stops
on missing `plutil`. No host tools were installed. Native required PR checks,
both manual profiles, strict receipt verification and the full-only JavaScriptCore
step succeeded on hosted runners. No app installation or release was performed.

The owner-selected new nightly is the normal used-feature profile at **05:00
America/New_York**, DST-aware; unused suites remain explicit manual full opt-in
at this measured revision. The minimal patch is
`0110a56430470106ad7ffed6c96707d3eb5cc636`, coordinated for integration with the
separate compile-once CI work to avoid duplicate macOS qualification. This report
does not claim that an unmerged schedule patch or a first scheduled occurrence
has executed. Its delivery record must identify the integrated PR/commit. The
existing output contract is Actions logs and path-gate/aggregate summaries plus
seven-day synthetic reset-timing artifacts on macOS, including failure uploads
when setup succeeded. Failures remain visible in job/aggregate conclusions;
no issue-automation feature was requested. Manual campaigns additionally upload
native receipts. GitHub may delay/drop scheduled events under service load;
see its [schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

Task-owned compact evidence remains under the measurement worktree's
`.build/used-feature-tests/`, capped at 64 MiB. Reported receipt SHA256 values:

| Receipt | SHA256 |
| --- | --- |
| Normal native arm | `13db2111bbc0318fb9dd3c539747b599ac7bec437a1f8e8a65504c6d076dc875` |
| Full native arm | `88f41643269a30021e59c8aed32989e46ac1990e5af79a219da4e6ce4c7f5409` |
| Source manifest | `c250e960d2f57b13eaba5e2eb51104aae580dc472dc9841c2d6add309d5a7436` |
| Bulk-review confirmation | `1bd43f02bcb2ff01c4691034457e835bac8c92048ae44f0bf61885a17060b82e` |

Remaining work beyond this profile revision: qualify compile-once CI and product
slimming separately, reconcile the nightly integration, retain needed CLI coverage
until usage is established, and remeasure enough representative PRs to assess
median/p90 and the 390-second budget. No further benchmark is implied by this report.
