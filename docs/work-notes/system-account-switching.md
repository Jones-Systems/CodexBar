# System Account switching repair

<!-- codex-section:begin id="worknote.system-account-switching#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.system-account-switching`

Purpose: Preserve the account-switching diagnosis, bounded repair, and installed-app evidence.

Governing artifact: `spec.system-account-switching`

Continuity owner: CodexBar repair coordinator

Consumers: CodexBar maintainers and M Jones

Authority effect: none
<!-- codex-section:end id="worknote.system-account-switching#ctx.artifact-header.001" -->

## Binding and evidence

Canonical repository: `Jones-Systems/CodexBar`, repository ID `1425008735`.
Base: `dd23db9c61065e35bb8855777f82b33e8f232a57`.
Worktree: `/Users/malcolmjones/.t3/worktrees/CodexBar/system-account-switch-b8d16f9b`.
Branch: `work/system-account-switch-b8d16f9b`; root is sole Git owner.

The installed, running Jones app is `~/Applications/CodexBar Jones.app`, identifier
`com.jonessystems.codexbar`, arm64, ad-hoc signature, source stamp `6bacc6b`.
Its source tree matches the verified canonical base. The stock `/Applications/CodexBar.app`
is a separate installation and outside replacement scope.

Earlier work exists: local compatibility thread `bf186a16-2ba0-4f8a-9b73-bf175d5b7c14`
and VPS fleet-login thread `0488f286-4c8b-4932-9b44-67ef47cb70a3` are completed/settled.
No inspected active thread owns this reported error. Signing/permissions thread
`6ebd85ff-86b6-45a4-b34a-d71c91e60128` separately owns PR26; PR25 owns updater work.
Those PRs touch the application entry file; any new entry hook must remain additive
and independent of their bootstrap/update lifecycle. No live installation or signing
operation from those threads was adopted here.

The System Account submenu bypasses existing friendly labels and named-profile
projection. Workspace rows can represent distinct workspace identities or extra
managed/live observations; email equality alone cannot justify deleting them.
The generic destination error conflates ambient override mismatch with protected-path
overlap. File/link metadata shows the ordinary home and five canonical fleet auth
paths are separate regular paths, with no auth symlinks. Credential contents were
not read. The shell has an account-specific CODEX_HOME; launchctl returns empty for
CODEX_HOME and CODEX_SQLITE_HOME. Neither proves the running app's environment.

## Work and ownership

Contributing threads: `Fix CodexBar Account Switching`, native ID
`b8d16f9b-7c98-41e6-b8da-855b7145b198`, coordination, source, verification and delivery;
native subagents `/root/switch_source_diagnosis` (source evidence),
`/root/home_launch_framing` (bounded launch diagnosis), and `/root/named_system_menu`
(menu implementation and synthetic capture), plus `/root/switch_correctness_review`
(focused source correctness review); their native IDs are unavailable.
The earlier compatibility/fleet-login/signing threads above are referenced sources,
not contributors to this repair.

Read-only source investigation completed on the exact base. A separate read-only
diagnosis lane assesses launch normalization; it owns no writes. The menu builder
owns only the provider menu, its presentation helpers, and fleet-menu tests.
Root owns label spelling, launch repair, documentation, CI, Git and installation.
No concurrent test/build processes are assigned.

## Verification and delivery

No pre-fix Swift run: a cold build is disproportionate to the direct menu seam and
the laptop has only about 5.9 GiB available. Native tests and packaging must run on
a qualified remote/hosted Mac; no large local build or cleanup is authorized here.
Preserve the repository's isolated full-suite, formatting and applicable CI scope.
Record exact candidate and installed postconditions before claiming completion.

## Remaining work

The bounded launch policy and menu implementation are complete. The actual-helper
subprocess proof passed three cases and verified scratch cleanup; see
`docs/review-evidence/system-account-launch-proof.json`. SwiftFormat passed on all
12 touched/new Swift files. `make check` then passed, including zero SwiftLint
violations across 2,172 files. Full native CI and packaged-app results belong to the
exact PR check/artifact records and are required before delivery.

The existing Jones candidate workflow also captures the actual SwiftUI menu-row
consumer with synthetic accounts, including a clearly labeled reconstruction of
the old rows. Hosted artifacts retain only the two named PNGs, package and receipt;
no live account media is uploaded.

Registration request `system-account-switching-b8d16f9b-r1` returned
`registration_unavailable`, `effect: none`, `endpoint_unavailable`; no repair or retry.

The delivery sequence requires successful CI and packaging, a standing-policy
merge, preservation of the prior Jones bundle, and installation/launch of the exact
verified candidate. Runtime replacement receipts remain host-local. Do not switch
live credentials as a test.
