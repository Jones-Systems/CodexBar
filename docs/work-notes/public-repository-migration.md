# Public repository migration continuity

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.public-repository-migration`

Purpose: Preserve the owner-requested standalone repository migration and delivery evidence.

Governing artifact: `spec.public-repository-migration`

Continuity owner: CodexBar Account Sync Verification coordinator

Consumers: repository owner, migration operator and source owners

Authority effect: none
<!-- codex-section:end id="worknote.public-repository-migration#ctx.artifact-header.001" -->

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.retirement.001" -->
## Legacy fork retirement record

On 2026-10-20, M Jones requested evaluation of all five open PRs in
`Jones-Systems/CodexBar-legacy-fork` (repository ID `1356759930`), preservation
of their useful conclusions in `Jones-Systems/CodexBar` (ID `1425008735`), and
publication and merge of that documentation before a separate Otto deletion.
The owner explicitly discarded the rest. This supersedes the migration's earlier
requirement to keep original discussions on the legacy host: no complete discussion
archive or continuing dependency on that host is required. This record evaluates
only those five open PRs, not every closed PR, issue or other repository history.
It records no deletion or archival operation and grants no authority for one.

### Source and successor mapping

Readback on 2026-10-20 found all five legacy PRs still open and all five successors
merged. Every legacy head below and each of the three distinct successor merge
commits is an ancestor of current `main` at
`d0f7c37e59d032c67b479b358a977d53de6896d8`. The first three successors share the
atomic stack's merge commit. The legacy repository is not needed to recover these
source revisions or their successor delivery records.

| Legacy PR and scope | Preserved legacy head | Successor PR | Merge commit |
| --- | --- | --- | --- |
| #11 — Authfleet accounts, controls and CAAM removal | `4f62ba08bd6c22940bd79189b451464ba2df3ba5` | [#1](https://github.com/Jones-Systems/CodexBar/pull/1) | `7138b98b978381be69a08b0c7acedae6549a783c` |
| #12 — Jones trial identity and isolated state | `405b6765d7ba4da09affb894e2e8d5fe6feea3da` | [#2](https://github.com/Jones-Systems/CodexBar/pull/2) | `7138b98b978381be69a08b0c7acedae6549a783c` |
| #13 — Native fixture containment and CI isolation | `99429988aefee925c0a2aaabf884e89792f25d7a` | [#3](https://github.com/Jones-Systems/CodexBar/pull/3) | `7138b98b978381be69a08b0c7acedae6549a783c` |
| #14 — Netdata multi-host node selection | `2fbbca5ed244a9a2873a0005c09f414a5063d6cf` | [#4](https://github.com/Jones-Systems/CodexBar/pull/4) | `8a4216c98fc6ca78ae2f5b5b39f0bee302993d0e` |
| #3 — Independent repository-sync safety core | `b981e7e5c824451d9ab6c47a0513e926c3a32bc5` | [#5](https://github.com/Jones-Systems/CodexBar/pull/5) | `bd4c3b27113428cfbc678ad0af7c4d46250cf9c1` |

### Useful conclusions retained

The evaluated material comprises the five PR bodies, nine issue comments, zero
submitted reviews and zero inline review comments; the bounded collection pages
were complete. Successor PRs retain the original bodies' substantive content.
Four comments on legacy #11 add account-recovery, native-verification and Authfleet
architecture context; the remaining five comments only identify successor PRs.
The useful conclusions are retained here and in the existing local records:

- **Authfleet and account recovery (#11):** exact, unique account identity and
  fail-closed source selection remain important. Selecting a usage source alone
  does not switch the system account. The owner subsequently approved use of the
  existing System Account credential-copy behavior for Authfleet source integration,
  superseding the earlier no-copy restriction for that implementation. The
  [promotion record](fleet-system-promotion.md#binding-and-owner-approval) preserves
  the ruling, typed-target validation and destination semantics. It does not grant
  live credential access, installation or running-session changes. App-owned writer
  exclusion does not establish exclusion against external refreshers or full
  transactional rollback; its [preservation limits](fleet-system-promotion.md#preservation-limits-and-operational-gates)
  remain explicit. [Account recovery and drain](account-recovery-drain.md) retains
  the AFR-001/AFR-002 source corrections and compilation follow-up.
- **Trial identity (#12):** the opt-in packaging overlay separates Jones-owned
  identity/state and disables upstream updates. Source integration and merge do not
  establish an installable trial or remove the seven gates in
  [Jones identity](../jones/IDENTITY.md). The
  [trial work note](trial-identity.md) retains its exact evidence and limitations.
- **Fixture and CI isolation (#13):** workspace-owned fixture allocation, propagated
  child isolation and drain-before-cleanup are the preserved contract. Historical
  native and plugin results are bound to their tested revision in
  [CI isolation evidence](../review-evidence/ci-isolation-r1.json); they are not a
  fresh verification of current source. Later migration repairs and their narrower
  proofs remain in the evidence below and the successor delivery record.
- **Netdata (#14):** both metric requests select the configured machine GUID using
  `nodes`, so a multi-host Parent does not cause valid data to be rejected as
  ambiguous. Wrong-node rejection remains required. The successor records the
  synthetic multi-host regression and historical 31-test Linux result. Deferred
  request-start freshness is unchanged; source delivery does not establish a
  configured, activated or rendered Mac app.
- **Repository sync (#3):** the delivered slice is an independent client safety
  core, not complete production synchronization. It persists intent before dispatch,
  fails closed on unsafe or unknown state, does not repeat ambiguous operations,
  and requires original-target readback and separately confirmed guarded rollback.
  Production Git/SSH host integration, discovery/fetch and preferences integration
  remain outside that slice. No `repo_updater` code was adopted; its unresolved
  license rider remains a reuse gate. The [local work note](repository-sync.md) and
  [engineering spec](../engineering-specs/repository-sync.md) preserve the contract
  and historical ownership boundary without requiring legacy-host links.

### Findings and evidence boundaries

Retirement does not correct, downgrade or waive findings. AFR-001 and AFR-002
retain their original P2 severity and blocking effects (explicit recovery-account
selection and shared-home cancellation/retry correctness) in the
[original ledger](../review-evidence/account-fixes-ccafd932.json); their authorized
source-correction disposition is recorded in the recovery note above.
TIR001 and TIR002 remain deferred P2 findings concerning the standalone fixture's
compile inputs and invalid identity metadata's fail-open behavior, with original
blocking effects in the [trial ledger](../review-evidence/trial-identity-4ff8b504.json).

The migration's retained deferrals below remain intact: NFCR-COR-002 blocks the
identity/scratch-parent proof; NFP-COR-002 concerns identityless success-history
mixing; FSP-PROC-002 is the originally nonblocking handler-restoration observation.
Their P2 severity, original effects and dispositions remain in the
[fixture containment](../review-evidence/native-fixture-containment.json),
[Claude fixture](../review-evidence/claude-native-gui-ab73cbaa.json) and
[process fixture](../review-evidence/fixture-scratch-parent-c5454c8b.json) ledgers.
NFCR-COR-003 retains its original P2 history; only its list-only stdout contamination
aspect has the focused correction recorded in the
[migration CI receipt](../review-evidence/migration-ci-repair.json).
Full scratch/identity proofs and EXPOSURE001's bounded public identity/path
disclosure finding remain as documented below. No new runtime, installation,
live-account or all-history security result is asserted by this record.

The remaining sections are the migration's historical chronology. Their original
host-preservation statements and then-pending delivery gates describe those earlier
checkpoints; this retirement record supersedes the host-retention requirement,
and the mapped successor PRs carry subsequent delivery results.
<!-- codex-section:end id="worknote.public-repository-migration#ctx.retirement.001" -->

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.intent.001" -->
## Accepted intent and ownership

The owner requested a public independent `Jones-Systems/CodexBar`, migration of
open PRs, useful native stacking and eventual eligible merges, under Frontier
mode. The requested goal and delivery finish line remain in force. This supersedes the earlier bounded continuation's
blanket no-merge finish line; readiness and protected effects remain separate.
The [engineering spec](../engineering-specs/public-repository-migration.md)
records the selected preservation mechanism and exact remaining approvals.

Thread `506fc1fd-d94f-4616-84f4-7751eda0aec8`, environment
`8750edf7-486b-41ac-81ce-cd50dfeb71eb`, retains continuity and sole Git ownership.
The dedicated linked worktree is `CodexBar-public-migration-506fc1fd`, branch
`work/public-repository-migration-506fc1fd`, based on
`99429988aefee925c0a2aaabf884e89792f25d7a`. Its write scope is migration
documentation and invocation-owned metadata evidence. The coordinator also owns
`CodexBar-native-catalog-repair-506fc1fd` on
`work/native-catalog-repair-506fc1fd` for declared CI source repairs and
`CodexBar-completion-506fc1fd` for isolated verification. All preexisting
worktrees and source branches are preserved; children have non-overlapping
writer scopes and no Git mutation authority.
<!-- codex-section:end id="worknote.public-repository-migration#ctx.intent.001" -->

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.evidence.001" -->
## Current evidence

The approved migration is now executed. Old repository ID `1356759930` is
`Jones-Systems/CodexBar-legacy-fork`; new public independent repository ID
`1425008735` is `Jones-Systems/CodexBar`. All 431 branch heads and 135 tag objects
(658 advertised records including peeled targets) matched the preserved source
manifest after the atomic import. Original PR IDs/discussions remained intact at
that checkpoint; the [retirement record](#legacy-fork-retirement-record) supersedes
the earlier requirement to retain their legacy host.

Old/new PR mapping is 11→1, 12→2, 13→3, 14→4, 3→5. All replacements are linked
natively, and all originals have a link to their replacement. Native stack #6
was verified to contain #1/#2/#3 in order with unchanged refs and incremental
diff sizes. Original native links and both owned bare origins now address the
legacy repository; explicit `standalone` remotes address the destination.

The monitor and release workflows are `disabled_manually`; only CI is active.
Real destination CI jobs have started. PR5 was preserved as draft during import,
then readied for qualification after confirming its declared safety-core scope
is complete. Production Git/SSH/host/UI integrations are later work, not a claim
of this slice. Astra/high bound the approved #1–#5 merge contract in the spec;
no further approval prompt is needed for those covered qualified merges.

Repo-local pinned lint tools are installed, plus an official checksum-verified
Node v24.9.0 in the owned tool directory because ambient Homebrew Node fails on
a missing simdjson dylib. No global dependency was repaired. Initial `make check`
revealed a stale generated parser hash; independent SwiftFormat found four files
and SwiftLint found 214 violations across 36 files. A declared source repair lane
owns only those paths, the generated hash and two necessary same-module helper
extractions. That repair and migration documentation were published in top PR3
at `cbc4a489f8a3faedf5e744f089a740d9424cde1f`. Scoped formatting and strict
SwiftLint passed. Every one of PR1's 165 hosted SwiftLint path/rule pairs maps to
the cumulative repair manifest; lower-layer failures require passing cumulative
top evidence before the atomic stack can qualify.

At that published head, local `make check` and hosted lint both reproduced a
list-only shard comparison failure: runner diagnostics entered stdout alongside
selection names. The selection union itself matches. A declared three-script
lane repairs the diagnostic stream contract and retains the union, lifecycle,
retry and failure assertions. This necessary mandatory-check repair is covered
by the owner's subsequent explicit completion and CI-repair instruction;
NFCR-COR-003 retains its original P2 severity and source history. Its exact
stdout-contamination aspect is corrected and passes the synthetic shard proof;
this does not qualify broader deferred containment proofs. The raw union/name/diagnostic assertions first passed, exposing
a stale included cancellation-test expectation: the installed SIGINT handler
raises `SystemExit(130)`, while the test expected `KeyboardInterrupt`. Its repair
asserts the exact signal status and retains all drain, identity, sentinel and
bounded-time assertions. Production cancellation behavior is unchanged. The corrected sharding harness
passes, including 95 process-cleanup tests with one platform skip; 38 focused
runner lifecycle cases and five isolated-command tests also pass. All three
groups ran serially under one canonical fixture parent, with proved process
drain and exact parent absence. The
[repair receipt](../review-evidence/migration-ci-repair.json) binds the commands,
source hashes and retained limitations. No unrelated deferred finding is swept
into the lane.

Hosted musl compilation also failed because account discovery imported `Glibc`
unconditionally outside Darwin. Both Codex and Claude discovery imports now
follow the existing Darwin/Glibc/Musl conditional pattern; all bytes below the
import blocks are unchanged, and scoped format/lint checks pass. Musl compilation
still requires destination CI. No required coverage or rule is removed.
A later PR1 macOS shard failure exposed architecture-catalog drift. The original
catalog repair remains present, but subsequent formatting/helper extraction and
Musl imports left 13 of 404 exact anchors stale in the cumulative candidate.
Two clusters must also be regrouped under the unchanged 12-line gap / 40-line
window rules, preserving the aggregate Codex, Claude and DeepSeek occurrences.
A declared one-file metadata lane refreshes those entries, preserving scanner
logic, negative fixtures, justification text and all 41 tests. The same static
anchor check fails before at 391/404 and passes after at 404/404. All 551 allowed
provider occurrences are retained, and scoped format/strict lint pass. Native
scanner execution remains due. The
[follow-up receipt](../review-evidence/migration-architecture-repair.json)
records the exact file hash, invariant counts and original failure. The lower
aggregate reports the already identified lint, musl and macOS failures; it is
not a separate runtime defect.

Current-head qualification at `b8d2a0076ed1e6e47cf6e03031a75abe2e847593`
passed hosted lint, both glibc Linux jobs and the musl build in run
`39192058451`. Both macOS shards failed compilation with the same nine errors
across three fixture-test files. The local focused gatekeeper invocation also
failed compilation after 900.18 seconds, executing zero tests; later native
phases did not start. Process drain and exact scratch-parent removal were
verified, and the verifier released its worktree.

Read-only diagnosis traced all nine errors to three closure-valued
`TaskLocal.withValue` arguments rewritten in lint repair `e6cfc398`.
The declared three-file repair binds explicitly typed override values before
passing them to `withValue`, preserving the closure bodies, operations,
assertions and isolation. The generic fixture wrapper retains its return value.
No production API, formatter rule or lint rule changes are required. All
`withValue` changes in that lint commit were inspected; exactly these three
changed the closure argument binding. The repaired revision still requires
native compilation, the three affected suites, the full suite, `make check`
and plugin A/B qualification before the accepted merge gates can be satisfied.
Scoped SwiftFormat 0.61.1, strict SwiftLint 0.65.0 and whitespace checks pass.
All 20 test annotations, 110 expectations, ten requirements and seven issue
records are retained, with original closure and operation bodies unchanged.
The [repair receipt](../review-evidence/migration-tasklocal-repair.json) binds
source hashes, the failing compiler evidence and exact scoped check arguments.

At this source-repair checkpoint, final-head verification and merges remain
pending. Subsequent exact-head native/CI results and merge postconditions belong
to the [destination PR3](https://github.com/Jones-Systems/CodexBar/pull/3) delivery
record. See the [import receipt](../review-evidence/public-repository-migration.json).

The pre-migration observations below remain historical source evidence.

The public fork is repository ID `1356759930`, parent `steipete/CodexBar`.
Authenticated API reports repository admin permission, Actions enabled, no
rulesets and unprotected main. CI/release workflow states are active; the
upstream monitor is `disabled_fork`. Active workflow state does not prove the
usage pause is cleared or that a run can start. Organization repository-creation
permission has not been exercised. The default collaborative GitHub browser is
signed out; the authenticated API is available. No login was attempted.

The local preservation snapshot contains 431 remote branch heads and 227 tag
records (including peeled annotated-tag targets), all five open PRs and their
comments/reviews, relevant non-secret settings and workflows. Ref-list SHA-256:
`b99229acdac6c2c78e6f482e517f82f53f2ca38b7d6b14888f16b202c38d3761`.
Raw metadata stays in the owned untracked `migration-evidence/` directory.
The separate bare source copy `CodexBar-public-migration-source-506fc1fd.git`
matches all 658 advertised branch/tag/peeled records exactly. It is owned by
this coordinator and is retained for the approved import, not auto-cleaned.

| Original PR | Head | Base and disposition |
| --- | --- | --- |
| 11 | `4f62ba08bd6c22940bd79189b451464ba2df3ba5` | main; owned account/CAAM source |
| 12 | `405b6765d7ba4da09affb894e2e8d5fe6feea3da` | 11 branch; identity candidate |
| 13 | `99429988aefee925c0a2aaabf884e89792f25d7a` | 12 branch; fixture/CI repair |
| 14 | `2fbbca5ed244a9a2873a0005c09f414a5063d6cf` | main; independent Netdata fix |
| 3 | `b981e7e5c824451d9ab6c47a0513e926c3a32bc5` | main; unfinished draft safety core |

Ancestry proves 11 → 12 → 13. Their native stack has not been registered.
The repository's existing native stack 10 is closed and contains old 2/4/5/6;
it is unrelated. Installed `github/gh-stack` is v0.2.1; link/merge help inspected.
The atomic merge CLI's basic checks do not replace readiness or a proved
expected-head contract.

Continuation inspection of official `github/gh-stack` v0.2.1 source established
that its async merge client omits `sha`, while its API reference supports that
guard. The spec now directs any accepted stack merge to the supported guarded
API rather than the unguarded CLI command. Native link/unlink capabilities are
available for remapping this thread's current 11/12/13 associations after the
rename; this avoids stale links addressing new-repository PRs after name reuse.
No merge or association mutation was attempted.

PR14 names source owner thread `718b02d7-0d4b-4670-b05f-57a5db28178d`, which is
not readable in this native environment. PR3 names historical JCV-A019/JCV-W142.
Neither identity is a freshly verified owner transfer. Preserve their source
and draft states; do not infer custody from their common GitHub author.

Two independent Sol evidence lanes covered official migration mechanics and
PR/ownership inventory. Astra/high supplied the bounded migration synthesis:
native detach loses metadata; rename/recreate is the preservation route; exact
namespace, CI exceptions and eventual merge readiness need separate binding.
Only one route satisfies the current preservation and exact-name requirements;
there is no unresolved implementation choice requiring recommendation voting.
<!-- codex-section:end id="worknote.public-repository-migration#ctx.evidence.001" -->

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.verification.001" -->
## Verification and retained findings

The published candidate `cbc4a489f8a3faedf5e744f089a740d9424cde1f` failed
`make check` attempt 1 at the synthetic shard-union comparison. Parser hash,
preceding portable package checks and all five isolated-command tests passed.
The invocation drained its children and removed its exact owned scratch parent;
full `make test` and plugin A/B were not started after that failure. This is
failed evidence, not a passing full check.

At `b35c499fc367ed5660f62f93c038f80369a9c7e8`, canonical `make check`
passed in 83.64 seconds and hosted lint passed. Full `make test` was cancelled
through its exact owned wrapper after 495.8 seconds of discovery because the
static architecture-catalog mismatch requires a new revision; no groups had
executed, and plugin A/B did not start. Cancellation drain was reconciled: all
35 observed invocation processes and the exact fixture parent were absent.
This is partial/cancelled native evidence, not a full-suite pass. Final native
qualification must bind the catalog-repaired revision. Discovery/build does not
have a runner per-command timeout; this invocation retained the audited outer
1800-second bound, while suite/group commands retain their 180-second default.

The following baseline remains valid only for its recorded source. Existing
receipt `docs/review-evidence/ci-isolation-r1.json` records
the full isolated Mac suite and both plugin engines passing at source
`1a3037561c867735ca5858e01168ff6f160b179c`; tested code is identical in `99429988`.
Those results do not establish the repaired candidate or destination CI. The
owner subsequently approved the required pinned tools, so the earlier
missing-tool hold is superseded. No empty rollup is counted as passing.

Preserve TIR001/TIR002 and the seven trial gates; deferred NFCR-COR-002,
NFP-COR-002 and FSP-PROC-002; the missing full scratch/identity proofs; and
NFCR-COR-003's original finding history with the exact stdout correction verified
by the focused synthetic proof. No broader proof is inferred from a focused correction. Preserve
EXPOSURE001's bounded public identity/path disclosure finding. No credential
exposure was identified by that earlier bounded audit; this is not a guarantee
about all history. The owner again explicitly chose public visibility.
No finding is repaired or reclassified by changing GitHub repository type.

Migration document checks: direct marker/header consistency and Git whitespace
checks pass. The canonical V3 sections validator is unavailable on this Mac:
its subprocess boundary requires Linux pidfd process-group containment and
raises `RuntimeError: Linux pidfd process-group containment is unavailable`.
The initial `invalid_repository` result masked that platform prerequisite;
native Git confirms the target is a valid non-bare linked worktree. No validator
source or process-containment policy was changed to bypass the limitation.
<!-- codex-section:end id="worknote.public-repository-migration#ctx.verification.001" -->

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.continuation.001" -->
## Next effect and registration

The owner subsequently explicitly approved the prepared migration, repository
creation and all listed work, including the requested CI/tool exceptions, and
instructed continuation without repeated approval prompts. This approval covers
the bounded namespace and setup sequence in the engineering spec. Carry it
through execution; retain readiness, identity, fixture and rollback checks.
The old pending-approval observations below are historical, not a current hold.

Preparation is complete enough to review the exact namespace and CI envelope.
No repository was renamed, created, deleted or detached; no workflows were
enabled and no PR was merged. Refresh identities/ref manifest before the first
approved operation. The coordinator must preserve this goal rather than start
the original account work again.

The first goal continuation revalidated the same old repository ID/name and all
five unchanged PR heads. It added the native-link transition and guarded async
merge evidence above. The namespace/CI/tool exceptions have not been approved;
the automated goal continuation is not an approval. With these preparations
complete, the next consequential migration effect remains held for that reply.

Registration status: `registration_unavailable`. Native thread/environment and
project identity are established, but an enrolled host key and last accepted
registration revision are not established in current evidence. Do not guess
them or overwrite a prior registration. This metadata limitation does not block
bounded source preparation. The register-thread skill and registration route
were read; no registry request or enrollment effect was attempted.
<!-- codex-section:end id="worknote.public-repository-migration#ctx.continuation.001" -->
