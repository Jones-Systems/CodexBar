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

Resolve quota identity from existing snapshots only. Codex identity combines
normalized workspace/account ID and email to distinguish seats in one workspace;
Claude uses its provider account identity with normalized email/organization
fallback. A repeated verified identity counts once. Unresolved identity, absent
row, loading or failed retained snapshot contributes unknown capacity rather
than another account. No credential, account or filesystem reads are added.

Use the same rounded headroom percentage that the compact rows show, including
their limiting windows. Do not call this Weekly or imply a fungible token budget.
Sum known contributions over the fixed selected denominator. Partial totals use
lower-bound notation and `k of N reporting`; no reporting uses an unavailable
state or suppresses the summary rather than displaying a confirmed zero.
Show the aggregate only in supported fleet account-list presentations, not
unrelated switcher, token-account or provider layouts without roster evidence.

The owner has now approved production pacing. Add a red 2-point-wide,
8-point-high tick centered vertically over the existing 4-point meter. This
reduces the mock's marker height by one-third; preserve the summary's text,
padding and overall row height. Keep the tick red when highlighted.

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
