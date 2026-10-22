---
summary: "Weekly and five-hour reset timing in compact Claude account rows."
read_when:
  - Verifying compact Claude reset placement or missing-window behavior
---

# Compact Claude reset timing

The second line of a collapsed Claude account pairs its weekly reset on the left
with its five-hour session reset on the right. Both use the configured reset-time
style and existing compact account typography. The session reset is ordinary
muted timing, without Codex's banked-credit count, clock inventory or urgency.

## Entry points and shared consumers

`JonesCompactAccountPresentation.claudeRowDetail` supplies the shared
`MenuCardCompactAccountRowView`. The dedicated Claude account list, Overview
account list, and minimized selected-account summary all consume these details.
The same component preserves Codex banked credit expiry, count and urgency.
This map is partial; expanded provider cards and account switching are outside
this change.

## Reproducible checks

Use synthetic dated session and weekly windows through
`JonesCompactAccountPresentationTests`, using the isolated runner documented in
[development](../DEVELOPMENT.md#run-tests-only). Verify both reset styles,
weekly-only, session-only, placeholder and error states. No real provider,
credential, shared preference or account reset is needed.

| Initial state and action | Observable result | Evidence boundary |
| --- | --- | --- |
| Collapse a synthetic Claude account with both windows | Weekly timing stays left; five-hour timing stays right on the same detail line | Presentation assertions; native layout capture remains separate |
| Remove either window or replace it with a synthetic placeholder | The other valid timing remains on its own side; no missing reset is invented | Deterministic model cases |
| Return an account error | Error handling remains intact; no stale timing appears | Existing error guard and regression cases |
| Supply a Codex account with banked reset credits | Existing count, clock and urgency remain available | Codex regression coverage |

Candidate verification runs on GitHub-hosted macOS runners. Local compilation,
local tests and local fixture captures are intentionally not run under the
owner's laptop resource restriction. Source discovery is not installed-app or
navigation proof. The pull request records current-head CI evidence and any
remaining native capture gaps.

Guidance: `Jones-Systems/Frontend-Development` at
`3a1f6935061597c2d4bfaabac9387d4b83874ee1`, UI view maps.
