# Work Note — Repository Synchronization

<!-- codex-section:begin id="work.repository-sync#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `work.repository-sync`

Purpose: Preserve research, implementation evidence, limitations, and continuation for safe repository synchronization.

Governing artifact: owner Task Text; the progressive `spec.repository-sync` will own implementation decisions.

Work owner: single Level 2 project agent

Consumers: CodexBar maintainers, host-capability implementer, owner, and reviewers

Authority effect: none
<!-- codex-section:end id="work.repository-sync#ctx.artifact-header.001" -->

## Goal and finish line

Reconcile each selected repository/environment pair against its configured canonical Git remote. Do not copy working directories or uncommitted content between machines. Deliver the safe repository-owned implementation, proving tests, documented host boundary, and one draft PR. A draft is a visibility checkpoint, not merge or deployment readiness.

The owner authorizes connected GitHub reads and task-branch commits/draft PR publication. No live laptop, Mac Mini, VPS, credential store, ChatGPT Web Connector, bot review, merge, deployment, installation, fork, new repository, force push, branch deletion, or protected-environment change is authorized here. Work uses sequential research, architecture, implementation, verification, security, maintainability, and self-review passes; there is no independent-review claim.

## Source strategy and current evidence

Native GitHub is the repository transport. Public primary documentation supplies Git semantics and platform guidance. Upstream implementation is not an implementation input.

| Binding | Immutable observation |
| --- | --- |
| Target | `Jones-Systems/CodexBar`, repository ID `1356759930`, public fork |
| Approved base | `main` at `d6e929cd736eccae187cd41ddb5305a670afb2c8` |
| Base tree | `d1e5d48281ed0ceabc34a06d6cbf0cc25d328068` |
| Task branch | `work/repository-sync-orchestration-20260907` |
| Level 2 guidance | `Jones-Systems/Codex-V3@a88f2e251961b9a9767cd09fa1e882205484e401` |
| Current V3 reference | `Jones-Systems/Codex-V3@6c049da2795d9cea922528021f9af80bf8640704` |
| Upstream evaluated | `Dicklesworthstone/repo_updater@b5fe0131d3bb53fe311f6ebfc54d60fbc2404c73` |
| Upstream LICENSE blob | `3d414da6ff83defe084707be6030866e8a7fb794` |
| Upstream README blob | `6b6b7ea6467e52fcc7a4b516ae11d5c3d06d0d77` |

The upstream head was resolved natively, not assumed from the prompt. The license is titled **MIT License (with OpenAI/Anthropic Rider)**. Its controlling rider defines restricted parties and says **“no rights are granted to any Restricted Party”** absent prior written permission. It also expressly addresses analysis, execution, testing, and derivatives. The README's MIT badge is not affirmative reuse permission. Engineering disposition: **reference_only**; no upstream implementation is copied, vendored, translated, ported, forked, installed, or executed. Any contrary reuse decision requires owner/legal disposition or an affirmatively compatible permission grant. This is factual license evidence and a conservative engineering gate, not a legal ruling about the owner.

Immutable evidence: [LICENSE](https://github.com/Dicklesworthstone/repo_updater/blob/b5fe0131d3bb53fe311f6ebfc54d60fbc2404c73/LICENSE), [README](https://github.com/Dicklesworthstone/repo_updater/blob/b5fe0131d3bb53fe311f6ebfc54d60fbc2404c73/README.md).

The merged CAAM foundation provides `CAAMEnvironmentConfiguration.id`, labels, and local/SSH connection configuration. The separate account-control v1 contract already requires environment binding, revision/plan checks, credential-free output, and unknown-effect reconciliation. Reuse its environment identity; do not add repository operations to its closed account-control command family.

[Existing draft PR #2](https://github.com/Jones-Systems/CodexBar/pull/2) remains unmerged at `0bdf8a262bc9342d9b62a5f12f8062db22273b50`. It changes CAAM controls, the environment preferences section, observability, subprocess code, locales, and related tests. New synchronization modules must not silently adopt or overwrite that draft. Any minimal entry-point overlap must be reported and reviewed.

## Research lanes and execution

One agent owns synthesis. Lanes are sequential because the owner prohibits subagents: licensing/adoption; documented upstream behavior and maturity; current CodexBar/host contracts; Git-state and threat model; UI alternatives; implementation and deterministic verification. The eight requested adoption/ownership directions will be compared before finalizing the specification.

Current checkpoint: source bindings, initial license gate, merged environment model, overlapping draft paths, and CI policy inspected. Research and implementation are not complete. The next effect is further bounded read-only research, followed by a progressive Engineering Spec and a coherent implementation checkpoint.

CI is triggered by PR events rather than ordinary non-main branch pushes. The current workflow defers required macOS tests for draft PRs and keeps aggregate CI incomplete. Preserve that gate; do not convert this explicitly requested draft to ready merely to obtain a green aggregate. Linux builds/tests and lint remain useful independent evidence.

## Blockers, incidents, and verification limits

- A percent-escaped branch-API route returned `INVALID_ARGUMENT` / HTTP 400. The alternate native Git-reference route succeeded. Known no effect; this was not repository access denial.
- Public codeload download from scratch failed with curl exit 6 (DNS resolution). Native connected GitHub reads work. Use exact file-content reconstruction and Git blob verification for the bounded source closure; do not claim a complete checkout or full local build from missing source.
- Scratch contains Swift 6.2.1, Git 2.47.3, Python 3.13.5, Bash, and make. SwiftFormat, SwiftLint, gh, macOS frameworks, Xcode, signing, and owner devices are not available. No dependencies or owner-device software were installed.
- No implementation checks have run at this research checkpoint. No live repository synchronization has occurred.

## Level 2 recovery checkpoint

<!-- chatgpt-level2-recovery:v1 -->
Recovery status: not created. This normal Work Note preserves the current useful continuation; there is no separate unfinished implementation payload yet. Do not create an empty recovery branch. If unique unfinished scratch later needs preservation, use only `scratch/level-2/work/repository-sync-orchestration-20260907` and link its verified README, manifest, and commit here or in a linked PR checkpoint. Never place `.chatgpt-scratch/` in the task branch or PR history.
