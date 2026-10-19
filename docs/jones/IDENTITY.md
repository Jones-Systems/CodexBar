# Trial identity and state roots

Authority effect: none. Source candidate based on
`0f842d7f26edcd1a1fff886409291ef9b4f846b6`. This documents source behavior,
not an installed or approved trial. The stock laptop app is unaffected.

## Packaging contract

`Scripts/package_app.sh` sources `.mac-release.jones.env` only when that exact
file exists. The file is executable local shell configuration, not a data parser;
review it before a separately authorized build. Never commit real values.
`.mac-release.jones.env.example` contains planning names and a literal team
placeholder, no real team, credential, signing key, or signing identity.
The `.gitignore` exception is one exact pattern line without a marker: Git does
not support an inline comment after a pattern. This paragraph is its ledger marker.

| Surface | No overlay | Placeholder overlay |
| --- | --- | --- |
| App | `com.steipete.codexbar` (debug suffix as before) | `com.jonessystems.codexbar` |
| Widget | app ID + `.widget` | `com.jonessystems.codexbar.widget` |
| App group | existing team + upstream release/debug ID | `<explicit-team>.com.jonessystems.codexbar` |
| iCloud | existing `iCloud.<bundle>` | `iCloud.com.jonessystems.codexbar` |
| Display name | `CodexBar` | `CodexBar Jones` |
| Sparkle | exact existing feed/key/check policy | empty feed, empty public key, automatic checks false |
| State key | absent | `JonesStateKey=jones` |
| Signing/profile | exact existing selection | explicit fork signer/profile; no upstream fallback |

Overlay identity is identical in debug/release; those overlay variants share trial
state. The single supported `jones` key selects one set of roots, not arbitrary
parallel fork identities. Bundle/team values are validated before build effects;
upstream bundle/team and missing required values fail. Identity-signed builds
require `JONES_SIGNING_IDENTITY`; release iCloud entitlements require the explicit
`JONES_PROVISIONING_PROFILE`. Ad hoc builds retain the existing absence of iCloud
entitlements. The metadata still carries the fork iCloud identifier.
`sign-and-notarize.sh` also refuses an absent or upstream fork signer.
No signing, profile read, notarization, install, or launch is part of these tests.

The app plist includes `JonesAppBundleID`, `JonesAppGroupID`, `JonesICloudID`,
`JonesStateKey`, and the existing `CodexBarTeamID`. The widget receives the first
four via a marked packaging hook. Its existing Xcode build-setting/template
already supplies `CodexBarTeamID`; no duplicate hook is needed.
`JonesStateRoot` uses this packaged metadata, never environment activation.
A bundled CLI reads only the nearest enclosing `.app/Contents/Info.plist` (also
when reached by a symlink through the runtime-resolved executable URL).
Missing state key preserves upstream behavior; a present invalid/incomplete
state key fails closed. App-group migration returns before consulting legacy
defaults or files. The fork team is resolved before code-signature fallback.

## Writable path manifest

`AS` means the platform's Application Support directory, `CACHE` its Caches
directory, `HOME` its home, and `TEMP` its temporary directory. App sandbox homes
may differ from CLI homes; the widget's shared snapshot uses the app group.
All suffixes, filenames, account keys and persisted property names stay unchanged.
Explicit injected URLs remain explicit. No-overlay resolution is byte-for-byte
unchanged; fork roots start empty and never migrate stock state.

| Owner/site | Existing default | Overlay default |
| --- | --- | --- |
| `CodexBarConfigStore.defaultURL` | explicit `CODEXBAR_CONFIG`, then absolute `XDG_CONFIG_HOME/codexbar/config.json`, existing `HOME/.config/codexbar/config.json`, existing `HOME/.codexbar/config.json`, else XDG default | explicit `CODEXBAR_CONFIG` still first; otherwise `HOME/.codexbar-jones/config.json`, without probing old paths |
| `AntigravityOAuthCredentialsStore` | `HOME/.codexbar/antigravity/oauth_creds.json` | `HOME/.codexbar-jones/antigravity/oauth_creds.json` |
| `AntigravityCLISession` record and lock | `HOME/.codexbar/antigravity/agy-session.{json,lock}` | same suffixes under `HOME/.codexbar-jones/` |
| `ClaudeOAuthPendingCacheClearStore` | `HOME/.codexbar/claude-oauth-cache.lock` | `HOME/.codexbar-jones/claude-oauth-cache.lock` |
| `ManagedCodexAccountService` | `AS/CodexBar/managed-codex-homes/` | `AS/CodexBar Jones/managed-codex-homes/` (CodexBar-created homes only) |
| `ManagedCodexAccountStore` | `AS/CodexBar/managed-codex-accounts.json` | `AS/CodexBar Jones/managed-codex-accounts.json` |
| `CodexAccountUsageSnapshotStore` | `AS/CodexBar/codex-account-snapshots.json` | same filename under `AS/CodexBar Jones/` |
| `CodexOpenAIWorkspaceIdentityCache` | `AS/CodexBar/codex-openai-workspaces.json` | same filename under `AS/CodexBar Jones/` |
| `TokenAccounts` | `AS/CodexBar/token-accounts.json` | same filename under `AS/CodexBar Jones/` |
| `ProviderSessionStoreFile` (Cursor, Augment, Factory, Notion) | `AS/CodexBar/{cursor,augment,factory,notion}-session.json` | same filenames under `AS/CodexBar Jones/` |
| `CookieHeaderCache` legacy files and lock | `AS/CodexBar/<provider>-cookie.json`, `cookie-cache.lock` | same filenames under `AS/CodexBar Jones/`; no stock legacy import |
| `HistoricalUsagePace` | `AS/CodexBar/usage-history.jsonl` | same filename under `AS/CodexBar Jones/` |
| `ClaudeSwapRetainedUsageStore` | `AS/CodexBar/claude-swap-retained-usage.json` | same filename under `AS/CodexBar Jones/` |
| `PlanUtilizationHistoryStore` | `AS/com.steipete.codexbar/history/` | `AS/CodexBar Jones/history/` |
| `OpenAIDashboardModels` | `AS/com.steipete.codexbar/openai-dashboard.json` | `AS/CodexBar Jones/openai-dashboard.json` |
| `CloudSyncPersistence` | `AS/com.steipete.codexbar/sync/engine-state.json` | `AS/CodexBar Jones/sync/engine-state.json` |
| `CloudSyncEngine` | `iCloud.com.steipete.codexbar` container | packaged `JonesICloudID`; existing zone/record keys |
| `ClaudeStatusProbe`, `ProviderStorageFootprint` | `AS/CodexBar/ClaudeProbe/`, including local settings/session state | `AS/CodexBar Jones/ClaudeProbe/`; overlay directory-creation failure never falls back to shared TEMP |
| `CodexStatusProbeIsolation` | `TEMP/CodexBar/CodexStatusProbe/` | `TEMP/CodexBar Jones/CodexStatusProbe/` |
| `AppGroupSupport` snapshot/shared defaults | team-prefixed upstream group and `widget-snapshot.json`; fallback `AS/CodexBar/` | packaged fork group; fallback `AS/CodexBar Jones/` |
| `CostUsageStore` and app/CLI cache clear | `CACHE/CodexBar/cost-usage/cost-usage.sqlite` plus SQLite sidecars | `CACHE/CodexBar Jones/cost-usage/`; writer and both clear paths agree |
| `CostUsageClaudeCache` | `CACHE/CodexBar/cost-usage/<provider>-v6.json` | same suffix under `CACHE/CodexBar Jones/` |
| `PiSessionCostCache` | `CACHE/CodexBar/cost-usage/pi-sessions-v<version>.json` | same suffix under `CACHE/CodexBar Jones/` |
| `ModelsDevPricing` | `CACHE/CodexBar/model-pricing/models-dev-v<version>.json` | same suffix under `CACHE/CodexBar Jones/` |
| `CodexWorkspaceUsageSidecar` | `CACHE/local-usage/codex-workspaces-v1.sqlite` plus sidecars | `CACHE/CodexBar Jones/local-usage/codex-workspaces-v1.sqlite`; injected cache roots unchanged |
| `OpenCodexUsageModels` CodexBar cache | `CACHE/CodexBar/opencodex-usage/` | `CACHE/CodexBar Jones/opencodex-usage/` |
| `UserProviderPlugins` loader and compilation cache | `HOME/.config/codexbar/providers/`, `HOME/Library/Caches/CodexBar/plugins/` | `HOME/.config/codexbar-jones/providers/`, `HOME/Library/Caches/CodexBar Jones/plugins/` |
| `FileLogHandler` | `HOME/Library/Logs/CodexBar/CodexBar.log` | `HOME/Library/Logs/CodexBar Jones/CodexBar.log` |
| `MainThreadHangWatchdog` samples | `HOME/Library/Logs/CodexBar/` | `HOME/Library/Logs/CodexBar Jones/` |
| `JonesDiagnosticDestination` export hooks | existing TEMP probe/purchase/dashboard filenames | same filenames under platform `Library/Logs/CodexBar Jones/Diagnostics/`; retained exports |
| `MiMoLocalUsageFallback` | `HOME/.codexbar/mimo-local-usage.json` | `HOME/.codexbar-jones/mimo-local-usage.json`; explicit override retains precedence |
| `JonesProviderScratchRoot` Gemini/Aliyun hooks | existing TEMP script/directory names | same names under `TEMP/CodexBar Jones/provider-scratch/`; cleanup ownership below |

Atomic temporary files, lock files, SQLite WAL/SHM and other children inherit the
parent directory in these rows. Existing test-only temporary isolation and explicit
fixture URL overrides remain in place. Platform root-unavailable fallbacks retain
the same base selection but use the fork child directory; the Claude creation-error
fallback is explicitly held to its fork path.

## Credentials and defaults

`JonesStateRoot.namespace(service)` is `<fork-bundle>.service.<full-original-service>`.
It is injective for a fixed identity, preserving case and suffixes. Account names
and provider keys stay unchanged. With no identity it returns the original string.
No credential is accessed by identity resolution or tests.

- `KeychainCacheStore`: `com.steipete.codexbar.cache` becomes
  `<fork-bundle>.service.com.steipete.codexbar.cache`; all cached provider entries
  inherit this namespace.
- `CookieHeaderStore`, `CopilotTokenStore`, `KimiTokenStore`, `MiniMaxAPITokenStore`,
  `MiniMaxCookieStore`, `SyntheticTokenStore`, `ZaiTokenStore`: their shared original
  `com.steipete.CodexBar` service becomes
  `<fork-bundle>.service.com.steipete.CodexBar`, with distinct existing accounts.
- `CLIHelpers` app preferences, `ClaudeOAuthCredentials` ownership/tombstone defaults
  and `ClaudeOAuthKeychainPromptMode` resolve the fork app domain. App `.standard`
  follows the packaged bundle; widget shared defaults follow the fork app group.
- Provider-owned Claude Code, Zed and browser Keychain services are deliberately
  unchanged. This is not permission to access them. Cached copies owned by
  CodexBar use the fork service above.

## Remaining trial gates and exclusions

This is a source candidate with explicit incomplete-isolation gates. Do not call
it a fully qualified trial or launch it while these gates remain unresolved.

1. **Diagnostic exports, source-addressed:** the Claude/provider probe files,
   purchase debug log and dashboard HTML/text now use
   `Library/Logs/CodexBar Jones/Diagnostics/` under packaged Jones identity.
   Stock paths remain exact. Creation/write errors do not fall back to shared
   temporary storage. These are retained diagnostic exports: probe files overwrite,
   purchase logs keep their existing reset behavior, and timestamped dashboard
   exports remain until explicitly removed. Eight synthetic test methods are
   authored; compilation and native qualification remain pending.
2. **External MiMo tracker:** the reader now defaults to
   `HOME/.codexbar-jones/mimo-local-usage.json` with Jones identity and retains
   `HOME/.codexbar/mimo-local-usage.json` without it. `MIMO_LOCAL_USAGE_PATH`
   keeps precedence. The unchanged external tracker needs that existing explicit
   output override to agree with the Jones reader. Synthetic Python writer tests
   pass; native reader/writer agreement and real tracker activation remain pending.
   Proposed invocation, not executed:

   ```bash
   MIMO_LOCAL_USAGE_PATH="$HOME/.codexbar-jones/mimo-local-usage.json" \
     python3 Scripts/mimo-usage.py --update
   ```

   This does not alter tracker inputs or authorize real-session access.
3. **Provider scratch, source-addressed:** Gemini login scripts, Gemini curl
   directories and Aliyun copied cookie databases now use
   `TEMP/CodexBar Jones/provider-scratch/` under packaged Jones identity. Stock
   paths stay exact. Aliyun registers cleanup before any database/sidecar copy;
   curl keeps its immediate defer; Gemini login removes failed/cancelled scripts.
   Successful login scripts retain the existing ten-second delayed cleanup owned
   by GeminiLoginRunner. This callback survives function return; app termination
   and removal failures remain unqualified. Twenty-two synthetic cases are
   authored, not executed. Native qualification and this retention disposition
   remain gates; no real browser, credential or Terminal operation was performed.
4. **Framework-managed state, partially hardened:** OpenAI dashboard WebKit
   cache keys and persistent identifiers now include packaged fork identity,
   account and scope. Missing-email overlay stores also receive identifiers;
   stock default-store behavior is unchanged. Nine pure identifier tests are
   authored, not executed. Shared HTTP state remains unresolved: StepFun relies
   on the generic client's shared cookies, and other shared/default sessions
   remain in CLI status, currency/pricing and Alibaba token-plan requests.
   App, widget and bundled-CLI containment still requires native proof. OS
   logging, saved application state and system preferences are not redirected
   by this helper. The framework trial gate remains open.
5. **Unbundled CLI / `swift run` / copied helper:** without enclosing packaged
   metadata these intentionally use upstream behavior. They must not be used for
   trial side effects. No environment opt-in or installation was added. Nonbundled
   app localization's `CodexBar` defaults fallback is likewise unsupported.
6. **Explicit user paths and other-tool state:** `CODEXBAR_CONFIG`, injected cache
   roots, CLI exports and user-selected paths intentionally retain precedence.
   The operator must choose isolated destinations. Canonical Codex/Authfleet homes,
   `.codex`, `.claude`, browser stores and `.opencodex/usage.jsonl` are provider-owned
   inputs, never retargeted. Existing external auth/probe effects are unchanged and
   require their own approval. This candidate does not establish login safety.
7. **Native/release qualification:** Swift 6.2+ build/test, native plist/entitlement
   output, Xcode widget build, signed team/app-group/iCloud validation and runtime
   state readback remain unproved here. Native tests are provided, not claimed run.
   Real identifiers, signing, install and launch remain separately held.

## Verification and ledger delta

`bash Scripts/test_jones_identity_overlay.sh` renders the actual shell identity
function and plist templates in an owned workspace fixture. It compares all twelve
no-overlay plist/entitlement outputs byte-for-byte with the pinned original script
and recorded SHA-256 values. It exercises overlay variants, invalid identities,
widget metadata mutations with a fixture PlistBuddy substitute, and the re-sign
identity guard. It never executes the build/sign/release body or reads the real
overlay. A Python context manager cleans the exact fixture on success, exception
and handled TERM/INT/HUP; unconditional kill/host failure cannot run cleanup.

`JonesStateRootTests` contains pure Swift metadata, path, injectivity, precedence
and migration tests. It uses synthetic URLs, a contained recording virtual
FileManager and dictionary-backed defaults; no live Keychain/provider/config calls.
The exact selector is `swift test --filter JonesStateRootTests`, with the repository's
Keychain, Codex-file and provider-session isolation signals. `make test` and
`make check` remain repository checks, subject to available tools and authority.
Final execution outcomes and candidate digests are in
`../work-notes/trial-identity.md`.

The following exact upstream-owned changed paths are the proposed ledger delta;
each has `JONES(trial-identity)` hooks except the documented `.gitignore` pattern.
No existing finding ledger is changed. Generic configurable-root extraction remains
`upstream-candidate`; the Jones-specific identity policy is fork-owned.

- `.gitignore`
- `Scripts/package_app.sh`
- `Scripts/sign-and-notarize.sh`
- `Sources/CodexBar/CodexAccountUsageSnapshotStore.swift`
- `Sources/CodexBar/CookieHeaderStore.swift`
- `Sources/CodexBar/CopilotTokenStore.swift`
- `Sources/CodexBar/HistoricalUsagePace.swift`
- `Sources/CodexBar/KimiTokenStore.swift`
- `Sources/CodexBar/MainThreadHangWatchdog.swift`
- `Sources/CodexBar/ManagedCodexAccountService.swift`
- `Sources/CodexBar/MiniMaxAPITokenStore.swift`
- `Sources/CodexBar/MiniMaxCookieStore.swift`
- `Sources/CodexBar/PlanUtilizationHistoryStore.swift`
- `Sources/CodexBar/Sync/CloudSyncEngine.swift`
- `Sources/CodexBar/Sync/CloudSyncPersistence.swift`
- `Sources/CodexBar/SyntheticTokenStore.swift`
- `Sources/CodexBar/UsageStore+TokenCost.swift`
- `Sources/CodexBar/ZaiTokenStore.swift`
- `Sources/CodexBarCLI/CLICacheCommand.swift`
- `Sources/CodexBarCLI/CLIHelpers.swift`
- `Sources/CodexBarCore/AppGroupSupport.swift`
- `Sources/CodexBarCore/CodexWorkspaceUsageSidecar.swift`
- `Sources/CodexBarCore/Config/CodexBarConfigStore.swift`
- `Sources/CodexBarCore/CookieHeaderCache.swift`
- `Sources/CodexBarCore/KeychainCacheStore.swift`
- `Sources/CodexBarCore/Logging/FileLogHandler.swift`
- `Sources/CodexBarCore/ManagedCodexAccountStore.swift`
- `Sources/CodexBarCore/OpenAIDashboardModels.swift`
- `Sources/CodexBarCore/PiSessionCostCache.swift`
- `Sources/CodexBarCore/Plugins/UserProviderPlugins.swift`
- `Sources/CodexBarCore/ProviderSessionStoreFile.swift`
- `Sources/CodexBarCore/ProviderStorageFootprint.swift`
- `Sources/CodexBarCore/Providers/Antigravity/AntigravityCLISession.swift`
- `Sources/CodexBarCore/Providers/Antigravity/AntigravityOAuthCredentialsStore.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthKeychainPromptMode.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthPendingCacheClearStore.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift`
- `Sources/CodexBarCore/Providers/Claude/ClaudeSwap/ClaudeSwapRetainedUsageStore.swift`
- `Sources/CodexBarCore/Providers/Codex/CodexOpenAIWorkspaceIdentityCache.swift`
- `Sources/CodexBarCore/Providers/Codex/CodexStatusProbeIsolation.swift`
- `Sources/CodexBarCore/TokenAccounts.swift`
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsageClaudeCache.swift`
- `Sources/CodexBarCore/Vendored/CostUsage/CostUsageStore.swift`
- `Sources/CodexBarCore/Vendored/CostUsage/ModelsDevPricing.swift`
- `Sources/CodexBarCore/Vendored/OpenCodexUsage/OpenCodexUsageModels.swift`

New fork-owned files: `.mac-release.jones.env.example`,
`Sources/CodexBarCore/JonesStateRoot.swift`,
`Scripts/test_jones_identity_overlay.sh`,
`Tests/CodexBarTests/JonesStateRootTests.swift`, this identity manifest, and
`docs/work-notes/trial-identity.md`. Source-only ownership returns to the coordinator
at handoff; publication and integration are the coordinator's responsibility.
