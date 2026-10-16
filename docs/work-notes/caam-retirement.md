# Work Note — CAAM Retirement

Artifact Type: `work-note`

Artifact ID: `worknote.caam-retirement`

Purpose: Preserve source identity, compatibility decisions, and bounded verification evidence for CAAM removal.

Governing artifact: `spec.caam-retirement`

Continuity owner: root coordinator

Consumers: integration owner and native verifier

Authority effect: none

## Identity and scope

Section ID: `worknote.caam-retirement#identity`

Starting revision: `948ab2fb1777e57f7d751df48bbd0e2bf90726ee`.

Worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/remove-caam-20261016`.

Branch: `work/remove-caam-20261016`. Initial status was clean. Root is sole Git owner. The builder has not staged, committed, switched branches, published, installed, invoked live status/login, read credentials or private configuration, or elevated privileges. The sibling Authfleet/System lane uses a different physical worktree; shared integration paths are `PreferencesProvidersPane.swift` and `CodexProviderConfig.swift`. This lane removes only their CAAM coupling and does not change System activation semantics.

Registration: `registration_unavailable`. This child has a collaboration task identity but no authoritative full native T3 thread ID supplied for registry enrollment. No registration request was sent, and no identity was guessed. Root retains native continuity. No additional agents were spawned under the capsule's explicit prohibition.

## Decisions and comment dispositions

Section ID: `worknote.caam-retirement#decisions`

The removed module included app controls/coordinator/settings, core process/protocol/receipt code, and integration-only tests. Generic observability now consumes independent service and account observations. Local account rows use cached native projection and order; explicit row IDs keep duplicate display labels distinct without establishing account correlation. Netdata host identities and generic cost/usage/work evidence remain independent.

The legacy field is retained as uninterpreted generic extension JSON, never accessed by an active CAAM type. Its synthetic test deliberately supplies a shape the removed typed schema would not accept and verifies native profile/order values plus exact JSON round-trip equality.

Comment dispositions: **delete** obsolete CAAM-only code comments with the retired implementation and localization headings for deleted controls; **keep near code** protected no-cross-account-correlation, distinct-ledger, bounded-work, and no-disk-cache-read invariants, correcting the last wording from CAAM account to specific account; **move to durable context** the historical integration history through archival banners and this compatibility note. No uncertain protected comment was discarded. No structural-replacement disposition is claimed.

Retained CAAM mentions are historical documentation/tool provenance, retirement tests/notes, and the inert JSON fixture key. No active shipped Swift source or localization key refers to CAAM. Contracts and old work notes remain historical evidence, explicitly superseded where they described active integration. The deferred review ledger was neither opened nor modified.

## Verification

Section ID: `worknote.caam-retirement#verification`

The unchanged `Scripts/test_caam_retirement.py` SHA-256 is `05bad21e00bc31b0151ff25a7b10541dd907af297ce544c7c932de331d55ef22`. On the starting production tree at the revision above, `python3 Scripts/test_caam_retirement.py` failed with 17 active shipped Swift references. The same command and script passed after removal. This is valid source-absence red/green evidence, not native semantic execution.

The locale checker was renamed with its unit-test caller; no workflow references required edits. Its outside-root test now creates a simulated repository and sibling fixture beneath its owned temporary directory, preserving the rejection assertion regardless of where TMPDIR is placed.

The new Swift tests cover inert legacy decoding and distinct local row identity. Existing hub tests now use independent fixtures and retain provider cost/usage, unavailable metrics, correlation, freshness, lazy work, and Netdata assertions. Architecture-gate line anchors move with unchanged constructs, fingerprints, and reasons; no broader suppression is added. No CAAM-specific architecture allowances existed at the base.

Portable checks ran serially with `PYTHONDONTWRITEBYTECODE=1` and TMPDIR under a context-managed `.build/caam-retirement-checks-*` root, removed on completion. The final admission sample was CPU 2.18% used, 41.56 GiB RAM available, one full core 6.25% of host capacity, allowing one serial test process.

Native execution remains unavailable because this host lacks Swift and macOS frameworks. Native UI rendering, compilation, runtime behavior, complete locale parser checks, and PR CI remain unverified; no deployment was attempted.

Executed final results:

| Check | Result |
| --- | --- |
| `python3 Scripts/test_caam_retirement.py` | PASS, 1 source-absence test; unchanged red/green script hash above. |
| `python3 Scripts/test_check_observability_locales.py` | PASS, 5 tests. |
| `python3 Scripts/check_observability_locales.py` | PASS, 80 feature keys across 23 catalogs, matching placeholders. Native-language review remains unverified. |
| Existing SwiftFormat 0.61.1 `--lint` on all 11 surviving touched Swift files | PASS, zero files need formatting. |
| Exact Preferences architecture anchor readback | PASS, all 9 existing anchors match current lines; 8 line numbers updated. |
| `git diff --check` | PASS. |
| `make test` | Unavailable, exit 2: Swift executable absent during discovery, zero selections executed. |
| `make check` | Unavailable, exit 2: initial locale gate requires missing `plutil`; later gates did not execute. No tool installation occurred. |
| Combined native affected selector below | Unavailable, exit 127: `swift: command not found`. |

```sh
CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 CODEXBAR_TEST_CODEX_FILE_ISOLATION=1 CODEXBAR_TEST_SESSION_FILE_ISOLATION=1 swift test --filter 'CAAMRetirementLinuxTests|ObservabilityHubLinuxTests|NetdataObservabilityBridgeLinuxTests|ProviderArchitectureGatekeeperTests|LocalizationLanguageCatalogTests|CodexVisibleAccountTests|CodexActiveSourceConfigTests|ManagedCodexAccountCoordinatorTests|ManagedCodexAccountServiceTests|CodexLoginRunnerTests|CodexAccountsSectionStateTests|StatusMenuCodexSwitcherPresentationTests|SyncModelTests'
```

The final selector attempt used a fresh admission sample: CPU 7.86%, 41.54 GiB available, one core 6.25%, one serial process permitted. The native verification limitation applies to both affected groups; full discovery is also unavailable.

Unchanged discovery contract SHA-256 identities:

- `Package.swift`: `0c9205e8d55cc3425362bde5d558d4a9b5385da7855ede962da3c83cd3d41721`
- `Scripts/test.sh`: `93b24b44e0e358d62cfff688a9e627f9f54410f9524173c30b3830acf5378c26`
- `Scripts/ci_swift_test_by_suite.py`: `1dac48724ca04b4260bbb01971bf8a5730a5f3cdde6ea07b4e3f1dfde18ca7bc`

## Exact handoff paths

Section ID: `worknote.caam-retirement#handoff`

Uncommitted source/test/script candidate digest: `1e0cc7c6635f220c72cc5e3290abe231225a07a66280ac510a5838eda1c17abb`. It hashes sorted records of relative path, NUL, and file SHA-256 (or `deleted`), joined by newline; documentation is excluded to avoid self-reference. Starting HEAD remains unchanged. Root owns staging/integration.

- `README.md`
- `Scripts/check_caam_observability_locales.py`
- `Scripts/check_observability_locales.py`
- `Scripts/test_caam_retirement.py`
- `Scripts/test_check_caam_observability_locales.py`
- `Scripts/test_check_observability_locales.py`
- `Sources/CodexBar/CAAMEnvironmentControlsView.swift`
- `Sources/CodexBar/CAAMEnvironmentCoordinator.swift`
- `Sources/CodexBar/CodexObservabilityHubView.swift`
- `Sources/CodexBar/PreferencesCodexEnvironmentsSection.swift`
- `Sources/CodexBar/PreferencesProvidersPane+Observability.swift`
- `Sources/CodexBar/PreferencesProvidersPane+Testing.swift`
- `Sources/CodexBar/PreferencesProvidersPane.swift`
- `Sources/CodexBar/Resources/ar.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/ca.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/de.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/en.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/es.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/fa.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/fr.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/gl.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/id.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/it.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/ja.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/ko.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/nl.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/pl.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/pt-BR.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/ru.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/sv.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/th.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/tr.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/uk.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/vi.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/zh-Hans.lproj/Localizable.strings`
- `Sources/CodexBar/Resources/zh-Hant.lproj/Localizable.strings`
- `Sources/CodexBar/SettingsStore+CAAMEnvironments.swift`
- `Sources/CodexBarCore/Observability/ObservabilityHub.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMControlModels.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMControlSession.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMControlValidation.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMEnvironmentClient.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMEnvironmentModels.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMEnvironmentValidation.swift`
- `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMOperationReceiptStore.swift`
- `Sources/CodexBarCore/Providers/Codex/CodexProviderConfig.swift`
- `Tests/CodexBarTests/CAAMEnvironmentCoordinatorTests.swift`
- `Tests/CodexBarTests/CAAMEnvironmentSettingsTests.swift`
- `Tests/CodexBarTests/LocalizationLanguageCatalogTests.swift`
- `Tests/CodexBarTests/ProviderArchitectureGatekeeperTests.swift`
- `TestsLinux/CAAMControlFixtures.swift`
- `TestsLinux/CAAMControlSessionLinuxTests.swift`
- `TestsLinux/CAAMControlTransportLinuxTests.swift`
- `TestsLinux/CAAMEnvironmentClientLinuxTests.swift`
- `TestsLinux/CAAMEnvironmentContractLinuxTests.swift`
- `TestsLinux/CAAMOperationReceiptLinuxTests.swift`
- `TestsLinux/CAAMRetirementLinuxTests.swift`
- `TestsLinux/NetdataObservabilityBridgeLinuxTests.swift`
- `TestsLinux/ObservabilityHubLinuxTests.swift`
- `docs/FORK_QUICK_START.md`
- `docs/contracts/caam-codexbar-control-v1.md`
- `docs/engineering-specs/caam-environment-control.md`
- `docs/engineering-specs/caam-retirement.md`
- `docs/work-notes/caam-environment-control.md`
- `docs/work-notes/caam-retirement.md`
- `docs/work-notes/netdata-observability-bridge-20261002.md`
