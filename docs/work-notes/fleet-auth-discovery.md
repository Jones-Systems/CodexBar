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

## Delivery record

The owner explicitly directs requested CodexBar work through merge and the local
Jones app update without another routine permission question. The standing
repository binding is recorded in `AGENTS.md`, section “Delivery and local app
updates”.
Owner direction on 2026-10-20: “You should always go and get your PRs merged in,
get the app updated whenever I'm requesting changes and all that, and get it all
installed.”
It covers PR #7 and later routine requested changes, replacing the historical
five-PR migration restriction for this delivery scope. Explicit future review
holds, native consent, failed verification and unknown effects retain their gates.

PR #7 delivers the complete fleet presentation, cached observation selection,
friendly labels and native-Claude menu-width repair. Its production candidate
`a102e500bbfbf7b0c5432e34121cb499fac18fc1` passed all eight hosted checks in
[run 39365319729](https://github.com/Jones-Systems/CodexBar/actions/runs/39365319729).
Full native `make test` passed all 1,040 selections in 87 groups, first attempt,
with no retries or timeouts; `make check` passed. Source hashes, owned process
drain and fixture-parent removal/absence were verified. The same unchanged
regression measured 408 points before the width repair and passed at 310 after.

The arm64 ad hoc Jones app built from that production candidate was installed
and opened at its verified Jones bundle/executable path. Its previous bundle
is retained for rollback; no preference migration, label seeding, credential
copy or system-account change occurred. Live screenshot verification remains
unqualified because the menu read back closed while concurrent pointer activity
was observed; further UI interaction stopped. Native synthetic layout proof
passed. This documentation-only delivery binding does not change app, test or
script bytes and needs no app replacement. Its current CI and merge result belong
to the [native PR](https://github.com/Jones-Systems/CodexBar/pull/7), rather than a
premature source claim of merge completion.

The delivery-binding documentation passed the link checker (250 local links)
using the existing Node 20 executable, `git diff --check`, and repeated
`make check`: zero SwiftLint violations in 2,160 files, 95 synthetic cleanup
checks with one declared skip, and six owned fixture parents removed with
absence verified. All compiled source, test and script bytes remain identical
to the fully tested production candidate. The default Node 24 executable was
unavailable because its existing simdjson library was missing; no tools were
installed. The configured formatter excludes these Markdown paths, so its
empty target result is not formatting evidence; the bounded diff was inspected.

FICR-COR001 remains deferred and uncorrected with its original P2 severity and
blocking claim. Other deferred findings and the seven original trial gates remain
unchanged. Registration remains unavailable pending a verified native project
binding; no registry repair or identity guess was attempted.

The state and next-action entries below are intake and checkpoint history, not
current blockers. The native PR and this delivery record own the current result.

## Intake outcome (historical)

Fix CodexBar discovery of existing UMICH, Malcolm and Wallace fleet logins, evaluate Headroom selectively, and report outstanding fork work. Source completion and bounded PR publication are in scope. Installation, privileged operations and unrelated provider-directory repair require their own route.

## Intake state and evidence (historical)

- User explicitly authorized parallel subagents and use of the existing fleet authorization credentials. No token or credential content has been read or emitted.
- Canonical fork: Jones-Systems/CodexBar, base `5f4a4c9474d2c44e136275fe5c42689a6c6e7a56`. Primary local checkout is upstream and is not the implementation base.
- Isolated worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/fleet-auth-discovery-20261016`; branch `work/fleet-auth-discovery-20261016`; root is sole Git owner. Core builder owns only the new discovery core and its focused test file. App integration is separately scoped. Root owns docs and Git.
- Fork PR #3 is a draft repository-sync core with disjoint paths. CAAM and Netdata source stacks are merged; installed behavior and live conformance remain unproved.
- Headroom research is pinned to `b1e4aa53ceb86715808fc38348ac38c863252535`; Graphify navigation snapshot is stale and current source controls conclusions.
- Native thread: `0488f286-4c8b-4932-9b44-67ef47cb70a3`; environment `6ec33bac-c2bb-4418-b6c6-c2515a13e8b5`. Registration is unavailable pending a verified native project binding; no project identity is guessed.

## Intake next action (historical)

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


## Current fleet-account presentation repair

The owner tried the separate Jones app built from standalone main
`7138b98b978381be69a08b0c7acedae6549a783c` and supplied four screenshots.
Codex shows wrapped account tabs, Claude shows one selected native account,
Overview shows one card per provider, and selecting a different Codex account
can retain an empty usage card with a newly updated subtitle. The owner wants
all enrolled Codex and Claude accounts listed together, with compact rows and
optional expanded detail. Existing Jones preferences must survive updates.
The owner explicitly authorizes installing and opening updated Jones builds;
this does not authorize copying credentials, promoting a system account,
reading protected stores, or terminating unrelated processes.

The active worktree is the root-owned `work/codexbar-install-transition-506fc1fd`
branch. The installed app is a copied artifact; source edits do not mutate it.
The prior research and verification entries above are historical. The public
standalone repository migration and PRs #1–#5 are merged. Native source checks
previously passed; these new changes require their own verification. AFR-001
and AFR-002 corrections were integrated before this candidate; their old
source-bound review record remains preserved.

Research uses two independent read-only source lanes, not live provider probes:

- Account-menu evidence: unset multi-account layout is segmented; compact
  Codex rendering and usage fan-out are gated by stacked layout. The existing
  compact renderer supports selected-card collapse and five initial rows, but
  a separate pre-planning six-account cap discards later accounts. Claude
  native enrollment supplies a single-profile picker; claude-swap is a separate
  external adapter. Overview maps one card per provider.
- Account-usage evidence: per-home Codex fetching already scopes CODEX_HOME and
  rejects stale or mismatched publication. A likely rendering defect retains
  the placeholder when fresh quota changes the card's tracked geometry, while
  the subtitle independently adopts fresh provider state. This is a source
  hypothesis with a cheap synthetic reproduction, not a live-fetch failure
  diagnosis. Native Claude has no per-profile fleet snapshot collection yet.

Claude Frontier is explicitly selected. The Jace Opus 5.5/high planning task
`codexbar-fleet-menu-opus-506fc1fd-7138-r1` owns the initial experience and
technical recommendation; root owns synthesis encoding, Git and delivery.
The recommendation is complete and encoded in the Engineering Spec. Builders have disjoint
write cones and use synthetic profile discovery, injected transports and the
repository's Keychain/Codex/session-file isolation. Tests run serially under
fresh same-host admission; no tools are installed to make checks pass.

Registration: `registration_unavailable` before submission. The current native
thread/environment are known, but an enrolled host/project identity and last
accepted registry revision have not been established in authorized context.
No identity is guessed and no registration request was sent. The register-thread
skill permits bounded implementation to continue with that limitation recorded.

Next: consume the planning result, mature the existing Engineering Spec,
implement the account view and refresh repair, run required checks, publish
current-head CI evidence, and prepare the next local Jones build. Any new PR
must satisfy a merge binding that covers it; the migration's #1–#5-only binding
is not silently expanded. Existing deferred findings and unrelated held scratch
remain outside this repair.


Implementation checkpoint: Slice A owns hosted-card refresh/readiness and its
focused tests. Slice B owns Codex layout defaults, complete account lists and
bounded fetch fan-out plus focused tests. Root owns shared .build/test state;
builders do not start competing SwiftPM builds. Claude aggregation follows B;
Overview follows both account projections. The native planning result reported
a shortened HEAD typo; the authoritative source is the exact root-verified
`7138b98b978381be69a08b0c7acedae6549a783c`, not that shortened text.


Owner follow-up: quota eventually appears after selecting another Codex account;
this narrows the symptom to latency/presentation rather than proving failed
account authentication. Selection invokes a new scoped refresh, while existing
per-account memory/disk snapshot caches are present. Preserve cached values with
honest freshness during refresh; do not remove identity/authorization guards to
make a cache hit. The account-view buttons select CodexBar's observation source;
they do not promote the laptop's system authentication. System Account promotion
remains a separate explicit operation outside this repair's runtime validation.

The owner also requests short friendly account labels, with personal label
preferences kept local rather than hardcoded personal identities/emails in
public source. The exact local display labels are supplied in the native owner
message; generic public code should consume aliases or a local display override.
A bounded existing-label/API investigation is in progress before its writer cone
is assigned.

Checkpoint r1 compiled the changed app but stopped on two readiness dictionary
keys using UsageProvider rather than ProviderInstanceID. Zero tests executed;
this is a failed check, not cache-isolation proof. Its direct process drain and
owned fixture-root removal passed. The narrow source/test key correction is
complete and r2 reuses the same focused selection. Claude aggregation remains
held until the synthetic cache proof actually passes.

Checkpoint r2 also stopped before test execution: the new readiness test's
nested selector needed explicit main-actor isolation. The narrow annotation is
corrected. The harness proved process drain and removed its invocation fixture
parent; r3 repeats the same focused selection with the correction. No cache
proof is claimed from compilation. The verifier owns the serial build/test
lease and records exact source digests under `.build/fleet-repair-evidence`.

Friendly labels have an isolated writer worktree, branch
`work/codexbar-friendly-labels-506fc1fd`, based on the same exact main revision.
Root remains its sole Git owner. This permits source work without changing files
under the native compiler. Label precedence is a local override, a validated
fleet alias, then a generic stable account discriminator. Raw provider identity
remains available to ownership/freshness guards; display labels cannot change
snapshot matching. Personal preferences are not embedded in public source.

The document-section frontdoor was unavailable: its source CLI reported
`invalid_repository` for this verified linked worktree. Manual section-marker
validation passed for both existing artifacts. This is a tooling limitation,
not a successful native section-tool check.

Checkpoint r3 compiled successfully in 115.97 seconds. Its loaded test binary
passed the three Claude cache-isolation tests, including both parameterized
selection directions: four actual cases. This clears Slice C's cache prerequisite;
the remainder of the focused union is still pending at this checkpoint. Slice C
may now implement serial side-profile fetching without claiming live account
availability. Friendly-label source is separately checkpointed before normal
integration into this branch.

R3 final readback passed 26 XCTest cases plus 317 Swift Testing cases. This
includes the nine-account/three-in-flight and cancellation regressions; those
XCTest classes were present separately from Swift Testing's summary. Its owned
fixture parent was removed after verified drain. The label suite and subsequent
C/D/cache-retention source were not part of that compiled candidate and require
the next focused union. Filenames extending another suite are not selectors:
Overview submenu cases belong to `StatusMenuTests`, and weekly-reset cases to
`CodexAccountScopedRefreshTests`.

Source checkpoints: A/B/cache proof `9f83ad09`, friendly labels
`e5fd486d88099e37cf2f78ddfad3ffee29d5dd1a`, normal integration
`b6857cd06b42d55a5954d1782bd494b018b76ebb`. Root remains sole Git owner.
The bounded cache-retention repair reuses synchronous uniquely matched owner
hydration, retains valid sibling rows on segmented refresh, and preserves
authentication-failure invalidation. Overview uses matching cached snapshots
independently of the provider-tab layout. Neither path changes system login.

The coherent C/D/cache candidate is frozen for r4's expanded native union.
SwiftFormat 0.61.1 from the existing pinned cache formatted 15 of 42 owned Swift
paths; no tool was installed. Full `make test` and `make check` remain due.
Source publication may proceed while this bounded local verification runs;
publication does not turn pending checks into passes.

One independent focused correctness pass reviewed r4's exact frozen file hashes.
It reported FICR-COR001, P2, preserved in
`docs/review-evidence/ficr-r4-001.json`: a selected main snapshot may be associated
with a newly changed enrollment identity between publication and aggregation.
The original blocking claim concerns complete discovery-identity isolation;
no credential exposure or operational effect was demonstrated. It is deferred
under the standing P2-P4 instruction, uncorrected, without a mid-workflow owner
question. No additional supported findings or further review round were added.

PR #7 published `9c8cd86b6ef95039831c555d82db7e690c00fbe2`. Its lint job
`118368983725` in run `39343052876` failed SwiftLint argument-formatting and
function/type/file-size checks. The completed job log is retained locally under
`.build/fleet-repair-evidence/publication-r1`; no tool installation is needed.
Lint repairs use the existing friendly-labels worktree under root's sole Git
ownership, preserving every test and moving cohesive unchanged declarations
instead of changing rule limits or adding suppressions.

R4 completed against source/test bytes matching that exact published head:
31 XCTest cases passed; 677 Swift Testing cases in 49 suites reported six issues
in four tests. All requested selectors executed. Native-profile aggregation,
selected-account cache, short-label, and credential-cache-isolation suites passed.
The Codex stale-selection regression exposed cached hydration during stale-result
owner reconciliation; its original assertions remain the regression contract.
Three new menu tests omitted the existing lazy menu-population seam before
inspecting rows; their setup is corrected without weakening assertions.
The harness verified process drain and removed its exact invocation fixture
parent. Detailed results remain in `checkpoint-r4/result.json`; this failed
checkpoint is not superseded by the earlier R3 pass.

Repair checkpoint `3c8df9e33fff721114bf57ba443ec482f0a193d0` preserves all
tests and assertions. Stale owner reconciliation disables cache hydration;
explicit selection and refresh preparation retain it. Four menu setup sites
now use the existing lazy open-time population seam, including an exclusion
case that otherwise passed vacuously against an empty menu. The extracted
declarations preserve their behavior and actor context. `make check` passed
with SwiftLint reporting zero violations in 2,160 files. All five pinned lint
tools were reused without downloads; synthetic harness cleanup and fixture
absence were verified. This result is bound to the second worktree's exact
source hashes, normally fast-forwarded into the install-transition worktree.
The repaired native union and full `make test` remain due; the original
FICR-COR001 P2 is unchanged and deferred.

R5 completed on `61d410914561b45869df99003f349cc69408c5cb`: 31 XCTest cases
passed; 677 Swift Testing cases reported two issues in the single six-account
Overview test. All 34 selectors executed. The stale-selection race, native-Claude
menu, and single-account Overview cases that failed R4 now pass. Source hashes
were unchanged; process drain and invocation scratch absence were verified.
The remaining Overview fixture configured Claude after seeding Codex; that
configuration revision invalidates the seeded projection. Configure Claude
before seeding Codex so the assertions inspect a current projection.

Hosted run `39344683839`, macOS shard job `118374700011`, failed eight issues
in grouped-account tests that still expect the old five-row default budget.
The accepted Codex default now shows every account. Preserve finite-budget
planner coverage through an explicit finite policy and separately assert the
new Codex default, including six and nine accounts. Lint and all three Linux
build jobs passed on `61d4109`; the other macOS shard was still running at
observation. Neither partial CI nor the failed R5 is a full-suite pass.

R6 on `35bf977e9d10070fac0b816bda96e8f47229328f` ran 40 tests in four
suites. All planner and grouped-account cases passed, including the original
finite-budget matrices and new unlimited Codex policy cases. The same Overview
test still reported two missing-row issues: changing fixture seed order was
insufficient. Source hashes stayed unchanged; drain and fixture absence passed.
The verifier stopped the sequence, so no R6 `make check` or full `make test`
was started. Further Overview diagnosis must trace the complete population
path rather than assume the earlier fixture hypothesis resolved the failure.

Hosted job `118385589844` in run `39348107517` failed the architecture
gatekeeper on `35bf977`: the new provider-specific label construct lacks a
specific justification, and affected menu/provider constructs have stale
reviewed anchors after the repair's moves/formatting. Repair only verified
affected catalog entries and the specific design justification; retain all
architecture checks. The completed log is retained under
`.build/fleet-repair-evidence/publication-r1`.

The subsequent Overview trace identified the remaining fixture defect:
`makeMenuDescriptor` obtains Codex account information, whose environment
resolution reads reconciliation and rebuilds the cached projection. Fabricated
menu rows alone therefore disappear before Overview rendering. The fixture now
injects immutable synthetic observed accounts, derives actual projected IDs,
and seeds matching usage identities. It asserts projection stability around
descriptor construction while retaining row counts, ordering, navigation and
strict wrong-owner/ID rejection. No production behavior is changed by this
fixture repair; native execution is still required.

The architecture repair relocates 79 existing anchors to exact unchanged
source lines, retains their reasons, adds 11 individually justified constructs,
and updates one refresh fingerprint from seven provider references to six after
the removed Codex clearing branch. A near-code comment explains Claude label
identity. Scanner implementation and existing test bodies are unchanged; no
new suppression or rule relaxation was added. SwiftFormat passed over the
three affected Swift paths. The actual gatekeeper and Overview checks remain
pending on this source candidate.

R7 on `ab95df0ffff2e0bccf268c87bbda31d309cbc866` stopped before test
execution because Swift Testing's `#require` expansion rejected the key-path
predicate passed to `first(where:)` in the repaired fixture. Replace the three
equivalent active-account lookups with ordinary predicate closures; retain the
same assertions and selection semantics. Zero tests executed, so neither the
architecture repair nor Overview is qualified by R7. Process drain and exact
fixture-parent removal passed; subsequent checks were not started.

R8 on `754b5bb47d7268b99fc5ab907e5801f63da4c052` compiled and ran 65 tests
in four suites. Overview, grouped-account and label suites passed, including
the previously failing six-Codex/two-Claude Overview case. The architecture
check reported one remaining mismatch: the refresh-failure cluster at line
842 has four references, including Codex cache failure handling at relative
line 22, rather than the catalog's three. Correct that exact fingerprint and
clarify the changed failure cluster's reason. The generic reason inspected by
root belonged to this pre-existing entry; the eleven new entries already had
specific provider/behavior reasons and remain unchanged.
Source hashes stayed unchanged; process drain and fixture absence passed.
The verifier stopped before `make check` and full `make test`.

R9 on `e6317b3a8b356256d0bac98b084c70b2671fa71f` passed all 41 architecture
tests, including the previously failing cross-provider cluster check. Overview,
grouped-account and display-label source/test bytes retain their R8 passing
results. Current-source `make check` also passed: SwiftLint found zero violations
in 2,160 files, five pinned tools were reused without downloads, and 95 synthetic
cleanup checks passed with one platform-specific skip. All six invocation fixture
parents were removed and their absence verified.

Full `make test` is now running with normal complete discovery/grouping, no
inherited shard/filter selectors, synthetic file/Keychain isolation and the
existing process-drain/cleanup lifecycle. Full-suite completion, current-head
hosted CI and the next local app update remain pending. Root's following
documentation-only checkpoint may advance HEAD during this run; compiled
source, tests and scripts remain frozen and require final hash comparison.

Full native attempt `final-test-r1` failed on unchanged
`c5cdc4f50de308d5224ec65d7a4136adc7aca552`: all 1,040 discovered selections
were selected in 87 groups; 79 groups passed, group 80 failed, and seven groups
were not reached. There were no retries or timed-out groups. The failure was
`ordinary refresh keeps selected token account warning episodes independent`
in `UsageStoreAccountQuotaWarningTests`: expected First/Second warnings, got
none. Hosted job `118399782186` in run `39352512518` reported the same failure.
The fixture's ordinary-refresh stub and the changed default stacked path need
inspection before another run; preserve both warning assertions and synthetic
transport control. Full-suite success is not claimed. The harness verified
process drain, removed its invocation parent and verified absence; tracked
source/test/script hashes remained unchanged.

The warning fixture repair explicitly selects segmented ordinary refresh, retains
both original tests and their six-observation warning assertions, and verifies
that each injected outcome is consumed exactly once. Both stores now use
in-memory settings/credentials, synthetic contained homes and widget paths,
and a rejecting provider pipeline so accidental fan-out cannot invoke a provider
transport. Production notification behavior is unchanged. Root inspected the
released builder diff; SwiftFormat and diff whitespace checks passed. Focused
native execution, repeated `make check`, and complete `make test` are pending.

R10 on `426edcd249bf407e441987fc667c34a2ae07dfc0` passed both quota-warning
tests (two tests, one suite), retaining both account-warning assertions and
proving the ordinary refresh consumed all six injected responses exactly once.
Build took 69.45 seconds; the suite took 0.084 seconds. Its owned fixture parent
was removed after process drain and absence was independently verified.
Repeated `make check` (`final-check-r3`) also passed on that source: zero
SwiftLint violations in 2,160 files, all five existing pinned tools reused
without downloads, and 95 synthetic cleanup checks passed with one platform
skip. Six owned fixture parents were removed and absence verified. Source,
test and script hashes remained unchanged throughout both checks.

Full `make test` attempt `final-test-r2` is now running through the supported
complete-discovery path with synthetic isolation and no inherited selectors.
This following work-note-only checkpoint is authorized during the run; the
verifier must compare all compiled source/test/script hashes at completion.
Full-suite success, replacement-head hosted CI, installation and launch remain
pending. No provider login, credential copy or system-account change occurred.

The prior full native run `final-test-r2` completed successfully: all 1,040
discovered selections in 87 groups passed on their first attempt, with no
retries or timeouts and normal declared skips. Compiled source/test/script
hashes were unchanged through the documentation-only advance to
`0fcb196ff1d8c919db01117246a00aa256148ff3`; process drain and exact
fixture-parent removal/absence were verified. All eight hosted checks passed
on that head. The Jones arm64 ad hoc bundle was built with automatic smoke
launch skipped, installed through exact-path recoverable replacement, and
opened with its build/path identity verified. The prior Jones bundle remains
retained; stock CodexBar, credentials and system authentication were untouched.

The owner's subsequent screenshots show native Claude `default` and a named
profile together, resolving the prior local profile-selection UI uncertainty.
The owner corrected one display label; only its obsolete local label override
was removed, and the supplied Overview screenshot confirms the correction.

The owner then reported menu width growing to roughly 410 points while the
Overview cards remain narrow. On `0fcb196`, the shared menu width deliberately
measures every enabled provider's native actions. Selecting native Claude
adds the long “Manage selected native profile in Claude Settings…” action,
which widens every merged tab. Keep the existing wider-label behavior for
other legitimate actions; shorten this settings action without changing its
destination. A synthetic selected-native merged-menu regression will prove
the ordinary 310-point width and action routing. Root remains sole Git owner
and documentation/build owner in the existing dedicated transition worktree.
The builder owns only the affected Claude action label and menu tests.
Regression red/green, affected menu suites, repeated `make check`, full
`make test`, replacement-head CI and the next Jones app update are pending.
The existing PR #7 merge hold and deferred findings remain unchanged.

Width regression red phase on `0fcb196` reproduced the exact reported change:
`./Scripts/test.sh --command swift test --no-parallel --filter
StatusMenuClaudeNativeProfileAccountsTests` measured 408 points instead of 310
for Codex, Claude and the Overview-style descriptor. The other four tests
passed. The unchanged regression file and production preimage were hashed;
only the new test was present, with production source unchanged. Runtime was
88.16 seconds including 78.62 seconds compilation. Source hashes were stable,
owned processes drained, and the exact fixture parent was removed with absence
verified. This is synthetic AppKit measurement, without live account access.

The width repair changes only the native Claude settings action label and its
existing integration expectation; the regression itself remains byte-identical
to the red phase. The affected native union passed 187 tests in three suites:
`./Scripts/test.sh --command swift test --no-parallel --filter
'StatusMenuClaudeNativeProfileAccountsTests|ClaudeNativeProfileIntegrationTests|StatusMenuTests'`.
The 310-point regression and unchanged legitimate expansion/rendered-window
contracts passed. Total runtime was 118.55 seconds, including 82.59 seconds
compilation and 28.261 seconds test execution. Source hashes remained unchanged
and exact fixture-parent removal/absence was verified.

The exact red-phase command also passed unchanged on the repair (five tests,
9.19 seconds including SwiftPM startup). Repeated `make check` passed in
75.75 seconds: zero SwiftLint violations across 2,160 files, existing pinned
tools reused, 95 synthetic cleanup checks with one declared platform skip,
and six exact fixture-parent removal/absence receipts. Source/test/script
hashes remained unchanged. Full native `make test`, current-head hosted CI
and the next exact-path Jones update remain pending at this checkpoint.

## Menu details follow-up intake

Owner requested restoring credit balance visibility with Show credits and extra usage enabled; restoring weekly reset information in compact account rows; adding the nearest unexpired banked-reset expiry at the far right of the second line; and correcting inconsistent row spacing, clipped cards and excess space below Quit during menu updates. The six supplied October 20 screenshots include the prior app as a visual reference. Preserve friendly labels, full fleet lists, observation-only selection, current preferences and all existing deferred findings. Delivery includes isolated native verification, current-head CI, merge and local Jones app installation/open under the standing repository binding.

Root remains sole Git owner of `/Users/malcolmjones/Projects/CodexBar-install-transition-506fc1fd`, branch `work/codexbar-install-transition-506fc1fd`, advanced normally to canonical merge `a0635c58983a8ecff96615f924d1751f90cf36fe`. No open PRs overlapped this follow-up at intake. The installed Jones app is production build `a102e500`; its binary SHA-256 is `05e9e15b2950f0bd719b0a4ca0ed8abdf0c936512680de779b3741b563c40c39`. Stock app and authentication remain outside the repair.

Claude Frontier initial framing task `codexbar-menu-details-opus-506fc1fd-r1` uses the verified Jace provider and Opus 5.5/high. The account route authorized dispatch with allowance unavailable (`fleet_managed_allowance_unsupported`, companion `account_authentication_unverified`); no quota is inferred and no login is attempted. Initial framing owns diagnosis of all symptoms before builder scopes are assigned. Root prepares delivery mechanics only, avoiding duplicate investigation. Native registration remains unavailable because the target repository's native project binding is not proved; no identity is guessed or registration runtime repaired.

### Menu details diagnosis and implementation assignment

Opus 5.5/high completed the read-only framing at canonical base `a0635c58`. Explicit per-account credits already reach the cards but are discarded by the override-card adjunct gate. Compact text comes from a constrained-window helper without reset timing. The geometry hypothesis is positional hosting-row reuse with changed heights and no native item-change notification; synthetic reconciliation must prove the repair rather than treating screenshots as AppKit-internals proof.

Three independent write lanes: credits projection/view/tests; compact Codex detail helper/row/controller/tests; and native row reconciliation/height refresh/tests. All use the same owned worktree with explicit disjoint paths and root-only Git/test/build ownership. Root retains documentation and delivery. Existing compiled source preimages are captured under the ignored invocation evidence directory for deterministic failing-before validation. Tests/builds wait until every source writer freezes.

Initial baseline attempt compiled substantial unchanged test code but failed in the new Overview fixture because it assigned the read-only reset-style property. Root stopped only the verified invocation-owned fixture runner through its registered SIGTERM cleanup, which drained children and removed/verified its exact scratch parent. The candidate production bytes were restored in `finally`. This attempt is a compiler failure/cancellation, not behavioral red evidence. The fixture is being corrected through the existing lane; screenshot-specific balance values in new tests were replaced with arbitrary synthetic data before publication.

The second baseline attempt compiled successfully and exercised 28 tests: expected account-balance and cached-row/resize assertions failed (14 issues), while the ordinary reconciliation control passed. Candidate restoration and fixture-parent removal were verified. The identical 28 tests then passed on the repaired production bytes, with unchanged test hashes and verified cleanup. The first affected union exercised 516 Swift Testing cases and 35 XCTest cases (13 existing screenshot-render skips); its four issues were confined to the new Overview detail fixture comparing different synthetic labels. Reset and expiry values matched. The owning lane is correcting comparable fixture identity inputs before the final union.

After supplying the same resolved label map to the synthetic compact path, the affected union passed: 516 Swift Testing cases and 35 XCTest cases, including 13 existing opt-in screenshot-render skips. The cached-switch/expand-collapse integration passed. The initial `make check` completed its synthetic checks and six fixture cleanup receipts, then reported two new lint violations: card-view file length and observer removal outside `deinit`. The owning disjoint lanes are correcting these structures without relaxing assertions or adding lint suppressions.

Both lint repairs are frozen: the unchanged balance presentation helper moved into the existing Codex credits view file, and the notification recorder now removes itself in synchronous `deinit` while tests retain its lifetime through scope exit. Final `./Scripts/test.sh --command make check` passed with zero lint violations in 2,160 files and one invocation-owned workspace fixture parent, removed with verified absence. Final affected native verification is rebuilding the frozen candidate; full `make test`, exact-head hosted CI, guarded merge and the local Jones update remain required. Source publication may overlap those pending native checks; no merge or install is qualified by publication alone.
