# Work Note — Test right-sizing and CI efficiency

<!-- codex-section:begin id="worknote.codexbar-test-right-sizing#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.codexbar-test-right-sizing`

Purpose: Carry baseline, audit decisions, delivery evidence and remaining CI budget gaps.

Governing artifact: `spec.codexbar-test-right-sizing`

Continuity owner: CodexBar test right-sizing coordinator

Consumers: CodexBar maintainers and this workstream's reviewers

Authority effect: none
<!-- codex-section:end id="worknote.codexbar-test-right-sizing#ctx.artifact-header.001" -->

## Scope and decisions

M Jones authorized this repository's whole-suite pass and CI efficiency work on
October 24, 2026. All CodexBar tests are owned for this pass. The native goal
covers source completion, separate removal PRs, CI repair/merge, one final bulk
review and restores, check declarations and the before/after report.

The accepted [engineering spec](../engineering-specs/test-right-sizing.md) records
the initial Astra/max plan. Frontier Max is an explicit workstream pin; the root
stays Sol/high. The installed preference CLI's revision 8 reports the inherited
High Intelligence default and rejects `frontier_max`; source guidance and the
explicit owner selection govern routing without changing the shared store.

Research uses current workflow/script/test source and GitHub Actions data.
Three disjoint audit groups cover A–C, D–O plus portable/plugin targets, and
P–Z plus script/embedded tests. Each screens every assigned file, then inspects
candidate bodies and retained coverage. Grouped keeps are allowed; the pass
does not claim an independent deep review of every assertion.

Open PR #26 owns signing/bootstrap changes. Its helpers/tests/branch are
preserved. Candidate placement uses labels/manual dispatch because direct
schedule support would alter its overlapping provenance helper.

## Baseline

Source: `06e1adf0ae16b9b3801405415535267ea79a96b2` on canonical `main`.

| Source tree | Swift files | `@Test` declarations | XCTest-style methods |
| --- | ---: | ---: | ---: |
| Tests | 987 | 10,227 | 157 |
| TestsLinux | 63 | 404 | 0 |
| TestsPlugin | 9 | 87 | 0 |

These are source scans, not discovered/executed case counts. Parameterized
arguments expand at runtime; platform guards can exclude cases. Portable/plugin
symlinks reuse native source and must not be summed as unique owned tests.
The 34 script test files contain 459 Python test-method definitions; shadowed
definitions are not independently discovered tests. Inline shell/Node checks
are audited separately.

Ten most recent successful PR runs from the 100-run CI query give:

| Measure | Baseline |
| --- | ---: |
| Run-created to final required check, median | 113.05 min |
| Run-created to final required check, p90 (nearest rank) | 195.68 min |
| Sum of job runner time per run, median | 109.78 min |
| macOS shard jobs, observed sample range | 27.45–58.03 min |

This successful-run sample excludes failed/cancelled attempts and is not a
population-wide service level. Run creation is an available queue-inclusive
proxy; exact push timestamps were not established. Advisory candidate workflows
are excluded from required-green and runner totals above.
Representative CI run [39984013345](https://github.com/Jones-Systems/CodexBar/actions/runs/39984013345)
has macOS test steps of 2,170/2,132 seconds; Linux ARM release compilation takes
418 seconds plus 137 seconds for debug build/tests, and x64 takes 262 plus 87.
The previous [runtime investigation](test-runtime-optimization.md) records
build/discovery alone at 1,413/1,893 seconds and group execution at 879/1,061.
Thus 390 seconds is not currently achieved by either phase; adding shards
without build and launch-cost evidence would multiply scarce-runner demand.

Raw baseline queries/logs and audit reports are task-owned ignored evidence in
`.build/right-sizing/`, bounded to 10 MiB and retained through final reporting.
No shared temporary directory is used. The coordinator owns its disposition;
GitHub logs/artifacts retain their existing repository/workflow lifetimes.

## Verification and delivery evidence

The root owns Git in the dedicated `work/right-size-tests-20261024` worktree.
Initial identity, canonical remote, branch, head and clean source were verified.
Repository identity is `Jones-Systems/CodexBar`, ID `1425008735`; CI workflow
is `388934113`. Legacy upstream is never a publication target.

Local baseline `make test` is unavailable: no Swift executable. Its owned
fixture root was removed and absence verified. `make check` is unavailable:
the app-locales check cannot find macOS `plutil`. Neither result is a pass.
Focused portable checks passed; applicable current-head hosted checks qualified each merged PR. Local tool absence is not a pass.

The CI placement change passes the platform/aggregate gate regression group,
all 70 campaign/evidence tests, and all eight isolated-command tests. Workflow
YAML parses, touched shell scripts pass `bash -n`, and the documentation-link
check passes. The plugin fixture caught and corrected an argument-boundary
error before publication. The synthetic macOS CPU-limit fixture now injects
storage evidence rather than reading this host's 15 GiB `/tmp`; its existing
CPU-limit assertions and separate storage-admission tests remain intact.
Final local `make test`/`make check` still report the missing tools above.

Native scope is resource relocation, warmed provider/profile menu, workspace
menu/window lifecycle, and isolated signed updater flow: four grouped journeys,
with all negative controls retained. External-driver fixture hosts stay opt-in;
resource-only packaging does not establish ordinary app or UI success.

Thread registration is `registration_unavailable`: the expected local Voice
registry endpoint is absent. No enrollment or permission repair was attempted.

Contributors:

- Right-size tests — CodexBar,
  `mcp-launch:v1:328783246af20d902cfb28f61186a055140894b4f177446089f4e44581fb9d10`:
  Sol/high coordinator, baseline, policy, artifacts, verification and delivery.
- `/root/initial_plan` (native ID unavailable): Astra/max initial plan.
- `/root/audit_a_c`, `/root/audit_d_o`, `/root/audit_p_z_scripts`
  (native IDs unavailable): Astra/high bounded test-value audits.
- `/root/ci_implementation` (native ID unavailable): Astra/high CI implementation.
- `/root/musl_placement_question` (native ID unavailable): Astra/high coverage-placement assessment.
- `/root/bulk_removal_review` (native ID unavailable): Astra/xhigh final bulk review.

## Musl configuration trial

Astra/high confirmed that musl must retain its required compiler/static SDK/
SQLite linking signal: glibc's static Swift standard library is not a substitute.
A bounded follow-up recommends trialling debug musl on PRs while keeping release
musl on main/manual runs. This deliberately moves release-only source branches
and optimizer/link behavior; it does not establish debug/release equivalence.
The same pinned compiler, SDK, target triple and SQLite preparation remain.
Both configurations reject dynamic-loader and dynamic-library dependencies.

The isolated trial worktree is `work/right-size-musl-pr-build-20261024`;
`/root` remains its sole Git owner. Six synthetic command cases prove debug/
release arguments, static-link success, dynamic-loader/library rejection and
build/readelf failure propagation, with exact fixture cleanup. YAML parses and
whitespace checks pass. Local `make test`/`make check` remain unavailable due to
missing Swift/macOS `plutil`. Hosted qualification is recorded below. No performance saving is inferred
from synthetic checks.

## Test-value results and coverage

The full pass screened all 1,059 Swift source entries, representing 1,054 unique
files after resolving five symlinks, and the script/inline/manual/skill checks.
Candidate bodies and retained behavior/source received focused reads. This was
not a line-by-line review of every assertion. The three task-owned audit records
contain per-file or grouped one-line keep/remove/move reasons.

| Count | Before | After removals |
| --- | ---: | ---: |
| Unique-source static Swift declarations | 10,800 | 10,777 |
| Hosted native discovered identities | 10,729 | 10,707 |
| Effective methods in `BuildJobsTests` | 46 | 46 |

The static scan is lexical and resolves source symlinks; it is not a count of
expanded runtime cases. The 23 removed Swift declarations include one excluded
non-macOS placeholder, hence 22 fewer native identities. The native baseline is
PR #31, before removals; PRs #34 and #36 both discover 10,707 identities,
with zero failed groups.
Three removed Python definitions were already overwritten by later same-name
methods; all 46 effective method ASTs were unchanged. The CI seam separately
adds two isolated command checks, and ten existing synthetic skill checks now
participate in portable lint. These are distinct from the removal counts.

| Removal category | Count | Examples |
| --- | ---: | --- |
| Exact or weaker overlap | 13 | Dashboard cache, stale refresh error, parser assertions, provider registry, Warp resolver, copy dispatch |
| Trivial compiler/library/test-local behavior | 7 | Gemini local calculations, synthesized Kilo equality, terminal enum synthesis, JSONEncoder wrapper, always-true placeholder |
| Over-granular checks | 2 | Future-age duplicate, 1,000 repeated cached lookups with no timing bound |
| Superseded constructor smoke | 1 | Recorder constructed by three stronger behavior tests |
| Obsolete shadowed Python definitions | 3 definitions, zero effective tests | Three overwritten build-admission methods |

Reasons and named retained coverage are in the separate removal-only PRs:
[#32](https://github.com/Jones-Systems/CodexBar/pull/32) (11 provider/parser declarations),
[#33](https://github.com/Jones-Systems/CodexBar/pull/33) (eight UI/policy declarations),
and [#34](https://github.com/Jones-Systems/CodexBar/pull/34) (four Swift declarations
and three shadowed Python definitions). Retained test bodies and production
code were unchanged by those PRs. No failing test was deleted, skipped or
weakened to obtain green.

Keep decisions preserve provider-specific units/aliases/error shapes, credential
precedence and siloing, cache invalidation/concurrency, process cancellation and
cleanup, migration/defaults isolation, finite numeric/cost parsing, persisted
wire values, shipped menu/scheduler bugs, bundled resources, Linux boundaries,
and scanner positive/negative controls. Performance and real-timer cases without
measured redundant signal remain.

One final Astra/xhigh bulk review accepted all 17 groups at combined revision
`89fec66a9fa58ea893360da42dc931c0e3cb5c84`. **Restore list: empty.** No additional
gap was supported. The [archived review](test-right-sizing-bulk-review.md)
records exact inputs and per-group retained evidence. Its original artifact
SHA-256 is `4d57962d3ee6df0eed8819d83c431dc5a6fc1556edca4df4bb96033ab5cf598a`.

The three pre-existing gaps were repaired separately in merged
[#35](https://github.com/Jones-Systems/CodexBar/pull/35): the timeout marker oracle
runs inside fixture lifetime; the active hosted-runner method asserts disk
admission was bypassed; the ten existing synthetic skill checks run in portable
lint. A contained negative control showed the old timeout oracle missed a
written marker while the corrected oracle detects it. Ten synthetic skill tests
and the focused hosted-runner case passed locally. No live provider/Keychain
probe or native app session was used.

## Observed CI after changes

[#31](https://github.com/Jones-Systems/CodexBar/pull/31) adds conservative PR and
push path gates, enforces selected-job results in the aggregate, cancels
superseded runs, and makes packaging opt-in by label/manual dispatch. Native
proof is four grouped critical journeys, advisory and opt-in. No ordinary
packaging job executed in the measured PRs; the candidate was skipped where its
workflow triggered. A direct nightly candidate route
remains outside this change because its provenance helper overlaps PR #26.

Repeated default-engine plugin goldens and duplicate JavaScript lint work were
removed from platform steps. Ordinary glibc PRs share debug compilation between
CLI, portable tests and smoke checks; main/manual runs retain release/static
standard-library builds. macOS retains two full shards. Their duplicated full
build/discovery is a recorded remaining cost, not a claimed solved item.
Required and advisory checks are declared in [AGENTS.md](https://github.com/Jones-Systems/CodexBar/blob/main/AGENTS.md#required-and-advisory-ci-checks) and
[the development guide](../DEVELOPMENT.md#ci-aggregate-contract).
No GitHub ruleset or branch protection was changed.

| Successful PR run | Required-green proxy (min) | Runner minutes | macOS shard minutes |
| --- | ---: | ---: | --- |
| [#31 / 40066991296](https://github.com/Jones-Systems/CodexBar/actions/runs/40066991296) | 39.35 | 92.77 | 38.82 / 33.03 |
| [#32 / 40069794039](https://github.com/Jones-Systems/CodexBar/actions/runs/40069794039) | 47.35 | 73.47 | 35.90 / 35.28 |
| [#33 / 40073011928](https://github.com/Jones-Systems/CodexBar/actions/runs/40073011928) | 42.97 | 87.00 | 35.35 / 42.55 |
| [#34 / 40075983000](https://github.com/Jones-Systems/CodexBar/actions/runs/40075983000) | 40.95 | 92.98 | 40.53 / 34.75 |
| [#35 / 40078859261](https://github.com/Jones-Systems/CodexBar/actions/runs/40078859261) | 41.65 | 97.02 | 41.27 / 36.72 |
| [#36 / 40081882902](https://github.com/Jones-Systems/CodexBar/actions/runs/40081882902) | 34.37 | 75.40 | 34.02 / 28.37 |

For these six successful workstream PRs, median runner time is 89.88 minutes;
run-created-to-required-green median is 41.30 minutes and nearest-rank p90 is
47.35 minutes. The baseline successful-PR sample (n=10) was 109.78 runner-minutes,
113.05 minutes median and 195.68 minutes p90 to green. This is a purposeful,
unpaired sample with different selected platforms, cache conditions and queues;
it does not establish a causal improvement or a population service level.
Run creation is the queue-inclusive proxy, not an exact push timestamp. Advisory
packaging is excluded from these required-workflow totals. A new two-week macOS
billable-hours figure is not yet available.

The measured exception is substantial: in PR #34, shard 0 spent 1,082.4 seconds
in discovery/build and 1,154.5 seconds in execution (2,236.9 seconds total), with
10,707 discovered identities and zero first-pass failed groups. PR #31's two
shards independently spent 894.7/1,064.1 seconds in discovery and 986.4/1,077.9
seconds in execution. Either phase already exceeds 390 seconds. PR #32's macOS
start delays were 594/680 seconds, illustrating shared-runner queue effects.
Deleting 22 runtime identities does not solve compiler or repeated process
startup cost. The 390-second required-job budget and 10/20-minute green targets
remain unmet; compiler/unit coverage remains required.

## Musl hosted qualification

Merged [#36](https://github.com/Jones-Systems/CodexBar/pull/36) retains the
required static-SDK/SQLite compatibility signal on PRs in debug configuration;
main/manual runs retain release. The PR's
[debug job](https://github.com/Jones-Systems/CodexBar/actions/runs/40081882902/job/120836991820)
passed with explicit static-link verification in 291 seconds (4m51s): 199 seconds
for compilation/linkage verification and about 92 seconds for setup/SQLite and
other steps. This required job is within 390 seconds. Earlier release PR jobs
were 540–697 seconds, but different configurations and runner conditions make
that an observed placement result, not an equivalent-work speedup.

Production `Sources`, `Package.swift` and `Package.resolved` identities are
identical between PR debug head `0bc0720542dabbff3fc58e279321e417882ec51b` and
main merge `7478fbde01d9b6962f2df291f8a65e3ede385971`. The resulting
[main run](https://github.com/Jones-Systems/CodexBar/actions/runs/40084329210)
passed the [release job](https://github.com/Jones-Systems/CodexBar/actions/runs/40084329210/job/120844077134)
with explicit static-link verification in 532 seconds (8m52s), including 440
seconds for compilation/linkage verification and about 92 seconds for setup and
other steps. Debug and release both qualify on the same production source.
Release-only branches and optimizer/link behavior remain exercised on main/manual
runs. The whole main workflow was still running when this job was qualified;
this records release-job success, not a claim that all main jobs had finished.

## Follow-up record: required CI budget

Status: open, measured exception. Continuity owner: CodexBar maintainers.
Repository issues are disabled; the read-only issue-list request returned that
state, so this checked-in record is the tracker. No repository setting was changed.

Resume with the completed run IDs above and a bounded performance campaign,
without launching an org-wide matrix. First distinguish rebuild/discovery from
SwiftPM process startup, group execution, cache reuse and runner queue time.
Evaluate a single-build artifact shared by shards, then larger process groups
against identical discovery manifests and outcome evidence. Record transfer and
setup cost, memory, isolation, timeout/cleanup and first-pass failures before
changing placement or concurrency. Preserve all supported compiler/platform and
provider-isolation contracts; do not reclassify unit/compiler coverage advisory.

Acceptance: every required job/shard at most 390 seconds, queue-inclusive
PR-to-required-green median at most ten minutes and p90 at most twenty minutes,
with sample size, selection, cache conditions and exact timestamp semantics
stated. Include a representative docs-only/path-gated run and native/core change
runs. If the shared hosted queue alone exceeds the target, record its measured
contribution separately from compute. Native nightly provenance, historical flaky
case ranking and a fresh two-week cost comparison remain later measurement work.
No further removal is justified without unique-signal and cost evidence.

## Completion and evidence custody

PRs #31–#36 were merged using merge commits with the exact qualified head guard.
Each readback verified the expected second parent and inclusion in canonical
`origin/main`; no branch was deleted. Required-check identity remained GitHub
Actions app `15368`, CI workflow `388934113`, repository ID `1425008735`.
The final documentation PR carries this report and the archived review only.

All audit/review children have returned; the coordinator is the sole Git owner
of the task worktrees. The three audit reports and bounded baseline/after JSON
remain task-owned ignored evidence in the original `.build/right-sizing/`,
about 1.3 MiB, for preservation until owner-directed cleanup. No shared temporary
artifact or background observer remains. Worktrees and branches are preserved;
readiness marking is metadata only and grants no deletion authority. No
production app source changed, so no installed app replacement is needed.
