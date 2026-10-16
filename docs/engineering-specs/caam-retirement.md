# Engineering Spec — CAAM Retirement

Artifact Type: `engineering-spec`

Artifact ID: `spec.caam-retirement`

Purpose: Remove the retired CAAM integration while preserving native account controls and independent observability.

Governing artifact: owner request carried by the root coordinator

Specification owner: account-auth-controls builder

Integration owner: root coordinator

Consumers: CodexBar builder, verifier, and delivery owner

Authority effect: none

## Scope

Section ID: `spec.caam-retirement#scope`

Remove the app's CAAM configuration controls, coordinator, process transport, protocol models, validation, receipts, and tests that exercise that retired integration. No app startup, settings, model, or transport path may invoke CAAM. Do not modify external CAAM installations or private state. Native Authfleet/profile discovery, managed accounts, account order, login cancellation, Active selection, and System behavior remain intact.

The owner has no custom CodexBar fork installed. This change describes source only and introduces no deployment or live migration.

## Compatibility and observability

Section ID: `spec.caam-retirement#behavior`

Delete the typed `codexCAAMEnvironments` accessor. The existing generic unknown-extension decoder retains legacy JSON without decoding or acting on its former schema. An ordinary future config save can round-trip that inert field through the generic encoder; retirement itself does not read or rewrite any user's configuration.

Keep Overview, Accounts, Systems, and Work. Replace CAAM-derived inventory with independent `HubAccountObservation` and `HubServiceObservation` inputs. The app projects already-cached native visible accounts in their saved order. Native row IDs distinguish equal display labels; they do not establish cross-environment account correlation. The adapter supplies no cross-account stable identity, no observation timestamp, and no claim of healthy authentication. Existing warning evidence may remain a warning.

Systems contains the local Mac and configured Netdata identities. Remote service state and runtime-effective profiles remain unknown without evidence. Existing provider usage/cost caches, unit distinctions, partial/stale evidence, bounded work details, and Netdata caching remain separate. The removal adds no refresh, browser launch, credential read, native process invocation, or System activation.

Current repository evidence is sufficient: source callers, generic config coding, cached account projection, and Netdata bridge interfaces determine this bounded retirement. No external protocol research is needed. The cross-module compatibility boundary is unknown-field preservation; its pure JSON test guards that boundary. No future extraction is a prerequisite.

## Affected checks

Section ID: `spec.caam-retirement#checks`

- `retirement-source`: `python3 Scripts/test_caam_retirement.py` checks all shipped Swift paths and contents for retired integration references.
- `observability-locales`: `python3 Scripts/test_check_observability_locales.py` and `python3 Scripts/check_observability_locales.py` validate the renamed checker, bounded reads, complete feature keys, and format placeholders.
- `native-retirement-observability`: SwiftPM selector `CAAMRetirementLinuxTests|ObservabilityHubLinuxTests|NetdataObservabilityBridgeLinuxTests|ProviderArchitectureGatekeeperTests|LocalizationLanguageCatalogTests`. The new `CAAMRetirementLinuxTests` module is part of this group and the existing `TestsLinux` discovery target. There is no static file-list manifest to update.
- `native-preservation`: existing selector `CodexVisibleAccountTests|CodexActiveSourceConfigTests|ManagedCodexAccountCoordinatorTests|ManagedCodexAccountServiceTests|CodexLoginRunnerTests|CodexAccountsSectionStateTests|StatusMenuCodexSwitcherPresentationTests|SyncModelTests`; profile discovery remains covered by existing discovery suites in the repository's full discovery.
- Required aggregate gates: `make test`, `make check`; targeted SwiftFormat lint on surviving touched Swift files; `git diff --check`.

Native tests are pure synthetic fixtures. New retirement coverage uses in-memory JSON and creates no scratch. Portable checker tests use task-owned temporary roots with context-managed cleanup on success and failure; no shared temporary root or private configuration is used. No native test success or installed-app behavior is inferred from static source checks.
