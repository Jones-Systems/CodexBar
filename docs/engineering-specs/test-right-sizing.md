# Engineering Spec — Test right-sizing and CI efficiency

<!-- codex-section:begin id="spec.codexbar-test-right-sizing#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.codexbar-test-right-sizing`

Purpose: Reduce avoidable CI cost while preserving meaningful CodexBar regression coverage.

Governing artifact: `none`

Decision owner: CodexBar maintainers

Consumers: CI maintainers and test right-sizing implementers

Authority effect: none
<!-- codex-section:end id="spec.codexbar-test-right-sizing#ctx.artifact-header.001" -->

## Project summary

Ordinary changes should run portable checks and the platform compiler/unit tests
selected by conservative changed-path evidence. Packaging and native workflows
belong on explicit labels or manual runs. Retained tests must catch meaningful
owned behavior; test count is not a success target.

## Research and decision basis

The initial Astra/max plan uses source revision
`06e1adf0ae16b9b3801405415535267ea79a96b2`, current Actions job/step timestamps,
and Codex V3's test-value, CI-budget, and native-tier rules at
`86230e4b70b4ec914606f349f015335bee153c4d`.
The accompanying [work note](../work-notes/test-right-sizing.md) holds measurements.
Graphify's older snapshot helps navigation only; current files decide behavior.

At baseline, macOS shards independently built the full graph before partitioning.
Linux jobs compiled release CLI and debug tests. Both platform lint jobs repeated
JavaScript checks. The plugin A/B step repeated default-engine golden tests
already discovered by the suite. CI optimization is separate from decisions
to remove tests.

Keep two macOS shards initially. A build-once artifact or larger process groups
needs measured build/transfer cost and identical discovery/outcome evidence
before adoption. Existing discovery and execution costs each exceed the
390-second job budget. Record that exception while reducing proven waste.

## Exact change surface and ownership

The coordinator owns Git, policy, the spec/work note, fan-in, and delivery.
One builder owns CI workflows, path/aggregate gates and their fixtures; audit
lanes inspect disjoint test file sets and return reports. Removal writers are
sequenced after their decisions are reconciled. No concurrent overlapping source
writers or independent Git owners share the worktree.

The impact universe is repository CI workflows, their referenced scripts,
`Package.swift` target selection, test files and agent/development instructions
at the source revision above. Current reference searches and script reads cover
these direct consumers; hosted timing remains an execution question. PR #26's
signing/bootstrap helpers, tests and branch are outside the edit scope.

## Interface contracts

- Path gates consume Git name-status rows, including deletions and both rename
  endpoints. Unknown paths and missing coverage evidence select conservatively;
  malformed rows fail. Explicit portable-only changes can skip compilation.
- The aggregate accepts success for selected jobs and skips only when the
  corresponding gate explicitly allows them. Missing/failed/cancelled results
  fail. Supported macOS and Linux architectures remain covered.
- Ordinary glibc PRs reuse debug CLI compilation for tests and smoke checks.
  Musl PRs retain their distinct compiler/static SDK/SQLite linkage check in
  debug configuration; main/manual musl builds retain release configuration.
  Both musl configurations verify static linkage. Release-only source branches
  and optimizer/link behavior move to main/manual qualification.
- App candidate provenance currently accepts push, PR and manual dispatch.
  Label/manual placement avoids introducing unsupported scheduled provenance.
  Packaging never counts as unit or visible native UI proof.
- Existing Keychain/file isolation, deadlines, process ownership and cleanup
  remain mandatory. Changes do not authorize live provider access.

## Tasks and dependencies

1. Baseline counts and CI, then accept the initial plan.
2. Publish/qualify/merge CI placement and gate changes, with explicit required
   and advisory policy. No test removals share this PR.
3. Complete the grouped whole-suite audit; inspect each removal candidate's
   assertions and name remaining behavior coverage. Preserve uncertain cases.
4. Land small removal-only PRs by area, with category/reason/coverage tables.
5. Review the batch once, using Astra/xhigh for sensitive removals; apply its
   restore list and real coverage gaps in separate follow-up changes.
6. Report counts, removals, restores, timings, and remaining budget exceptions.

Independent read-only audit groups may overlap CI implementation. Publication
is batched to avoid redundant macOS runs. Every local test/agent start requires
fresh telemetry; the coordinator owns the serial local test slot.

## Test plan

Exercise path decisions, malformed/empty inputs, renamed/deleted paths, each
aggregate success/failure/skip combination, and workflow wiring. Run normal
`make test` and `make check`, reporting missing tools/platforms as unavailable.
Use focused portable checks locally and current-head GitHub CI for Swift.
Removal batches preserve assertions in all retained tests. Named retained
coverage is required; obvious dead/trivial cases need no artificial seeded bug.

Measure run-created-to-required-green including queue separately from actual
push-to-green when the exact push timestamp is unavailable. Report sample size
and outcome selection, job runner-minutes, platform minutes and exceptions.
Never equate a skipped workflow, a model estimate, or an advisory success with
the required execution result.

## Stop, recovery, and delivery boundaries

Use only `Jones-Systems/CodexBar`, non-main task branches, normal pushes and
head-guarded merge commits. Verify exact head checks/review state, merged
parents and canonical-main inclusion. Preserve branches and worktrees.
No ruleset, credential, signing, release, installation, sudo or other-thread
operation is needed for this source/test/CI work. An unexpected prior effect,
scope collision or native denial stops only its dependent edge.
Source rollback is an ordinary revert of the relevant separate commit/PR.

## Delivery result and measured exception

CI placement and check declarations landed in PR #31; three separate removal-only
PRs (#32–#34) removed 23 Swift declarations and three already-shadowed Python
definitions. One Astra/xhigh bulk review accepted all 17 groups with an empty
restore list. The three pre-existing coverage gaps were repaired separately in
PR #35. PR #36 qualified required debug musl on PRs and release musl on main,
with static linkage verified in both configurations on identical production source.
The [work note](../work-notes/test-right-sizing.md) records exact counts,
retained coverage, run IDs and before/after measurement limits.

The macOS shards still exceed 390 seconds in both discovery/build and execution.
The 10/20-minute PR-green targets remain unmet. The work note owns the concrete
follow-up because repository issues are disabled. Shared-build artifacts and
larger groups require measured manifest/outcome equivalence before adoption.
No unit/compiler coverage was demoted to advisory to claim a target.
