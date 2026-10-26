# Codex and Claude Product

Artifact ID: spec.slim-codex-claude-product
Kind: Engineering Spec
Authority effect: none
Owner: CodexBar product implementation coordinator

<!-- codex-section:begin spec.slim-codex-claude-product#scope -->
## Scope and compatibility

Ship only Codex and Claude provider implementations. Delete other provider source,
provider plugins and their JavaScript engines, hooks, iCloud transport and their
feature-only tests. Git history at `91bd5fb4af704da9181212bea636d527a058e615`
retains the removed implementation for deliberate restoration.

Preserve current usage, quota/reset tracking, account switching and authentication,
provider identity isolation, SPEND/history, local scanning and cache integrity,
shared TTY/process cleanup and cancellation, widgets, and fleet/local identity.
Do not reduce scanner limits or persistence regressions. Persisted configurations
containing removed provider/plugin entries must decode fail-soft, without mapping
their identities or credentials onto Codex or Claude. Obsolete hooks/sync settings
must be inert. No migration reads real credentials or private configuration.
<!-- codex-section:end spec.slim-codex-claude-product#scope -->

<!-- codex-section:begin spec.slim-codex-claude-product#architecture -->
## Source-bound architecture and impact

`Providers/Providers.swift` closes `UsageProvider` to Codex/Claude; both
`ProviderManifest` and the app's `ProviderImplementationManifest` must change with
it because the registry requires metadata for every enum case. Keep shared PTY,
process and cookie capabilities used by these providers regardless of old names.

Remove `CodexBarCore/Plugins`, its bundled JavaScript resources and `CQuickJS`,
then remove their Package.swift target, dependency and JavaScriptCore linkage.
Crypto remains required by managed Codex accounts and CLI authentication;
SweetCookieKit remains required by both retained descriptors. Remove hook command
entry points/config behavior, provider-specific renderer/settings branches and
plugin commands. Preserve unknown JSON extension handling where needed to read
old files safely; do not retain executable plugin behavior.

Remove CloudKit sync transport/coordinator and its app lifecycle wiring. Retain or
relocate shared account/menu/fleet identity models that happen to live in `Sync`.
Keep the shared provider-instance availability predicate independent of removed
plugin ownership: classify an instance as Codex/Claude before delegating to the
unchanged availability/environment policy; reject unknown IDs without aliasing.
Remove deleted-provider-only startup calls without restoring those providers.
Source-level architecture changes affect app, core, CLI and widget consumers, so
all applicable platform compiler jobs remain required. The CI sibling authored
compile-once sharding. Root transferred patch01 and then the exact qualified PR40
source plus frozen seven-path patch02 to this coordinator for task-branch integration.
Root retains CI watching, hosted qualification and remote PR merge coordination.

`swift-build-macos` builds/discovers once; both existing shards verify the same-run
artifact and execute only `--skip-build`, with no compilation fallback. Preserve
`ci_swift_test_artifact.py` and `ci_swift_test_native.py` identity, manifest, archive,
native-fingerprint, cleanup and provenance checks. Patch02 removes the obsolete
JSC option/engine wrapper and its four wrapper-only tests; the full-profile test
continues proving discovery, one skipped-build execution and owned cleanup.
The daily 05:00 America/New_York normal-profile schedule, separate concurrency,
producer/shard/aggregate gates and normal/full selector identities remain intact.
Scheduling takes effect only after default-branch integration. The Work Note and
comparison record identify the qualified source, frozen bytes and narrow adaptations.
<!-- codex-section:end spec.slim-codex-claude-product#architecture -->

<!-- codex-section:begin spec.slim-codex-claude-product#verification -->
## Verification and evidence

Remove tests only with deleted product behavior; preserve shared account,
privacy/isolation, quota, cost scanner, persistence and TTY cleanup cases. Update
mixed suites to assert the retained two-provider contract and add synthetic old
config regression coverage. Normal/full membership must reference existing source.
Claude local accounting retains Vertex metadata classification and explicit scanner
filters even though the Vertex provider product is removed. Test compilation
closure must preserve both inclusion/exclusion cases, exact rows/tokens/costs,
cache/deduplication assertions and scale fixtures under the Claude identity.
Synthetic screenshot inputs use distinct Codex/Claude IDs. Pure history fixture
helpers stay nonisolated; actor annotations must follow actual actor-owned state.
Feature-only test removals receive a per-method reason in the Work Note/comparison;
changes to formerly exact cost blobs receive method-level preservation evidence.
For Swift Testing property-access macro failures, materialize the unchanged
nonoptional collection expression before asserting its property; preserve the
filter/tuple predicate and expectation rather than changing the tested contract.
Mixed-provider fixtures must retain distinct provider/scope keys after removal.
Standalone menu fixtures must represent a supported state without the history
cluster; keep both standalone separators and normal grouped-history assertions.
Menu fixtures must distinguish plain first-refresh row activation from generic
history submenus. Use public selection edits for explicit-empty overview state
below the provider limit; preserve exact provider identities, navigation tags,
deferred rebuilds and stale viewport-restore protections.
Overview summary activation preserves account expansion for both retained
providers; use the provider switcher for navigation proofs and verify native
action delivery. Preserve generic unknown-window policy separately from retained
provider whitelists, plus saved-history fallback without a current snapshot.
Highest-usage fixtures must select a supported retained-provider metric explicitly
when replacing a retired provider's lane policy; retain ranking and exhaustion
assertions without changing Codex/Claude defaults or enabled-instance isolation.
SPEND retention fixtures distinguish source IDs from provider IDs: three source
roles can use a scoped Codex account alongside Codex/Claude without duplicate
dictionary keys. Preserve cross-provider auth-rotation isolation, independent
failure retention and account/provider ownership invalidation; keep strict input
uniqueness in product dictionaries.
Generic duration-based history proofs use the existing direct component and
persistence seam with explicit synthetic account scope. Keep both saved series,
values and provider/account isolation; production Claude retains fixed lane roles
and its stricter identity policy.

SPEND subscription identity and model identity are separate contracts: source
rows retain account-scoped IDs, while model rows aggregate by provider/model.
Partial-pricing fixtures must use distinct retained provider/model keys to preserve
same-name cross-provider rows; a scoped Codex account can supply the third
subscription beside priced Codex and unpriced Claude. Keep known/nil totals,
all-unpriced unavailability, row cardinality, token conservation and presentation.
Do not change production model grouping to preserve an invalid migrated fixture.

Extra-usage fixtures must preserve retained-provider display policy: Claude
uses currency for the extra-usage preference and automatic quota fallback uses
primary before secondary. Shared percent/combined formatting can be proved with
the actual extra-usage rate window without restoring the removed Cursor-only
controller exception. Check explicit quota-versus-spend preference switching and
missing-cost fallback with both present-primary and absent-primary states.

Derived percentage guards allow only a justified binary64 rounding bound;
keep exact user-facing text expectations and fail closed for missing/nonfinite
values. Do not round production accounting/quota values to satisfy a setup guard.

Hosted submenu release fixtures must distinguish populated chart providers from
providers with no scoped cost data. Preserve native link/unavailable row identity
across full close while releasing only actual hosted views; do not turn seeded
chart data into an unavailable expectation when retiring a provider fixture.

Switcher geometry fixtures cover overview plus every retained provider with
visible, bounded quota bars. Distinguish the supported three-segment inline
height from obsolete larger provider inventories; quota presence must not be
inferred solely from row height or weakened to fit missing bars.

Account-override fixtures use retained-provider manual-cookie prerequisites,
then prove explicit account precedence over a distinct saved selection without
mutating provider settings or account IDs. Preserve disabled cross-provider
cookie policy and fail-closed credential behavior with memory-only stores and
explicit startup isolation; retired mode-forcing policy is not a Claude default.

Run `make check` and `make test`; report missing local Swift/formatter tools as
unavailable. Use the shared nonblocking benchmark lock and fresh CPU/RAM admission
before local test starts. Hosted macOS/Linux compilation and isolated tests must
prove the complete source removal. A final focused bulk correctness review checks
removed versus retained behavior. Record source/test counts at the exact base and
candidate revisions. Linux SwiftLint and macOS SwiftFormat are distinct checks;
Linux success alone cannot qualify the producer's pinned formatter gate. Formatting
repairs preserve literals, assertions, test inventories and scale limits, with
explicit source dispositions for redundant effects/returns and hoisted try. Native
formatter/compiler results remain required when local tools are unavailable.
Binary/bundle size and cold-build comparisons require exact,
comparable hosted artifacts; source counts are not size or speed forecasts.
<!-- codex-section:end spec.slim-codex-claude-product#verification -->
