---
summary: "Menu bar UI, icon rendering, and menu layout details."
read_when:
  - Changing menu layout, icon rendering, or UI copy
  - Updating menu card or provider-specific UI
---

# UI & icon

## Settings
- Usage & Spend heatmap tooltips prefer the space above the hovered cell and stay within the grid, falling below when needed. On narrow grids they compact vertically and may overlap cells; keyboard selection remains available in the daily grid.
- Both the application menu and status menu open About in the Settings window. An existing Settings window is reused
  and switches to the About pane.

## Menu bar
- LSUIElement app: no Dock icon; status item uses custom NSImage.
- Merge Icons toggle combines providers into one status item with a switcher.
- Provider status items use stable autosave names and are reused across provider toggles so macOS can preserve icon
  positions.
- When Overview has selected providers, the switcher includes an Overview tab that renders up to 6 provider rows.
- Overview row order follows provider order; selecting a row jumps to that provider detail card.
- The global open-menu keyboard shortcut toggles the currently tracked menu closed before opening a new one.
- Display → Menu Bar → Layout provides presets plus a token editor. Tokens can be clicked to append, dragged from the
  palette, reordered between one or two lines, dragged out, or removed with Delete. Layouts can be global or overridden
  per provider. Manual edits select the Custom preset.
- All providers previews the default layout and lists enabled providers with saved overrides, even when an override
  currently matches the default. Each “Use all-providers layout” action removes only that provider's override;
  global edits preserve overrides, and disabled providers are left untouched. Before a default is first saved,
  editing still starts from the representative provider's effective layout.
- Small/Regular controls the token font scale. Tight/Regular controls status-item padding. Compact stacked uses two
  tightly spaced lines sized to fit the menu bar.

### Layout tokens

| Group | Tokens | Behavior |
| --- | --- | --- |
| Identity | Icon, Provider name, Account | Provider-scoped branding and identity |
| Usage | Session %, Weekly %, Scoped weekly %, Auto %, Usage bar | Window percentage or a compact three-glyph usage bar |
| Usage | Session pace, Weekly pace, Auto pace | Signed pace delta for that window |
| Time | Resets in, Reset at, Runs out | Relative reset, absolute reset, or pace estimate |
| Money | Balance, Cost today, Cost 30d | OpenRouter credit balance, or local cost estimate for the selected period |
| Structure | Separator dot, Space, Line break | Spacing and optional two-line composition |

The pace tokens render the same delta the menu card shows as "in deficit"/"in reserve", in the compact signed form the
pre-0.45 **Both** display mode used: `+11%` means usage runs that far ahead of the sustainable rate, `-8%` that far
behind it, `0%` on pace. Each pace token reads its own window, so `Weekly pace` never borrows the session delta — unlike
`Runs out`, which always estimates from the weekly (or automatic) lane. A pace token renders an en dash while pace is
unavailable, including the first 3% of a window. The weekly menu-bar pace token may appear after 1% of its weekly
window has elapsed; session, automatic, and Runs out tokens keep the 3% threshold. See [Pace tracking](#pace-tracking).

Balance is available only for OpenRouter and renders the same remaining-credit value shown in its menu card. Auto %
uses the same provider-aware automatic-window resolution as the legacy menu bar metric setting. If a snapshot
does not provide a token's data, that token renders an en dash while its siblings remain visible. Existing installs
derive their first layout from the prior style, display mode, metric, and reset settings; those legacy keys remain
untouched for downgrade safety, while a saved token layout takes precedence.

Scoped weekly % selects the most constrained active model-specific weekly carve-out. The editor keeps a stable,
model-generic token label while the rendered menu-bar prefix and accessibility label follow the active model title.

## Icon rendering
- 18×18 template image.
- Bar windows are provider/style-specific primary and secondary windows.
- Fill represents percent remaining by default; “Show usage as used” flips to percent used.
- Renderer/critter icons dim when last refresh failed and can render incident indicators; brand display mode uses provider branding plus title text.
- Loading animation runs at a bounded frame rate and has a hard continuous-duration ceiling so provider hangs cannot keep
  the menu bar redrawing forever.
- The token renderer composes provider branding and text through the same attributed-title path used for high-contrast
  status items. Critter and bar styles keep their existing renderers.

## Menu card
- Provider-specific rows with resets (countdown by default; optional absolute clock display). Primary, secondary,
  tertiary, and extra windows render when the provider snapshot has data for them.
- Manual refresh updates the open card subtitle and persistent Refresh-row spinner in place. Repeated clicks share the
  active request, and the existing row geometry remains fixed through success or failure.
- Live pace and metric detail text use the full row width. Updates that exceed the space reserved when the menu opened
  show a trailing ellipsis; reopening the menu measures the updated text again.
- Codex credits can add a separate “Buy Credits…” menu action.
- Claude capped Extra Usage follows the used/remaining fill preference; spending amounts and “% used” copy stay unchanged.
- Codex OpenAI web extras: code review remaining and usage breakdown render when dashboard data is attached.
- Token accounts: optional account switcher bar or stacked account cards (up to 6) when multiple manual tokens exist.
- Token/cost, credit-usage breakdown, credits-history, and plan-history chart date labels retain their full text width
  in narrow menus. Credits and plan history reserve plot-edge space to avoid clipping; token/cost and usage-breakdown
  charts retain their automatic scale range. Shared styling uses a
  bar-centered anchor, and each chart retains its own date formatting, domain, and tick-selection behavior.
- Provider storage usage is opt-in from Advanced settings. When enabled, overview rows and provider detail cards can show
  local provider-owned storage totals, with a submenu for path breakdowns and copyable paths.

## Selected-account aggregate

The fleet account lists end with a shared **Total remaining** row on Codex,
native Claude, and each corresponding Overview section. The meter and normalized
percentage use the full selected pool; the second line shows reporting count and
the sum together with its denominator. Codex selects Malcolm, Jace, Umich, Steven
and Wallace (500%); Claude selects its default and Jace profiles (200%). Display
label overrides do not change selection. Extra default/system/token accounts do
not add capacity, and matching verified quota identities count only once.

The figure is equal-weight account headroom using each compact row's rounded,
limiting-window percentage, not a pooled token or monetary balance. A failed,
unresolved or missing reading leaves the fixed denominator intact and produces
a lower-bound total with `k of N reporting`. No reading is not confirmed zero.
The aggregate pacing tick is 2 points wide and 8 points tall, centered over
the 4-point meter. Each account's target uses its own limiting window and reset;
those rounded targets are summed over the same fixed denominator as actual
headroom. Existing workday settings apply to weekly windows. An incomplete pool
or missing valid timing hides the exact marker while retaining the actual total
and reporting count. Accessibility describes the target or its unavailability.
The overlay leaves the collapsed row's text, padding and height unchanged.
It is green for reserve, red for deficit and neutral on pace, using the native
pace and selection colors. Clicking Total remaining expands its signed balance
in raw account percentage points, target, approximate current-rate exhaustion
and next reset. Codex's +20 points is out of 500%, not +4% normalized. An estimate
past the first reset explicitly excludes refills; missing or too-early timing
has no precise estimate. Zero activity does not imply an exhaustion date.

Supported fleet Codex account menus admit only the five unambiguous enrolled
profile homes; live/default, managed and extra profile rows are excluded.
Named Codex and native Claude accounts each share one Personal section;
verified workspace identities remain part of routing and quota deduplication.
Minimized Overview summaries use the selected Codex or Claude account's display
name and existing personal-information redaction. A hidden live Codex source is
represented by a named account only when their verified identities match uniquely.
An unresolved match leaves the named rows and aggregate visible without an extra
current-account summary.

### Partial menu view map

This map covers only the selected-account summary consumers, not every native
view. Source discovery alone does not verify an installed build.

| View and entry | Expected state and placement | Shared consumer and source check |
| --- | --- | --- |
| CodexBar Jones menu → Codex, supported fleet account list | One Personal section, no default row or workspace headings; total follows accounts before storage or Plan Usage; partial readings retain /500 | Shared Codex account display and compact renderer; `OverviewFleetAccountsTests`, `StatusMenuCodexSwitcherPresentationTests` |
| CodexBar Jones menu → Claude, native fleet profiles | Personal heading; total follows the two profile rows; partial readings retain /200; centered pacing marker requires both accounts' timing | Compact account renderer; `StatusMenuClaudeNativeProfileAccountsTests`, `JonesAccountAggregateTests` |
| Merge Icons → Overview with Codex and Claude selected | Minimized summaries show selected account names with privacy redaction, without duplicate or default rows; each section ends in its own total | Overview fleet renderer; `OverviewFleetAccountsTests` |
| Each Total remaining row → click, click again, close and reopen | In-place pace disclosure toggles independently; required raw balance and approximate time remain readable; idle session resets expansion | Aggregate row, menu interaction and Overview expansion state; native disclosure and aggregate regressions |

Use synthetic fleet-discovery and account-snapshot fixtures for the named suites,
through the isolated test runner documented in [development](DEVELOPMENT.md#run-tests-only).
Their owning runner allocates and drains fixture scratch; no live account reset,
credential access or shared preference reset is part of this journey. A native
check requires the freshly built Jones bundle, account lists already populated
by normal owner operation, and a visible menu-bar icon. Open the menu, select
each tab, and observe the stated placements and reporting counts. Closing the
menu ends the journey; preserve any captures before fixture cleanup. Installed
native entry points remain unverified until explicit candidate-bound evidence
is recorded in the [work note](work-notes/aggregate-account-usage.md).

## Pace tracking

Pace compares your actual usage against the expected consumption rate for the current window. Most providers use an even-consumption budget; Codex can use historical pace data when historical tracking is available.

The **Work days** setting selects the weekly pace model. **Automatic** uses Codex historical pace when enough data is available. Selecting 4, 5, or 7 days uses that explicit schedule for pace and ETA instead; CodexBar continues collecting history in the background, but does not use historical predictions until the setting returns to Automatic.

- **On pace** – usage matches the expected rate.
- **X% in deficit** – you're consuming faster than the even rate; at this pace you'll run out before the window resets.
- **X% in reserve** – you're consuming slower than the even rate; you have headroom to spare.

When usage is in deficit, the right-hand label shows an estimated "Runs out in …" countdown. When usage will last until the reset, it shows "Lasts until reset".

Pace is calculated for any provider window with enough reset timing data and is hidden when less than 3% of the
window has elapsed. The weekly menu-bar pace token is the one exception: it may appear after 1% of the weekly
window has elapsed, including when Codex historical tracking predicts less than 1% usage. Session, automatic, and
Runs out tokens remain hidden until 3% of their window has elapsed.

## Preferences notes
- Advanced: “Disable Keychain access” turns off browser cookie import; paste Cookie headers manually in Providers.
- Advanced: “Show provider storage usage” enables background scans of known provider-owned local paths; CodexBar only
  reports sizes and cleanup ideas, it does not delete files.
- Display: “Overview tab providers” controls which providers appear in Merge Icons → Overview (up to 6).
- If no providers are selected for Overview, the Overview tab is hidden.
- Providers → Claude: “Avoid Keychain prompts” selects the Security.framework reader's `Never prompt` policy.
- The lower-level “Keychain prompt policy” picker remains visible as the source of truth for Claude OAuth prompts.

## Widgets (high level)
- Widgets render shared usage snapshots for the supported widget families and
  provider picker; detailed pipeline in `docs/widgets.md`.

See also: `docs/widgets.md`.
