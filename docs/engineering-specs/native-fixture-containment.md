# Native fixture containment

<!-- codex-section:begin id="spec.native-fixture-containment#ctx.artifact-header.001" -->
Artifact Type: Engineering Spec
Artifact ID: spec.native-fixture-containment
Purpose: Make native verification fixtures remain inside one invocation-owned workspace parent.
Governing artifact: Existing CodexBar account recovery and trial identity work notes.
Specification owner: CodexBar Account Sync Verification coordinator/root.
Integration owner: coordinator/root, sole Git owner.
Consumers: Native test runner, repository test targets, verification operator.
Authority effect: none
<!-- codex-section:end id="spec.native-fixture-containment#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.native-fixture-containment#req.parent.001" -->
## Required behavior

Use a package-scoped resolver with an explicit existing canonical workspace-descendant parent. Reject a missing, invalid or escaping parent before allocating isolated fixtures. Preserve explicit fixture overrides and ordinary runtime paths. Under Codex test isolation, resolve the validated parent before TMPDIR; retain only an existing canonical override at or below that parent, otherwise use the parent. Isolated fixture allocation must not call Foundation's default temporary-directory resolver. Preserve unique child names, synthetic data, assertions, and test identities across Tests, TestsLinux and TestsPlugin; all three targets participate on macOS. Preserve in-memory and recording filesystem injection.

The default make-test entry point may own exactly one workspace parent, with cleanup and absence readback on success, failure and cancellation. A supplied parent remains caller-owned. Direct swift-test invocation requires a prepared explicit parent and caller cleanup, with a clear missing-parent diagnostic. Drain every owned subprocess, including discovery and Sparkle metadata commands, before creator cleanup. Unknown process ownership or drain effects must preserve evidence and parent and fail rather than remove live state. Existing per-fixture cleanup remains; do not mechanically rewrite hundreds of cleanup statements.

Propagate the parent through standalone isolation proofs and test children that replace their environments. Route the eight identified source test/default branches through the resolver while preserving ordinary provider behavior. Claude's test working-directory path must not create user Application Support state. No live credentials, account files, Keychain, usage calls, app launch or user-state inspection is part of this change. Framework/compiler internal scratch is a separate boundary and is not proved contained merely by fixture routing.
<!-- codex-section:end id="spec.native-fixture-containment#req.parent.001" -->

<!-- codex-section:begin id="spec.native-fixture-containment#ctx.evidence.001" -->
## Research and impact

Astra source diagnosis found 594 candidate temporary-path references in 212 native test files, 26 in 15 TestsLinux files and two in two TestsPlugin files. These are references, not a count of proved external writes. Owned native logs prove cost fixtures outside the requested workspace and execution of Claude test paths that call the production Application Support resolver. Historical creation-versus-preexistence and external cleanup remain unknown; this change neither inspects nor deletes that state.

Explicit parent routing avoids dependence on the unresolved Darwin/Foundation versus SwiftPM environment mechanism. Impact includes isolated source defaults, direct swift-test compatibility, child environment replacement, and runner discovery/metadata cancellation. No new public API, production authentication mechanism or provider feature is intended. Existing synthetic assertions and gated skips must remain. Prior full-run timing and timeout evidence provide the performance baseline; no new sharding or test removal is authorized.
<!-- codex-section:end id="spec.native-fixture-containment#ctx.evidence.001" -->

<!-- codex-section:begin id="spec.native-fixture-containment#dec.ownership.001" -->
## Implementation ownership

Coordinator/root owns Git, docs, manifest and integration in the dedicated worktree on work/native-catalog-repair-506fc1fd. One builder owns fixture implementation in Tests/CodexBarTests (excluding ProviderArchitectureGatekeeperTests.swift), TestsLinux, TestsPlugin, TestProcessSafety and the eight named source branches, test.sh, ci_swift_test_by_suite.py, the two standalone isolation proof scripts, their provider proof fixture and a focused scratch-parent harness. The architecture metadata repair is a separate released one-file lane. No builder may mutate Git or run native checks before the coordinator issues a safe verification capsule. No lockfile, dependency installation or formatter-generated shared state is authorized.

Proceed from source evidence to explicit-parent helper, target migration and child propagation, then lifecycle-safe runner integration. Preserve independently injected filesystem semantics. Stop on overlap, unbounded production effects, unsafe cleanup or unknown prior effects. Source rollback is a normal task commit revert; no historical state cleanup is included. Operator Interaction Inventory: no protected operation introduced or exercised.
<!-- codex-section:end id="spec.native-fixture-containment#dec.ownership.001" -->

<!-- codex-section:begin id="spec.native-fixture-containment#ac.verification.001" -->
## Acceptance and verification

After static review and explicit writer release, run focused resolver rejection/containment, isolated defaults, cost fixtures, Claude sessions, standalone child isolation and runner lifecycle checks under the repository's Keychain, Codex and session isolation. Verify architecture metadata with its unchanged negative coverage. Then run the required full make test once with one invocation-owned workspace parent, exact source hashes, serial admission and creator cleanup/absence evidence. Report affected-suite and original recovery-suite coverage, every timeout/fallback, and all skips. Preserve the four existing gated skip reasons; adding skips or removing tests is not a substitute for passing.

Run make check only when inspection establishes no installation/signing; currently absent pinned lint tools hold it. Record exact commands, revision, failures, unavailable prerequisites and remaining gates. The Actions pause, release/signing/installation holds, deferred NFP-COR-002 and FSP-PROC-002 findings, seven trial gates, and historical unknown effects remain separately visible. Do not claim merge, installation or operational account switching from synthetic source evidence.
<!-- codex-section:end id="spec.native-fixture-containment#ac.verification.001" -->
