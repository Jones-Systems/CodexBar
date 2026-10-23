---
summary: "Jones About-pane update states and their source contracts."
read_when:
  - Changing Jones update status, preferences, or restart behavior
---

# Jones installation and update views

This partial map covers Settings → About for Jones builds. The ordinary upstream
controller and channel selector keep their existing behavior. The Jones pane uses
the sealed package's display name, source revision and channel, with a link to
the canonical Jones repository. The version includes the monotonic Jones build.

| State | Visible behavior | Action and next state |
| --- | --- | --- |
| Bootstrap channel | Manual installation; updates are not configured | Use the verified-candidate install route in the [guide](../jones/INSTALL-AND-UPDATES.md) |
| Invalid trust configuration | Update source could not be verified | Replace with a verified Jones candidate; no network check starts |
| Idle / up to date | Ready to check, or up to date | Check for Updates, enabled only when Sparkle can check |
| Checking / downloading / preparing | Distinct progress text; offered build where known | Sparkle handles download and validation; downloaded alone is never ready |
| Prepared, automatic updates enabled | Installs when idle or at quit; explicit restart action | Apply only at eligible idle, user restart, or normal quit |
| Prepared, automatic updates disabled | Still installs at quit; explicit restart action | Turning the preference off does not revoke Sparkle's prepared installation |
| Installing | Installing offered build | Restart/relaunch and later bundle readback establish completion |
| Capacity or download failure | Storage requirement or retry/reinstall explanation | Correct the condition and check again; failed state does not expose a stale restart handler |

The automatic-update switch controls both Sparkle checks and downloads. Jones
channel selection is package-owned; the upstream beta preference cannot redirect
the Jones feed. Source text can be selected for exact revision readback.

Source owners:

- `PreferencesAboutPane.swift` and `Jones/JonesUpdatePresentation.swift` render
  the states. The 23 locale catalogs carry their user-facing strings.
- `Jones/JonesUpdateController.swift` projects prepared readiness into existing
  `UpdateStatus.isUpdateReady`, shared by the status-menu action and width cache.
  Those menu consumers are unchanged by this work.
- `CodexbarApp.swift` supplies account-operation, refresh, menu, window and HID
  idle observations. The shared TTY registry contributes a read-only busy snapshot.
- `Jones/JonesUpdateApplyPolicy.swift` denies idle installation for unknown or
  busy inputs. User inactivity is a courtesy condition, not the safety proof.

Verification covers typed trust, state transitions, stale callback rejection,
disk admission and idle eligibility through focused `JonesUpdate*Tests`, plus
the TTY registry's launch-reservation test. The updater-only harness exercises
the real Sparkle replacement path under a separate packaged identity; it never
opens Settings or initializes providers.

These source and fixture references are not a claim of native visual or installed
verification. The delivery record must identify the exact candidate and observed
About-pane state after an authorized installation. No screenshot or live provider
content is required to prove these metadata-only states.
