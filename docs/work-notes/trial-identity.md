# Trial identity source handoff

Authority effect: none. Source write ownership: **RELEASED to coordinator/root**.
Completed 2026-10-16 07:24:02 PM EDT. No background work or agents remain in this lane.

## Binding and authority

- Worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/trial-identity-20261016`.
- Branch: `work/codexbar-trial-identity-20261016`.
- HEAD/base: `0f842d7f26edcd1a1fff886409291ef9b4f846b6`, unchanged.
- Task: `spec.codexbar-upstream-isolation#task.trial-identity.001` and the six
  contract/requirement/acceptance/test/context/default sections named in the capsule,
  read at Codex V3 revision `e71609aae0c2be1e2809c8438b1df789c4d260eb`.
- Explicit Frontier Astra/high workstream; resolved preference source
  `explicit_workstream`, revision 0. No shared preference writes.
- Coordinator/root remains sole Git/index owner. No staging, commit, branch,
  reset, cleanup, push, PR or merge operation performed by this lane.
- Codex V3 backing worktree remained read-only. No sibling edits or new agents.
- No real overlay read, live auth/status/login/refresh, credential/Keychain/config
  read, laptop command, sudo, install, sign, notarize, launch, release or workflow edit.
  The existing mocked-signing fixture invokes only its local `codesign` stub.

## Candidate result

Recovered the owned interrupted 46-file candidate rather than restarting it.
Preserved the optional overlay, identity/state hooks, injective full-service
namespace and existing widget team wiring. Added seven pure Swift behavior tests,
a complete writable-path/gate manifest and final synthetic packaging proof.

Recovery corrections: plist interpolation defaults preserve the existing isolated
plist fixture; explicit nil config identity no longer falls through a global
identity hook; the overlay Claude probe creation-error path cannot return shared
TEMP. Only the original 46 tracked paths were edited; all six new files are in
the approved cone. `docs/jones/IDENTITY.md` is the proposed hook/ledger delta;
no old finding ledger or auth protocol logic was edited.

## Verification

| Check | Result |
| --- | --- |
| `bash Scripts/test_jones_identity_overlay.sh` | PASS, 27 checks; actual identity function/templates, 12 byte-identical no-overlay outputs versus pinned base and recorded hashes, overlay variants, iCloud fragment, widget metadata via fixture PlistBuddy, invalid inputs and re-sign guard |
| `bash Scripts/test_package_info_plist.sh` | PASS, original fixture now works with no identity initialization; fixture HOME/TMPDIR |
| `bash Scripts/test_package_signing.sh` | PASS, fixture stub only; no real signing |
| SwiftFormat 0.61.1 on 45 scoped Swift files | Format completed; final `--lint --cache ignore` PASS, 0/45 require formatting |
| `bash -n` on each of the three changed/new shell scripts | PASS |
| `git diff --check` | PASS |
| Writer-cone/marker/readback check | PASS, 46 tracked modifications + 6 new files; HEAD unchanged, index empty; every tracked source/script has JONES marker, `.gitignore` exact-pattern exception documented |
| `PYTHONDONTWRITEBYTECODE=1 make test` | UNAVAILABLE/exit 2 at discovery: `FileNotFoundError: swift`; zero discovered/executed selections |
| `swift test --filter JonesStateRootTests` | UNRUN: same missing Swift toolchain; seven tests supplied, no typecheck/native-pass claim |
| `make check` | NOT RUN: inspected recipe invokes tool installers and broader checks; no installations authorized. `make -n check` confirms `./Scripts/lint.sh lint`. Scoped formatter/syntax/portable fixtures are partial evidence only. |
| Native `plutil`, Xcode/widget/package/runtime checks | UNAVAILABLE here; not replaced by fixture proof |

A fresh telemetry snapshot preceded each test/format start. Observed CPU was
6.23–20.56% and available RAM 42.47–43.86 GiB; one full logical core is 6.25%
of host capacity. Each snapshot admitted one serial test process. No overlapping
test command ran. Workspace-owned Python context-managed fixtures were removed
and absence read back; no shared `/tmp` material was created or cleaned.
The helpers handle normal exit, failure and TERM/INT/HUP; abrupt kill/host failure
cannot execute cleanup. Swift tests use a virtual filesystem and in-memory defaults.

Native follow-up, only in an authorized environment with the required toolchain:

```sh
CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 \
CODEXBAR_TEST_CODEX_FILE_ISOLATION=1 \
CODEXBAR_TEST_SESSION_FILE_ISOLATION=1 \
swift test --filter JonesStateRootTests
```

Repository `make test`/`make check` and native macOS qualification remain due;
no static check-group manifest exists in this target and no Codex V3 integrity
check is relevant to this source candidate.

## Remaining gates

The complete path list and seven gate categories are in `../jones/IDENTITY.md`:
fixed TEMP debug exports; external MiMo tracker; UUID runtime scratch outside the
cone; framework-managed WebKit/network/defaults state needing native proof;
unbundled/copied CLI; explicit overrides and other-tool state; native/release
qualification. These are not silently waived. The trial is **not launch-ready**.
No broad API redesign or further writer expansion was attempted. Real identifier
confirmation, signing, installation and runtime use remain separately held.
AFR001/002 and eligible integration belong to the coordinator/sibling lane; this
handoff neither edits nor re-disposes their findings. PR #11 CI absence is not
native verification. No publication, merge or installed-build claim is made.

## Exact payload manifest

There are 52 candidate paths: these 51 payload files plus this handoff note.
Below are SHA-256 file-byte digests, sorted by repository-relative path. The
payload digest is SHA-256 of these exact `digest + two spaces + path + LF` records
(UTF-8, no code fences): `32deb5e2ab03a46560e2dc258b9965954b747df0d20d3413679a4f0e20b8d327`.
The note excludes itself to avoid a circular digest. The final response supplies
the complete 52-file digest, including this note, using the same algorithm.

```text
d79bd083a825b8cbd31f0f877d6fd7744f5463056b4e740b910adc73606c36f9  .gitignore
5ce9cdf273744c83574cce35dfb5199ec8dcf0196bb85101cbb3bfae647a5df7  .mac-release.jones.env.example
c6aaa708a0aa1b9c6c7b705c517938f3e30399f3aa80349b29d58600c26702d4  Scripts/package_app.sh
c942bd2adf055172c46d69095ecfba4b4f3769b07d231ac81acefdab921d13a8  Scripts/sign-and-notarize.sh
d4328d8f1b5890e3a152835cedc41d57fe0be72550fc58081887dd59ab19f02c  Scripts/test_jones_identity_overlay.sh
3263e5a49d97ede2bb64b498a41dac7e314d99d6645480ca646b653dc07da50f  Sources/CodexBar/CodexAccountUsageSnapshotStore.swift
0bbf6af9adced8876fe22e82412bfe38c05e79b485629fe4d0c264f998989bda  Sources/CodexBar/CookieHeaderStore.swift
ae751e9323bab8033ba87c3850a5940cece763f2ca54c49986e79ac42f42ae34  Sources/CodexBar/CopilotTokenStore.swift
805e4f278b2c31c0182a6687c4781bd041f909bfd00b7c1be5bf9bf3ca003dc9  Sources/CodexBar/HistoricalUsagePace.swift
481e36fa24829d535d71022d9a617881f456318e6d070df00c76ea8aa88c1b38  Sources/CodexBar/KimiTokenStore.swift
2c0a08e1ec4cf6d6ef8a77671de634435b3d563dd3ad1c92acf953e1a6648d2b  Sources/CodexBar/MainThreadHangWatchdog.swift
1ca9f717e9d9fb5439dc468064cb651f843717fe63ef6a70e187b0a284e51cbb  Sources/CodexBar/ManagedCodexAccountService.swift
f5c5de88cdc9bf00d41c21a6adb9fff227f0c3a70bdc86f4a9caf221985015a9  Sources/CodexBar/MiniMaxAPITokenStore.swift
081a39687ede5075fba5f2b0e0a1707e8ee8cc86e2f232838c8830c8d523a8c1  Sources/CodexBar/MiniMaxCookieStore.swift
e60d4e901712092655afd2204b5095864db46d40ab226f284035ed52474d07af  Sources/CodexBar/PlanUtilizationHistoryStore.swift
0a11bbdb6aa55374327f8ed66020e874fe56b518803c93214359beb2ff654db1  Sources/CodexBar/Sync/CloudSyncEngine.swift
67b64d029d3e46f59d0383e7a11652afb55b9ddf45a6ba05b1950c3d9453af4b  Sources/CodexBar/Sync/CloudSyncPersistence.swift
a9f7fe21778c34558499178df78d42ff8569babd4318bfbf85b1d9f6ad3eeac1  Sources/CodexBar/SyntheticTokenStore.swift
c9d0e205916f01c8ba527b4a10430e899e068a0e234a918d0ab3af9cc72f699c  Sources/CodexBar/UsageStore+TokenCost.swift
616908f8e0279d2e96e7c4775dfdd90aa32f3d4345314b18f18ae9df64c82c25  Sources/CodexBar/ZaiTokenStore.swift
29991749df43f8d8dd93592e8a6c23b980996a3905fc7347309155121e01b7d6  Sources/CodexBarCLI/CLICacheCommand.swift
d0058efec90e92bd46c6930a71e9ab195d95db409de6fb47e3f7a57dfc3388c9  Sources/CodexBarCLI/CLIHelpers.swift
95be2dda3c2e27b19bc1dabf9514ab0c915ab52f2e6315a9687538dc55dcbbb9  Sources/CodexBarCore/AppGroupSupport.swift
410c69849fa054b5e1e8400c9f94233d7c0f80b524e4a04093a24df5bdd56e13  Sources/CodexBarCore/CodexWorkspaceUsageSidecar.swift
405bcfb6df96c0a818f9d0977e1c319e28fac69893f231f08154ca15c3bbd345  Sources/CodexBarCore/Config/CodexBarConfigStore.swift
667d7c2f1c248b3f5a77688ecd643993077718a20a268f5e2ed94ef1c06a6a53  Sources/CodexBarCore/CookieHeaderCache.swift
3efa4dbdb5385e454c6465d93a0bc60106a653cf24de28b10d6f41f778edf151  Sources/CodexBarCore/JonesStateRoot.swift
b235d56c2b6fe73c518668b4d04c654650a791bf51470b135ef0b5afb0362915  Sources/CodexBarCore/KeychainCacheStore.swift
fd4c657411f260276b2cf066d831a4ec8237219a0dbe3b52496aacaaff3563c9  Sources/CodexBarCore/Logging/FileLogHandler.swift
776f1a9662e70bd04b376a852ffc6ed052488e2ab68a5268946b73a90d2ae46a  Sources/CodexBarCore/ManagedCodexAccountStore.swift
517f8fae12cc4e35d3ef843a35332c129a6baec4a94c0f8ad7de0dd772aa8e82  Sources/CodexBarCore/OpenAIDashboardModels.swift
6900de173bda8836a23e3cf666375fe8c63ecf75eec5ee73027a87c6c1640a11  Sources/CodexBarCore/PiSessionCostCache.swift
e14745a2118ed3025c5621d32f0c06ac76c728bb285bfa0d1bf34e7f2d3dabc4  Sources/CodexBarCore/Plugins/UserProviderPlugins.swift
4e47e460c81bbc419d824a2d2e2a341f261d12e62c22e4223df259fb3352d335  Sources/CodexBarCore/ProviderSessionStoreFile.swift
a1b9c5774f5274f4b661b46d9db54ef19456259b5e1d54c00aee2e35a71858b7  Sources/CodexBarCore/ProviderStorageFootprint.swift
7414133dab1144d594ab494b9b2360ebc8785b70bb4d74dbb95c2f6637701547  Sources/CodexBarCore/Providers/Antigravity/AntigravityCLISession.swift
3e7ac39388a62cae293998fa25ce59330cafc8105592ca3a9f26e1257efef9c3  Sources/CodexBarCore/Providers/Antigravity/AntigravityOAuthCredentialsStore.swift
41732aab505a5787b3a5385daf91b8f7333bab703371b6fbf8288213976e5082  Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift
8ee05a060a9672f1cc1a52714f568f8e830a3aa167863112f3e99b689a1b14a9  Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthKeychainPromptMode.swift
b08c0f09407f287b939b5f85de6823741f84176302ec2839e02013eb75812987  Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthPendingCacheClearStore.swift
587dec8ac83495531063dc79e1373333237cc20e9414c564497331c253e6750a  Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift
324086d2830caa8b0f9ff0386af5cdf5a990551b1f8d2db0c42c47231d5b47c8  Sources/CodexBarCore/Providers/Claude/ClaudeSwap/ClaudeSwapRetainedUsageStore.swift
de857c22dcb3214d3106f67002695631297f8562d2fdd7359d4d62bb81cd855b  Sources/CodexBarCore/Providers/Codex/CodexOpenAIWorkspaceIdentityCache.swift
f1d1f95141e0a48f7c1e49305e2a36e0c6bd50de1f34650089101783794da29a  Sources/CodexBarCore/Providers/Codex/CodexStatusProbeIsolation.swift
c308c4de6623729930e8b09a7f58762ce52b10c0bfed5e41908a1cd1b3a8b132  Sources/CodexBarCore/TokenAccounts.swift
0edcf2619fb290d10d6add1295a620a8f6cb1689f8b87d23248bfcae40a34922  Sources/CodexBarCore/Vendored/CostUsage/CostUsageClaudeCache.swift
7d097e98447a16e2edf2c475e05e41ae0381709db242544fcf08c01606077e7b  Sources/CodexBarCore/Vendored/CostUsage/CostUsageStore.swift
f4ffdf4d4bb8436ad4b92e91d9dccac28941f812f21cf71855d99f4202f600e6  Sources/CodexBarCore/Vendored/CostUsage/ModelsDevPricing.swift
1ffed5b2832f1348fc6be702b0fd9a07c6267df21604decf9bf6b5ddf51bba09  Sources/CodexBarCore/Vendored/OpenCodexUsage/OpenCodexUsageModels.swift
5b6212d6e5173704c50b1605075affcda44df9228872570d9737a139add8e547  Tests/CodexBarTests/JonesStateRootTests.swift
eca99a33261f59b7dcda5ed825eabaf682863b7fc390b9fe4ce0944303e94bed  docs/jones/IDENTITY.md
```

Recovery: use this exact preserved candidate; the coordinator owns subsequent
writes and all Git/index effects. No installation or operational approval is
implied by source completion. Source ownership has been released.

## Coordinator integration and independent review

The original 52-file manifest above remains bound to candidate `4ff8b5040930da2dd74b97b6d69b746a96544a0a`; it is historical handoff evidence, not the final integrated file set. PR #12 publishes this source checkpoint above PR #11. The authorized account fixes at parent `5519723504787c83f17f6eeb799f2a888309ab9c` were merged without conflicts in `d1fb9db946fe90ddc9a0840ab66bcb0d7c04c7a0`. Their source changes do not overlap the identity hooks.

Independent Astra/high correctness review of `4ff8b5040930da2dd74b97b6d69b746a96544a0a` found TIR001 and TIR002, both P2. Exact source/result bindings, original severities and blocking effects are preserved in `docs/review-evidence/trial-identity-4ff8b504.json`. Both remain uncorrected and deferred under the explicit-direction rule; the owner authorized AFR001/002, not these new findings. No severity or blocking claim is waived. Native checks and all previously recorded trial gates remain open. No merge or installation is claimed.

## Laptop continuity takeover and VPS source assignment

Coordinator relay received from laptop thread
`506fc1fd-d94f-4616-84f4-7751eda0aec8`, environment
`8750edf7-486b-41ac-81ce-cd50dfeb71eb`, reporting M Jones's current direct
completion direction. Attribution remains agent relay, not independent agent
approval. Laptop retains overall continuity, Mac verification, eligible merge
sequencing and final delivery. VPS root retains sole Git/index ownership of
existing declared source worktrees, publishes source checkpoints, and does not
merge behind the coordinator. No live authentication, protected-store reads,
host activation, installation, signing or release is covered.

New source scope: collapsible active/top Codex account with coherent compact /
expanded rows; five initially visible Codex accounts; source-first Claude AFCL
reuse investigation without a second independent login lifecycle; known
TIR001/TIR002 source repairs and concrete disposition of seven trial categories;
proportionate upstream-friendly isolation remains in scope. Original finding
severities and exact review bindings remain unchanged. Screenshots concern stock
installed CodexBar, not proof this candidate was run.

Current clean integration branches verified: PR11
`c2a3118daf3d6824bba648abe6f4e84ef710272d`, PR12
`21c34561387b26f76d0a27e9f00d1538fbc0926f`, matching fork remote refs.
No source writer or unknown prior effect remained before assignment. PR3 is
unrelated repository-sync work with no path overlap. New task worktrees:
`account-presentation-20261017` from PR11 and
`trial-blocker-repairs-20261017` from PR12. Root owns Git in both; builders own
only their declared UI/test or two-finding repair cones. Sol source research of
Claude and Astra trial framing are read-only. No duplicate top-level thread
was created. Frontier remains explicit; no preference writes.

Fresh admission before the first three lanes: CPU 2.83%, available RAM 40.16 GiB;
before the known-blocker builder: CPU 8.36%, RAM 39.87 GiB. One fully used core
is 6.25% of host capacity. Native verification remains laptop-owned and is not
substituted by missing-Swift results on the VPS. Current registered cross-host
return route still targets a different peer environment; checkpoint reports are
retained here and in Git for the coordinator's authorized VPS reader.
