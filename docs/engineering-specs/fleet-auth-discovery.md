# Engineering Spec — Fleet authentication discovery

<!-- codex-section:begin id="spec.fleet-auth-discovery#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.fleet-auth-discovery`

Purpose: Reuse declared local fleet Codex profiles without duplicating credential authority.

Governing artifact: none

Specification owner: root coordinator, using auth_diagnosis framing

Integration owner: root coordinator

Consumers: fleet discovery core and app builders

Authority effect: none
<!-- codex-section:end id="spec.fleet-auth-discovery#ctx.artifact-header.001" -->

## Requirements And Acceptance

Discover same-host Codex profile homes from the existing host-tooling binding and combine them with explicit CodexBar profile homes. Existing native profile-home credential reads and CLI-owned refresh remain authoritative. An existing app-managed selection with one verified fleet match may migrate its observation source only on exact provider/workspace identity plus matching normalized email. Email-only, unresolved, mismatched and ambiguous identities never migrate. No token import, independent refresh, account switch, login, remote credential transport or new credential vault is added.

Validate exact schema, actual home, local Codex `codex-file` store and consistent registered config/auth paths; reject unsupported, malformed and escaping input. Missing or unreadable discovery is distinct from expired authentication. Non-Codex records and remote targets never become local profile homes. Bound input size and prevent ordinary tests reading the live binding.

A selected fleet profile remains the selected identity when its binding disappears or becomes unreadable, including after restart. Block both OAuth and CLI before credential reads/launches while it is unavailable or removed; never retarget it to ambient auth. A valid reappearance recovers. Explicit configured homes remain usable independently of fleet metadata. All normalized selected profile identities now remain selected when removed, requiring explicit reselection; this intentionally replaces ambient fallback for removed explicit profiles too. The user may select another account explicitly.

## Research And Decision Basis

Current fork base is `5f4a4c9474d2c44e136275fe5c42689a6c6e7a56`. Diagnosis found only explicit codexProfileHomePaths, ambient CODEX_HOME and the app-managed store; no fleet discovery. Existing native auth expiry delegates refresh to scoped CLI. The existing resolver would otherwise replace a profile absent from its configured set with liveSystem, requiring a guard for unavailable fleet selections.

Fleet source is Jones-Systems/host-tooling `fc332722914b21dc86e1772c0736d511ef37e18a`, core.py binding schema `host-tooling.auth-fleet-binding/v1`. Installer writes `~/.local/share/host-tooling/runtime/auth-fleet-binding.json` as 0600. Codex records declare `.codex-t3/<alias>` homes and `auth.json`. The operational status command is unsuitable for discovery because it reads credentials, invokes native auth checks and acquires locks; it is not called.

Headroom evaluation is recorded in the Work Note. It does not control this fix. The owner confirmed the native Mac menu is the affected surface. This source slice addresses the confirmed native discovery gap; installed revision and live reproduction remain unproved.

## Boundary And Hidden Impact

Caller view: the app and applicable CLI use existing profile-home selection and reconciliation; discovery contributes declared local homes. Host-tooling owns enrollment and metadata, native Codex owns credentials/refresh, and CodexBar owns presentation and selection. Binding metadata is private and is never logged wholesale.

Consumers: settings, reconciliation, usage routing, app/CLI account enumeration and their synthetic tests. Discover them through codexProfileHomePaths and profileHome callsites; preserve explicit-config coding and iCloud machine-local exclusions. Do not modify CAAM protocol, remote environment controls or CloudSync snapshots.

Interface depth: one bounded metadata reader plus pure parser projects the existing binding into homes and availability. Authentication stays behind existing scoped profile APIs. No second host catalog or persisted discovery cache is introduced.

Compatibility: absent binding preserves existing explicit homes. Every normalized selected profile identity is retained on removal/discovery loss and rejected before auth access; malformed active paths retain existing validation. Recovery is restoring valid metadata or explicit owner selection; reverting source removes only this feature and changes no fleet credentials.

Load-bearing claims: parser/path/isolation tests establish bounded metadata handling; selected-source and pre-fetch tests establish no ambient fallback or token refresh. Source tests do not prove live login validity, installed-binary currentness or remote-machine coverage.

## Change Surface, Task Graph And Checks

- Core builder owns new CodexFleetProfileDiscovery.swift and its focused test file. Read-only source schema evidence precedes this task. Acceptance is bounded valid discovery and negative/isolation fixtures.
- App builder follows core API and diagnosis, owns Codex settings/reconciliation/usage routing and focused integration tests, with exact paths bound in its capsule. It must preserve selection and guard unavailable profiles. Root owns Git and docs. Independent write cones permit overlap in time; app integration verification depends on the final core API.
- Root consolidates changes, inspects affected callsites/diff, runs smallest feasible affected checks plus required make test and make check, and publishes one task PR. Missing Swift/macOS checks are unavailable locally and must be supplied by CI. Do not install unapproved tooling to disguise missing checks.

## Stop, Recovery And Delivery

Stop on credential exposure, unknown runtime effect, branch/owner variance or inability to prove no ambient fallback. Do not repair Wallace provider-directory startup problems, alter private bindings, run live status or refresh commands, install the app, use sudo, merge without valid authority, or deploy. Open PR publication and current-head CI observation are source delivery; installation remains a separate effect. Preserve all existing unrelated work.
