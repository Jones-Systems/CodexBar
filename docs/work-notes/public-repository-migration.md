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

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.intent.001" -->
## Accepted intent and ownership

The owner requested a public independent `Jones-Systems/CodexBar`, migration of
open PRs, useful native stacking and eventual eligible merges, under Frontier
mode. A goal is active. This supersedes the earlier bounded continuation's
blanket no-merge finish line; readiness and protected effects remain separate.
The [engineering spec](../engineering-specs/public-repository-migration.md)
records the selected preservation mechanism and exact remaining approvals.

Thread `506fc1fd-d94f-4616-84f4-7751eda0aec8`, environment
`8750edf7-486b-41ac-81ce-cd50dfeb71eb`, retains continuity and sole Git ownership.
The dedicated linked worktree is `CodexBar-public-migration-506fc1fd`, branch
`work/public-repository-migration-506fc1fd`, based on
`99429988aefee925c0a2aaabf884e89792f25d7a`. Its write scope is migration
documentation and invocation-owned metadata evidence. All preexisting worktrees
and source branches are preserved. Research children performed read-only work.
<!-- codex-section:end id="worknote.public-repository-migration#ctx.intent.001" -->

<!-- codex-section:begin id="worknote.public-repository-migration#ctx.evidence.001" -->
## Current evidence

The approved migration is now executed. Old repository ID `1356759930` is
`Jones-Systems/CodexBar-legacy-fork`; new public independent repository ID
`1425008735` is `Jones-Systems/CodexBar`. All 431 branch heads and 135 tag objects
(658 advertised records including peeled targets) matched the preserved source
manifest after the atomic import. Original PR IDs/discussions remain intact.

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
extractions. No required coverage/rule is removed. Final-head verification and
merges are still pending. See the [public receipt](../review-evidence/public-repository-migration.json).

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

No source code was changed for migration preparation and no new native suite
was started. Existing receipt `docs/review-evidence/ci-isolation-r1.json` records
the full isolated Mac suite and both plugin engines passing at source
`1a3037561c867735ca5858e01168ff6f160b179c`; tested code is identical in `99429988`.
Those results do not establish destination CI. `make check` remains unavailable
under the missing-tool/no-install constraint; the available VPS route lacks
Swift. No empty rollup is counted as passing.

Preserve TIR001/TIR002 and the seven trial gates; deferred NFCR-COR-002/003,
NFP-COR-002 and FSP-PROC-002; the missing full scratch/identity/sharding proofs;
and EXPOSURE001's bounded public identity/path disclosure finding. No credential
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
