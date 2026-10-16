# Account recovery and ambient login drain

Artifact ID: work-note.account-recovery-drain
Kind: Work Note
Authority effect: none
Status: source implementation complete; native validation unavailable; ownership RELEASED to root
Updated: 2026-10-16 07:25:10 PM EDT

## Task binding and authority

- Worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/account-recovery-drain-20261016`.
- Branch: `work/account-recovery-drain-20261016`.
- Base/unchanged HEAD: `0f842d7f26edcd1a1fff886409291ef9b4f846b6`; initially clean.
- Builder: implementation sub-agent, Frontier Astra/high, `explicit_workstream` revision 0. No children or shared preference writes.
- Root remains sole Git/index/publication/merge owner. This builder made source/test edits and this note only; no staging, commits, branch mutation, checkout, publication, or merge.
- Direct owner approval relayed in the assignment: **“Authorize both fixes and eligible merges.”** This authorizes implementation of both recorded P2 findings. Eligible merge execution remains with root; no merge readiness is asserted here.
- CodexV3 backing worktree was read-only. Instructions read: target root `AGENTS.md` (no nested AGENTS found), applicable development/fixture sections, released cross-repository rules and touched comment/scratch guidance. Direct source inspection sufficed for these exact defects; no external research, Graphify query, agent delegation, or install was needed.
- Exclusions preserved: discovery binding/parser, credentials or state on host, CAAM, independent hub, unrelated ordering, package paths, resources, live auth/status/Keychain/private-home inspection, build-sandbox live proof, host/app install, sudo, release. The separate trial-identity worktree was not touched.

## Finding dispositions

Original ledger: `docs/review-evidence/account-fixes-ccafd932.json`, SHA-256 `4218de156c65d72241f8d00eb7f50ef6cc8cd473fd65dd02629f583112ad4a62` (unchanged).
Original reviewed revision: `ccafd932fa8e7f9160ab1dd133677e8d622b45bc`; review ID `account-fixes-review-ccafd932-r1`; source native task `/root/account_fixes_review`, profile `codex-v3-code-reviewer`. No original finding fields were edited or reclassified.

### AFR-001 — original P2

Original blocking effect: “Blocks the specified ability to recover by explicitly selecting another existing account.”
Disposition: authorized source correction implemented, native verification pending.

Removed the reconciliation early-empty return so valid configured profiles, managed metadata, and a live system account remain available for explicit recovery. The resolver still retains the unavailable selected profile, and the existing fetch-unavailable guards remain unchanged. Enumeration is deliberately distinct from fetching the selected account; enumeration can inspect allowed alternative sources without choosing one.

Settings and menu selection now remain available with one surviving alternative and no active visible row. Settings uses an empty selection with an em-dash placeholder; the menu does not highlight a fallback row. Recovery displays an explicit switcher even when the normal preference is stacked cards. Ordinary selected-account layouts and ordering remain unchanged. No new localized error strings or resource edits.

Added/updated synthetic coverage for one/two surviving configured profiles, explicit reselection, managed/live alternatives, unreadable-store recovery, settings selection, both menu layout preferences, and the actual sole-row click path. The prior test forbidding all reconciliation enumeration was replaced because that expectation directly caused AFR-001; selected-fetch isolation was strengthened with zero credential-I/O and zero CLI-resolver/launch-path counter assertions instead.

### AFR-002 — original P2

Original blocking effect: “Blocks cancellation/retry correctness for the shared ambient Codex home.”
Disposition: authorized source correction implemented, native verification pending.

The promotion coordinator now owns the live authentication task and its generation. Cancel changes the requested UI state immediately but retains the task and promotion exclusion. A retry retains and waits for the previous attempt, including a cancelled queued predecessor. Completion of an older generation cannot clear a newer attempt, and cancelled results cannot produce success UI.

A shared MainActor FIFO writer gate covers settings ambient login, the separate menu ambient login entry point, and direct promotion-service calls. Promotion acquires before reading its preparation context and releases with `defer`; queued cancelled work checks cancellation before reads/writes. This serializes app-owned shared-home operations across coordinators, not merely UI generations. The existing runner already terminates and `waitUntilExit()` reaps its owned process before returning; its two-second grace and managed-home cleanup behavior were not changed. No claim covers unrelated external writers.

Added deterministic fake-runner completion gates and a shared-writer overlap recorder. Tests cover cancel–retry–cancel–retry, stale success suppression, retained promotion blocking, direct service promotion waiting for drain, and cancellation while queued with zero runner launches. They use readiness handshakes with a bounded two-second observation budget, explicitly release continuations, and drain every task before fixture teardown. Managed same/different-account retry cleanup tests remain unchanged and are included in the native follow-up scope.

## Checks and limitations

- `make test`: **unavailable**, exit 2. Discovery attempted `swift`, which raised `FileNotFoundError: [Errno 2] No such file or directory: 'swift'`. Zero selections discovered/executed. No native red/green result exists; failing-before execution was unavailable for the same reason. Source-before evidence is the deleted early-empty snapshot branch and cancellation's deleted immediate handle/gate clear.
- `make check`: **unavailable**, exit 2 at the first locale check: `spawnSync plutil ENOENT`. This stopped before any lint-tool installer. No tool was installed. SwiftLint/SourceKit/native UI verification were unavailable, not passed.
- `../caam-environments/.build/lint-tools/bin/swiftformat --lint <all 17 Swift paths in the manifest below>`: **passed**, SwiftFormat 0.61.1, `0/17 files require formatting`. Initial formatting findings in five files were fixed with the same formatter limited to this manifest. This is formatting/parser evidence, not Swift type-checking or behavioral execution.
- `git diff --check`: **passed**.
- Ledger byte equality against HEAD and write-cone inspection: **passed**. HEAD/branch unchanged; only the 17 manifest paths and this note are changed.
- No source-text “behavior tests” were added as substitutes for Swift execution; no unrelated portable suite, live probe, or app launch was run.
- Fresh admission snapshots preceded check starts: 23.20% CPU / 43.03 GiB RAM before `make test`; 24.52% / 42.99 GiB before `make check`; 36.99% / 39.78 GiB before final formatting lint. Each allowed one serial test process (CPU <85%). One fully used logical core = 100% process CPU = 6.25% of this host's measured 16-core capacity.
- No test fixture was instantiated here because Swift discovery failed. Native fixture execution should set `TMPDIR` to an invocation-owned workspace directory; existing `CodexCredentialFixtures`/container teardown owns exact fixture cleanup. No shared `/tmp` cleanup or private-home access occurred.

Native follow-up (root/eligible CI): `make test`, `make check`, and affected suites `CodexAccountReconciliationTests`, `CodexProfileHomeAccountTests`, `CodexFleetProfileIntegrationTests`, `CodexAccountsSectionStateTests`, `CodexAccountsSettingsSectionTests`, `CodexAccountMenuDisplaySnapshotTests`, `StatusMenuCodexSwitcherTests`, `CodexSystemPromotionUITests`, `CodexAccountPromotionServiceTests`, `CodexLoginRunnerTests`, `ManagedCodexAccountCoordinatorTests`, and `ManagedCodexAccountServiceTests`. Keep standard fixture/file/Keychain isolation. No trial-ready, installed, independently reviewed, or native behavior-pass claim is made.

## Exact source/test revision and ownership release

This is an uncommitted working-tree revision over the bound HEAD, not a fabricated commit.
Source/test manifest SHA-256: `7170b7ad4b94da9a664c34ec0e10395d898c7b684c5cef1d6ba2deb12e43fe98`.
Source/test diff SHA-256 (`git diff --binary HEAD -- <manifest paths>`): `dc29815f82ad8fc347416b6c49fc17d041fe3057776178914ed42ae39f5fe423`.
Manifest format: SHA-256, two spaces, repo-relative path, LF; sorted by path. The note itself is excluded to avoid a self-referential digest; its digest is returned in the final handoff.

```text
92e7ab91a9c1453b5e2722bc17f4fff5f7a2b463bb9c4a0794b9932bc7b2ab24  Sources/CodexBar/CodexAccountPromotionCoordinator.swift
49fe6349ef653b07dfd69773948f32c801cf46bc1548cd8ffa0eb3d5d075f477  Sources/CodexBar/CodexAccountPromotionService.swift
8793ab461252547c69e5f72229591ea5bb410134de4a2f94e3022d4f6bced8f5  Sources/CodexBar/PreferencesCodexAccountsSection.swift
8078aa7bd7ddff4628d1823ccc93de3bcdc1f5c33761e5686bd86f9f9618bb2f  Sources/CodexBar/PreferencesProvidersPane.swift
2ef860f4fe94a023b6b69eb5ccea37d67c9bdc23c6f23b96da3362811e0fbbab  Sources/CodexBar/Providers/Codex/CodexLoginFlow.swift
0264fc2be05a20c1b44293f22becfd1f357b7f777e8516d8293e529e1d19c353  Sources/CodexBar/StatusItemController+AccountMenuDisplay.swift
651c25918b32be850122692f27fe30838821c3d802de81e694bb68893325eb35  Sources/CodexBar/StatusItemController+SwitcherViews.swift
25206cdb706b0ff45f775c6d30ff96d6d1eae335ea4f73cfd2873883d62ccf62  Sources/CodexBarCore/Providers/Codex/CodexAccountReconciliation.swift
9e0809f2c79a293fc26590e9c3dccf5bebf247ffb23870dda9d7a7acf0660c64  Sources/CodexBarCore/Providers/Codex/CodexVisibleAccountProjection.swift
bb34d33cca88eea85f87d8de7d2b59fbec9f5c2613550a63f86bdd80e6768573  Tests/CodexBarTests/CodexAccountMenuDisplaySnapshotTests.swift
853e856942ec3475a473ceb7d6b67a57caf5385365d0cbae690107f1b18c8492  Tests/CodexBarTests/CodexAccountPromotionTestSupport.swift
2be28e65b6394c450db29539a651219960cbce49f84aaa1475c95aca4f976cb9  Tests/CodexBarTests/CodexAccountReconciliationTests.swift
13de8aa7e0da57e9ef76172d1ab61581af61c8fb0fcad468ca2b9fd155b21c05  Tests/CodexBarTests/CodexAccountsSectionStateTests.swift
74cd8e35bd1e0ee43f73c571be7cc1858400eb263debec4a2fcd869ba2fae1a3  Tests/CodexBarTests/CodexFleetProfileIntegrationTests.swift
2e3059f41ef723fa7a95fb9a529733a1117820edca7ffd1f76dc80ab52f3c372  Tests/CodexBarTests/CodexProfileHomeAccountTests.swift
0d55dfb49fca92847a4b10dc83d49ebab6f45660c194a9d7f8a1d9a2600cd8ad  Tests/CodexBarTests/CodexSystemPromotionUITests.swift
358410bbf82d33bfe4252e37762409a2558789ef76503f7e072026f714909f6b  Tests/CodexBarTests/StatusMenuCodexSwitcherTests.swift
```

**Ownership RELEASE:** all source/test writes complete. Root may verify these exact bytes, stage/commit/publish the scoped changes, merge into PR 11 under its gates, and reconcile trial identity by the separately planned ordinary merge. This builder retains no mutating lane, task, fixture, child process, or Git ownership. Root owns remaining native checks, review/disposition closure, publication, eligible integration, and any separate installation decision.
