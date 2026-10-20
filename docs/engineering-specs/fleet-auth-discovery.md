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


<!-- codex-section:begin id="spec.fleet-auth-discovery#req.fleet-presentation.001" -->
## Full fleet account presentation

For the owner-requested follow-up to the initial discovery slice, show all local
Codex accounts and all enrolled native Claude profiles in compact lists under
the selected account, including in Overview. Selected detail remains collapsible.
A missing or stale quota must remain attached to its own account; timestamps
must not imply fresh quota while a hosted placeholder is frozen. Enrollment is
not authentication or usage proof. Explicit existing layout choices are retained.
<!-- codex-section:end id="spec.fleet-auth-discovery#req.fleet-presentation.001" -->

<!-- codex-section:begin id="spec.fleet-auth-discovery#dec.fleet-presentation.001" -->
## Presentation and fetch decisions

The Claude Frontier Opus 5.5/high recommendation defines four slices:

1. Layout-safe refresh: subtitle adoption requires hosted model layout and
   identity compatibility. Readiness encodes snapshot/error presence and selected
   identity, so existing open-menu invalidation rebuilds placeholder geometry.
2. Codex lists: absent both modern and legacy preference keys defaults to stacked;
   explicit modern values and legacy true/false retain their meaning. Show every
   Codex row without healthy-tail folding. Remove the six-account cap only for
   Codex/Claude. Preserve other-provider policy. Replace unbounded concurrent
   fan-out with an ordered sliding window of at most three account fetches.
3. Native Claude lists: while a native profile is selected, reuse its main
   snapshot and serially fetch other enrolled profiles after the main refresh.
   Use existing native selection and transport pipelines with an alias override;
   never run main selection reconciliation for side fetches. Retain in-memory
   account snapshots only. Reject completion after alias discovery identity,
   selected alias or refresh generation changes. Cancellation keeps prior rows;
   failures retain stale quota with its error; unavailable rows remain visible;
   loading has an explicit refreshing state. No row switches provider accounts.
4. Overview: retain the selected provider card and append every non-selected
   Codex/native-Claude compact account row. Clicking navigates to that provider
   and expands that row, without changing the active login.

Native Claude aggregation is conditional on a synthetic proof that the existing
profile-keyed credential cache cannot serve one profile's record to another.
Stop that slice if the proof fails; do not add a parallel credential cache or
read live stores. Token-account/claude-swap precedence remains intact.
<!-- codex-section:end id="spec.fleet-auth-discovery#dec.fleet-presentation.001" -->

<!-- codex-section:begin id="spec.fleet-auth-discovery#ctx.fleet-repair-plan.001" -->
## Repair task graph and verification

A (stale-card refresh) and B (Codex defaults/list/cap/bounded fan-out) have disjoint
writers and may run together. C (Claude aggregation) follows B's cap policy; D
(Overview rows) follows B/C. Root is the sole Git/index owner, documentation
writer and shared build/test owner. Exact builder cones are assigned in native
capsules. Keep every existing account identity, cancellation, PAT and recovery
selection guard. No unrelated findings are repaired in this follow-up.

Affected tests cover hosted placeholder-to-metrics rebuilding, compatible live
subtitles, identity mismatch, account-selection readiness; six/nine-account full
lists and selected collapse; preference migration; other-provider equivalence;
fetch ordering/cancellation and peak concurrency; serial Claude profile routing,
cache isolation, stale/error/loading states and late-result rejection; Overview
account-row counts/navigation/expansion. Fixtures inject discovery, in-memory
settings, transports and owned synthetic homes. Existing Keychain/Codex/session
file isolation and invocation-owned scratch/drain cleanup remain mandatory.

No debug test binary exists at intake. A separate pre-change full compile is
not a cheap failing-before seam; bind source diagnosis to the baseline and run
the closest direct deterministic regressions on the candidate. Run focused
suites while iterating, their deduplicated final union, then make test and make
check. Record commands, exact heads and unavailable/failed/skipped evidence.
Hosted CI must qualify the exact PR head; missing checks never count as passes.
<!-- codex-section:end id="spec.fleet-auth-discovery#ctx.fleet-repair-plan.001" -->

<!-- codex-section:begin id="spec.fleet-auth-discovery#ctx.local-update-effects.001" -->
## Local update and remaining boundaries

The owner explicitly authorizes installing and opening subsequent Jones updates.
After source/check qualification, rebuild with the existing Jones ad hoc identity
and skipped automatic smoke launch; preserve current Jones preferences. Update
only the installed Jones app using a recoverable exact-path replacement and
normal graceful quit of that identified app. Open the installed copy and verify
its build identity. No broad process termination, stock application replacement,
Keychain probe, token copying, new login or system-account promotion is covered.
Retain all seven original trial gates outside the bounded Codex/Claude scope;
widgets, real signing, iCloud and public release remain unqualified.

Routine delivery follows the owner's standing delivery and local app update
binding in `AGENTS.md` (section “Delivery and local app updates”), including PR #7
and subsequent requested CodexBar changes. This supersedes the migration's historical
five-PR limit for routine delivery. Qualify every current candidate and preserve
native review/check requirements; do not bypass them or request routine merge
and installation permission again.
Rollback source through normal reviewable commits; restore the preserved prior
Jones app only after verifying its exact replacement postimage. Unknown prior
install/process effects stop replay and require direct reconciliation.
<!-- codex-section:end id="spec.fleet-auth-discovery#ctx.local-update-effects.001" -->


<!-- codex-section:begin id="spec.fleet-auth-discovery#dec.friendly-labels.001" -->
## Friendly account labels

Use one presentation-only label policy for switcher tabs, compact account rows,
Overview rows and account headers: a local override keyed by provider/profile
identity, otherwise a verified fleet alias, otherwise a generic Account label
with the existing stable discriminator. Keep the native default label distinct
from named profile aliases. Never infer authentication identity from email-local
parts, or commit the owner's personal display mapping to public source.

Retain the alias as optional Codex projection presentation metadata only; leave
home, email, workspace identity, selection, reconciliation and snapshot ownership
unchanged. Native Claude already carries its alias. A shared pure resolver and
one local settings override map serve all menu surfaces. Card headers prefer an
explicit resolved display label while preserving existing PII-redaction behavior.
Old callers with no presentation label retain their existing semantics.

Prove same-email/different-home distinction, deterministic alias fallback,
explicit override and collision handling, and redaction with synthetic fixtures.
The local installer may seed the owner-requested nonsecret display override only
in the Jones settings domain; preserve unrelated preferences and fleet bindings.
<!-- codex-section:end id="spec.fleet-auth-discovery#dec.friendly-labels.001" -->

<!-- codex-section:begin id="spec.fleet-auth-discovery#dec.cached-selection.001" -->
## Cached quota during observation selection

Reuse the existing uniquely owner-matched quota hydration synchronously after
outgoing account state is cleared, using the selection's already-created guard
and projection. Do not add a credential read or weaken workspace/source identity
checks. Keep the cached snapshot's original timestamp while refresh proceeds.

The segmented path retains valid sibling account rows instead of clearing the
whole collection. A successful single-account publication upserts its row and
persists the retained collection through the existing store. Prune removed or
changed owners against the current projection. A selected-account failure must
still invalidate rejected authentication/ownership state; retained cache cannot
resurrect quota that existing failure policy rejects. Keep transient-failure
stale-data behavior, refresh generation guards and manual refresh semantics.

Tests cover immediate matching hydration, wrong workspace rejection, revisiting
multiple cached accounts, stale timestamps and authentication-failure eviction.
This changes cache retention and presentation only, with no new storage, TTL,
request suppression or system-account switching.
<!-- codex-section:end id="spec.fleet-auth-discovery#dec.cached-selection.001" -->

<!-- codex-section:begin id="spec.fleet-auth-discovery#dec.native-profile-menu-width.001" -->
## Native profile action width

Keep the ordinary merged menu at its existing 310-point baseline when native
Claude profiles are selected. The action that opens Claude profile settings
uses the concise label “Manage native profile…”, retaining its existing
provider-settings destination. Preserve native measurement and expansion for
other legitimately wide actions. Prove the selected-native merged menu width
with synthetic discovery/settings, alongside the existing expansion and
rendered-window width contracts. No authentication or account selection
semantics change.
<!-- codex-section:end id="spec.fleet-auth-discovery#dec.native-profile-menu-width.001" -->
