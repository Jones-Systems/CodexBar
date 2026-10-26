# Engineering Spec — Netdata app lifetime

<!-- codex-section:begin id="spec.netdata-app-lifetime#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.netdata-app-lifetime`

Purpose: Connect the existing Netdata client and cache to application-owned polling, Systems, and a compact menu item.

Governing artifact: `spec.netdata-menu-bar`

Specification owner: Fleet readiness successor

Integration owner: CodexBar source integration coordinator

Consumers: App integration builder, lifecycle tests, source reviewers

Authority effect: none
<!-- codex-section:end id="spec.netdata-app-lifetime#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.netdata-app-lifetime#ctx.project-summary.001" -->
## Project Summary

The app owns one Netdata coordinator independently of settings-window lifetime
and enabled usage providers. A user explicitly applies one loopback target and
enables monitoring. Systems and a dedicated compact status item observe the same
bridge and presentation clock. Unconfigured installations remain inert.

This slice completes source integration. It supplies no actual host origin,
machine GUID, tunnel, credentials, installation, or live qualification.
<!-- codex-section:end id="spec.netdata-app-lifetime#ctx.project-summary.001" -->

<!-- codex-section:begin id="spec.netdata-app-lifetime#req.behavior.001" -->
## Requirements

- Persist a versioned, local-only record using the existing injected defaults.
  Default to disabled. Separate draft editing from an explicit Apply action.
- Validate environment identity, label, loopback origin and machine GUID before
  replacing configuration. Reserve `local` for the existing local observation.
  Reject invalid Apply without replacing a valid applied record.
- Missing, malformed, disabled, unsupported-version or invalid persisted records
  cannot bind a client, schedule a poll, or fetch.
- Reuse the existing bridge, client, parser, freshness projection and refresh
  decisions, including five/ten-second cadence and bounded failure backoff.
- Keep one physical fetch across reconfiguration, cancellation, sleep and stop.
  A cancelled task retains occupancy until its transport drains. Obsolete replies
  cannot publish or clear newer task handles.
- Sleep suspends polling; wake refreshes once after any prior task drains.
  Repeated start/wake/stop and manual refresh are coalesced and idempotent.
- Systems or menu visibility selects visible cadence without resetting an
  issued due date or bypassing failure backoff.
- Show the existing compact CPU/available-memory projection in an actual status
  button, with source, age, availability, refresh, settings and optional validated
  dashboard navigation in its menu. Provider settings cannot gate telemetry.
<!-- codex-section:end id="spec.netdata-app-lifetime#req.behavior.001" -->

<!-- codex-section:begin id="spec.netdata-app-lifetime#ac.source.001" -->
## Acceptance

Synthetic tests prove inert defaults, rejected configuration, persistence,
shared production composition, cadence/backoff, cancellation occupancy,
sleep/wake/shutdown, stale callback rejection and presentation aging. A focused
native status-item seam proves the button/menu connection, provider independence,
recovery and removal. Applicable current-head hosted checks pass.

Source tests and compilation do not establish native rendered appearance, live
metric accuracy, a private route, installed adoption or measured polling cost.
<!-- codex-section:end id="spec.netdata-app-lifetime#ac.source.001" -->

<!-- codex-section:begin id="spec.netdata-app-lifetime#dec.design.001" -->
## Research And Decision Basis

At canonical `main` revision `6db7cfb598405093e1de6e818417ed1340dad561`,
inspection of app construction, Preferences, the bridge and refresh state found
an empty pane-owned bridge and no production client binding or polling owner.
The bridge already protects binding identity and per-environment physical fetch
occupancy. Its caller deliberately owns transport cancellation and scheduling.
The app coordinator adds occupancy across environment changes without rewriting
those core contracts. Dashboard navigation remains independent of API access.

Impact coverage is partial for the named CodexBar app/core consumer universe at
that revision: symbol searches and direct source reads covered production
construction, preferences, status lifecycle and Netdata tests. Installed apps,
private configuration, live endpoints and rendered UI were excluded and remain
unknown. Existing portable client/parser semantics remain unchanged.

Open PR #41 at `ba523f60b7161e70a3afd201f87d49dd2b0e37fe` changes adjacent
AppDelegate lifecycle and constructor fields for unrelated provider removal.
Keep Netdata ownership additive and preserve the current cloud-sync behavior;
do not make that work a dependency. PR #26 changes entry-point bootstrap only;
the Netdata slice does not edit that entry point.
<!-- codex-section:end id="spec.netdata-app-lifetime#dec.design.001" -->

## Exact Change Surface And Ownership

One source builder owns configuration, settings state, coordinator, preference
injection, Netdata settings, observability visibility, status-item wiring and
their focused tests. The parent alone owns Git and these documentation updates.
Scheduling and its consumers remain one implementation lane because cancellation,
visibility and injected lifecycle interfaces are coupled. No generated output,
package, lockfile, workflow, provider model or core parser/client rewrite belongs
to the slice.

<!-- codex-section:begin id="spec.netdata-app-lifetime#iface.lifecycle.001" -->
## Interface Contracts

`AppDelegate` constructs the coordinator inertly, starts it on launch and stops
it before menu teardown. Settings windows receive that same instance; closing a
window releases only its visibility contribution. StatusItemController owns the
native status item and delegates polling to the coordinator.

The coordinator accepts explicit configuration and injected clocks, scheduling,
notification centers and fetchers for tests. It hides transport tasks and
cancellation identities from views. Binding invalidation is immediate, but
physical task retirement waits for completion before any replacement starts.
Lifecycle generations reject delayed callbacks after stop or reconfiguration.

The new local record requires no migration of provider or synced settings.
Unknown versions fail closed. Disabled/default state preserves prior app
behavior. No configuration is inferred from dashboard URLs or existing private
stores. The existing HTTP loopback-only client validator remains authoritative.
<!-- codex-section:end id="spec.netdata-app-lifetime#iface.lifecycle.001" -->

## Test Plan

Use dictionary-backed defaults, fake time/scheduling, private notification
centers and recording or deliberately held fetchers. Do not use real HTTP,
shared defaults, credentials or wall-clock sleeps. Cover healthy zero, partial
data, failure backoff, stale/unavailable aging, changed environment IDs,
disable/re-enable and A-to-B-to-A changes during an uncooperative fetch.

Retain existing Netdata bridge, Systems, refresh, hub and loopback suites.
Run the repository's contained `make test` and `make check` or their checked-in
hosted CI equivalents on an authorized execution surface. No laptop test,
compiler, capture or heavy lint process is allowed for this assignment.

The owning pull request's description is this slice's deferred-review ledger;
the coordinator persists findings at review fan-in. NETDATA-01 records partial
fixture isolation in two wiring-test preferences selections, deferred under the
owner's P2 rule. Do not claim complete synthetic isolation for those calls.

<!-- codex-section:begin id="spec.netdata-app-lifetime#ctx.stop-recovery.001" -->
## Stop, Recovery, And Delivery Boundaries

Deliver an ordinary source pull request and applicable green checks. Do not
merge, install, launch the app, activate monitoring, access a private endpoint,
or resume the original producer. Preserve existing configuration and adjacent
work. Stop the affected mutation for incompatible concurrent changes, unknown
prior effects or protected-input expansion. A disabled record and normal
source rollback preserve the previous inert behavior; neither authorizes an
installed rollback operation.
<!-- codex-section:end id="spec.netdata-app-lifetime#ctx.stop-recovery.001" -->
