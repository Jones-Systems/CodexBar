# Authfleet System Account copy — fork ledger delta

Authority effect: none. This ledger records source ownership; native qualification
and installation are bound to the exact PR and installed-build delivery records.

This delta is bound to Jones-Systems/CodexBar task base
`e6837457ce42e0d1782e8c5b4399280277975e2d`. Upstream identity is
`steipete/CodexBar`; this task does not establish a new upstream import or change
product identity. Root owns integration with the fork's broader ledger. The
separate PR12 identity work and its ledger are outside this delta.

Feature: established Authfleet profiles remain usage sources and also carry a
typed System Account copy target. Canonical credentials stay in their fleet home.
No enrollment, login, binding parser, refresh daemon, launcher, or identity overlay
is introduced.

Fork-owned additions:

- `Sources/CodexBarCore/Jones/JonesCodexAppLaunchEnvironment.swift`: app-entry normalization of uniquely enrolled inherited homes; explicit profile and CLI routing remain separate.
- `Tests/CodexBarTests/JonesCodexAppLaunchEnvironmentTests.swift`: pure environment policy, explicit profile routing and distinct refusal messages.
- `Sources/CodexBarCore/Jones/JonesCodexSystemPromotionTarget.swift`: typed managed/fleet provenance and captured identity.
- `Sources/CodexBar/Jones/JonesCodexFleetPromotionAdmission.swift`: fresh membership, identity, default-home and preservation-path admission; prepared target sum type.
- `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionTests.swift`: copy, separate homes, queued changes, absence, override and cancellation tests.
- `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionBoundaryTests.swift`: preservation/failure, identity, repeated admission, default-home and alias tests.
- `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionMenuTests.swift`: usage/system distinction, typed menu payload, activation and distinct profile targets.
- `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionTestSupport.swift`: synthetic membership, auth-read, snapshot, selection and home seams.

Existing shared-source hooks use `JONES(fleet-system-promotion)`. This table
accounts for this delta; it does not reclassify unrelated historical fork edits.

| Exact hook path | Hook and reason |
| --- | --- |
| `Sources/CodexBar/CodexbarApp.swift` | `JONES(fleet-system-promotion)` normalizes a verified inherited fleet home before application consumers initialize; smoke/hook exits remain earlier. |
| `Sources/CodexBarCore/Providers/Codex/CodexVisibleAccountProjection.swift` | Carry the optional typed promotion target; construct it only from fleet-proven profile rows. Managed ID fallback preserves existing callers. |
| `Sources/CodexBar/Providers/Codex/CodexProviderImplementation.swift` | Enable System Account entries from typed targets using the named roster and friendly labels when enrolled. |
| `Sources/CodexBar/MenuDescriptor.swift` | Replace UUID-only action payload with typed target. |
| `Sources/CodexBar/StatusItemController+MenuActionMapping.swift` | Preserve the target in `representedObject`. |
| `Sources/CodexBar/StatusItemController+Actions.swift` | Decode the typed target and call the existing coordinator. |
| `Sources/CodexBar/CodexAccountPromotionCoordinator.swift` | Typed entry point retains interaction/drain gates; managed wrapper and existing labels remain. Map new refusal errors. |
| `Sources/CodexBar/CodexAccountPromotionService.swift` | Inject admission; share writer and swap pipeline; report actual target; fleet copies cannot take managed convergence shortcuts. |
| `Sources/CodexBar/CodexAccountPromotionPreparation.swift` | Prepare typed fleet material with direct identity validation after admission; keep existing managed preparation. |
| `Sources/CodexBar/CodexAccountPromotionPlanning.swift` | Exclude a managed target ID only when present. |
| `Sources/CodexBar/CodexAccountPromotionExecution.swift` | Optional managed exclusion ID plus protected-home guards at import, repair, refresh and cleanup boundaries. Existing transaction/swap semantics remain. |
| `Tests/CodexBarTests/CodexAccountPromotionTestSupport.swift` | Synthetic fleet-home creation and injected admission/default destination; dictionary-backed defaults. |
| `Tests/CodexBarTests/CodexSystemPromotionUITests.swift` | Extend existing cancelled-login drain test to both target kinds; update managed typed-menu expectation. |

Directly affected compatibility test edits:

- `Tests/CodexBarTests/CodexAccountPromotionPreparationTests.swift`: unwrap the managed arm before existing identity/home-state assertions.
- `Tests/CodexBarTests/CodexAccountPromotionExecutionTests.swift`: unwrap the managed arm for the existing self-overwrite rejection test.

The service/preparation/execution integration necessarily touches existing state
flow rather than copying that subsystem into Jones code. Fork decisions and path
checks reside in the two Jones helpers; existing preservation and atomic auth-file
swap helpers remain the executor. No broad extraction, dependencies, resources,
localization sweep, auth symlinks, or package/trial-identity hooks were added.

Affected native suites: `JonesCodexFleetPromotionTests`,
`JonesCodexFleetPromotionBoundaryTests`, `JonesCodexFleetPromotionMenuTests`,
`CodexAccountPromotionPreparationTests`, `CodexAccountPromotionPlanningTests`,
`CodexAccountPromotionExecutionTests`, `CodexAccountPromotionServiceTests`,
`CodexSystemPromotionUITests`, `CodexFleetProfileIntegrationTests`, and
`CodexVisibleAccountTests` and `CodexVisibleAccountProjectionRuntimeIdentityTests`. Suite execution remains unproved here.

System Account presentation/launch repair is based on canonical
`dd23db9c61065e35bb8855777f82b33e8f232a57`; its scope and invariants are recorded in
[the repair spec](../engineering-specs/system-account-switching.md).
