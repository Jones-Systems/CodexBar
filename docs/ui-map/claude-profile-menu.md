---
summary: "Native Claude profile menu entry points, states, and isolated verification."
read_when:
  - Changing Claude native profile selection
  - Verifying Claude menu actions
---

# Claude profile menu

This map covers the direct native-profile selector added to the existing menu.
It does not establish complete UI coverage for CodexBar.

## Entry points and consumers

Open the menu bar item, select Claude, then open **Claude profile**. The same
provider action entries are consumed by the overview and SwiftUI fallback menu.
`ClaudeProviderImplementation.appendActionMenuEntries` creates the submenu;
`ClaudeNativeProfileMenuSelection` owns its items and validated selection.
AppKit dispatches through `StatusItemController+Actions`; `MenuContent` handles
the SwiftUI consumer. **Profile settings…** opens existing Claude settings.

## State and behavior

Native-profile mode must be selected. Discovery provides available aliases and
the settings store supplies the saved alias. The current alias has a checkmark.
Duplicate display names include their aliases; personal-info hiding applies to
display labels. A saved alias absent from discovery remains a checked, disabled
**Unavailable saved profile** row. Empty discovery adds **No available profiles**.
Other Claude account modes retain their existing actions.

Selecting an available profile persists only the alias. Existing settings
observation invalidates the old fetch and refreshes the account presentation.
Selecting the current alias does nothing. If discovery or mode changes while
the menu is open, selection is rejected and the menu is rebuilt. This controls
the profile shown in CodexBar; it does not promote a different ambient CLI login.

## Verification journeys and evidence

Use `ClaudeNativeProfileAccountsFixture` and in-memory stores. Exercise default
to secondary selection, current selection, stale discovery, changed mode,
duplicate labels, unavailable saved alias, empty discovery, and both action
dispatch paths. `ClaudeNativeProfileMenuSelectionTests` contains synthetic
behavior coverage. Captures must use synthetic identities and the same native
theme and viewport. Never publish the owner's account screenshots or real
profile data. Test and capture results belong to the delivered revision's PR;
this map alone is not a claim that those checks passed.

## Prerequisites and cleanup

Native tests require macOS and the repository's Swift toolchain. Use the capped
isolated test launcher, with no live provider or Keychain access. Fixture scope
restores discovery and removes its synthetic home. Capture output is task-owned
evidence, separate from live settings. No new provider login, preference reset,
or credential migration is required.
