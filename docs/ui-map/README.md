---
summary: "Partial inventory of CodexBar reset timing and Jones update views."
read_when:
  - Changing menu-bar or account-list reset presentation
  - Changing Jones update status and preferences
---

# CodexBar UI map

This partial map covers reset timing and the Jones update section of About.
Other settings, provider cards, widgets, and menu journeys have not been
inventoried. Start with the [development guide](../DEVELOPMENT.md) for
build and isolated-test prerequisites.

| View | Entry points and states | Source and shared consumers |
| --- | --- | --- |
| [Reset timing](reset-timing.md) | Menu-bar reset display and compact account rows; weekly reset, earlier banked expiry, unavailable timing, quota warning, and error | Status-item rendering, stored layout preview, compact account menu, and Overview |
| [Jones updates](updates.md) | Settings → About; bootstrap, checking, downloading, preparing, ready, installing, and failure | Jones updater controller, menu readiness projection, packaged trust and source metadata |

Source discovery alone does not verify an installed app. Each entry records its
bounded fixture checks and any remaining interaction gaps.
