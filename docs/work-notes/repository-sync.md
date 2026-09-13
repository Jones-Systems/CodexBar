# Work Note — Repository Synchronization

<!-- codex-section:begin id="work.repository-sync#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `work.repository-sync`

Purpose: Preserve independent implementation evidence, ownership boundaries, and continuation for repository synchronization.

Governing artifact: owner Task Text; implementation decisions are in [`spec.repository-sync`](../engineering-specs/repository-sync.md).

Work owner: `JCV-A019`, work `JCV-W142`; one sequential project author

Consumers: CodexBar maintainers, host-capability implementer, owner, and reviewers

Authority effect: none
<!-- codex-section:end id="work.repository-sync#ctx.artifact-header.001" -->

## Goal, inherited authority, and current disposition

Reconcile each selected repository/environment pair against its configured canonical Git remote. Do not copy working directories or uncommitted content between machines. The existing owner authority is task-branch commits and one draft PR in the Jones Systems fork, not merge, deployment, installation, live-host synchronization, credential access, or account changes. No usage or billing feature is authorized.

**Current disposition: safety-core implementation candidate; end-to-end production sync is not complete.** The code implements typed state, mapping, cancellation requests, at-most-once client dispatch, private durable intent, same-operation readback, conflict fences, and guarded rollback planning. It has no production Git/SSH host conformer or UI entry point, and defaults to no qualified targets. Live host implementation/conformance, accepted PR #2 UI ownership, and native repository checks remain gates.

The retained prompt said no committed continuation had been verified. Fresh connected GitHub reads found an actual research Work Note commit, `88c7bbb0ddba05e2dd62e292110a3cd13679c4bf`, on the existing task branch. This supersedes only that uncertainty, not the finding that implementation and a sync PR were missing. The prior note remains in immutable Git history; no source browser conversation was reopened or searched.

## Immutable source and ownership readback

| Binding | Observed state before implementation publication |
| --- | --- |
| Repository | `Jones-Systems/CodexBar`, repository ID `1356759930` |
| Main | `d6e929cd736eccae187cd41ddb5305a670afb2c8` |
| Existing task branch | `work/repository-sync-orchestration-20260907` |
| Existing branch head | `88c7bbb0ddba05e2dd62e292110a3cd13679c4bf` |
| Existing branch tree | `7a5b0f04fe5cf45e49767b87d298bcf26736bad9` |
| PR #2 | Draft, open, unmerged; author `Mjones13`; head `0bdf8a262bc9342d9b62a5f12f8062db22273b50` |
| PR #2 overlaps | Its 51 changed paths were read; zero changed-file overlap with this candidate |
| PR #2 handoff | No comments returned; no owner handoff, review, or approval inferred |
| PR inventory | Only PR #1 and PR #2 returned; no prior sync PR found |
| PR #2 current-head CI | Run `34004200721` completed with conclusion `failure`; not treated as sync-candidate evidence |

PR #2 owns CAAM controls, observability, environment preferences, shared subprocess changes, locales, related fixtures, and its own specification/Work Note. This candidate touches none of those files and does not import that unmerged branch. Any later entry-point integration requires explicit owner coordination.

Repository `AGENTS.md`, the package manifest, existing environment identity model, lint configuration, Makefile, and current CI workflow were read. No additional `AGENTS.md` was found at the inspected new-code/documentation/test/script ancestor paths. The historical V3 Level 2 root locator returned 404; code search returned no match with `incomplete_results: true`, so the guide's current location is **unresolved**, not proven absent. No new authority is inferred from that failed lookup.

## License-safe engine decision

The prior research pinned `Dicklesworthstone/repo_updater@b5fe0131d3bb53fe311f6ebfc54d60fbc2404c73` and recorded an unresolved MIT/OpenAI/Anthropic rider. Reuse remains prohibited absent a separate affirmative owner/legal disposition. The successor did not fetch, copy, translate, port, install, or execute that implementation. All new Swift logic is requirements-derived, uses Foundation/POSIX and the existing repository toolchain, and introduces no dependency. No legal clearance for the upstream source is claimed.

## Changed implementation

`Sources/CodexBarCore/RepositorySync/` contains the independent target/snapshot/plan/receipt models, durable journal, and coordinator. `TestsLinux/RepositorySync*.swift` contains synthetic fixtures and three suites. `Scripts/test_repository_sync_core.sh` is an offline source-closure runner; it installs nothing. The progressive specification defines the host contract and the exact unimplemented integration boundary.

The journal reserves a full immutable plan before dispatch, retains idempotency tombstones, blocks overlapping pending/unknown/conflicted operations, bounds records and bytes, pins its private directory, uses no-follow file opens and nonblocking process locks, and persists through file fsync, atomic rename, and directory fsync. Missing/corrupt state cannot silently reset history. Unknown outcomes never call execute again. Contradictory terminal results persist a conflict fence requiring manual disposition.

Rollback requires a separately confirmed operation and a stored applied original with unchanged target/physical identity/current HEAD. Actual Git restoration is deliberately not fabricated as a client-side shell command; the missing host must implement and qualify it.

## Verification and self-review evidence

The scratch runtime was freshly checked: Swift 6.2.1 for Linux x86_64, Git 2.47.3, Python 3.13.5, Bash, and make are present. SwiftFormat and SwiftLint are not present. No installation, live host, credential, provider, account, or ChatGPT Web Connector execution occurred.

The first source-closure build passed. The first 28-test/2-suite run passed. Adding persistence cases produced two fixture failures: the tamper test replaced an unescaped slash that the JSON encoder had escaped, and a contention test incorrectly required exactly one dispatch although fail-closed pre-dispatch contention may yield zero. Both fixtures were corrected without weakening at-most-once behavior. A subsequent complete run reported **39 tests in 3 suites passed**, including the bounded 256-record retention case. Fresh final debug and release runs of `bash Scripts/test_repository_sync_core.sh` (release with `-c release`) each passed **39 tests in 3 suites**. `bash -n` passed. All candidate Swift lines are within 120 columns and a candidate whitespace scan passed; these are not SwiftFormat/SwiftLint results.

Sequential security/recovery self-review found and repaired a real gap: conflicting terminal outcomes must not preserve a misleading success/no-effect state. The journal now stores `conflicted`, blocks overlaps and rollback, and refuses ordinary status-based clearing. It also rechecks directory permissions on every transaction and uses nonblocking rather than indefinitely blocking process locks. Those changes are covered by the passing suites.

The offline source closure is not the full repository. The exact original Makefile was reconstructed and blob-verified in a separate bounded check context. `make test` and `make check` each exited **2** because `Scripts/test.sh` and `Scripts/lint.sh` were absent there (their shell commands exited 127); no full repository test or linter ran. SwiftFormat/SwiftLint, native macOS behavior, repository CI, host crash/power-loss qualification, and independent review remain separate evidence gates; no standalone result substitutes for them. Final publication/readback and exact-head CI belong in the draft PR and final delivery receipt, rather than inventing a self-referential commit hash here.

## Open gates and next concrete effect

| Gate | Required next effect |
| --- | --- |
| Host implementation | Implement and independently qualify the proposed separate Git/SSH host protocol before any production target is admitted |
| PR #2 path/owner handoff | Obtain accepted ownership for an explicit sync entry point; preserve all existing CAAM/account-control boundaries |
| Exact-head checks | Observe this candidate's own lint/Linux jobs and retain any failures; required macOS evidence remains deferred while draft |
| Native/device qualification | Obtain separate live authorization and execute exact-configuration tests without inferring authority from this PR |
| Independent review | Obtain a non-author review under separate authority; this lane has only sequential self-review |
| V3 guidance locator | Resolve the historical Level 2 guide location before asserting compliance with that unavailable document |

No merge, force push, branch deletion, upstream PR, deployment, release, installation, live synchronization, destructive Git operation, or external owner message is included. No existing unknown-effect implementation tree was replayed. If a publication call has an unknown result, read its exact immutable object/ref/PR state before any retry.

## Level 2 recovery checkpoint

<!-- chatgpt-level2-recovery:v1 -->
The tested implementation is intended for the existing task branch and one draft PR, not an empty recovery branch. No `.chatgpt-scratch/` content or raw workspace handle belongs in this history. The final delivery receipt must name the verified commit, tree, PR, check observations, and remaining gates; an unverified write is never publication proof.
