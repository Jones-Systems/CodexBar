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

## Current state and evidence

The root owns Git in the dedicated `work/right-size-tests-20261024` worktree.
Initial identity, canonical remote, branch, head and clean source were verified.
Repository identity is `Jones-Systems/CodexBar`, ID `1425008735`; CI workflow
is `388934113`. Legacy upstream is never a publication target.

Local baseline `make test` is unavailable: no Swift executable. Its owned
fixture root was removed and absence verified. `make check` is unavailable:
the app-locales check cannot find macOS `plutil`. Neither result is a pass.
Focused portable checks and current-head hosted qualification remain required.

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

## Remaining work

Qualify CI changes, land separate removal batches, apply the final bulk review,
and report observed after measurements. Build-once test artifacts and larger
groups remain measurement-gated candidates. The 390-second job and 10/20-minute
required-green budgets remain unmet until measured evidence demonstrates them.
