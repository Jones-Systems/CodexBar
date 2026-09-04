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

The first draft pull request is a dependency-complete foundation rather than false production activation: versioned models and protocol validation, provider-scoped environment configuration, safe command construction, fixture-backed read-only projection, and the smallest reviewable Codex settings UI slice. Credential-changing controls remain unavailable until the CAAM V3 public adapter and gateway satisfy the contract.
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
- Coherent checkpoints now cover the foundation (`be99bc4b5`), bounded client (`f0b2d6aa9`), snapshot-validation hardening (`24c641591` and `d3c0206a9`), formatting reconciliation (`802cde60c`), settings UI (`5bf27d79b`), verification reconciliation (`662333949`), and plan-bound fallback restoration (`987aef824`).
- SwiftFormat 0.61.1 passes all touched Swift files. `git diff --check`, touched-file width inspection, direct-shell absence inspection, localization-key presence, repository-size checks, shell syntax checks, documentation links, generated `llms.txt`, and site locales pass.
- The portable suite passed parser hashes, provider manifests, bundled plugin generation, package/release path checks, checksum checks, the Python process-cleanup suite, Swift-test sharding, and the CI path gate. Its Homebrew tap fixture could not start because this VPS lacks `jq`; that check is unrelated to the changed paths.
- SwiftLint 0.65.0 cannot load `libsourcekitdInProc.so` without a Swift toolchain on this VPS. The app-locale script also requires macOS `plutil`. These are unavailable checks rather than passing evidence.
- Synthetic Swift tests exist for configuration, contract validation, row projection, exact command construction, failure redaction, settings persistence, and coordinator refresh, but they have not executed on this VPS.
- No compile, UI screenshot, live CAAM, SSH gateway, credential, or mutation evidence exists yet.
- Swift build and macOS UI verification are unavailable on this VPS because `swift` is not installed and the complete app target is macOS-only.
- Production switching stays blocked until the CAAM V3 service is composed into a public, versioned gateway adapter with exact operation lookup and recovery semantics.
- The public `Jones-Systems/CodexBar` fork was created from upstream commit `392310c665485f8d57c93881e7416c5ebf69d8ef` and verified as a fork of `steipete/CodexBar`. Branch publication and draft-PR readback remain pending.
- Installation on the laptop, VPS, and Mac Mini; gateway provisioning; signing; release; automatic updates; merge; and deployment are outside the first PR's authority and finish line.
<!-- codex-section:end id="worknote.caam-environment-control#ctx.execution-evidence.001" -->
