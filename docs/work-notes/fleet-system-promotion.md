# Authfleet → System Account copy

Artifact Type: work-note
Artifact ID: work.fleet-system-promotion
Authority effect: none
Decision owner: M Jones
Implementation owner: delegated Astra/high builder, generic native role fallback
Git/index/publication owner: root exclusively

## Binding and owner approval

Exact worktree: `/home/malcolmjones/Projects/CodexBar-worktrees/fleet-system-promotion-20261017`.
Branch: `work/fleet-system-promotion-20261017`.
HEAD/base: `e6837457ce42e0d1782e8c5b4399280277975e2d`, verified clean before edits.
Mode: Frontier, explicit_workstream, revision 1; supplied runtime Astra/high.
No agents delegated; the task explicitly prohibited further delegation.

Latest owner direction supplied in the task: “we can mimic that same behavior ...
making a copy of the authentication that we use ... swap it over to Jace ...
knows where the Jace account authentication is ... copies that over so that it
also exists as the default Codex home.” This supersedes the prior no-copy design
restriction for this bounded source implementation only.

Covered effects: source, synthetic tests, this work note, and the Jones hook ledger
delta in the bound worktree. End condition: coherent source candidate and exact
handoff to root. Excluded: live credentials/bindings, Keychain, provider calls,
login, host/app process changes, installs, signing, build wrappers, sudo, releases,
fleet propagation, Git/index/publication, and sibling/backing-checkout writes.
No operational or elevation approval was supplied or used. Registration and any
publication/qualification remain root-owned; no private registry was accessed.
AFR001/002 fixes and root's two discovery-macro fixes at the base are preserved.
TIR001/002 in separate PR12 remain deferred and untouched.

## Implemented source behavior

An Authfleet profile row carries a typed fleet target containing its canonical
home, normalized expected email, provider/workspace account identity, and observed
auth fingerprint. It stays a profile usage source, has no fabricated managed UUID,
and requires no CodexBar enrollment or login. The existing System Account submenu,
represented-object routing and coordinator accept that target. Usage selection
alone still does not change the system account.

The service acquires the existing shared writer and checks cancellation before
admission or credential reads. Fresh fleet membership is checked before snapshot
loading, again before preparing the source, and after asynchronous preparation.
Direct parsed source identity and fingerprint must match the captured target;
source bytes are reread and compared before preservation/write. Removed, rebound,
stale, ambiguous, absent and unreadable sources fail closed without fallback.
Canonical auth remains in place; only `auth.json` bytes are copied through the
existing preservation executor and atomic live-file swapper. Fleet promotion
cannot use the managed convergence shortcut to report a copy that did not occur.

Displaced auth keeps the existing managed-preservation workflow. Every fleet home
and the live destination are excluded from preservation writes/deletions,
including alias/ancestor overlap. Existing managed promotion behavior, the shared
writer, login cancellation and drain/reap exclusion remain in force.

## Exact destination semantics

For a fleet request, the intended destination is
`FileManager.homeDirectoryForCurrentUser/.codex`, resolved through the existing
`CodexHomeScope.ambientHomeURL(env: [:], fileManager:)` seam. Tests inject the
ordinary home or an explicit owned default-home URL. The service also compares the
process ambient home (the existing nonempty `CODEX_HOME`, otherwise ordinary
`.codex`) with that default. A conflicting override fails closed **before auth
reads**, even if it points at the selected fleet profile. No environment variable
is changed. Source/destination equality, resolved aliases, and overlaps with other
fleet homes are rejected.

This deliberate refusal keeps `.liveSystem` consumers aligned with the actual
copy destination. It does not claim that a harness launched with fleet
`CODEX_HOME` has switched the ordinary desktop/CLI account. Managed targets retain
the pre-existing ambient-home semantics. No running session is retargeted.

## Preservation limits and operational gates

This is not a new rollback engine. As before, refreshing/repairing a managed
preservation destination can copy auth before its metadata commit; a metadata
failure may leave changed managed auth with stale metadata. A later swap failure
can leave a successfully preserved displaced account in managed storage while
system and fleet auth remain unchanged. Synthetic tests assert those postconditions.
The in-process writer excludes CodexBar writers; it does not lock external CLI or
Authfleet refreshers. Reread checks reduce stale preparation but do not prove
cross-process refresh safety or transactional rollback.

Remaining root-owned gates: native Swift/macOS qualification, full lint toolchain,
review/publication, and separately authorized ordinary desktop/CLI effective-home
verification. No installed app, laptop run, live auth copy, system-account switch,
refresh safety, or cross-host result is claimed. No owner live-operation request
is made by this handoff.

## Synthetic coverage and evidence

Fixtures use `CodexCredentialFixtures` scoped roots with teardown/defer cleanup,
dictionary-backed defaults, explicit managed-store/home URLs, injected membership,
reader/snapshot/writer seams, and an injected synthetic `FileManager` home when
proving the ordinary default. No fixture grants the real user home or reads a real
fleet binding. The bounded command scratch was created inside this task worktree
and verified removed after the unavailable test run.

Added tests cover successful copy and preserved canonical bytes, no target
enrollment, same-email/different-home and same-identity/different-home targets,
queued removal/rebinding/identity change/credential rotation, workspace mismatch,
missing/unreadable sources even with matching live identity, equal/aliased homes,
conflicting launch override, cancellation before reads, post-preparation membership,
protected fleet preservation, metadata/swap failure postconditions, typed menu
payload and coordinator activation. The existing drain test now exercises both
managed and fleet targets. Existing managed suites remain the regression baseline.

- Fresh telemetry before test entry: CPU 7.19%, available RAM 42.21 GiB; one core
  is 6.25% of host capacity. Serial ceiling 1; tests prohibited at CPU ≥85%.
- `make test`: exit 2; discovery failed with `FileNotFoundError: swift`.
  Zero selections/groups/tests executed. No repeat of the unavailable native run.
- `make check`: execution held after `make -n check` and script inspection.
  It invokes installer/packaging checks and on-demand tooling installation;
  `Scripts/install_codexbar_cli.sh` is absent and SwiftLint is unavailable.
  No tool installation or package/build wrapper was attempted.
- SwiftFormat 0.61.1: owned-file-only `--lint --cache ignore` passed, exit 0;
  0/20 files require formatting. Final admission CPU 4.32%, available RAM
  42.17 GiB, serial ceiling 1.
- `git diff --check`: passed, exit 0. Index remains unstaged; branch and HEAD unchanged.

The new test source is not passing-test evidence. SwiftFormat is not a compiler.
The fork boundary and exact affected suites are recorded in
`../jones/fleet-system-promotion-ledger.md`.

## Ownership release and exact candidate manifest

Builder releases all source/test/document write ownership to root at terminal
handoff. No other lane's files were changed. The index remains root-owned and
untouched by this implementation; no stage, commit, branch, push or PR action was
performed. Root may now review and mutate this candidate. No further writes by
this builder are pending.

SHA-256 values below cover every changed path except this work note itself;
its final-byte SHA-256 is returned in the terminal handoff to avoid a recursive
self-digest. Paths are relative to the exact worktree above. These identify
uncommitted source bytes, not a new commit or executed native result.

| Path | SHA-256 |
| --- | --- |
| `Sources/CodexBar/CodexAccountPromotionCoordinator.swift` | `dbe50d6ba801b13d5e3666effec4f22473b1a33b657e535d2a6119a2e32b759d` |
| `Sources/CodexBar/CodexAccountPromotionExecution.swift` | `6d3ca8f932e0f2a41f548758484d2637fc0cefa6b4fb369e72b881b24825c40b` |
| `Sources/CodexBar/CodexAccountPromotionPlanning.swift` | `1fb1a9906cd5feca51764e5134cd2e321eaabf6c6c7ce559702947b44dcfd00a` |
| `Sources/CodexBar/CodexAccountPromotionPreparation.swift` | `4f06da2f6815dedc821017db15f59f2d8475d3f5a7b4499e5853fd7d80606ca8` |
| `Sources/CodexBar/CodexAccountPromotionService.swift` | `f7f14c48d1a0b65fe1b6b6fad7e30833056e2f1c30178dae2877f19ba7d8ecca` |
| `Sources/CodexBar/Jones/JonesCodexFleetPromotionAdmission.swift` | `d1eceee3811998c5e7a3d3226b3d3c09513da2da63eccf4965d354cf0a3cc440` |
| `Sources/CodexBar/MenuDescriptor.swift` | `6c736add0cffc96fdc6e3c7ab84654f42b7588d613b1a130a1aa5a40c9d3c03c` |
| `Sources/CodexBar/Providers/Codex/CodexProviderImplementation.swift` | `ab41e947d7f71b4aa72048ba45e5630be7a29e57265571b098374538853ba69b` |
| `Sources/CodexBar/StatusItemController+Actions.swift` | `84e8fa1029e32720ae3894a9633e6f0ce452aa7966374b7f709f1d64a6d8a6ab` |
| `Sources/CodexBar/StatusItemController+MenuActionMapping.swift` | `1aa9c5bacd874b1ca5d5a43c7448aea18e725f98c4c255cdcc9d1fc1894bb838` |
| `Sources/CodexBarCore/Jones/JonesCodexSystemPromotionTarget.swift` | `488455e832cfbc7e9f8a8e0cab059a85246769621f78c17ac4cd52eca5afc996` |
| `Sources/CodexBarCore/Providers/Codex/CodexVisibleAccountProjection.swift` | `bfff8d1ee9f3801b026c372adc1d4508d41ef32a9130c41490490eb2bbfaabbc` |
| `Tests/CodexBarTests/CodexAccountPromotionExecutionTests.swift` | `b25ed854c425332fe57eeeabf325c3dd2ff40735d013a19144546715a2bc9366` |
| `Tests/CodexBarTests/CodexAccountPromotionPreparationTests.swift` | `37cf7b1cd7303191f6901b46de7276e0d576fffcaf4b2b3876652ea662ed7c57` |
| `Tests/CodexBarTests/CodexAccountPromotionTestSupport.swift` | `b6181e2d7915f0894f2dd414d8325c4da5f252ce091ceff960d705d7ffe790ca` |
| `Tests/CodexBarTests/CodexSystemPromotionUITests.swift` | `03f6ea02269dff549f4de7758045e3c395feaa402c5ea240d91708288dd12538` |
| `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionBoundaryTests.swift` | `12b0a11e56aaf9ea6753e89502d8b5152103b793babbd4a87f22f95db2861c05` |
| `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionMenuTests.swift` | `cef62a3156b5e1d34a9f41be254e23642a00bb6282b0c0c647ab4ca9d44faea8` |
| `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionTestSupport.swift` | `b7ebdaa6c7009079308952024a4064a2888442b03d88d050305a299222f57244` |
| `Tests/CodexBarTests/Jones/JonesCodexFleetPromotionTests.swift` | `25c5f9ab9573bfe79b08f3c682ea9db4bafbe0946d690ed2ece63f89b6d7f667` |
| `docs/jones/fleet-system-promotion-ledger.md` | `e20b03b103538e87038614baf5aed7231c1c26299a71ad88e26597953b168263` |

## Root integration and focused review

Source committed at `7805dac297e19d882e249434c9c0d52d056f05d2` and integrated
without source differences at `0f06d9e4dedc733dd3c349f504f0fe4b11a80bb5`.
Independent Astra/high correctness review found no actionable changed-surface
findings; exact binding is `../review-evidence/fleet-system-copy-7805dac29.json`.
This is source review only; native compilation, affected suites and lint gates remain.
The existing private-registry endpoint-unavailable result remains a capability gap;
no registration, endpoint repair or enrollment is claimed.

Laptop handoff delivery gap: installed cross-host metadata binds peer environment
`62b43f49-f7ac-46e8-a52c-8640a933c697`, rather than requested laptop environment
`8750edf7-486b-41ac-81ce-cd50dfeb71eb`. No route/configuration or recipient change,
and no cross-host send was attempted. Root supplies a self-contained handoff.
