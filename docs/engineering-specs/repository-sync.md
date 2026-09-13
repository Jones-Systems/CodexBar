# Engineering Spec — Independent Repository Sync Safety Core

<!-- codex-section:begin id="spec.repository-sync#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.repository-sync`

Revision: 1

Work owner: `JCV-A019`, work `JCV-W142`; one sequential author/reviewer

Purpose: Define the independent sync-only safety core and the unqualified host boundary.

Governing artifact: owner Task Text and the existing task-branch/draft-PR authority recorded in `work.repository-sync`.

Authority effect: none; this specification does not authorize live synchronization, merge, installation, or deployment.
<!-- codex-section:end id="spec.repository-sync#ctx.artifact-header.001" -->

## Decision and delivery boundary

Implement new requirements-derived Swift code in `Sources/CodexBarCore/RepositorySync/` with no new dependency. The evaluated `repo_updater` implementation is not an input: no copying, translation, porting, vendoring, installation, or execution. Its unresolved rider remains a reuse gate. This is an engineering provenance decision, not a legal opinion or license clearance for that upstream project.

This candidate implements **client-side planning, durable intent, at-most-once dispatch, cancellation requests, same-operation readback, mapping validation, and guarded rollback planning**. It does **not** implement a local Git executor, SSH service, host discovery/fetch, or preferences UI. `RepositorySyncHost` is a proposed separate host interface, not an existing service claim. There is no production conformer, automatic host selection, or qualified production target. Consequently this candidate cannot synchronize a real repository by itself. Production completion remains blocked on the host implementation/conformance and UI ownership gates below.

The goal remains reconciliation of selected repository/environment pairs against their canonical Git remotes, not copying directories or uncommitted content between machines. No usage, billing, credit, spend, telemetry, account mutation, or provider feature belongs to this lane.

## Ownership and integration

Base: `Jones-Systems/CodexBar@d6e929cd736eccae187cd41ddb5305a670afb2c8`. Continue the existing `work/repository-sync-orchestration-20260907` branch from research checkpoint `88c7bbb0ddba05e2dd62e292110a3cd13679c4bf`.

PR #2 remains separately owned by `Mjones13`, draft and unmerged at `0bdf8a262bc9342d9b62a5f12f8062db22273b50`. Its 51 changed paths were read. This candidate has **zero changed-file overlap** with that set. In particular, do not edit its CAAM models/commands, coordinator, environment preferences section, observability views, subprocess runner, locale catalogs, tests, or Work Note. No PR #2 owner handoff or approval is inferred from an empty comment timeline.

The later UI owner must use the existing `CAAMEnvironmentConfiguration.id` as `environmentID`, bind `configurationRevision` to the exact local/SSH endpoint configuration, and present these plans through a separately approved entry point. CAAM's closed account-control command family is unchanged. A revision label is not itself endpoint attestation: the host adapter and qualification record must establish that binding. Switching environment configuration cannot redirect an existing operation's readback.

## Model and state

`RepositorySyncTarget` binds the stable environment ID, configuration revision, repository ID, absolute root, relative path, credential-free canonical HTTPS remote, and branch. Whole-target equality is required for qualification and receipts. The initial surface deliberately rejects SSH/file remote URLs, credentials, query/fragment parameters, percent encodings, ambiguous path components, non-ASCII/control characters, and unsafe branch names. This is a conservative supported subset, not a universal Git URL parser. Spaces in host paths are preserved literally; strings are never shell commands.

Client-side overlap detection conservatively collides case variants, nested paths, and the same repository ID within one environment, even after a configuration revision change. Lexical mapping is not proof of filesystem containment. The host must independently resolve symlinks, mount aliases, inode/common-Git-directory identity, and linked worktrees under its authoritative lock.

Snapshots bind the complete target, physical repository identity, opaque state revision, observation time, resolved path, actual remote/branch, exact SHA-1 or SHA-256 object IDs, ahead/behind counts, ancestry, and hazards. Dirty, unknown-cleanliness, in-progress, bare, shallow, linked-worktree, submodule, sparse-checkout, untrusted-configuration, and unresolved-path states all block planning. An adapter must report missing evidence as unsafe; it must not treat an incomplete scan as a clean snapshot.

Only an unchanged state or a proven clean fast-forward can produce a normal plan. Ahead or diverged repositories are blocked rather than pushed, rebased, merged, stashed, reset, cleaned, or force-updated. A snapshot is usable for at most 60 seconds and cannot be future-dated. Plans have a 60-second lifetime, are immutable, and are revalidated after deserialization. The host must check its own current clock and state under lock immediately before mutation; client freshness cannot close a time-of-check/time-of-use race.

| Stored state | Meaning and permitted next action |
| --- | --- |
| `pending` | Durable intent exists; dispatch may or may not have occurred. Original-operation readback only. |
| `unknown` | Transport, cancellation, malformed receipt, not-found, or incomplete status cannot establish outcome. No replay. |
| `conflicted` | Two different terminal outcomes were received. Persistent manual-resolution fence; ordinary status cannot clear it. |
| `applied` | A matching terminal receipt reports the exact destination and required preserved backup reference. |
| `notApplied` | A matching terminal receipt proves no Git mutation, or the client recorded a snapshot-based unchanged no-op. |
| `cancelled` | Cancellation before local dispatch, or a matching host receipt proving cancellation with no Git mutation. |

Unchanged means no mutation was dispatched based on the captured snapshot. It is not a claim that a remote has remained unchanged since that observation. Inconsistent terminal replies become `conflicted`; older unresolved reads never downgrade a valid terminal outcome. No journal-deletion or automatic fence-clear control is provided.

## Intent, idempotency, and persistence

The coordinator uses an explicit `RepositorySyncJournal` and an empty-by-default exact-target qualification set. Calling `execute(plan)` is the trusted caller's confirmation boundary; the eventual UI must show that exact plan and obtain a fresh explicit confirmation, not reconstruct a plan from labels afterward.

The journal atomically reserves the complete plan before invoking the host. Only a newly reserved UUID may dispatch. The same UUID and same plan returns its stored record; the same UUID with different content is rejected. Existing intents remain non-replayable after restart, expiry, dequalification, cancellation, or a pre-dispatch crash. New operations overlapping unresolved records are rejected; independent targets may continue. This guarantees at-most-once client dispatch, not exactly-once distributed execution or automatic progress after a crash. The host independently deduplicates the complete request under the same operation ID.

The journal is a versioned JSON envelope capped at 256 records and 1 MiB. Terminal idempotency tombstones and unresolved evidence are not evicted to admit more work. Reaching capacity stops new work until a separately designed, evidence-preserving archival policy is approved. No pruning or user-data deletion occurs here.

The caller must supply an existing owner-private directory with trusted ancestors, outside repository worktrees and credentials. The implementation pins its directory descriptor, requires the effective UID, rejects group/other permissions, symlinks, nonregular files and hard-linked data/lock files, and rechecks directory permissions on each transaction. Creation is explicit and exclusive; missing/corrupt existing storage never becomes an empty history.

Each transaction uses a nonblocking `flock`; contention fails closed without an indefinite wait. A unique mode-0600 temporary file is fully written and `fsync`ed, renamed relative to the pinned directory, then the directory is `fsync`ed. This requires a local filesystem with those POSIX semantics. NFS/distributed filesystems, malicious same-UID processes, replacement of trusted ancestors, and media loss are not qualified. A failed write/read/fsync halts the affected operation; a failed result save after dispatch must not trigger another execute. A surviving pre-dispatch intent remains sufficient to require readback. Orphan temporary files do not replace the authoritative journal.

## Cancellation and unknown effects

Pre-dispatch Swift task cancellation records `cancelled` without a host call. Once host dispatch starts, every thrown error, including `CancellationError`, is treated as unknown, not proof that Git stopped. `cancel` first persists a request flag, sends a same-operation cancellation request to the original target, and reconciles status. Signal acknowledgement alone is not a terminal result. An applied completion wins an ordinary cancellation race while retaining the request flag. Contradictory *terminal* reports instead fence as `conflicted`.

A host must durably retain cancellation tombstones even when cancellation arrives before execute; otherwise a transport-ordering race can launch work after cancellation. Status must be bounded, credential-free, and bound to the entire original plan. Not-found is unresolved, never an authorization to retry. A conformer must impose finite process/transport deadlines and drain its children. This core does not claim to bound an arbitrarily nonconforming async host implementation.

## Rollback

Rollback is a **new, separately confirmed operation**, never an automatic error handler. It requires a stored `applied` fast-forward original, the same complete target and physical repository identity, a fresh clean snapshot, and current HEAD exactly equal to the original destination. Its destination is exactly the original HEAD, and its backup reference is exactly `refs/codexbar-sync/<original-operation-uuid>`.

The journal rejects an invented or unrecorded original even if a caller constructs an in-memory applied record. The host must verify the preserved reference still points to the original HEAD, recheck branch/index/worktree state under lock, preserve evidence, and refuse if anything has changed. No `reset --hard`, forced checkout, automatic stash, file deletion, or loss of uncommitted content is permitted. An unknown rollback is a new fence on the same resource, not permission to replay either operation.

## Required host conformance before activation

The host implementer owns actual canonical-remote observation, controlled object preparation, repository identity/containment, authoritative exclusion, and safe Git effects. Qualification must demonstrate all of the following on each exact environment configuration:

- Bounded read-only inspection and explicit accounting for any fetch/object/ref preparation effects; no inspection disguised as a mutating unjournaled fetch.
- Noninteractive, credential-free transport outputs; executable/argv construction without shell interpolation; trusted Git configuration and hooks/filters disabled or otherwise proven nonexecuting. No live credential probes are part of this candidate.
- Durable full-plan deduplication and cancellation tombstones, with exact target/branch/remote/HEAD/revision/path revalidation under the host lock, including physical aliases and other Git writers.
- A preserved original reference and recoverable branch/index/worktree protocol for fast-forward and separately confirmed rollback; crash, partial effect, corrupt status, lost response, and process-tree termination tests.
- A terminal `notApplied` or `cancelled` means no Git mutation, not merely an unchanged visible HEAD after partial metadata effects. Ambiguous partial mutations remain unresolved.

A conforming host, explicit owner approval for live qualification, accepted PR #2 UI ownership, and native checks are prerequisites to activation. None is manufactured by this document or by inserting a value into a Swift set.

## Verification and review

New sources are automatically included in the existing `CodexBarCore` target. Fixtures under `TestsLinux` join the existing `CodexBarLinuxTests` target without editing `Package.swift` or CI. The offline runner `Scripts/test_repository_sync_core.sh` copies precisely these source and fixture files into a temporary dependency-free package; it exercises the same core but is **not** a full-repository build, macOS test, host integration test, or live Git sync.

Fixtures cover state/URL/path guards, SHA-1/SHA-256 identity, expiry, disabled qualification, repeated and colliding UUIDs, interrupted intent, status readback, cancellation races, conflicting terminal evidence, independent/overlapping targets, rollback provenance, file modes/symlinks/corruption, schema/size limits, lock contention, restart, orphan temporary files, and capacity without evidence eviction.

The author performs sequential correctness, security/recovery, maintainability, and bounded-resource self-review. No independent review, bot review, power-loss proof, rendered UI evidence, device qualification, or production performance claim is made. Preserve the repository's draft-macOS gate; do not convert the PR to ready just to change aggregate CI.
