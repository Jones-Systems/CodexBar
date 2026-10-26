# Test execution profiles

Normal testing follows M Jones’s app use: Codex and Claude, their accounts and
shared app behavior. Other provider behavior, hooks, plugins and iCloud sync
are preserved in source and run only with an explicit full profile. No nightly
job runs these unused suites. Product code, targets, dependencies and fixtures
are identical in both profiles.

## Commands and restoration

```sh
make test                                      # normal by default
CODEXBAR_TEST_PROFILE=normal make test          # explicit normal
CODEXBAR_TEST_PROFILE=full make test            # all existing offline tests
CODEXBAR_TEST_PROFILE=full ./Scripts/lint.sh lint-linux
./Scripts/test-plugin-engines.sh                # explicit full engine A/B proof
python3 Scripts/test_profiles.py describe
```

In the CI workflow’s manual dispatch, select `test_profile: full` and provide the
exact `expected_sha` and the existing campaign controls. PR, push and daily
scheduled events always select normal. Full is offline: it does not grant live
provider, Keychain, browser-cookie, private-account, signing or packaging access.
The native journey cap and advisory label/manual placement remain unchanged.

The CI workflow runs the normal used-feature profile daily at **05:00
America/New_York (EST/EDT)**, following daylight saving time automatically. It uses
the default branch's latest commit and selects the macOS build producer, both
existing macOS shards, both Linux test architectures and the musl CLI build. Its
concurrency group is separate from push/PR runs. Unused providers, plugins, hooks
and iCloud tests remain manual full-profile opt-in. GitHub may delay or drop
scheduled events under runner/service load; this is a requested trigger time,
not a guaranteed start time.

Results use the existing Actions job/step logs and path-gate/aggregate summaries.
The producer and both macOS shards must pass; failure or skipped selected jobs
fail the aggregate. Compiled artifacts expire after one day. Synthetic reset-timing
artifacts upload on macOS success or failure when setup succeeded and are retained
for seven days. Failure includes existing crash diagnostics; no issue is created
automatically. Campaign receipts remain specific to manual measurement runs.
See GitHub's [schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

`Scripts/test_profiles.json` is the reviewed selector and reasons manifest.
`Package.swift` excludes its whole-file paths only from **test** targets in
normal. Full defines `CODEXBAR_FULL_TEST_PROFILE` only for test targets, restoring
mixed test declarations without changing their bodies. Both direct SwiftPM and
the wrappers use this selection; execution filters alone are insufficient.
An invalid explicit profile fails. Keep helper sources and copied fixtures.

To re-enable one whole-file group normally, remove its entries from
`full_only_groups`. To re-enable a mixed group normally, remove only its profile
guards and corresponding `mixed_full_only` entry. Run the profile contract and
normal/full native qualification. Selecting full restores all groups immediately
without editing source; reverting this profile change restores the former default.
Caches and campaign evidence are segregated by profile and manifest digest.

## Retained boundaries

Keep Codex/Claude account switching, credential isolation, persistence, package
resource resolution, permission/security/privacy and relevant shipped regressions.
OpenAI dashboard/web and OpenCodex ingestion are Codex app coverage. OpenAI API is
a separate unused provider. MiniMax-named LogRedactor tests cover shared redaction.
Kiro-named TTY process/hard-stop suites protect shared process cleanup used by
Codex and Claude and remain normal. Local fleet/account tests are distinct from
iCloud synchronization. Shared
invariants retain representative unused-provider fixtures where their subject is
shared behavior. `CodexBarCoreResourcesPortableTests` remains in the plugin test
target because the app/helper resource contract is shared.

CodexBarCLI is the repository’s `codexbar` terminal command, separate from the
external `codex` and `claude` provider tools. Remote Agent Sessions invokes its
sessions protocol. Terminal/remote usage is unresolved, so CLI-dependent coverage
and all platform CLI build checks remain enabled. No private settings were read.

## Full-only groups

Every row retains its original source and full-profile execution. The used-app
and shared coverage above remains in normal. Mixed declarations are listed by
exact method identity in the manifest.

| Group | Category | Paths | Reason |
| --- | --- | ---: | --- |
| hooks | unused_hooks | 8 | hooks are unused in the owner’s app workflow; retain source for explicit full runs. |
| icloud | unused_icloud | 2 | icloud are unused in the owner’s app workflow; retain source for explicit full runs. |
| plugins | unused_plugins | 16 | plugins are unused in the owner’s app workflow; retain source for explicit full runs. |
| Abacus | unused_provider | 2 | Abacus provider-specific behavior is outside the owner’s Codex/Claude app use. |
| AiAnd | unused_provider | 1 | AiAnd provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Alibaba | unused_provider | 9 | Alibaba provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Amp | unused_provider | 2 | Amp provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Antigravity | unused_provider | 29 | Antigravity provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Augment | unused_provider | 5 | Augment provider-specific behavior is outside the owner’s Codex/Claude app use. |
| AzureOpenAI | unused_provider | 2 | AzureOpenAI provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Bedrock | unused_provider | 6 | Bedrock provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Chutes | unused_provider | 2 | Chutes provider-specific behavior is outside the owner’s Codex/Claude app use. |
| ClawRouter | unused_provider | 1 | ClawRouter provider-specific behavior is outside the owner’s Codex/Claude app use. |
| ClinePass | unused_provider | 1 | ClinePass provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Codebuff | unused_provider | 2 | Codebuff provider-specific behavior is outside the owner’s Codex/Claude app use. |
| CommandCode | unused_provider | 3 | CommandCode provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Copilot | unused_provider | 7 | Copilot provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Crof | unused_provider | 2 | Crof provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Cursor | unused_provider | 19 | Cursor provider-specific behavior is outside the owner’s Codex/Claude app use. |
| DeepInfra | unused_provider | 3 | DeepInfra provider-specific behavior is outside the owner’s Codex/Claude app use. |
| DeepSeek | unused_provider | 7 | DeepSeek provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Deepgram | unused_provider | 1 | Deepgram provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Devin | unused_provider | 1 | Devin provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Doubao | unused_provider | 3 | Doubao provider-specific behavior is outside the owner’s Codex/Claude app use. |
| ElevenLabs | unused_provider | 2 | ElevenLabs provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Factory | unused_provider | 5 | Factory provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Fireworks | unused_provider | 2 | Fireworks provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Gemini | unused_provider | 16 | Gemini provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Grok | unused_provider | 12 | Grok provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Groq | unused_provider | 3 | Groq provider-specific behavior is outside the owner’s Codex/Claude app use. |
| IBMBob | unused_provider | 1 | IBMBob provider-specific behavior is outside the owner’s Codex/Claude app use. |
| JetBrains | unused_provider | 3 | JetBrains provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Kilo | unused_provider | 7 | Kilo provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Kimi | unused_provider | 2 | Kimi provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Kiro | unused_provider | 6 | Kiro provider-specific behavior is outside the owner’s Codex/Claude app use. |
| LLMProxy | unused_provider | 2 | LLMProxy provider-specific behavior is outside the owner’s Codex/Claude app use. |
| LiteLLM | unused_provider | 2 | LiteLLM provider-specific behavior is outside the owner’s Codex/Claude app use. |
| LongCat | unused_provider | 2 | LongCat provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Manus | unused_provider | 2 | Manus provider-specific behavior is outside the owner’s Codex/Claude app use. |
| MiMo | unused_provider | 5 | MiMo provider-specific behavior is outside the owner’s Codex/Claude app use. |
| MiniMax | unused_provider | 7 | MiniMax provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Mistral | unused_provider | 3 | Mistral provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Moonshot | unused_provider | 2 | Moonshot provider-specific behavior is outside the owner’s Codex/Claude app use. |
| NeuralWatt | unused_provider | 3 | NeuralWatt provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Notion | unused_provider | 3 | Notion provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Ollama | unused_provider | 4 | Ollama provider-specific behavior is outside the owner’s Codex/Claude app use. |
| OneConsole | unused_provider | 1 | OneConsole parsing serves only unused Alibaba, Qwen Cloud and Aliyun provider integrations. |
| OpenAI API | unused_provider | 6 | OpenAI API provider-specific behavior is outside the owner’s Codex/Claude app use. |
| OpenCode | unused_provider | 8 | OpenCode provider-specific behavior is outside the owner’s Codex/Claude app use. |
| OpenCodeGo | unused_provider | 13 | OpenCodeGo provider-specific behavior is outside the owner’s Codex/Claude app use. |
| OpenRouter | unused_provider | 3 | OpenRouter provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Perplexity | unused_provider | 6 | Perplexity provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Poe | unused_provider | 4 | Poe provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Qoder | unused_provider | 4 | Qoder provider-specific behavior is outside the owner’s Codex/Claude app use. |
| QwenCloud | unused_provider | 1 | QwenCloud provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Sakana | unused_provider | 2 | Sakana provider-specific behavior is outside the owner’s Codex/Claude app use. |
| StepFun | unused_provider | 1 | StepFun provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Sub2API | unused_provider | 4 | Sub2API provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Synthetic | unused_provider | 2 | Synthetic provider-specific behavior is outside the owner’s Codex/Claude app use. |
| T3Chat | unused_provider | 1 | T3Chat provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Venice | unused_provider | 2 | Venice provider-specific behavior is outside the owner’s Codex/Claude app use. |
| VertexAI | unused_provider | 2 | VertexAI provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Warp | unused_provider | 2 | Warp provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Wayfinder | unused_provider | 2 | Wayfinder provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Windsurf | unused_provider | 4 | Windsurf provider-specific behavior is outside the owner’s Codex/Claude app use. |
| XAI | unused_provider | 2 | XAI provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Zai | unused_provider | 4 | Zai provider-specific behavior is outside the owner’s Codex/Claude app use. |
| Zed | unused_provider | 1 | Zed provider-specific behavior is outside the owner’s Codex/Claude app use. |
| ZenMux | unused_provider | 1 | ZenMux provider-specific behavior is outside the owner’s Codex/Claude app use. |
| ZoomMate | unused_provider | 3 | ZoomMate provider-specific behavior is outside the owner’s Codex/Claude app use. |

Five TestsPlugin paths are aliases of existing native sources, not additional tests.
