# Work Note — Codex Account Order and Login Cancellation

Artifact Type: `work-note`

Artifact ID: `worknote.account-auth-controls`

Purpose: Carry exact source identity, implementation decisions, and verification gaps for the bounded account-controls slice.

Governing artifact: `spec.account-auth-controls`

Continuity owner: root coordinator

Consumers: root coordinator and native verifier

Authority effect: none

## Identity and ownership

Starting revision: `5f4a4c9474d2c44e136275fe5c42689a6c6e7a56`.

Worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/account-auth-controls-20261016`.

Branch: `work/account-auth-controls-20261016`. Initial status was clean. Root is sole Git owner. The builder did not stage, commit, switch branches, publish, install, invoke login, inspect credentials, or use elevation. The sibling fleet-discovery lane owns its own worktree and settings-loader changes. This lane avoids `CodexSettingsStore.swift` to simplify integration.

Research basis: direct current repository evidence in the settings account view, managed coordinator/service, Codex process runner, account projection/menu ranking, config extension coding, and explicit sync payload. This is bounded source work; no external research or further delegation was needed.

## Implementation

- Added settings arrows and a Codex-specific persisted order, keyed by stable account source rather than changing display IDs. Applied it to settings, segmented menus, stacked/compact account selection, and adjacent workspace sections. Preserved active selection and machine-local sync boundaries.
- Added explicit settings cancellation, owned tasks, generation guards, cancellation-aware login waiting, distinct cancelled outcome, service checks before persistence, and process exit before staged-home cleanup.
- Extended five existing test modules. The retry regression has same-account and different-account cases; it checks no stale store write/callback, no stale busy-state clearing, and unique-home cleanup while the retry remains active.

Comment dispositions: **keep near code** for the new source-identity ordering explanation and process-exit/owned-home lifecycle explanation. Existing provider-silo and side-effect-free menu comments remain true. No unrelated comments were removed.

## Verification

Swift and macOS frameworks are unavailable on this Linux host. There is no valid executed failing-before evidence: the safe native fixture seams exist in source but cannot run with this toolchain. Starting-source inspection identified the uncancellable unstructured runner task and coordinator state that only clears on completion; that inspection is not claimed as a red test.

Focused command attempted after the implementation:

```sh
CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 CODEXBAR_TEST_CODEX_FILE_ISOLATION=1 CODEXBAR_TEST_SESSION_FILE_ISOLATION=1 swift test --filter 'CodexVisibleAccountTests|CodexActiveSourceConfigTests|ManagedCodexAccountCoordinatorTests|ManagedCodexAccountServiceTests|CodexLoginRunnerTests|CodexAccountsSectionStateTests|StatusMenuCodexSwitcherPresentationTests|SyncModelTests'
```

Result: unavailable, exit 127, `swift: command not found`. No Swift tests executed or passed.

Existing SwiftFormat 0.61.1 was used without installing tools. Invocation: `/home/malcolmjones/Projects/CodexBar-worktrees/caam-environments/.build/lint-tools/bin/swiftformat --lint` followed by all 17 changed Swift paths (the Git diff paths plus `Sources/CodexBar/SettingsStore+CodexAccountOrder.swift`). Final result: zero files require formatting. `git diff --check` passes. Every changed Swift line is at most 120 characters.

Existing SwiftLint 0.65.0 invocation: `/home/malcolmjones/Projects/CodexBar-worktrees/caam-environments/.build/lint-tools/bin/swiftlint lint --strict` followed by the same changed Swift paths. Result: unavailable, process exit -4, `Loading libsourcekitdInProc.so failed`. No lint pass is claimed. No new tool installation was attempted.

Telemetry before serial checks admitted one process; samples ranged from 1.56% to 10.49% CPU with at least 41.68 GiB available memory. One fully used core is 6.25% of the measured 16-core capacity.

Affected group IDs are the eight suite names in the focused command above. Discovery contract identity: `Scripts/ci_swift_test_by_suite.py` SHA256 `1dac48724ca04b4260bbb01971bf8a5730a5f3cdde6ea07b4e3f1dfde18ca7bc`; runner `Scripts/test.sh` SHA256 `93b24b44e0e358d62cfff688a9e627f9f54410f9524173c30b3830acf5378c26`; package manifest SHA256 `0c9205e8d55cc3425362bde5d558d4a9b5385da7855ede962da3c83cd3d41721`. No new test module changes the discovery contract. Root owns required final `make test`, `make check`, and combined PR CI.

Candidate source identity: SHA256 `34d15ffefad2382bc089ecec2a850c50203d102fc95a35f0a4e7557041ea0e12`, computed over the sorted 17 changed Swift paths, each UTF-8 path plus NUL, file bytes plus NUL. This identifies the uncommitted source tree, not a commit or executed native test result.

All new filesystem fixtures allocate unique roots and register exact-path deferred cleanup before creating files. The fake-process test cancels and awaits the owned process before cleanup; it has a runner timeout as a second bound. No test artifacts were created here because Swift could not start.

Remaining evidence: native compile/test results, macOS visual/layout proof, and the root's integrated checks. No installed-app fix or live OAuth success is claimed.

Localization expansion authorized by root: appended exactly five translated UI entries to each of 23 existing catalogs. No unrelated catalog entries changed. Bounded Python parsing verified each new key occurs once with a nonempty quoted value in every locale. The native `node Scripts/check-app-locales.mjs` checker is unavailable here (exit 1: `spawnSync plutil ENOENT`), so full catalog validation remains a macOS CI check. Translations have not received native-speaker review.
