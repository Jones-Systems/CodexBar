# System Account names and launch scope

<!-- codex-section:begin id="spec.system-account-switching#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.system-account-switching`

Purpose: Make the named System Account picker consistent with default-home promotion.

Governing artifact: `none`

Specification owner: CodexBar maintainer

Integration owner: Jones Code thread `b8d16f9b-7c98-41e6-b8da-855b7145b198`

Consumers: CodexBar app, account promotion, and native verification

Authority effect: none
<!-- codex-section:end id="spec.system-account-switching#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.system-account-switching#ctx.project-summary.001" -->
## Project Summary

The app's System Account submenu presents the enrolled named fleet roster using
the same display labels as account rows. Managed workspace alternatives remain
stored and available through their existing management surfaces. They are not
extra fleet names and are not deleted or conflated by email.

When the app inherits a uniquely enrolled fleet CODEX_HOME, its entrypoint removes
that override before initializing settings, observation and providers. System
Account then retains its existing ordinary-home meaning. Explicit profile usage
still receives its scoped environment; CLI behavior is unchanged.
<!-- codex-section:end id="spec.system-account-switching#ctx.project-summary.001" -->

## Research And Decision Basis

At base `dd23db9c`, provider menu construction used `visibleAccounts` and raw
`displayName`, while `menuAccounts` and SettingsStore labels already supplied the
desired roster elsewhere. Fleet promotion explicitly targets the ordinary home,
but system observation and reconciliation use ambient CODEX_HOME. Removing the
promotion guard alone would make readers and writes disagree.

The source diagnosis supports an inherited-override failure but the failing
installed process's environment was not inspected. Separate path metadata ruled
out symlinks at the inspected ordinary/five canonical auth paths. The error also
covered overlap failures; distinct errors must preserve that uncertainty.
No external research is needed for this repository-defined path contract.

## Exact Change Surface And Ownership

The provider menu and presentation extension reuse the existing roster/identity
seams. The launch helper lives in the Jones core namespace and is called once
after resource-smoke and hook exits, before application consumers initialize.
Core owns the pure removal decision; only the app entrypoint invokes process
mutation. Fleet discovery remains the metadata validator. Promotion owns membership,
identity, writer serialization, displaced-account preservation and atomic swapping.
No storage schema, provider registration, credential migration or refresh service changes.

The application entry file also appears in open updater/signing work. This repair
is based on verified canonical main and adds only the independent environment
hook; it does not adopt or alter those PRs' lifecycle work.

<!-- codex-section:begin id="spec.system-account-switching#iface.behavior.001" -->
## Interface Contracts

- Named fleet presence selects the existing menu roster. Without that roster,
  managed/live menu choices keep their previous behavior.
- Titles honor local overrides. The Codex alias `umich` defaults to `UMICH`.
- The system checkmark uses the live identity, independently of usage selection;
  matching an enrolled row requires a unique email/workspace identity.
- Only an absolute normalized CODEX_HOME matching exactly one validated enrolled
  home is removed. Unenrolled, absent, relative and ambiguous overrides remain.
  Missing or invalid discovery never normalizes the process environment.
- A CODEX_SQLITE_HOME denoting that same removed home is also removed. Independent
  SQLite routing remains explicit and unchanged. Unrelated environment survives.
- Default/source overlap, symlink alias, stale membership and changed identity
  still fail closed. Custom launch overrides retain the promotion guard and a
  distinct recovery message. Startup normalization reads no credential contents.
<!-- codex-section:end id="spec.system-account-switching#iface.behavior.001" -->

<!-- codex-section:begin id="spec.system-account-switching#ctx.test-plan.001" -->
## Test Plan

Affected suites: JonesCodexAppLaunchEnvironmentTests, JonesAccountDisplayLabelTests,
JonesCodexFleetPromotionMenuTests, JonesCodexFleetPromotionTests,
JonesCodexFleetPromotionBoundaryTests, CodexSystemPromotionUITests,
CodexAccountPromotionServiceTests, CodexVisibleAccountTests and the existing
provider architecture gate. The full isolated native suite remains required.

New cases cover the five names, extra workspace rows, typed targets, current-system
versus selected-usage identity, ambiguous identity, nonfleet compatibility,
custom/duplicate/unknown homes, SQLite pairing, explicit profile routing and error
distinctions. A small isolated executable compiled from the actual launch helper
proves ProcessInfo readback after removal without changing the test runner environment.
No live account switching, Keychain reads or provider probes are verification steps.

Hosted CI runs required checks and both complete native shards. Extend the existing
Jones menu candidate workflow's path triggers to package this app/menu change;
retain its arm64 identity, signature verification, storage gate and seven-day artifact
retention. The laptop's limited storage precludes a cold full Swift build.
<!-- codex-section:end id="spec.system-account-switching#ctx.test-plan.001" -->

<!-- codex-section:begin id="spec.system-account-switching#ac.delivery.001" -->
## Stop, Recovery, And Delivery Boundaries

Deliver the ordinary PR with current green required checks, merge under the
repository's expected-head policy, and install the verified Jones candidate after
a graceful quit. Retain the prior exact bundle and preserve preferences. Verify
the installed bundle and running executable/source stamp. A source/test pass does
not establish that a live credential switch occurred. Stop replacement on identity,
signature, source, ownership, storage or prior-effect uncertainty. Stock CodexBar,
provider CLI updates, credential copying tests, public signing and release are outside
this repair's scope.
<!-- codex-section:end id="spec.system-account-switching#ac.delivery.001" -->
