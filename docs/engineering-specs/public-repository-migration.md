# Public standalone repository migration

<!-- codex-section:begin id="spec.public-repository-migration#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.public-repository-migration`

Purpose: Preserve CodexBar source and review history while establishing an independent public GitHub repository and qualifying its delivery path.

Governing artifact: none

Specification owner: CodexBar migration coordinator

Integration owner: CodexBar migration coordinator

Consumers: repository owner, migration operator, source owners and verification coordinator

Authority effect: none
<!-- codex-section:end id="spec.public-repository-migration#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.public-repository-migration#req.preservation.001" -->
## Requirements

The destination is public `Jones-Systems/CodexBar` with `fork: false`. Preserve
the existing fork, repository ID `1356759930`, its Git refs, PRs and discussions.
Preserve all local worktrees and unrelated changes. Copy only published Git
branches/tags; do not publish local scratch, remote-tracking refs, credentials,
user state or synthetic test artifacts. Preserve upstream license and attribution.

Recreate the five currently open PRs with original authorship attribution,
exact source heads, bases and draft states, and explicit legacy discussion links.
The owned account chain is old #11 → #12 → #13. Old #14 remains independent;
old #3 remains an unfinished draft. Migration does not establish source readiness.

Keep upstream monitoring disabled. Do not execute release workflows, publish
packages, sign/install/launch apps, access live authentication, change accounts,
reroute runners, restart services, or modify other machines.
<!-- codex-section:end id="spec.public-repository-migration#req.preservation.001" -->

<!-- codex-section:begin id="spec.public-repository-migration#dec.mechanism.001" -->
## Selected mechanism

Preserve the fork as `Jones-Systems/CodexBar-legacy-fork`, then create an empty
public `Jones-Systems/CodexBar`. GitHub's native detachment permanently discards
PRs and other metadata, so it does not satisfy preservation. Reusing the old
name removes its redirects: historical PR links must use the legacy name,
and stale Git remotes can reach the replacement repository. Obtain exact
approval for that namespace consequence before renaming.

Do not delete either repository as recovery. The legacy repository remains
the source of historical discussions and existing release metadata. The new
repository receives source, not an asserted copy of integrations or secrets.

Primary references: [detachment](https://docs.github.com/en/pull-requests/how-tos/work-with-forks/detaching-a-fork),
[rename effects](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository),
[Actions permissions](https://docs.github.com/en/rest/actions/permissions).
<!-- codex-section:end id="spec.public-repository-migration#dec.mechanism.001" -->

<!-- codex-section:begin id="spec.public-repository-migration#ctx.execution.001" -->
## Execution and checks

1. Refresh old repository identity, branch/tag manifest, all five PR identities,
   heads, bases and draft states; reconcile any writer or source movement.
2. Confirm the legacy name is available. Rename by the bound old repository,
   then read back the same ID at the legacy name and every original PR ID.
3. Create the empty public destination without initializing or rewriting history.
   Read back a different ID and `fork: false`; bind subsequent calls to that ID.
4. Disable destination Actions and verify `enabled: false` before importing refs.
   Use a separate migration source clone and explicit branch/tag refspecs, with
   no force, deletion or local scratch refs. Verify every destination SHA against
   the fresh manifest, including annotated tag objects and peeled targets.
5. Set default branch `main`; preserve applicable non-secret repository settings.
   Explicitly disable the monitor and release workflows before any CI activation.
   Verify workflow identities and states. If Actions registration requires
   execution, hold instead of enabling the whole repository speculatively.
6. Keep the existing shared bare repository's origin addressing the legacy object;
   any remote edit affects all linked worktrees and requires owner coordination.
   Give the new destination its own explicit remote and verify its repository ID.
7. Recreate old #11, #12, #13 in dependency order and old #14/#3 independently.
   Preserve #3 as draft. Record old ID/number → new ID/number mappings. Register
   every worked PR with this thread and cross-link exact legacy discussions.
   Before name reuse, reconcile this thread's existing native PR links: after
   verified rename, link each legacy URL and unlink its old-name association.
   Verify the resulting native list before creating replacement PRs; old-name
   links must not silently identify different PRs in the new repository.
8. Use installed `github/gh-stack` v0.2.1 only after freezing before/after refs,
   OIDs, diffs, writers and membership. Link full new PR URLs, then read the native
   stack endpoint to verify complete order and all member refs. No rebase or force.
9. Activate only approved CI effects. Watch native current-head runs, repair
   in-scope source failures, and retain every owned test. Empty, skipped required,
   cancelled, stale or missing checks are not passes. Refresh resource admission
   before local tests; preserve the repository's synthetic fixture lifecycle.
10. Merge only under a separately bound readiness contract for the new repository
    and PR identities, using merge commits and native expected-head guards.
    Recheck required checks, reviews, resolved conversations and source ownership;
    read back each merged state, merge commit and destination base afterward.

The installed stack extension's v0.2.1 async merge implementation sends merge
method/action but no head SHA. Do not use its merge command to satisfy an
expected-head requirement. The official versioned
[async merge API reference](https://github.com/github/gh-stack/blob/v0.2.1/docs/src/content/docs/reference/merge-api.md)
documents a `sha` request field. If this route is accepted for the qualified
native stack, bind the exact top head through that field and reconcile the
response's method/action/expected-head values. Freeze and recheck every member
and source owner as well; a top-head guard is not a guard on every mutable member.
Retain an accepted pending UUID and observe that same request through its
native result endpoint. An existing-request conflict is reconciliation, not
permission to submit another merge or fall back to the synchronous PR endpoint.

The old repository currently has no protected main branch or rulesets. Absence
of protection is not an accepted merge policy. Do not add or weaken rulesets,
bypass checks, or delete branches as part of this migration.
<!-- codex-section:end id="spec.public-repository-migration#ctx.execution.001" -->

<!-- codex-section:begin id="spec.public-repository-migration#ctx.operator-effects.001" -->
## Operator interaction inventory and approval envelope

This record has `Authority effect: none`. Existing owner direction covers the
public independent destination, source preparation and PR migration. Exact
additional approval is needed for the following effects, before their first use:

| Boundary | Exact proposed effect | Limit and readback |
| --- | --- | --- |
| Namespace | Rename repository `1356759930` to `CodexBar-legacy-fork`; reuse `Jones-Systems/CodexBar` for the public independent replacement | Preserve both objects and all original PRs; accept loss of old-name redirects; verify old/new IDs and public non-fork status |
| CI administration | Pause new-repository Actions before import; explicitly disable monitor/release; later enable CI only | No upstream-monitor or release runs; verify workflow states and actual current-head runs |
| Hosted CI setup | Existing `ci.yml` on GitHub-hosted Ubuntu/macOS: checksum-pinned lint/toolchain downloads, Linux package prerequisites and Swiftly post-install through `sudo`, macOS `sudo xcode-select` | Disposable hosted runners only; no laptop, Mini or VPS elevation, installation, service or runner changes |
| Linux negative CLI check | Existing two `CodexBarCLI usage --provider codex --web` invocations | Clean disposable Linux runner only, no imported credentials/browser state; expected macOS-only rejection, not live usage success |
| Local lint, optional | Repository-pinned SwiftFormat 0.61.1, SwiftLint 0.65.0, oxlint 1.76.0, oxfmt 0.61.0 and TypeScript 5.9.3 through the inspected repository installer | Task checkout locations only, no sudo/global tool installation; separately require coverage before use |
| Merge | Establish a bounded merge contract after new repository/PR IDs and qualified heads are known | Enumerate PRs, allowed base/method, applicable check identities, review requirement, resolved threads, expected-head guard and direct readback; no bypass |

Approval of migration does not waive trial/runtime gates or defer a required
check silently. The literal earlier no-install/no-sudo/no-usage constraints stay
effective until their bounded exceptions are explicitly accepted. The current
CI is not activated merely because the new repository is standalone.
<!-- codex-section:end id="spec.public-repository-migration#ctx.operator-effects.001" -->

<!-- codex-section:begin id="spec.public-repository-migration#ac.completion.001" -->
## Acceptance

The new repository is public, independent and correctly named, with verified
source ref equality and retained provenance. The old repository and original
PR metadata remain readable under the legacy name. All five open PRs have an
exact migration mapping; dependency and draft distinctions remain intact.
Monitoring/release exclusions are verified. Applicable current-source checks
actually pass before eligible merges; merged-state readbacks establish delivery.
Installation or account-switch success is not claimed from source/CI evidence.
<!-- codex-section:end id="spec.public-repository-migration#ac.completion.001" -->

<!-- codex-section:begin id="spec.public-repository-migration#ctx.recovery.001" -->
## Stop and recovery

Stop on identity/ref/writer variance, lost rollback, unknown prior effect,
unsupported capability, unapproved setup/probe effects or a failed required check.
After any ambiguous GitHub mutation, read repository IDs and native state before
retrying. If creation fails after rename, preserve and report the verified legacy
repository; do not delete, reverse-rename or vacate another name without covered
recovery. A partial ref import is reconciled ref by ref, never by force mirror.
Keep both repositories, all source refs and all existing worktrees until exact
separate cleanup authorization. Deferred findings retain their original severity
and evidence; missing proofs remain missing after migration.
<!-- codex-section:end id="spec.public-repository-migration#ctx.recovery.001" -->
