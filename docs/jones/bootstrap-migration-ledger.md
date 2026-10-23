# Jones bootstrap migration ledger

Authority effect: none. Source implementation; hosted/native qualification pending.

Artifact ID: `jones-bootstrap-migration`. Section ID: `jones-bootstrap-migration#scope`.
This implements accepted CB-MIGRATION-R1 from task base
`889d2f341b0d4512df9baafaf1e9acd62d8e941d`. It does not authorize private-store
access, signing, environment activation, installation or launch.

Fork-owned source and tests:

- `Sources/CodexBarCore/JonesBootstrapMigration.swift`: injected, macOS-only
  allowlist planner, source/preimage/postimage receipts, intent-before-write and
  exact interrupted-plan reconciliation. No default store or filesystem lookup.
- `Sources/CodexBar/JonesBootstrapCommand.swift`: explicit early command, native
  identity checks, process Keychain disable, private journal, observable absence,
  exact persistent domains, supported preferences writes and fresh-process verify.
- `Tests/CodexBarTests/JonesBootstrapMigrationTests.swift`: dictionary-backed
  storage, no suite creation or ambient home; synthetic sentinels and interruptions.
- `Scripts/jones_install_app.py`: separate explicit bootstrap preparation, receipt
  consumption, install-only commit, launch and prelaunch rollback. Native app-data
  operations run only through the signed candidate command. Existing ordinary
  cross-team rejection is retained.
- `Scripts/test_jones_install_app.py`: fake native command boundary, receipts,
  binding/schema/replay/concurrency, before-launch rollback, v1 preservation and
  subsequent production rotation.
- `Scripts/jones_signing.py` and `Scripts/test_jones_update_metadata.py`: profiles
  may grant `2CUPSQS986.*`; signed app/widget entitlements remain exact.

Shared-source hook: `Sources/CodexBar/CodexbarApp.swift` carries
`JONES(bootstrap-migration)` before every application entry path. A marker-only
normal-entry guard prevents manual opening from bypassing the explicit launch
boundary; no startup data migration is introduced. The focused
`CodexBarLaunchModeTests` extension verifies explicit routing and disable-before-
operation. Existing upstream AppGroupSupport migration, provider initialization,
CloudKit persistence and Keychain ACL logic are unchanged.

The affected groups and exact invocations are in
[INSTALL-AND-UPDATES](INSTALL-AND-UPDATES.md#cb-migration-r1-affected-checks).
The initial portable cumulative run passed 52 installer, 42 metadata, 53 candidate
and 14 harness tests. Later candidate checks belong to the PR's exact revision.
The unchanged wildcard profile test failed against the in-memory validator from
`889d2f34` with the expected App Group grant refusal, then passed the candidate.
An initial baseline harness import-path failure was excluded from that evidence.
No local Swift compiler, dependencies, make check/test, signing, profiles or owner
stores were accessed. Hosted native results remain necessary.

Touched comments/docstrings use **keep near code** for intent-before-write,
absence/error, Keychain ordering and private-output invariants. The former native
adapter description was corrected for its explicit private bootstrap operation;
usage/retention/approval details live in the durable installation guide.
