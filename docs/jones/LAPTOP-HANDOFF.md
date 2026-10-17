# Laptop native verification and continuity handoff

Authority effect: none. This replaces the old c2a3118 PR11-only handoff. Source stays
on VPS; laptop thread `506fc1fd-d94f-4616-84f4-7751eda0aec8` in environment
`8750edf7-486b-41ac-81ce-cd50dfeb71eb` retains continuity, native verification,
trial disposition and eligible merges. No installation or live switching is authorized.

## Source continuation notice

All three follow-up source lanes are integrated: Claude native GUI selection ab73cbaa,
single-parent shell fixtures c5454c8b and nonpersistent WebKit fixtures eecd20ac, plus
Gemini Sendable correction8effc1ec. Independent Claude correctness review found NFP-COR-001 P1 (delegated refresh can
fallback to a non-enrolled executable), source-remediated at eb9bb968 and independently
confirmed with no new scoped findings; native execution pending, and NFP-COR-002
P2 (identityless success can reopen previous history), deferred and unrepaired under
the finding policy. Original severities/blocking claims remain in
../review-evidence/claude-native-gui-ab73cbaa.json. Await repair and exact confirmation,
then the source-ready message before a native checkout advance;
this documentation checkpoint is not native acceptance or a request for an interim run.

## Candidate binding

Use the **exact published PR12 head in the accompanying VPS source-ready message**,
not a moving branch. PR12: https://github.com/Jones-Systems/CodexBar/pull/12,
branch `work/codexbar-trial-identity-20261016`, base
`work/fleet-auth-discovery-20261016`. Its integrated source checkpoint is
`75c03d065bc14c641228da117724f88734cb6027`; later publication adds evidence/docs only.
Verify ancestry and every source-file hash in
`docs/review-evidence/final-source-native-candidate.json` before the pinned run.
If the message SHA is unavailable, resolve/read back the exact PR12 head and verify
that manifest before acting; do not assume a changing head or older baseline is final.

PR11 parent is `c0f7ffa78afb8d5016404461495ec9a469cf8232`, base fork main.
PR12 contains that exact parent, identity repairs and all source lanes. Preserve
historical 55197235 and 21c3456 evidence, existing worktrees and unrelated changes.
Root is sole Git/index owner of declared VPS worktrees; do not edit the pinned source.

## Source and verification evidence

Included: Authfleet discovery/System Account copy and cancellation drain; account
ordering; coherent flat-list collapse down to one account and five initial healthy
Codex accounts; trial identity TIR001/TIR002 source corrections; MiMo cache agreement;
retained diagnostic destinations; Gemini/Aliyun scratch cleanup; WebKit identifier
namespacing; named native Claude profile service/cache/recovery routing.

Claude source `7cfd882e` received independent Astra/high correctness review with no
supported findings. Its PR12 composition retains the existing two trial-owned
application-defaults/tombstone domain hooks. UI CAIR001/002/003 remain P2 under their
original a7381944 binding, now source-addressed, native pending. Original TIR P2
severities/blocking effects remain preserved. See the three component evidence files
and final manifest; no source review establishes runtime behavior.

VPS final-source checks: scoped SwiftFormat0.61.1 passed38 Swift files; whitespace
passed; identity overlay passed30 portable checks (stub-compiler source-list/cleanup,
not native Swift); MiMo writer passed3 synthetic tests. Invocation scratch cleanup
was verified. make test failed exit2 before discovery because Swift is absent;
zero tests executed. make check remains held because missing tools require installation.

## Native run

Continue accepted serial, fixture-isolated mechanics with fresh Mac capacity evidence
and invocation-owned workspace scratch, preserving logs then exact cleanup. No tool
installation or Homebrew Node repair. Preserve Keychain suppression, Codex-file and
session-file isolation, exclude live/fixture grants and disable non-timeout retries.
Run discovery and the deduplicated admitted affected groups through existing runner
functions. Full make test is HELD: actual persistent WebKit-store cases lack standard
isolation or a production-runner full-suite exclusion seam. Do not run or count
unsafe groups. Report this as partial affected verification, never a full-suite pass.
Report absent suite names as absent, not passed. Existing credential/history suites must retain their documented
synthetic overrides. Do not run broad persistent WebKit-store cases; the safe
JonesFrameworkIsolationTests create identifiers only. If full make test would cross
that boundary, report the precise held group rather than silently running or passing it.

Report exact SHA, commands, discovery/test counts, failures/skips/unavailable/held
checks, cleanup and manifest match. Source fixes return to VPS. Static installed-app
compatibility evidence is already complete; do not repeat it. Stock behavior is owner
observation, not candidate installation or switching proof.

## Current native evidence, exact bindings

Laptop reports baseline `21c34561387b26f76d0a27e9f00d1538fbc0926f` compilation/discovery
PASS, attempt1, exit0, elapsed1876.72s: 10,371 identifiers, 1,015 runner selections,
zero unknown lines and ZERO behavior tests. Invocation scratch removed, source/index
unchanged, build cache retained. This does not qualify later source changes.

Interim `44a43f5928154e08b4ce14724c2a1231b88143a9` is terminal FAIL, exit1 after128.77s,
zero discovery/tests. Its checkout remains fixed, source/index clean; scratch removed,
cache retained and no live process remains. No final source acceptance is implied.

That interim build has reported GeminiLoginRunner.swift120:22/126:22 compiler errors:
fileManager (FileManager, non-Sendable in the macOS26.4 SDK) is captured by @Sendable
onCancel/delayed-cleanup closures. Zero behavior tests ran; the original compile was
terminal as recorded above and must not be retried unchanged. VPS source repair8effc1ec is integrated into PR12 at025c9bd8; it preserves the injected
manager through a locked per-script cleanup capability. Native compilation remains
pending. Preserve the fixed checkout and await the new combined
exact-head handoff after Claude GUI and fixture containment integration. No passing rerun is claimed.

Full-suite hold is source-confirmed: OpenAIDashboardWebViewCacheTests lines108–129 and
134–140 call persistent factories unguarded; lines89–106 and609–637 have only CI guards.
OpenAIDashboardWebsiteDataStore uses default() at27 and persistent forIdentifier at35;
clearCache at71–72 drops references only. No ordinary isolation/TMPDIR override or
production-runner full-suite exclusion seam exists. That hazard is source-addressed by eecd20ac: fixtures use mandatory injected nonpersistent constructors and verify requested UUIDs. See ../review-evidence/webkit-synthetic-eecd20ac.json. Native safety qualification remains pending; no actual persistent-runtime containment or full-suite pass is established.
Identifier-only JonesFrameworkIsolationTests remain safe. Existing admitted affected
runner groups may proceed, with partial coverage reported exactly.

The laptop independently passed all three synthetic Scripts/test_mimo_usage.py cases
at44a43f59; no unchanged rerun is required. Both shell scripts now support one caller-owned workspace scratch parent via optional
CODEXBAR_TEST_SCRATCH_PARENT, source c5454c8b integrated at e73b14de. See
../review-evidence/fixture-scratch-parent-c5454c8b.json for exact commands and hashes.
Historical checks passed50 lifecycle cases and30 identity checks. NEW P1 execution hold:
DO NOT EXECUTE Scripts/test_fixture_scratch_parent.py as-is: poll/communicate can reap
the leader before unconditional finally killpg, allowing recycled-PGID signaling.
Source repairb9d2ca08 retains identity with waitid/WNOWAIT until signaling is complete.
Targeted independent confirmation is active; execution hold remains until that result.
On macOS use Python3.13+ with waitid/WNOWAIT; unsupported capability fails before spawn.
Native qualification awaits the final candidate. Preserve
native rejected-case16 as unrun until actual Swift execution. Stub proof is not native.

## Open completion gates

Installed AFCL source evidence (release7aba0e03524bddd042cd538cf138e7e50f079caa) shows
login also establishes a laptop-local native subscription usage companion, with native
CLI refresh ownership. The native selector can reuse that companion when present;
this fits the owner workflow without a second CodexBar login. Actual presence/readiness
and native behavior remain UNKNOWN. See ../review-evidence/afcl-installed-companion-source.json.
Automation-token usage-endpoint/granted-scope support remains unproved separately;
do not imply that this limitation means AFCL lacks a native companion. Selected native
CLI/profile refresh routing is subject to the NFP-COR-001 repair/confirmation. Workspace-grouped
menus are source-addressed at50a67106 with a global five-account budget and collapsible
active account; native behavior remains pending. Shared HTTP state ownership and
native containment remain unresolved despite WebKit identifier hardening. All seven
trial categories retain their exact dispositions in IDENTITY.md/final JSON.

Required CI is absent, not green. Prior bounded investigation found no runs/checks,
with organization-policy inspection denied403. Subsequent laptop public Actions UI evidence
identifies a fork-wide pause due to Actions usage scale (repoID1356759930); active/API
enabled metadata does not clear it. No setting changed. Preserve upstream-monitor
disabled_fork. Re-enable/dispatch/settings changes require exact owner approval or
owner authenticated UI initiation; laptop is preparing that separate gate. Native local results
cannot waive ac.trial-gates. Do not repeat close/reopen, settings or permission changes.
Extraction remains read-only until PR11 AND trial identity merge to fork main, or
explicit M Jones release of ac.custom-base-settled.001; coordinator takeover is no waiver.

No real auth/config/binding/Keychain reads, credential copies, account switching,
provider/usage calls, browser imports, app lifecycle/smoke wrappers, signing, package,
release, installation, launchctl, sudo or fleet propagation belongs to this verification
lane. Do not claim installability or operational success without direct evidence.

Delivery gap: the registered VPS bridge targets another environment. No send to the
laptop was attempted. Consume this Git handoff and the exact-head source-ready message
through the existing authorized laptop-to-VPS route; receipt is not native success.
