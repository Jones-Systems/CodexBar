# Work Note — Fleet authentication discovery

<!-- codex-section:begin id="worknote.fleet-auth-discovery#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.fleet-auth-discovery`

Purpose: Correct disconnected Codex accounts by reusing the owner’s fleet authentication authority.

Governing artifact: `spec.fleet-auth-discovery`

Continuity owner: root coordinator

Consumers: CodexBar maintainers and fleet-auth implementation

Authority effect: none
<!-- codex-section:end id="worknote.fleet-auth-discovery#ctx.artifact-header.001" -->

## Outcome

Fix CodexBar discovery of existing UMICH, Malcolm and Wallace fleet logins, evaluate Headroom selectively, and report outstanding fork work. Source completion and bounded PR publication are in scope. Installation, privileged operations and unrelated provider-directory repair require their own route.

## Current State And Evidence

- User explicitly authorized parallel subagents and use of the existing fleet authorization credentials. No token or credential content has been read or emitted.
- Canonical fork: Jones-Systems/CodexBar, base `5f4a4c9474d2c44e136275fe5c42689a6c6e7a56`. Primary local checkout is upstream and is not the implementation base.
- Isolated worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/fleet-auth-discovery-20261016`; branch `work/fleet-auth-discovery-20261016`; root is sole Git owner. Core builder owns only the new discovery core and its focused test file. App integration is separately scoped. Root owns docs and Git.
- Fork PR #3 is a draft repository-sync core with disjoint paths. CAAM and Netdata source stacks are merged; installed behavior and live conformance remain unproved.
- Headroom research is pinned to `b1e4aa53ceb86715808fc38348ac38c863252535`; Graphify navigation snapshot is stale and current source controls conclusions.
- Native thread: `0488f286-4c8b-4932-9b44-67ef47cb70a3`; environment `6ec33bac-c2bb-4418-b6c6-c2515a13e8b5`. Registration is unavailable pending a verified native project binding; no project identity is guessed.

## Next Action

Fleet source and its 10 integration tests are implemented. Existing app-managed selections prefer a registered fleet home only on unique exact workspace identity and normalized email; selection removal/unavailable cases fail closed. Core parser tests and integration source cover projection, scoped routing, metadata loss/recovery, duplicates, identity ambiguity and isolation. SwiftFormat and whitespace checks passed. `make test` was attempted and cannot discover tests because `swift` is absent. `make check` was attempted and stops at the macOS `plutil` dependency before source checks. SwiftLint additionally lacks `libsourcekitdInProc.so`. These are unavailable local checks, not passes. macOS CI and native UI evidence remain required.

Owner followup confirmed the native Mac menu. Additional independent source work covers account ordering and cancel/retry re-auth in `/home/malcolmjones/Projects/CodexBar-worktrees/account-auth-controls-20261016`; an Opus 5.5 high Jace Claude task drafts fork-isolation planning/guidance in the Codex V3 worktree, followed by requested fresh Opus extra-high review. Frontier mode applies prospectively; already launched builders keep their accepted tuples.

Read-only independent lanes: `headroom` evaluates useful reset/pacing/ranking ideas; `auth_diagnosis` traces current fork credential discovery and supplies minimal fix framing; `codexbar_status` completed current PR/source inventory. Coordinator consolidates results, binds source changes and synthetic checks, then publishes the fix. No launch depends on Headroom adoption.

Headroom evaluation completed against public revision `b1e4aa53ceb86715808fc38348ac38c863252535`:

- Consider compact limiting-window and exact-reset explanations; do not add its separate dashboard or vault.
- Account ranking by the smallest remaining quota is already present in CodexBar. Headroom does not incorporate plan size, task needs or reset timing into that rank.
- Existing CodexBar historical/workday pacing is broader; only consider missing freshness, sample-span and idle-use quality gates after a demonstrated gap.
- Signed webhooks could become future machine signals. Headroom does not implement account/session/agent handoff; its documented “Hand-off” is alert replacement, and ACP is out of scope.
- Skip Wallet, Telegram, credential storage, login duplication and reset redemption in this scope. No Headroom code is copied. Its MIT license and any third-party notices would govern future copying.

Primary evidence: [ranking](https://github.com/amitray007/headroom/blob/b1e4aa53ceb86715808fc38348ac38c863252535/apps/web/src/views/compare/compare-model.ts#L174), [timeline](https://github.com/amitray007/headroom/blob/b1e4aa53ceb86715808fc38348ac38c863252535/apps/web/src/views/timeline/tips.ts#L64), [pace estimator](https://github.com/amitray007/headroom/blob/b1e4aa53ceb86715808fc38348ac38c863252535/packages/view-model/src/pace.ts), [alert hand-off](https://github.com/amitray007/headroom/blob/b1e4aa53ceb86715808fc38348ac38c863252535/docs/architecture/notifications.md#L68), [ACP boundary](https://github.com/amitray007/headroom/blob/b1e4aa53ceb86715808fc38348ac38c863252535/docs/research/acp.md#L27). Source-level findings do not establish runtime accuracy.

## Blocker Or Decision

Requested cross-provider plan task: `node:delegated-task:command%3Amcp%3A3794ecaf-e0be-474c-9ff6-2d313aa3bc3b%3Adelegate-task%3Acodexbar-fork-guidance-opus-high-20261016-r1`, `claudeAgent_jace_claude`, `claude-opus-5-5`, `effort=high`. Fresh requested `effort=xhigh` review must be launched with a distinct delegate_task request after its result; never send continuation to backing childThreadId. Source target for planning/guidance is Codex V3 branch `t3/fix-codexbar-fleet-auth` at `214a9c36a9e5620f17ccb5e86344149a7ebb564b`.

Local verification update: SwiftFormat 0.61.1 from the existing caam-environments worktree matches the current pinned version and can run. SwiftLint 0.65.0 cannot load libsourcekitdInProc.so without Swift; native test/build execution is unavailable. No new host toolchain was installed.

Do not treat valid Jones Code authentication as proof CodexBar can discover it. The current Jones Code catalog recognizes Malcolm/UMICH authentication but reports Wallace provider startup failure due to a pre-existing non-symlink generated-images entry; no repair is authorized by inference. Swift is absent from the VPS PATH; native build/test availability remains unresolved. No sudo use, live Keychain probe, new login, or automatic credential rotation is planned.

## Independent correctness review and deferred findings

Source review `account-fixes-review-ccafd932-r1`, native task `/root/account_fixes_review`, profile `codex-v3-code-reviewer` (Astra/high), reviewed exact `ccafd932fa8e7f9160ab1dd133677e8d622b45bc`. Finding record: [immutable source-bound review record](../review-evidence/account-fixes-ccafd932.json), SHA-256 `4218de156c65d72241f8d00eb7f50ef6cc8cd473fd65dd02629f583112ad4a62`. The source review's original severity and blocking effects remain unchanged:

- AFR-001, P2: a missing selected profile hides healthy alternative accounts, preventing explicit recovery selection.
- AFR-002, P2: ambient cancellation releases the shared-auth/promotion gate before the previous login process has drained; late UI guards do not exclude overlapping filesystem writers. No live overwrite was observed.

Both are deferred under the owner's standing P2–P4 instruction; neither is corrected or accepted as proof of runtime readiness. Continue source publication and CI. Installed trial readiness retains these original blocking claims until exact owner-directed work or valid bounded disposition resolves them. No mid-workflow approval question is created by these findings.

Owner clarification: the laptop runs the standard CodexBar app. This fork has not been installed or tried on any machine. The reported symptoms are motivation and acceptance requirements for the first usable fork trial, not a reproduced defect in a deployed fork. First-trial readiness also needs an explicit fork app/update-feed identity decision.

Post-integration affected checks: all 26 changed Swift files passed SwiftFormat together. Three unchanged preferences gatekeeper anchors were updated to their new source lines with exact base/head anchor checks. The account-order extension moved under its existing Codex provider ownership boundary without content changes, avoiding new generic-provider suppressions.


## Local account switching requirement clarification

The owner requires one local CodexBar account selector that determines the account used by subsequent standalone Codex CLI/thread and Codex desktop app launches on the laptop. Fixed-profile usage enumeration alone is insufficient. This does not request VPS or Mac Mini switching. Usage must continue reading existing canonical Authfleet homes. The earlier fixed-profile-versus-launcher question is resolved as product intent; the implementation mechanism still needs source and laptop evidence. No live credentials, auth switching, launcher changes, or installation have been attempted. A read-only source investigation is checking desktop and CLI account-loading semantics; the owner offered a laptop evidence thread. Claude Authfleet authentication fixes are being handled separately.

CAAM retirement was integrated through merge 2fb2df0d6a965af247fad23a15d530554177f2fe (lane commit 082cd4943). This does not resolve the two findings preserved in account-fixes-ccafd932.json. First-trial readiness remains unproved.

Final integrated portable verification: source-absence test (1), locale-checker tests (5), feature locale coverage (80 keys across 23 catalogs), SwiftFormat lint (35 surviving changed Swift files), and whitespace passed. Fresh CPU admission was 3.75% used, 41.68 GiB available, one fully used core 6.25% of host capacity; one serial check process. Temporary check storage was context-managed under .build and removed. Native checks remain unavailable as recorded above.
