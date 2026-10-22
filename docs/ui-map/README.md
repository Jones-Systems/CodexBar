---
summary: "Partial inventory of CodexBar reset timing views and fixture journeys."
read_when:
  - Changing menu-bar or account-list reset presentation
---

# CodexBar UI map

This partial map covers the reset timing surfaces changed by the banked-reset
display update. Settings, provider cards, widgets, and other menu journeys have
not been inventoried. Start with the [development guide](../DEVELOPMENT.md) for
build and isolated-test prerequisites.

| View | Entry points and states | Source and shared consumers |
| --- | --- | --- |
| [Reset timing](reset-timing.md) | Menu-bar reset display and compact account rows; weekly reset, earlier banked expiry, unavailable timing, quota warning, and error | Status-item rendering, stored layout preview, compact account menu, and Overview |

Source discovery alone does not verify an installed app. Each entry records its
bounded fixture checks and any remaining interaction gaps.
