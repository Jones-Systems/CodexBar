---
summary: "Reset countdown, banked credit expiry, and compact account timing verification."
read_when:
  - Verifying reset selection, colors, or refresh boundaries
---

# Reset timing

The menu-bar reset display helps identify the next relevant deadline without
opening the menu. Codex banked reset credits are optional-use inventory with an
expiry date; an expiry is not a prediction that the provider will refill quota.

## Surfaces and consumers

- `StatusItemController+MenuBarLayout.swift` supplies the stored layout renderer.
  `MenuBarLayoutRenderer.swift` renders reset tokens; `MenuBarLayoutEditor.swift`
  also previews these layouts.
- Legacy menu-bar reset-time and exhausted-quota rendering live in the status
  item controller. `StatusItemController+CountdownRefresh.swift` schedules text
  refreshes and deadline changes.
- `Jones/JonesCompactAccountPresentation.swift` supplies account reset details.
  Compact account menus and Overview share the compact account row component.

The menu-bar percentage and countdown retain normal menu-bar text color and the
existing layout font size. An available Codex credit expiring before the displayed
quota reset supplies the countdown and the same hourglass symbol used by the
layout editor's Runs out chip, configured at the surrounding text's point size.
The attachment scales the configured symbol's natural canvas to 80% in both
dimensions and centers it on the text's cap height. The existing countdown
formatter keeps `h` and `m`.
Expired credits do not control the display. Healthy left account-list reset labels
use secondary text; actual account errors retain error styling. The right-hand
banked expiry clock, countdown and count use orange beyond 24 hours and red at or
within 24 hours; selection highlighting preserves the menu's selected text color.

Expanded Codex and Claude quota metrics show the forecast first, then the pace
balance, then the existing settings clock symbol and the quota reset weekday/time:
`Runs out in 1d 5m · 19% in deficit · [clock] Thu 3:00 PM`. Each metric uses its own
rate window's actual reset, independently of estimated depletion and credit expiry.
Missing or elapsed resets omit the clock detail. Reset timing remains visible when
pace is hidden, and the existing header countdown remains available. Other providers
retain their existing metadata order.

The footnote retains the standard font, neutral/selected colors and two-line wrapping;
accessibility identifies the clock detail as the reset time. Weekday/time uses
America/New_York with daylight-saving conversion, without calendar dates or a timezone
suffix. Aggregate Runs out labels and timing help also omit the timezone suffix.

## Reproducible journeys

Run commands from the repository root, with the toolchain and isolation described
under [Run Tests Only](../DEVELOPMENT.md#run-tests-only). The provided runner owns
its synthetic fixture parent and drains its processes before cleanup. Do not
import a real account or change shared defaults to manufacture these states.

| Entry point | Initial state, action, and observable result | Coverage boundary |
| --- | --- | --- |
| Menu-bar reset display | Use synthetic quota windows and reset credits. Render with weekly reset later than the credit expiry; verify the earlier countdown and trailing hourglass. Repeat with later, expired, and absent credits. | Model/renderer fixtures; installed menu-bar interaction requires separate observation. |
| Countdown refresh | Advance the injected clock through the 24-hour boundary and credit expiry; verify account-row urgency and menu-bar fallback to the quota reset or next eligible credit. | Deterministic clock checks, without waiting on wall time. |
| Compact account menu | Supply a healthy account with low remaining quota and a dated reset. Verify neutral left reset detail alongside quota severity, and orange/red right-hand banked expiry details. Supply an actual account error and preserve its error indication. | Shared presentation/component checks; account activation is outside this task. |
| Expanded Codex and Claude | Supply synthetic session and weekly windows with distinct reset dates. Verify forecast, pace balance and clock weekday/time order; hide pace and preserve the reset; compare normal and selected rows at 314 points. | `MenuCardMetricTimingTests`, `MetricTextUpdateLayoutTests`, and model/layout checks; installed navigation and live provider data require separate observation. |
| Overview and layout editor | These consume the same row and reset renderer. Verify shared data propagation; opening every settings/Overview entry remains unverified unless explicitly captured. | Shared-component coverage does not prove all navigation paths. |

## Evidence

Native AppKit/SwiftUI fixture captures use a synthetic account, a fixed clock,
340-point-wide light-appearance canvases, and the actual menu title renderer and
compact account row. They do not capture the installed app or prove navigation,
live account state, or automatic refresh by themselves.

Before, at source `e4dd4d051818f00a5d84e1b5865428c581f112f6`, the title
ignores the earlier credit expiry and the healthy account reset label is red:

![Before: 4% in 4d 15h](../screenshots/reset-display-before-menu-bar.png)

![Before: red reset label beneath a healthy synthetic account](../screenshots/reset-display-before-account-row.png)

The following historical captures predate the 80% hourglass adjustment. With the
same synthetic account and deadlines, they show banked expiry and a trailing
hourglass in normal menu-bar color; the account percentage and urgent expiry remain red:

![After: 4% with a neutral five-hour credit countdown and text-sized hourglass](../screenshots/reset-display-after-menu-bar.png)

![After: neutral left reset label, with percentage and urgent right expiry red](../screenshots/reset-display-after-account-row.png)

A separate 50%-remaining fixture shows that a deadline beyond a day also keeps normal menu-bar color:

![Neutral menu-bar deadline beyond a day with a trailing hourglass](../screenshots/reset-display-orange-menu-bar.png)

The task pull request records the exact source candidate, isolated test results,
native fixture captures, and their limitations. The owner-supplied before images
illustrate the reported behavior but are not a synthetic baseline. Never present
an HTML mockup as a capture of the native app. No live provider or credential
probe is needed for these checks.

For native expanded-card captures, set `CODEXBAR_CLOCK_RESET_CAPTURE_DIR` to a
task-owned directory under `.build` and run the isolated focused tests. This exports
`codex-expanded.png`, `codex-selected.png`, `claude-expanded.png`, and
`claude-selected.png` from the production SwiftUI usage section with synthetic data.
These are component captures, not installed-app screenshots. The current candidate's
PR records whether these captures and required local checks were available.
The existing macOS CI test shards also export these synthetic captures and the
tested checkout commit in `reset-timing-<commit>-<shard>` artifacts retained for
seven days. Each job creates its own capture root outside the build cache,
uploads evidence even on failure, then removes and checks absence of that root.
The capture upload does not change test selection or add another build.

Map guidance: `Jones-Systems/Frontend-Development` revision
`3a1f6935061597c2d4bfaabac9387d4b83874ee1`, UI view maps. This map is partial;
other provider cards, settings navigation, widgets, and accessibility text-size
variants remain outside its verified coverage.
