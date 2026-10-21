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

The proposed red pacing tick remains a separate review mock. Do not add its
calculation, settings or rendering to production in this change.
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
adapters and focused tests. Root owns this specification, the Work Note, UI
documentation, all shared generated/build/test state, Git and delivery. The
pacing mock lives in the original V3 task worktree and has no production writer.
Stop on unowned edits, identity ambiguity that would inflate capacity, unsafe
fixture access, failed required checks or unknown Git/runtime effects.
