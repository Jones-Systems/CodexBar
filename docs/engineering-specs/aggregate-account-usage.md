# Engineering Spec — Aggregate Account Usage

<!-- codex-section:begin id="spec.aggregate-account-usage#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.aggregate-account-usage`

Purpose: Show selected-account remaining headroom without duplicate capacity.

Governing artifact: owner-approved aggregate summary mock A

Specification owner: M Jones

Integration owner: Codex root

Consumers: CodexBar menu builder and verification owner

Authority effect: none
<!-- codex-section:end id="spec.aggregate-account-usage#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.aggregate-account-usage#req.behavior.001" -->
## Required behavior

Add mock A's compact `Total remaining` row beneath the account list on the Codex
and native Claude tabs and beneath each provider's account list on Overview.
Show a mini meter, normalized percentage, reporting count, and summed remaining
percentage together with its denominator. Do not add a cross-provider total.

Codex selects only the fleet aliases `malcolm`, `jace`, `umich`, `steven`, and
`wallace`, representing the owner's Malcolm, JC, Umesh, Steven and Wallace.
Its denominator remains 500%. Claude selects `default` and `jace`, representing
the two selected Claude accounts, with denominator 200%. Enrollment metadata
binds each allowed alias to its profile; an additional enrolled alias, system
default, managed account, or token account must not add capacity. Presentation
labels never establish identity. Preserve existing label preferences.

Resolve quota identity from provider-bound snapshots. Codex identity combines
normalized workspace/account ID and email to distinguish seats in one workspace;
Claude uses its provider account identity with normalized email/organization
fallback. A repeated verified identity counts once. Unresolved identity, absent
row, loading or failed retained snapshot contributes unknown capacity rather
than another account. The selected native Claude fetch reuses its prompt-free
Claude-owned plaintext profile UUID lookup before and after transport. A stable
UUID enriches OAuth usage with no email; a changed or conflicting UUID must not
publish a relabeled reading. Agents do not inspect real profile or credential
contents, and the presentation adds no account or filesystem reads.

Use the same rounded headroom percentage that the compact rows show, including
their limiting windows. Do not call this Weekly or imply a fungible token budget.
Sum known contributions over the fixed selected denominator. Partial totals use
lower-bound notation and `k of N reporting`; no reporting uses an unavailable
state or suppresses the summary rather than displaying a confirmed zero.
Show the aggregate only in supported fleet account-list presentations, not
unrelated switcher, token-account or provider layouts without roster evidence.

The owner has now approved production pacing. Add a 2-point-wide,
8-point-high tick centered vertically over the existing 4-point meter. This
reduces the mock's marker height by one-third; preserve the summary's text,
padding and collapsed row height. The tick uses the native pace colors: green
when remaining exceeds the time-based target, red when below it, and neutral
on pace. Highlighted content uses the existing selection contrast treatment.

For every selected, distinct reporting account, compute on-pace remaining
from the same limiting usage window that supplies its actual headroom. Use
each window's own duration and reset; never average reset timestamps. Sum the
rounded per-account targets over the unchanged 500% or 200% denominator. Only
show an exact marker when every selected slot reports and has valid timing.
Missing, expired, out-of-range or nonpositive timing hides the marker. A
limiting monthly-credit window without a duration also hides it. When multiple
windows tie at the raw minimum headroom, prefer the valid timed window with the
latest reset, retaining planner order for equal resets. Preserve partial totals
and reporting counts; accessibility describes the target or pacing unavailability.

Codex account-menu presentations must exclude the live/default source and any
source-defined default fleet alias. Arbitrary user labels do not establish a
default source. Render the named accounts together in one Personal section,
without workspace headings or workspace discriminators. Preserve all original
quota identity and routing metadata internally.

Minimized Overview summaries for Codex and native Claude use the selected
account's display name with existing personal-information redaction. A hidden
live Codex source may map to a named row only through one unique verified
identity match. Use that same presentation identity for the summary label and
the additional-row exclusion, avoiding duplicate named rows. If no unique named
counterpart exists, omit the redundant Codex summary while retaining named
account rows and their aggregate; never invent an account name or expose default.
<!-- codex-section:end id="spec.aggregate-account-usage#req.behavior.001" -->

<!-- codex-section:begin id="spec.aggregate-account-usage#dec.boundaries.001" -->
## Implementation boundaries

Reuse existing fleet enrollment and cached display snapshots, projecting fleet
profile paths into the core visible-account projection when needed. Keep the
aggregate calculation pure and the hosted row presentation shared between
provider tabs and Overview. Provider-specific adapters supply distinct identity
and roster shapes. No new persisted state, refresh timers, network calls,
background work or authentication operations are needed.

Direct consumers are the compact Codex menu, native Claude menu and Overview
fleet rows; source searches identify their menu render signatures and height
fingerprints as indirect consumers. Preserve other providers and existing menu
actions. Add the summary to any affected render/height identity so totals update
with their inputs. New projection fields keep compatible constructor defaults.
No migration is required; source rollback removes the added presentation.

The production pacing consultation applies `UsagePace.weekly` with each limiting
window's explicit duration and the existing workday setting. Historical forecasts
and the per-card text visibility thresholds do not define this even-use target.
The generic aggregate remains labeled remaining rather than Weekly because its
limiting windows can differ. The approved tick is added without changing visible
summary labels or adding settings.

Core `AccountMenuLayoutPlanner` owns eligible-window selection, including unknown
usage and synthetic-placeholder exclusions. Expose its tied limiting windows as
an additive read-only API rather than duplicating that selection in the app.
Existing headroom and compact-row results remain compatible. The app aggregate
owns per-account pacing, distinct identity counting and fixed denominators.
Factories accept an injected time and workday setting with compatible defaults.
Direct consumers remain the compact Codex menu, Claude native menu, Overview and
aggregate tests. The source investigation also identifies segmented pickers,
stacked fallback sections, current-card labels and summary exclusion as consumers
of the shared account display model. No persisted state or migration is introduced.

Compute targets at menu construction using the same time as nearby account
details. Reuse normal menu/store refresh behavior. Keep time-varying pacing out of
the existing height/readiness fingerprint: the overlay does not change geometry,
and a continuously changing signature would repeatedly rebuild the menu.
Raw projection/source selection is preserved; only the shared display projection
filters defaults and resolves a unique named active presentation identity.

The technical consultation proposed using all enrolled aliases. This spec
instead follows the owner's explicit selected-account scope and fixed 500%
concept, excluding every extra alias. Failure snapshots are excluded using
the existing error state; no independently invented cache-age policy is added.
<!-- codex-section:end id="spec.aggregate-account-usage#dec.boundaries.001" -->

<!-- codex-section:begin id="spec.aggregate-account-usage#ac.verification.001" -->
## Acceptance and verification

- The sample 98, 59, 97, 24, 79 yields 357% / 500% and 71.4%.
- An absent or failed Umesh reading yields a 260% / 500% lower bound and 4/5.
- Default aliases, extra enrolled aliases and duplicate credentials cannot inflate
  capacity. Distinct email seats sharing one workspace remain distinct.
- Claude default/Jace yields a 200% denominator; unresolved identities remain unknown.
- Synthetic weekly targets yield 400% / 500% (80%) for Codex and 150% / 200% (75%)
  for Claude. Mixed durations prove per-account timing rather than averaged resets.
- Pace tests cover limiting session/extra windows, tied limits, workday settings,
  missing/expired/out-of-range timing, credits without duration, failed or duplicate
  accounts, unchanged actual totals, and a stable height/readiness fingerprint.
- A distinct sixth live default is excluded from stacked, segmented and Overview
  account presentation independently of deduplication. A verified named counterpart
  appears once; ambiguous identities do not create a guessed or default summary.
- One Personal section preserves original account metadata. Minimized Codex/Claude
  names honor display labels and privacy redaction; existing interactions remain.
- Preserve displayed rounding and limiting-window semantics. Test missing
  enrollment, loading, retained-error snapshots and duplicate identities.
- Menu fixtures prove placement after accounts, before storage/Plan Usage, on
  provider tabs and within both Overview sections. Render identity includes totals.
- Use only synthetic fixtures. Root owns build/test/lint state and runs focused
  tests, required `make test` and `make check` with fresh host admission.
- Publish one non-draft PR and qualify exact-head CI under target `AGENTS.md`.
  Continue its accepted merge and Jones-only local app update with retained rollback.
<!-- codex-section:end id="spec.aggregate-account-usage#ac.verification.001" -->

## Sequencing and ownership

One builder owns the aggregate model/view, projection propagation, three menu
adapters, shared account-display repairs and focused tests. Root owns this
specification, the Work Note, UI documentation, all shared generated/build/test
state, architecture-anchor updates, Git and delivery. Source writes pause during
root's failing-before and final verification runs. The original pacing mock is
retained in the V3 worktree; the approved production marker is 8 points high.
Stop on unowned edits, identity ambiguity that would inflate capacity, unsafe
fixture access, failed required checks or unknown Git/runtime effects.

<!-- codex-section:begin id="spec.aggregate-account-usage#req.disclosure.001" -->
## Expandable pacing details

Clicking Total remaining expands details in place, on both provider pages and
both Overview sections. Clicking again collapses it; closing the menu session
resets disclosure state. This reuses existing menu interaction, invalidation,
weak capture and session ownership. No new window, timer or persisted preference
is required. Dedicated Claude native account lists start with one Personal
heading using the existing section styling.

The signed balance is summed actual remaining minus summed target remaining,
measured in raw account percentage points. With 340% remaining and a 320% target,
Codex has +20 points out of its 500% capacity, not +4 points. Positive is reserve
and green; negative is deficit and red; zero is on pace and neutral. Exact
balance requires every selected slot and valid timing, as does the exact marker.
Partial actual totals remain lower bounds with their original denominator.

Estimate exhaustion from the current combined rate: sum each controlling
window's used percentage divided by elapsed pace time, including already-empty
accounts, then divide summed remaining by that rate. This assumes demand can
move between selected accounts. Never claim this is a pooled token balance.
Show the approximate date/time and first reset, with an explicit no-refill
qualification when that reset precedes the estimate. Do not simulate speculative
refills or promise an actual exhaustion date after reset. Zero observed activity
has no finite estimate; all-zero remaining reports exhausted now. Partial,
missing, invalid or too-early timing reports unavailable rather than fabricated
precision. Windows with nonzero usage need at least 3% elapsed for an estimate.

Use the existing workday schedule when every controlling window is weekly;
mixed durations use one common wall-clock basis. Any additive core rate fields
must retain defaults and preserve historical and existing per-window outputs.
Workday-to-wall-clock conversion is bounded to avoid an unbounded walk. Calendar
injection makes tests deterministic. Clock labels use America/New_York and the
seasonally correct EST/EDT abbreviation; localizable durations need no zone.

Expanded text exposes balance, target, approximate exhaustion and next reset
without emails or raw account IDs. Keep required values readable at normal
menu width. Accessibility identifies the row as a button, conveys expanded
state, and includes detail text. Height fingerprints include disclosure and
line-shape state, excluding changing clock text and identity material.

The strict Codex presentation roster activates with recognized enrolled fleet
homes. Only unambiguous normalized .profileHome matches for the five approved
aliases are admitted, independently of usage or authentication health. Internal
projection, routing and authentication remain intact. Generic nonfleet layouts
retain their existing behavior outside the supported fleet integration.
<!-- codex-section:end id="spec.aggregate-account-usage#req.disclosure.001" -->

<!-- codex-section:begin id="spec.aggregate-account-usage#iface.follow-up-boundaries.001" -->
## Follow-up ownership and verification boundaries

Root owns Git, documents, build state and delivery. Independent bounded writers
own roster presentation, Claude fetch identity and disclosure/core pace source,
with no overlapping active scopes. The source research covers native profile
fetch, aggregate construction and the dedicated/Overview/picker consumers at
the follow-up base. Impact coverage is partial for this named universe; external
consumers of additive core APIs are not exhaustively inventoried, so full native
suite discovery and the repository's Linux CI remain required. No storage,
configuration, credential, account-selection or installation-identity migration
is introduced. The retained previous Jones bundle supplies installation rollback.

Affected checks cover native OAuth nil-identity enrichment, stable/missing/changed
UUIDs and duplicate identities; five-slot admission with managed/nonfleet/default
extras and privacy; raw +20/500 and deficit/neutral/partial balances; forecast
before/after reset, zero activity, all-zero, too early, mixed clocks and workday
weekends; click enablement, toggle, idle reset, height shape and Claude heading.
Preserve existing quota, source-ownership and menu assertions. New fixture scratch
uses the existing isolated test runner and contained synthetic homes. Core and
menu changes receive make check, make test, final-head CI and native component
renders. A component render is not proof of installed account data or live
provider availability; installed process/build identity is verified separately.
<!-- codex-section:end id="spec.aggregate-account-usage#iface.follow-up-boundaries.001" -->
