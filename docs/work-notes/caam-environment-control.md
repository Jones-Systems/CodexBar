# Work Note — CAAM Environment Control

<!-- codex-section:begin id="worknote.caam-environment-control#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.caam-environment-control`

Purpose: Carry research, coordination, execution evidence, blockers, and deferred findings for CAAM-backed Codex environment control.

Governing artifact: `spec.caam-environment-control`

Continuity owner: coordinator

Consumers: CodexBar implementer, CAAM implementer, reviewers, verifier, and release owner

Authority effect: none
<!-- codex-section:end id="worknote.caam-environment-control#ctx.artifact-header.001" -->

<!-- codex-section:begin id="worknote.caam-environment-control#ctx.question-and-finish-line.001" -->
## Question and finish line

Make the laptop-hosted CodexBar application the control surface for observing and eventually switching the Codex account on the laptop, VPS, and Mac Mini. Each environment runs CAAM locally and retains sole custody of its credentials and vault. CodexBar receives only bounded configuration, redacted account/profile identity, health, capability, and operation-result data.

The project finish line is a macOS-tested CodexBar environment panel backed by a versioned CAAM gateway contract, with per-environment status, profile selection, exact switch planning/execution, interrupted-operation recovery, explicit fallback restoration, capability negotiation, and postcondition readback across local and restricted-SSH transports.

The first pull request is a dependency-complete foundation rather than false production activation: versioned models and protocol validation, provider-scoped environment configuration, safe command construction, fixture-backed read-only projection, and the smallest reviewable Codex settings UI slice. Credential-changing controls remain unavailable until the CAAM V3 public adapter and gateway satisfy the contract.
<!-- codex-section:end id="worknote.caam-environment-control#ctx.question-and-finish-line.001" -->

<!-- codex-section:begin id="worknote.caam-environment-control#ctx.source-strategy-and-evidence.001" -->
## Source strategy and current evidence

Repository evidence is bound to upstream CodexBar `392310c665485f8d57c93881e7416c5ebf69d8ef` and fresh CAAM `origin/main` `2f9c8428e1fb880fe6eeb4025eb97b61b9bb4781` as observed on 2026-09-04.

- CodexBar's `Active` account selection controls usage observation. Its `System` account selection promotes managed auth into the live auth slot on the Mac. The existing UI already describes that slot as the default Codex account on this Mac.
- Managed promotion preserves the displaced live account, validates account/workspace identity, stages replacement bytes, and atomically renames the staged file over live `auth.json`. It does not establish the account cached by an already-running Codex process.
- CodexBar's `RemoteSessionFetcher` already uses the shared bounded `SubprocessRunner`, but it sends an unrestricted remote shell command. It is precedent for process handling only, not an acceptable authority boundary for remote credential changes.
- Provider configuration preserves provider-specific extension values, allowing a `codexCAAMEnvironments` field without broadening the generic configuration schema or adding another store.
- The macOS settings architecture supports a supplementary Codex section with stable state/model seams. Repository guidance prefers testing those seams instead of live AppKit menus.
- Published CAAM provides `status codex --json`, `ls codex --json`, and `activate codex <profile> --json`, but those are legacy direct-vault paths. The newer transaction/recovery service is not yet the public CLI/API/TUI path.
- CAAM's current machine abstraction synchronizes vault files; it does not observe or switch the active profile on another machine. Remote vault synchronization is not the controller design.
- CAAM status identifies provider, current profile, profile health, and redacted account metadata. Refresh-token bytes and complete auth-file hashes are not stable cross-machine account identity.
- Current OpenAI Codex authentication can use a file or operating-system credential store. CAAM must prove compatible file-backed storage locally before advertising switch capability.
- The VPS has no Swift toolchain. It can perform repository/static validation but cannot supply compile or macOS rendering evidence. Mac compilation, screenshot proof, and credential-free transport integration remain explicit later gates.
- The installed laptop application and version remain unverified because the current approved Mac gateway denied the read-only host-summary operation after successful SSH transport/authentication.

No third-party implementation is copied. Upstream CodexBar source is the implementation base under its existing license. No credential file, token, vault content, live account, or private process data was read during research.
<!-- codex-section:end id="worknote.caam-environment-control#ctx.source-strategy-and-evidence.001" -->

<!-- codex-section:begin id="worknote.caam-environment-control#ctx.lanes-dependencies-and-synthesis.001" -->
## Lanes, dependencies, and synthesis

The research map covered four questions: CodexBar account-promotion semantics, CodexBar UI/config/process seams, CAAM's published and V3 switching surfaces, and OpenAI credential-store constraints. These lanes are conceptually independent, but current session policy prohibits new sub-agent launches, so the coordinator used bounded sequential repository reads and batched independent commands. Earlier read-only specialist results were validated against fresh repository revisions before planning.

Synthesis:

1. CodexBar owns presentation, environment configuration, refresh scheduling, and user confirmation.
2. One CAAM installation per environment owns observation, local vault/profile mapping, switching, recovery, fallback selection, and final postcondition evidence.
3. The transport carries a closed versioned JSON contract over local execution or one fixed remote gateway operation. It never carries raw auth or vault bytes and never invokes a caller-supplied shell.
4. The UI distinguishes account usage selection, host-default auth, effective running-process state when known, interrupted-operation recovery, and fallback restoration.
5. The first PR implements the safe read-only/configuration foundation and capability-gates mutations. Later CAAM delivery activates mutation without redesigning the UI or transport.
6. A dedicated Environments section inside the existing Codex provider settings is the smallest reversible first placement. A top-level settings destination remains a later product decision after real macOS rendering evidence.

The coordinator is the sole Git owner of `/home/malcolmjones/Projects/CodexBar-worktrees/caam-environments` on `work/caam-environments`. No other writer is assigned. The owner selected `Jones-Systems/CodexBar` as the organization-controlled delivery fork; no pull request will target the upstream `steipete/CodexBar` repository.
<!-- codex-section:end id="worknote.caam-environment-control#ctx.lanes-dependencies-and-synthesis.001" -->

<!-- codex-section:begin id="worknote.caam-environment-control#ctx.execution-evidence.001" -->
## Execution evidence, blockers, and missing evidence

- Planning started from a clean worktree at `392310c665485f8d57c93881e7416c5ebf69d8ef`.
- The primary upstream checkout remains on `main`; all project mutations occur in the declared linked worktree.
- Specification revision 1 is the accepted implementation baseline for this first-PR slice.
- Coherent checkpoints cover the foundation, bounded client, snapshot-validation hardening, settings UI, plan-bound fallback restoration, fork/PR closure, and exact-head CI remediation through validated implementation head `3ff983dd2a04289a5f4554a30a01c132123bc513`.
- SwiftFormat 0.61.1 passes all touched Swift files. `git diff --check`, touched-file width inspection, direct-shell absence inspection, localization-key presence, repository-size checks, shell syntax checks, documentation links, generated `llms.txt`, and site locales pass.
- The portable suite passed parser hashes, provider manifests, bundled plugin generation, package/release path checks, checksum checks, the Python process-cleanup suite, Swift-test sharding, and the CI path gate. Its Homebrew tap fixture could not start because this VPS lacks `jq`; that check is unrelated to the changed paths.
- SwiftLint 0.65.0 cannot load `libsourcekitdInProc.so` without a Swift toolchain on this VPS. The app-locale script also requires macOS `plutil`. These are unavailable checks rather than passing evidence.
- Repository CI executed the synthetic configuration, contract-validation, row-projection, command-construction, failure-redaction, settings-persistence, and coordinator-refresh coverage and passed the complete Linux suites on x64 and ARM64 at validated implementation head `3ff983dd2a04289a5f4554a30a01c132123bc513`.
- The same exact-head run passed SwiftLint, Linux x64 and ARM64 release builds and CLI smoke tests, the static Linux-musl build, both macOS Swift-test shards, the app-locale and SwiftFormat precheck, provider architecture gates, provider plugin goldens, and the aggregate gate.
- GitHub-hosted macOS CI supplied compilation and synthetic native-test evidence for the exact merge candidate. Interactive UI rendering and screenshots, live CAAM, SSH gateway, credential, and mutation evidence remain outside this foundation slice.
- Swift execution and interactive macOS UI verification remain unavailable on this VPS because `swift` is not installed and the complete app target is macOS-only.
- Production switching stays blocked until the CAAM V3 service is composed into a public, versioned gateway adapter with exact operation lookup and recovery semantics.
- The public `Jones-Systems/CodexBar` fork was created from upstream commit `392310c665485f8d57c93881e7416c5ebf69d8ef` and verified as a fork of `steipete/CodexBar`. PR #1 is the delivery vehicle inside the Jones Systems fork. Fork Actions are enabled for PR verification; the inherited scheduled upstream-monitor workflow remains disabled.
- Merge of PR #1 completes the CodexBar foundation slice. Installation on the laptop, VPS, and Mac Mini; gateway provisioning; signing; release; automatic updates; and deployment remain outside this slice's authority and finish line.
<!-- codex-section:end id="worknote.caam-environment-control#ctx.execution-evidence.001" -->

## Combined environment controls and observability hub — 2026-09-05

The owner authorizes one sequential implementation agent in `Jones-Systems/CodexBar`,
on `work/caam-codexbar-observability-hub`, through one draft PR against the fork's `main`.
No live account operation, installation, host-service change, upstream publication, or PR merge is authorized.
The historical foundation evidence above is not evidence for this new candidate.

### Workspace synchronization and plan

- Verified repository root, canonical `origin` (`github.com/Jones-Systems/CodexBar.git`),
  task branch, process/worktree/Git ownership (same UID), clean status, and absence of merge,
  rebase, cherry-pick, and revert state. Initial HEAD is `d6e929cd736eccae187cd41ddb5305a670afb2c8`.
- No uncommitted attributable work needed rescue. The existing foundation remains checkpointed
  in that commit. Fetched only canonical `main`; it is the same commit and already reachable.
  No merge, rebase, reset, clean, or force operation was needed.
- Read the synchronized root `AGENTS.md` (the only in-tree AGENTS file; `CLAUDE.md` resolves
  to it), `VISION.md`, complete accepted control contract, engineering spec, and this Work Note.
- Sequential passes: reconcile implementation/contract and data sources; implement typed control
  and read-only aggregation seams; integrate bounded responsive UI; add synthetic tests; run
  affected checks; self-review correctness/security/maintainability/performance; publish a draft PR.
- Read-only dependency target: `Jones-Systems/CAAM`,
  `work/caam-codexbar-gateway@8fdf44a1c2c3af0d36b934d79725608945790f32`.
  Inaccessible external evidence will not block independent CodexBar work.

## Connector and runtime incidents

### C11 — GitHub CLI body edit failed on a deprecated GraphQL field

- Intended effect/action: update only draft PR #2's description with the final implementation/check/incident summary.
- Safe invocation shape: `gh pr edit 2 --repo Jones-Systems/CodexBar --body <bounded project summary>`.
  No token, environment, recovery-bundle, or permission inspection was requested.
- Native result: exit 1, 52 output tokens; GraphQL rejected `repository.pullRequest.projectCards`, with
  a message about deprecated Projects (classic). This is a CLI/API-schema failure, not evidence of denied
  repository ownership or publication authorization.
- Effect reconciliation: an initial grouped read-only REST/CI-status check was platform-blocked because safety
  status could not be determined; it returned no subprocess exit/session. A simple `gh pr view ... --json`
  then exited 0 (966 tokens), confirming the original PR body was unchanged, draft=true, and head at
  `76616f4b8cfea3aa65fc23c60a8992e0b5af365e`. The attempted body edit had no observed effect.
- Workaround: prepare the bounded description in ignored repository scratch space and use GitHub's REST
  pull-request update through the same bound connector and already-qualified host credential.
- Blocked dependants: description refresh only; branch push and draft creation already succeeded. No new PR,
  force push, credential change, or host installation is needed. Resolution pending the REST postcondition;
  next diagnostic is the updated PR body/head/draft readback.
- Resolution evidence: REST `PATCH repos/Jones-Systems/CodexBar/pulls/2` with a repository-local body file
  exited 0 and returned the existing PR URL (13 output tokens). Subsequent PR readback exited 0 (1740 tokens),
  showed the updated description and C1-C11 reference, and preserved OPEN/draft=true and the exact task head.
  No additional PR or repository setting was created or changed.

### C10 — Bounded CI log preview closed its pipe early

- Intended effect/action: read failed lint diagnostics for this draft PR using `gh api` on its completed job log,
  filter output, and cap the preview with `head`.
- Native result: exit 141 with pipefail enabled; 3437 output tokens. The filter included progress lines,
  so the preview filled before the actual diagnostics. This is a partial read/SIGPIPE, not a failed write.
- Postcondition/workaround: narrow the filter to errors/warnings/summary and use `sed -n` to drain the stream
  while bounding displayed lines. Retry exited 0 (2624 tokens) and supplied all 40 reported lint violations.
- Blocked dependants: first diagnostic preview only. No repository, branch, PR, or credential mutation occurred.
  Remediation of the actual source findings continued. Resolution: resolved; next diagnostic on recurrence
  is pipeline exit/status interpretation, not retrying a publication operation.

### C8 — Standard check entrypoint cannot launch Apple's catalog parser

- Intended effect/action: run the required repository entrypoint `make check`.
- Native result: exit 2 (Make recipe error 1); Node reported `spawnSync plutil ENOENT`, errno -2,
  no child PID/status/output. The bounded response was 328 tokens.
- Effect/postcondition: the script stopped at its first catalog check, before Swift lint-tool installation.
  No tool was installed and no native format/lint result was obtained.
- Workaround: run the available portable feature-catalog checker, documentation-link checker, and index
  checker directly. All exited 0; 111 feature keys in 23 catalogs, 192 documentation links, and the
  existing `docs/llms.txt` index passed. `git diff --check` also exited 0.
- Blocked dependants: native catalog parsing and downstream standard check steps. Source review,
  fixture authoring, portable validation, commits, and draft publication continue.
- Resolution: platform dependency remains absent; next diagnostic is existing CI against the candidate,
  not tool installation on the bound host.

### C9 — A later inspection process could no longer resolve ripgrep

- Intended effect/action: inspect the staged core diff, list fixture tests, and find overlong Swift lines.
- Safe invocation: read-only `git diff --cached` followed by repository-scoped `rg` commands.
- Native result: staged diff returned normally; then Bash reported `rg: command not found`, exit 127.
  The complete bounded response was 2931 tokens. Earlier `rg` invocations had succeeded; cause is unknown.
- Effect/postcondition: no repository mutation was requested by this invocation; already staged content
  remains preserved. The later searches did not execute because the wrapper used `set -eu`.
- Workaround: use Git's built-in grep or standard grep for the remaining read-only inspection.
  Native Swift checks were already unavailable independently; implementation and publication are unaffected.
- Resolution: fallback inspection pending confirmation. Next diagnostic: command availability in the same
  bound workspace, without changing PATH, installing utilities, or inspecting credentials.
- Resolution evidence: `git grep` completed the full in-scope long-line audit with exit 0. Standard Git,
  grep, sed, and Python resolved successfully. The environmental cause of missing `rg` remains unknown,
  but no remaining task depends on it.

### C7 — Inline locale maintenance could not obtain platform safety status

- Intended effect: register missing feature strings as explicit English fallbacks without overwriting translations.
- Actions / safe shapes: connector `exec_command` with relative-path inline Python catalog edits;
  then read-only Python and shell-loop key inspection. Three invocations returned the same
  "couldn't determine the safety status" block, without a process exit, output, or session.
- Effect classification/postcondition: the intended edit was initially unconfirmed. A simple Git diff plus
  English-catalog tail/count read exited 0 (88 output tokens), showed no catalog diff and the original
  1567-line file. Connector file read also confirmed the original modification time. No edit had occurred.
- Workaround: add the bounded, repository-local `Scripts/check_caam_observability_locales.py` through
  `apply_patch`; invoke its explicit `--sync-locales` mode normally. Exit 0, 57 output tokens:
  73 new English keys across 23 catalogs; all 111 feature literal keys have matching format placeholders.
- Blocked dependants: catalog registration only. Source review and documentation continued; no private or
  external data was requested. Resolution: resolved. The script's normal mode is read-only and its sync mode
  reconciles each catalog independently after partial interruption. Next diagnostic: platform classification
  of the original inline calls, not additional repository permissions.

### C4 — Inspection glob did not match an existing source file

- Intended effect/action: read-only search for account-scoped token-cache invalidation using `rg`.
- Safe shape: `rg <cache-symbols> Sources/CodexBar/UsageStore+Account* ...` inside the repository.
- Native evidence: `rg: ...UsageStore+Account*: No such file or directory (os error 2)`;
  the multi-command wrapper exited 0, and the subcommand exit was not retained.
- Effect/postcondition: no mutation. The actual source was found under
  `Sources/CodexBar/Providers/Codex/UsageStore+CodexAccountState.swift` and read successfully.
- Workaround/resolution: use the discovered exact path and `set -eu` for verification command groups.
  No dependent implementation was blocked. Next diagnostic: preserve individual native status when grouping checks.
- Recurrence: a later read-only localization search included nonexistent
  `Sources/CodexBarCore/Localization*`, returned exit 2 (86 tokens), while identifying the actual app
  `Sources/CodexBar/Localization.swift`; that exact file was then read successfully. No mutation or blocked work.

### C5 — Native test discovery cannot launch Swift

- Intended effect/action: run the repository's isolated native test entrypoint, `make test`.
- Native result: connector command exit 2; Make reported test recipe error 1; Python raised
  `FileNotFoundError: [Errno 2] No such file or directory: 'swift'`.
- Bounded evidence: test runner reported zero discovered selections, zero selected groups, and zero executed
  groups. The combined inspection/test response was 3000 reported tokens; no full traceback is persisted here.
- Effect/postcondition: no native tests ran and no account operations were attempted. `swift` is absent from PATH
  and the three checked conventional binary locations. No installation or credential inspection was attempted.
- Blocked dependants: local Swift compilation and native test results. Independent source review, fixtures,
  portable checks, documentation, and publication continue. Existing Linux CI may provide native evidence;
  existing macOS CI policy explicitly defers macOS tests on draft PRs.
- Resolution: toolchain limitation remains. Next diagnostic: native CI outcomes for the exact published HEAD.

### C6 — Repository Git author identity is unset

- Intended effect/action: verify commit attribution with `git var GIT_AUTHOR_IDENT`.
- Native result: exit 128, `Author identity unknown` / `fatal: empty ident name ... not allowed`.
  The surrounding inspection response was 3461 reported tokens; host-derived fallback identity is omitted.
- Effect/postcondition: this read did not create a commit or modify Git configuration.
- Workaround: use command-scoped `-c user.name='ChatGPT' -c user.email='chatgpt-agent@example.invalid'`
  for this agent's commits. Do not impersonate the owner or change global configuration.
- Blocked dependants: commit attribution only. Implementation and checks continued. Resolution will be
  confirmed by the first successful attributed commit; next diagnostic is `git show` author/HEAD metadata.
- Resolution evidence: command-scoped identity produced commit
  `425b0a8ea64c992ed6d2254b56f4e715260d9249` with author `ChatGPT <chatgpt-agent@example.invalid>`.
  No global Git setting was changed.

### C3 — Edit invocation had indeterminate platform safety status

- Intended effect: refactor CAAM snapshot validation and freshness gating in one repository file.
- Action / safe invocation: connector `exec_command`, relative-path Python text edit of
  `Sources/CodexBarCore/Providers/Codex/CAAM/CAAMEnvironmentValidation.swift`.
- Native result: "blocked by OpenAI because we couldn't determine the safety status of the request."
  No process exit, output size, or session was returned.
- Effect classification: initially unconfirmed. Readback showed the original 350-line file with
  its original modification time and unchanged decoder/row logic; the intended edit had not occurred.
- Workaround: after reconciliation, use the connector's repository `apply_patch` operation.
  It exited 0 and explicitly reported the validation file and new typed validator as updated/added.
- Blocked dependants: only that edit. Model work was preserved; interface and test work continued.
- Resolution: resolved through an authorized patch, not a broader access path. Next diagnostic:
  platform safety-classification details for the denied command; do not infer a repository permission failure.

### C1 — Virtual path rejected before command launch

- Intended effect: read-only identity, ownership, Git-state, and remote verification.
- Action / safe invocation: connector `exec_command`, bound workspace (handle omitted),
  `workdir: /project`, command containing `stat /project` plus read-only Git queries.
- Native result: `INVALID_COMMAND_PATH`; tool `is_error: true`; explicitly reported
  "No command was run." No process exit or command session was supplied; bounded error only.
- Effect classification / postcondition: known no effect; subsequent read confirmed exact initial
  HEAD, clean status, and no Git operation in progress.
- Workaround: retain virtual `workdir`, use only relative shell paths (`stat .`). Retry exited 0
  with 233 reported output tokens and verified identity/ownership/state.
- Blocked dependants: initial verification only. Unaffected work continued immediately through
  canonical fetch and guidance reads.
- Resolution: resolved. Next diagnostic on recurrence: distinguish virtual tool paths from native
  shell paths; do not retry a mutation until its actual postcondition is reconciled.

### C2 — Bundled read-only inspection rejected by platform safety

- Intended effect: enumerate in-repository tooling/tests/guidance and read the exact external CAAM commit.
- Action / safe invocation: connector `exec_command` with relative repository searches,
  `command -v`, and a conditional `gh api repos/Jones-Systems/CAAM/commits/<pinned-sha>` read.
- Native result: "This tool call was blocked by OpenAI's safety checks." No subprocess status,
  exit code, output, or session was returned. The platform supplied no narrower cause.
- Effect classification: no repository mutation requested; command execution was not evidenced.
  No external CAAM response was obtained. No bypass or equivalent external retry was attempted.
- Postcondition/workaround: connector file reads and a subsequent command restricted to CodexBar
  inspection succeeded (exit 0, 332 output tokens). Status showed only this agent's Work Note edit.
- Blocked dependant: pinned CAAM implementation/conformance inspection. Independent contract,
  interface, model, UI, fixture, cache, and test work continues from the accepted CodexBar contract.
- Resolution: repository inspection recovered; external dependency remains unverified. Next diagnostic:
  owner-side platform rejection details, not broader credentials or recovery-bundle inspection.

### Implementation reconciliation

- The existing client executes only snapshots; mutation argv exists but typed plans/results and
  execute-once coordination do not. Row capability flags ignore observation age, degraded reachability,
  target eligibility, and the full recovery/status capability set. These are in-scope safety fixes.
- The shared subprocess result omits exit status. CAAM needs bounded error stdout on nonzero exit,
  while retaining redacted diagnostics and rejecting success envelopes on failed commands.
- Existing `CostUsageTokenSnapshot` and `CostProvenance` are reusable read-only inputs. Local session
  estimates, vendor-metered amounts, provider quota windows, and host-resource metrics must not be summed.
- No Netdata implementation, endpoint contract, fixture, or configured host was found in repository
  source/docs/tests. Ship a typed unsupported facade and validated user-supplied dashboard deep links;
  do not invent a Netdata API response or initiate network collection.
- `swift`, `swiftformat`, `swiftlint`, and `jq` are absent from PATH; `gh` and Python are available.
  No toolchain installation is authorized. Native compile/lint results must come from existing CI or
  remain explicitly unavailable; static checks do not substitute for them.

### Implementation pass and early sequential self-review

- Added typed plan/operation envelopes, semantic plan/result validation, native exit and UTF-8 status retention,
  closed redacted error mapping, and a pure execute-once state machine. Unknown effects retain operation identity
  through refresh, failed status lookup, and restart; fallback and interrupted-operation recovery are separate.
- Added source-age mutation gates (60 seconds, 5-second future-skew allowance) and a 15-minute bounded
  stale-while-revalidate display cache. Refresh coalesces, publishes completed environments incrementally,
  and suppresses results for changed configuration generations.
- Added an actor-isolated receipt store containing only validated configuration selectors and operation UUIDs.
  Receipt persistence precedes launch; storage failure blocks launch/qualification. A single application
  coordinator serializes operations and receipt writes; independently constructed test coordinators use fixtures.
- Self-review found potential cross-environment receipt-write races, ID-only qualification reuse after an endpoint
  edit, stale configuration publication, and loss of an unresolved operation after a snapshot with an empty journal.
  Remediated with global operation serialization, full-configuration qualification/binding, generation checks,
  and retained-operation lookup that never treats snapshot absence as terminal evidence.
- Self-review also found display helpers that can read credential-adjacent disk caches. The hub deliberately avoids
  those helpers. It reads existing in-memory provider publications, labels cost as historical/unattributed to CAAM
  accounts, and preserves currency, window, estimate/metered provenance, source timestamps, and confidence.
- Overview, Accounts, Systems, and Work are compact views on distinct typed ledgers. Work materialization is lazy
  and capped at 100 records. No combined utilization/cost total, live-job inference, host metric, or Netdata API is invented.
- Existing test-process detection disables implicit CAAM transports and real receipt-file access. New tests use
  synthetic runners, fixed clocks, memory receipts or temporary fixture-only directories, and no live credentials.

### Core checkpoint review and check outcomes

- Sequential correctness self-review: checked command/response bindings, single-use confirmation, fresh terminal
  postconditions, target matching, no-effect versus unknown-effect distinction, and recovery/fallback separation.
  Existing fixed-date projection tests now inject their observation date rather than depending on wall-clock age.
- Sequential security self-review: checked exact closed argv, rejected relative PATH entries, credential-field
  rejection, error-text redaction, bounded decoding/receipt IO, same-operation lookup, and safe dashboard URLs.
- Sequential maintainability/performance self-review: transport, pure state, persistence, aggregation, and UI are
  separate seams; all arrays/caches/details have explicit bounds; collectors do not read credentials or initiate
  new host/provider scans. No independent review or measured performance result is claimed.
- Added fixture test cases remain unexecuted because Swift is absent. `make test` and `make check` are attempted
  but blocked as C5/C8 describe. Portable catalog coverage, documentation links/index, and whitespace checks pass.
- No live CAAM, SSH account operation, Netdata collection, credential inspection, installation, or deployment ran.

### Presentation checkpoint and final sequential self-review

The second checkpoint connects the typed core to Codex preferences, preserves the existing account-selection
flow, and supplies Overview, Accounts, Systems, and Work views. English catalogs add 73 new keys in each of
23 locales as explicitly labeled fallbacks, not completed translations. The portable checker covers 111 literal
keys across the affected preference/control/hub files, including multiline calls.

| Finding | Disposition |
| --- | --- |
| A failed mutation could otherwise be mistaken for retryable failure | Closed effect classification; execute-once confirmation; same-UUID lookup; terminal fresh snapshot required |
| Refresh with an empty journal could erase a locally unknown operation | Preserve intent through refresh/restart; receipt bound to exact configuration; original-target lookup retained |
| Concurrent operations could overwrite receipt images | One application coordinator and global sequential operation gate; persistence precedes launch; no-effect storage failure cannot dispatch |
| Qualification keyed only by ID could survive endpoint replacement | Qualification and receipts bind full configuration; late-generation observations rejected |
| Cached provider display helpers can inspect credential-adjacent files | Hub consumes only already-published memory snapshots; historical costs are not attributed to CAAM accounts |
| Unlike spend/usage/host measurements could be blended or fabricated | Separate typed ledgers; explicit provenance, confidence, time, currency/window; no combined total; host metrics unsupported and nil |
| Default view construction could reach actual CAAM during tests | Existing test-process detection selects no-launch runner and memory-only receipts; explicit test clients are synthetic |
| Interrupted locale maintenance could leave non-English catalogs incomplete | Sync reconciles each catalog independently and preserves existing values; regression test proves restart idempotence |
| New source lines exceeded the repository's width guideline | Manually wrapped identified new-source lines; native SwiftFormat/SwiftLint remain unavailable, not marked passed |

These are this agent's sequential correctness, security, maintainability, and performance **self-review**,
not independent review. Performance review establishes explicit bounds and asynchronous ownership, not measured
latency. No additional behavioral blocker was found by static inspection; native compilation, tests, and rendered
UI evidence remain required before production qualification or a merge decision.

Actual checks after the presentation pass:

- `python3 Scripts/test_check_caam_observability_locales.py`: exit 0; **5 tests passed**. These test only the
  portable catalog helper (multiline/escaped literals, placeholders, bounds, restart-safe sync), not Swift behavior.
- `python3 Scripts/check_caam_observability_locales.py`: exit 0; **111 literal keys / 23 catalogs**, placeholders match.
- `node Scripts/check-documentation-links.mjs`: exit 0; **192 local links** checked.
- `node Scripts/generate-llms.mjs --check`: exit 0; documentation index current.
- Both unstaged and staged `git diff --check`: exit 0.
- New Swift tests: **29 declared cases** (24 Linux core cases and five macOS coordinator cases), plus fixed-clock
  updates to existing projection/settings tests. They were **not executed** locally; C5/C8 describe exact blockers.
- No screenshot, interactive UI run, native build, native formatter pass, live gateway conformance, Netdata
  telemetry, independent review, installation, or account switch is claimed.

Publication remains one normal push of only `work/caam-codexbar-observability-hub` and one draft PR to the
Jones Systems fork. Production mutation qualification intentionally remains empty; CAAM dependency access,
native platform evidence, translation review, and Netdata API qualification are recorded limitations, not
reasons to withhold the independent implementation from a draft PR.

### Published draft and CI remediation

- Normal non-force push of the task branch succeeded against the verified fork push destination.
  Prior matching PR search returned none. Created **draft PR #2**:
  <https://github.com/Jones-Systems/CodexBar/pull/2>. API readback confirmed OPEN, draft=true,
  base `main`, exact task head, and implementation HEAD `db5e39a36be393724d6efbd85addc5085054a098`.
- Implementation commits: `425b0a8ea64c992ed6d2254b56f4e715260d9249` (typed core/models/fixtures)
  and `db5e39a36be393724d6efbd85addc5085054a098` (app integration, UI, catalog helper/tests, specification).
- Re-fetched canonical main before publication; it remained the original `d6e929cd736eccae187cd41ddb5305a670afb2c8`.
  Worktree was clean; the complete implementation diff covered 51 files, including 23 append-only locale catalogs.
- Existing CI run <https://github.com/Jones-Systems/CodexBar/actions/runs/34002315176> started for that HEAD.
  Path-gate detection passed; macOS native tests were explicitly skipped by draft policy. Linux x64/ARM64
  builds/tests and musl build were in progress at first inspection, not passed.
- CI lint supplied real native evidence unavailable locally: **40 serious violations across 2116 files**, all
  in the touched CAAM/hub sources and fixtures. Findings were unnecessary guard parentheses, mixed multiline
  arguments, missed 120-column limits, and one non-failable fixture Data-to-String conversion.
- Remediation preserves behavior: use named permission booleans, one argument per line for mixed-layout calls,
  wrap long touched lines, and require valid fixture UTF-8. The bounded diagnostic retrieval issue is C10 above.
  The same draft PR receives the remediation commit and normal push; CI will rerun for its exact HEAD.

### Final delivery verification

- Remediation commit `76616f4b8cfea3aa65fc23c60a8992e0b5af365e` was normally pushed and verified as
  the head of draft PR #2. The replacement CI run is
  <https://github.com/Jones-Systems/CodexBar/actions/runs/34002533888>.
- **Native CI lint passed** on that implementation HEAD: completed successfully at
  `2026-09-06T00:57:03Z`, job
  <https://github.com/Jones-Systems/CodexBar/actions/runs/34002533888/job/101403882429>.
  The earlier 40 findings are therefore remediated with successful rerun evidence, not merely source edits.
  This is the existing Linux lint route; it does not establish a macOS SwiftFormat or UI-rendering result.
- Path-gate detection also passed. Linux x64/ARM64 build/test jobs and the musl build remained in progress at
  this inspection. macOS native tests were explicitly skipped for the draft. No unobserved build/test pass is claimed.
- Final metadata-only checkpoint adds C11 and these verified delivery outcomes to this same Work Note;
  it changes no implementation, tests, catalog, contract, or workflow. PR description update used the
  already-qualified REST route after the GraphQL failure, with postcondition readback confirming one open draft.
- Persistent incident evidence is this committed path, `docs/work-notes/caam-environment-control.md`,
  linked from <https://github.com/Jones-Systems/CodexBar/pull/2>. All incidents C1-C11 include bounded
  native evidence, effect classification, postconditions, workarounds, and remaining diagnostics.
