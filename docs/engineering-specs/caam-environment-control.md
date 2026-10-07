# Engineering Spec — CAAM Environment Control

<!-- codex-section:begin id="spec.caam-environment-control#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.caam-environment-control`

Purpose: Specify the product behavior, protocol, implementation graph, verification, and delivery boundaries for CAAM-backed Codex environment control in CodexBar.

Governing artifact: `none`

Specification owner: coordinator

Integration owner: CodexBar CAAM environment owner

Consumers: CodexBar implementation, CAAM gateway implementation, reviewers, verifier, and release owner

Authority effect: none
<!-- codex-section:end id="spec.caam-environment-control#ctx.artifact-header.001" -->

Specification revision: 2

Revision 2 adds the combined control workflow and observability-hub candidate below. The
first-PR and prior merge language is historical; the current owner authorization permits
one draft PR to `Jones-Systems/CodexBar:main`, no merge and no live account operation.

<!-- codex-section:begin id="spec.caam-environment-control#ctx.outcome-and-scope.001" -->
## Outcome, scope, and finish line

CodexBar running on the owner's laptop presents one coherent view of Codex accounts and three initial environments: the laptop, VPS, and Mac Mini. Environment configuration is general rather than hard-coded. Each environment has one local CAAM authority, one current host-default profile, an optional configured fallback profile, capability and health state, and optional running-process/recovery state.

CodexBar can observe every configured environment. When an environment advertises the complete mutation capability set, CodexBar can request a switch plan, confirm its exact consequences, execute once, query an operation after ambiguous transport completion, recover an interrupted transaction, or explicitly restore the fallback profile. It never synchronizes or reads credential payloads.

The full project finishes only after macOS compilation and UI proof, credential-free local/SSH integration tests, CAAM V3 adapter conformance, and real read-only then bounded mutation qualification on the three intended environments. The first PR stops at the capability-gated foundation described in `spec.caam-environment-control#ctx.delivery-boundaries.001`.
<!-- codex-section:end id="spec.caam-environment-control#ctx.outcome-and-scope.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#ctx.boundaries-and-assumptions.001" -->
## Boundaries and working assumptions

- The laptop is the permanent UI/control device. The local environment is represented explicitly and sorted first.
- CodexBar's existing `Active` usage selection and local `System` promotion remain unchanged in the first PR.
- The initial Environments UI is a dedicated section inside Codex provider settings. Moving it to a top-level pane is reversible and waits for macOS evidence or owner direction.
- Remote endpoints are user-configured SSH aliases or `user@host` values. No private hostnames are committed.
- SSH uses batch mode, no TTY, cleared forwarding, a short connection timeout, and one fixed gateway executable/operation. No `sh -lc`, pipelines, redirection, or caller-supplied command text is permitted.
- Local and remote outputs are bounded before decoding. Errors are summarized without including raw stdout or credential-adjacent payloads.
- A fallback profile belongs to CAAM on its environment. CodexBar displays and invokes it but does not choose or store the profile as a second authority.
- `recover-switch` resolves a journaled interrupted operation. `restore-fallback` is a separate deliberate mutation.
- A host-default profile and an account cached by running Codex processes are separate fields. Unknown runtime state is shown as unknown, not inferred.
- The first PR adds no dependency and no background polling loop. Refresh remains explicit or owned by a later bounded scheduler.
- The first PR is delivered to the organization-controlled `Jones-Systems/CodexBar` fork and does not target upstream `steipete/CodexBar`.
<!-- codex-section:end id="spec.caam-environment-control#ctx.boundaries-and-assumptions.001" -->

## Requirements

<!-- codex-section:begin id="spec.caam-environment-control#req.environment-configuration.001" -->
### Environment configuration

Provider-scoped configuration stores an ordered list of unique environments. Each record contains a stable bounded ID, user-facing label, and exactly one connection:

- `local`, with an optional absolute CAAM executable override; or
- `ssh`, with one validated SSH destination and no command fragments.

Normalization rejects duplicate IDs, duplicate local environments, blank labels, relative executable overrides, unsafe SSH destinations, and unsupported connection kinds. An absent field remains backward compatible and means no CAAM environment UI is enabled. The UI can create a safe initial local record without inspecting credentials.
<!-- codex-section:end id="spec.caam-environment-control#req.environment-configuration.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#req.snapshot-and-identity.001" -->
### Snapshot and account identity

An environment snapshot binds schema, environment ID, monotonically comparable revision, observation time, CAAM version, protocol version, capabilities, reachability, host-default profile, fallback profile, profiles, pending operation, and runtime-effective state.

Profile identity is redacted and rotation-stable. It may carry provider, opaque stable ID, masked/display email, workspace/account ID, workspace label, plan label, and health. It never carries access tokens, refresh tokens, ID tokens, cookies, API keys, auth-file bytes, auth-file paths, vault paths, or a digest of the complete credential file.

Unknown profile, runtime, fallback, and recovery state remain explicit. A profile name is environment-local and is not a global account ID.
<!-- codex-section:end id="spec.caam-environment-control#req.snapshot-and-identity.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#req.capability-gating.001" -->
### Capability negotiation and fail-closed UI

The closed v1 capabilities are `snapshot`, `plan_switch`, `execute_switch`, `operation_status`, `recover_switch`, and `restore_fallback`. Unknown capabilities are retained only for diagnostics and do not enable controls.

CodexBar enables an action only when the current snapshot advertises that action, the protocol major version is supported, no conflicting operation is pending, the exact target profile is eligible, and required expected-revision or operation identifiers are present. An unreachable, stale, malformed, unsupported, or legacy-only environment remains read-only or unavailable.
<!-- codex-section:end id="spec.caam-environment-control#req.capability-gating.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#req.transport.001" -->
### Local and restricted-SSH transport

CodexBar uses a single typed client over an injected command runner. The local transport executes a configured CAAM gateway binary directly. The SSH transport executes `/usr/bin/ssh` or a validated resolved binary with fixed security options, a validated destination, and the fixed remote gateway `caam-codexbar` followed by one closed operation and validated scalar arguments.

No shell is launched locally or remotely. No command accepts a path, environment assignment, free-form reason, arbitrary flag, or payload from persisted configuration. The client applies time and output bounds, accepts only UTF-8 JSON for the expected response kind, and maps nonzero exit, timeout, cancellation, malformed JSON, schema mismatch, and output overflow to closed redacted errors.
<!-- codex-section:end id="spec.caam-environment-control#req.transport.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#req.mutation-and-recovery.001" -->
### Switching, unknown effect, recovery, and fallback

A switch begins with `plan-switch` bound to environment, target profile, observed current profile, and expected snapshot revision. The plan returns a stable plan digest, affected profile names, reload implication, and expiry. Execution supplies the exact plan digest plus a new operation ID and idempotency key.

Known completion must return a typed result and a fresh matching snapshot. Known no-effect permits a new plan. If transport ends after execution might have begun, CodexBar records the operation as unknown and invokes only `operation-status` with the same operation ID. It never blindly executes again.

`recover-switch` references the pending operation and lets host-local CAAM complete or roll back according to its journal. `restore-fallback` executes only from a plan digest bound to the configured fallback profile and expected revision. Recovery does not silently become fallback restoration. If no valid fallback exists, the fallback action is unavailable.
<!-- codex-section:end id="spec.caam-environment-control#req.mutation-and-recovery.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#req.presentation.001" -->
### Settings presentation

The first UI section renders deterministic environment rows from state rather than launching processes from SwiftUI views. A row shows label, local/SSH scope, reachability, current profile/account, fallback profile, runtime mismatch or reload-needed state, CAAM compatibility, pending/recovery state, and last observation age.

The first PR presents configuration and fixture/client-fed read-only states and keeps mutation controls disabled unless complete supported capabilities are supplied. Later activation adds a profile picker, switch confirmation, operation progress, exact unknown-result recovery, and fallback restoration without changing account usage selection.

The local environment is labeled `Laptop` by default in user configuration; source code and fixtures use public-safe generic labels. No existing `System` wording is renamed in the first PR.
<!-- codex-section:end id="spec.caam-environment-control#req.presentation.001" -->

## Interface

The independently consumed cross-project wire contract is `contract.caam-codexbar-control-v1`. CodexBar models and command construction must conform to that contract. CAAM production activation requires a separate conformance implementation and tests against the same fixtures.

## Acceptance

<!-- codex-section:begin id="spec.caam-environment-control#ac.foundation.001" -->
### First-PR foundation acceptance

- Configuration round-trips through provider extension coding and preserves unknown provider fields.
- Validation covers duplicate IDs/local records, unsafe SSH destinations, relative executables, blank labels, and bounded counts/lengths.
- Snapshot decoding accepts the canonical v1 fixture and rejects secrets, unsupported schema, mismatched environment, duplicate profiles, invalid pending operations, and oversized input.
- Projection deterministically distinguishes reachable, unavailable, incompatible, recovery-required, and reload-needed rows.
- Command construction proves exact local and SSH argv, security options, fixed gateway operation, scalar validation, and absence of shell invocation.
- The Codex settings pane conditionally renders an Environments section through a stable state seam without changing existing account-selection behavior.
- Mutation controls are absent or disabled when the environment lacks complete capability/currentness evidence.
- Documentation identifies the exact-head macOS CI evidence, unavailable interactive UI evidence, and the CAAM activation dependency.
<!-- codex-section:end id="spec.caam-environment-control#ac.foundation.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#ac.full-project.001" -->
### Full-project acceptance

- Mac tests compile and render local, remote, unreachable, incompatible, recovery-required, and reload-needed states without real credentials or Keychain prompts.
- A fixture-compatible CAAM V3 gateway passes cross-repository contract tests.
- Local and forced-SSH read-only qualification returns redacted snapshots from the laptop, VPS, and Mac Mini.
- One explicitly authorized switch per environment proves plan binding, execute-once behavior, operation lookup after simulated response loss, postcondition readback, and runtime-state presentation.
- Recovery completes or rolls back an interrupted operation from journal evidence. Fallback restoration is separately confirmed and verified.
- CodexBar never reads, persists, logs, synchronizes, or renders credential or vault payloads.
<!-- codex-section:end id="spec.caam-environment-control#ac.full-project.001" -->

## Test Intents

<!-- codex-section:begin id="spec.caam-environment-control#test.config-contract.001" -->
```json
{
  "schema_version": 1,
  "kind": "contract/configuration",
  "validates": [
    "spec.caam-environment-control#req.environment-configuration.001",
    "spec.caam-environment-control#req.snapshot-and-identity.001",
    "spec.caam-environment-control#req.capability-gating.001",
    "spec.caam-environment-control#ac.foundation.001"
  ],
  "scenario": "Round-trip bounded local and SSH environment configuration and decode canonical and adversarial redacted gateway snapshots.",
  "evidence": {
    "predicate": "focused Swift tests pass using only in-memory JSON and contained temporary config files",
    "invalid": "a test reads live Codex configuration, credentials, Keychain, SSH configuration, or CAAM vault data",
    "unknown": "the test cannot attribute decoded state to the exact fixture schema and environment ID"
  },
  "environment": ["Swift 6.2+", "Linux or macOS", "synthetic fixtures"],
  "obligation_owner_task": "spec.caam-environment-control#task.models-and-config.001",
  "evidence_executor_task": "spec.caam-environment-control#task.models-and-config.001",
  "acceptance_owner": "coordinator",
  "activation": {"after_accepted": ["spec.caam-environment-control#task.transport-and-client.001"]},
  "target_hints": ["Sources/CodexBarCore/Providers/Codex/CAAM", "TestsLinux", "Tests/CodexBarTests"]
}
```
<!-- codex-section:end id="spec.caam-environment-control#test.config-contract.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#test.transport.001" -->
```json
{
  "schema_version": 1,
  "kind": "transport/security",
  "validates": [
    "spec.caam-environment-control#req.transport.001",
    "spec.caam-environment-control#req.mutation-and-recovery.001",
    "spec.caam-environment-control#ac.foundation.001"
  ],
  "scenario": "Construct and execute fixed local and SSH gateway operations through a recording runner, including timeout, nonzero, malformed, overflow, cancellation, and unknown-effect classifications.",
  "evidence": {
    "predicate": "tests prove exact argv and closed error/result mapping without launching SSH or CAAM",
    "invalid": "the implementation or test composes a shell command or permits unvalidated command fragments",
    "unknown": "a possible execute effect is classified retryable without operation-status evidence"
  },
  "environment": ["Swift 6.2+", "recording subprocess runner", "no network"],
  "obligation_owner_task": "spec.caam-environment-control#task.transport-and-client.001",
  "evidence_executor_task": "spec.caam-environment-control#task.transport-and-client.001",
  "acceptance_owner": "coordinator",
  "activation": {"after_accepted": ["spec.caam-environment-control#task.settings-ui.001"]},
  "target_hints": ["Sources/CodexBarCore/Providers/Codex/CAAM", "TestsLinux", "Tests/CodexBarTests"]
}
```
<!-- codex-section:end id="spec.caam-environment-control#test.transport.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#test.presentation.001" -->
```json
{
  "schema_version": 1,
  "kind": "presentation/state",
  "validates": [
    "spec.caam-environment-control#req.capability-gating.001",
    "spec.caam-environment-control#req.presentation.001",
    "spec.caam-environment-control#ac.foundation.001"
  ],
  "scenario": "Project fixture snapshots into stable environment-row states and render the supplementary Codex settings section with mutations gated by capability and currentness.",
  "evidence": {
    "predicate": "state tests pass on Linux-compatible core and macOS compile/screenshot tests pass in PR CI or on the laptop",
    "invalid": "tests construct a live AppKit menu, inspect credentials, or issue a real subprocess",
    "unknown": "macOS compilation or rendering has not run against the exact candidate head"
  },
  "environment": ["Swift 6.2+", "synthetic environment snapshots", "macOS 14+ for rendering"],
  "obligation_owner_task": "spec.caam-environment-control#task.settings-ui.001",
  "evidence_executor_task": "spec.caam-environment-control#task.settings-ui.001",
  "acceptance_owner": "coordinator",
  "activation": {"after_accepted": []},
  "target_hints": ["Sources/CodexBar/PreferencesCodexEnvironmentsSection.swift", "Tests/CodexBarTests"]
}
```
<!-- codex-section:end id="spec.caam-environment-control#test.presentation.001" -->

## Implementation graph and ownership

<!-- codex-section:begin id="spec.caam-environment-control#task.models-and-config.001" -->
### Task 1 — Models, contract fixtures, and provider configuration

Dependencies: none.

Writer scope: `Sources/CodexBarCore/Providers/Codex/CAAM/**`, Codex provider configuration extension, focused config/model tests, canonical public-safe fixtures, and the three governing artifacts.

Implement bounded identifiers, connection records, capability/state models, snapshot and pending-operation validation, row projection, provider extension coding, and fixtures. Run the narrow config/model suites available on the executing platform. This forms the first coherent Git checkpoint.
<!-- codex-section:end id="spec.caam-environment-control#task.models-and-config.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#task.transport-and-client.001" -->
### Task 2 — Command construction and client boundary

Dependencies: `spec.caam-environment-control#task.models-and-config.001`.

Writer scope: CAAM core transport/client files and focused recording-runner tests.

Implement exact local/SSH argv construction, fixed gateway operations, timeout/output limits, response binding, redacted error mapping, and injected runner seams. Do not enable real mutation or add a background scheduler. Commit after focused tests and diff inspection.
<!-- codex-section:end id="spec.caam-environment-control#task.transport-and-client.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#task.settings-ui.001" -->
### Task 3 — Codex environment settings slice

Dependencies: `spec.caam-environment-control#task.models-and-config.001` and `spec.caam-environment-control#task.transport-and-client.001`.

Writer scope: supplementary Codex provider settings state/view/coordinator seams, localization source keys required by repository practice, and focused state/UI tests.

Add the conditional Environments section with local-first deterministic rows, refresh/configuration affordances, status, fallback, runtime, compatibility, and recovery presentation. Mutation remains capability-gated and unavailable without a conforming service. Do not rename existing account controls. Commit after source/static verification; macOS evidence remains a PR/laptop gate.
<!-- codex-section:end id="spec.caam-environment-control#task.settings-ui.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#task.fanin-review-publication.001" -->
### Task 4 — Fan-in, review, synchronization, and candidate PR

Dependencies: Tasks 1–3.

Writer scope: candidate-wide remediation and truthful artifact/PR updates. Git scope: sole Git owner.

Inspect all touched comments under the project comment practice, run every feasible repository check, classify unavailable Swift/macOS evidence explicitly, inspect the complete diff, and perform focused security and maintainability review. Refresh canonical upstream main, forward-merge when needed, rerun invalidated checks, verify the selected Jones Systems fork, publish the exact branch without force, and open one draft PR with checks and limitations. No merge, release, signing, installation, or deployment.
<!-- codex-section:end id="spec.caam-environment-control#task.fanin-review-publication.001" -->

Sequential plan: Task 1, Task 2, Task 3, then Task 4.

Phased plan:

1. Foundation — artifacts, contract, models, configuration, fixtures.
2. Integration seam — command construction and client.
3. Presentation — environment settings section.
4. Candidate closure — checks, review, upstream synchronization, and draft PR.

Proven-independent waves: none. Task 2 consumes Task 1 types; Task 3 consumes Tasks 1–2; fan-in consumes all code. Research source questions were independent, but session policy disallowed new delegated lanes and implementation has one Git/writer owner.

Fan-in owner: coordinator. Affected checks: focused config/model/transport/projection tests; Codex provider settings tests; localization coverage; SwiftFormat/SwiftLint; Swift build/test where a Swift toolchain is available; PR CI across supported macOS/Linux jobs.

Stop/recovery rules: stop mutation on worktree identity or ownership drift, unexpected changes, contract ambiguity that could expose credentials, unknown prior remote effect, loss of exact operation identity, unsafe SSH command construction, failed required check with unclear causality, macOS compile failure requiring product intent, or publication target ambiguity at the push boundary. Preserve coherent commits; do not reset, clean, rebase, squash, force-push, or retry an unknown remote effect.

<!-- codex-section:begin id="spec.caam-environment-control#ctx.delivery-boundaries.001" -->
## Delivery boundaries

The first PR may contain planning artifacts, a versioned inactive protocol, environment configuration, synthetic fixtures, pure model/projection logic, safe command construction, injected client seams, and a capability-gated Codex settings section. It does not claim that CAAM currently conforms, that real SSH switching works, or that the app compiled on this VPS.

The initial publication request authorized creating/using a task fork, committing the declared paths, refreshing and forward-merging canonical upstream main, pushing the exact task branch normally, and opening one draft PR. The owner's later merge request authorizes merging PR #1 into `Jones-Systems/CodexBar:main` after its required checks pass. Neither request authorizes upstream submission to `steipete/CodexBar`, signing, notarization, release, Homebrew publication, device installation, SSH gateway provisioning, live credential access, live account switching, daemon termination, or automatic software update.
<!-- codex-section:end id="spec.caam-environment-control#ctx.delivery-boundaries.001" -->

<!-- codex-section:begin id="spec.caam-environment-control#ctx.observability-candidate.002" -->
## Combined controls and observability candidate

The accepted [v1 control contract](../contracts/caam-codexbar-control-v1.md) remains the wire authority.
The read-only dependency is `Jones-Systems/CAAM` at
`work/caam-codexbar-gateway@8fdf44a1c2c3af0d36b934d79725608945790f32`.
Its implementation was not accessible during this pass; capability advertisement is not
independent conformance evidence. Production mutation qualification therefore defaults to an
empty set of exact environment configurations. There is no settings switch that bypasses this
qualification. Read-only discovery, plans, status lookup, model/UI work, fixtures, and caching
remain independently useful. The candidate does not claim full-project activation acceptance.

### Control state and confirmation boundaries

`CAAMControlSession` owns a pure state machine, separate from transport and SwiftUI. Plans bind
the environment, source revision/current profile, eligible target, affected profiles, digest,
reload consequence, and expiry. Confirming consumes a unique confirmation once; execution
receives a new operation UUID and idempotency UUID. Fallback and interrupted-operation recovery
have separate confirmation kinds and typed commands. Recovery retains the original operation UUID.

Unknown mutation effects remain unresolved through refresh and application restart. A snapshot
with an empty pending journal does not prove a locally ambiguous operation completed. Only a
bound, semantically valid terminal operation result with a fresh postcondition snapshot can settle
it. A failed status or recovery request cannot erase the original operation. Manual-required
state disables automatic recovery. A rollback is reported as rollback, not successful switching.

The application coordinator is a single UI-actor instance with sequential, bounded refresh and
operation coordination. It publishes each completed environment independently, coalesces refresh
requests, and rejects late results from a changed configuration generation. It does not block
the application waiting for subprocess completion. Intent receipts are persisted on a separate
actor before any possible mutation launch, with only validated configuration selectors and UUIDs.
The bounded atomic receipt file is private to the user (0600; newly created parent 0700).
Failed persistence disables mutations; unresolved records remain available for lookup against
their original configuration even if the configured environment list changes externally.

The transport preserves native exit status and UTF-8 validity. A valid error envelope on nonzero
exit can establish a typed effect; a success envelope on nonzero exit cannot. Timeout, cancellation,
oversize, invalid encoding, and invalid responses after possible launch remain unknown-effect.
UI errors use closed descriptions and validated codes, never raw stdout, stderr, or remote messages.

### Cache and freshness policy

CAAM mutation evidence expires after 60 seconds, with a maximum five-second future-clock allowance.
Successful snapshots remain displayable for at most 15 minutes, measured against both their source
timestamp and receipt time. Refresh failure marks retained values stale rather than fresh or zero.
No background poll is added: configured environments refresh on section appearance when needed,
or explicitly on user request. Fifteen-second UI timeline ticks update presentation age only.

Environment configuration remains bounded to 32 records and each snapshot to 64 profiles and
64 KiB. The coordinator bounds retained observations and does not silently evict an unresolved
operation. Full configuration identity, not a reused ID, binds cached evidence and qualification.

### Observability ledgers and views

`ObservabilityHub` aggregates already-published local values. It never performs a network request,
credential lookup, session scan, account switch, or host-process inspection. There is deliberately
no combined utilization or spend total across unlike measurements.

| View | Evidence shown | Boundary |
| --- | --- | --- |
| Overview | CAAM service state; provider quota windows, confidence, source/time; separate cost and metered amounts | Preserve currency, window and estimate/vendor/mixed provenance; unavailable is not zero |
| Accounts | Environment-local profiles and redacted identities with health/source/time | Only matching provider and stable ID establish cross-environment identity; no email/name join |
| Systems | Host-default versus runtime-effective profile and recovery state | Unknown runtime remains unknown; host-resource ledger is separate |
| Work | At most 100 already-loaded local session records, materialized only on this tab | Historical partial evidence, never a live job queue; no private session IDs or paths in the view |

Provider inputs are bounded to 64. Provider cache timestamps older than five minutes or following
a refresh failure are labeled stale. Synthetic placeholder quota values and non-finite/negative
numeric costs are unavailable. Existing historical cost publications are not attributed to a CAAM
account and are not presented as billing receipts. The hub avoids display helpers that can resolve
disk-backed identity or cookie caches. Current provider-configuration publication revision is checked
before admitting cost records; provider identity and account control remain separate authorities.

### Netdata boundary

No Netdata endpoint contract, configured collector, or response fixture exists in this tree.
`NetdataReadOnlyFacade` therefore reports unsupported host telemetry, with no observation timestamp
and no fabricated CPU/memory values. Systems offers a user-entered dashboard link, never stored or
prefilled from guessed host data. URLs require HTTPS, or HTTP on a literal loopback target; credentials,
query parameters, fragments, control characters, invalid ports, and other schemes are rejected.
Opening that link neither imports telemetry nor verifies host identity. No installation or Netdata
service modification is part of this candidate.

### Candidate verification and residual gates

New fixture suites cover stale/capability gating, plan expiry and confirmation reuse, exact response
binding, nonzero typed errors, invalid UTF-8, bounded output, unknown-effect lookup, recovery/fallback
separation, receipt restart/failure behavior, lazy aggregation, provenance, and safe dashboard links.
App tests exercise coalescing and late-result suppression through synthetic runners and fixed clocks.
Implicit CAAM subprocesses and real receipt-store access are disabled under existing test-process detection.

The [single evolving Work Note](../work-notes/caam-environment-control.md) records actual check outcomes,
sequential self-review dispositions, incidents, and publication evidence. Source inspection and portable
catalog checks do not replace Swift compilation, native tests, or macOS UI proof. English fallback keys
are explicitly marked pending linguistic review. External CAAM conformance/activation, Netdata collector
qualification, and native platform evidence remain separate gates; none authorizes a live mutation here.
<!-- codex-section:end id="spec.caam-environment-control#ctx.observability-candidate.002" -->
