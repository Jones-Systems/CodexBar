# Jones CodexBar installation and updates

Authority effect: none. This guide describes the APP-UPDATES-20261022 source
contract. Source implementation and synthetic tests do not prove a native
installation, a working feed, or a public release. Keep the existing
[identity and trial limitations](IDENTITY.md) and native consent boundaries.

## Candidate artifact and external verification

The default bootstrap artifact is an **ad-hoc sealed, universal ARM64/x86_64, canonical-main CI bundle**.
It is for the separately authorized local Jones install. It is not a signed,
notarized public distribution. PR artifacts and local builds are not eligible
for this installer.

Before passing an archive to the helper, the root/operator must independently
verify canonical GitHub metadata and retain the verification capsule:

- Repository `Jones-Systems/CodexBar`, repository ID `1425008735`, canonical
  `main`, and the complete reviewed 40-character source revision.
- The successful, authorized candidate workflow/run, its exact source revision,
  event/base and artifact association. A URL in a plist is only a claim.
- The exact downloaded package archive, byte count and SHA-256 associated with
  that verified run. Do not accept a checksum supplied by an unrelated download.
- The exact installation target and applicable Mac resource/installation
  authorization. An available helper does not grant operational permission.

The helper performs no network request or GitHub authentication. Its
`--expect-revision` and `--sha256` inputs bind it to that external capsule;
matching them alone does not establish GitHub authenticity.

The input is the **package ZIP**, not an outer GitHub Actions artifact wrapper:

```text
candidate.zip
└── CodexBar.app/                 # CodexBar Jones.app/ is also accepted
    └── Contents/
        ├── Info.plist
        ├── MacOS/CodexBar
        ├── PlugIns/CodexBarWidget.appex/
        │   └── Contents/{Info.plist,MacOS/CodexBarWidget,...}
        └── ...sealed resources and embedded frameworks...
```

Include Unix file modes and contained relative framework symlinks. There must
be exactly one top-level app and no siblings, `__MACOSX`/AppleDouble entries,
absolute paths, path traversal, duplicate names, case/Unicode path collisions,
symlink traversal, special files or encrypted entries. Nested Sparkle helper
apps remain inside the sealed main bundle. ZIP compression must be stored or
deflate. The archive is limited to 256 MiB, the declared expanded contents to
1 GiB, and entries to 50,000. A fresh CI package can be archived without resource
fork/extended-attribute sidecars; the helper never strips quarantine from an
existing artifact to make it eligible. Seal validation after extraction must
still pass.

The candidate must carry `JonesSourceRevision` (lowercase 40-hex),
`JonesBuildOrigin=ci-main`, a canonical `JonesBuildRun` Actions URL,
`JonesUpdateChannel=none|stable`, a dotted display version and
`CFBundleVersion=<BUILD_NUMBER>.<first-parent commit count>`. The app and widget
builds must agree. Compare build components numerically; an equal/lower build
is refused even when its source revision differs.

## Local CLI and preflight

Run the helper from a reviewed source checkout, using an available Python 3.9+
interpreter. It uses only the Python standard library and system macOS commands.
The shell wrapper verifies the Python version and prints an actionable error
when unavailable; it does not install Python or invoke a build toolchain. An
Xcode command-line-tools shim is not evidence that Python is usable.

```bash
bash Scripts/jones_install_app.sh \
  --archive /absolute/path/candidate.zip \
  --sha256 VERIFIED_64_CHARACTER_LOWERCASE_SHA256 \
  --expect-revision VERIFIED_40_CHARACTER_LOWERCASE_SOURCE_REVISION \
  --preflight
```

The default target is `~/Applications/CodexBar Jones.app`. Use
`--target '/absolute/path/CodexBar Jones.app'` for another explicitly identified
target. Target paths must be absolute, have no symlink components, and be outside
application state, other app bundles, translocation and recovery storage. A
missing target parent can be created by an actual install; preflight never
creates it. A read-only or inaccessible destination requires another approved
location, not elevation or a permission bypass.

Preflight uses one private scratch directory on the target volume's nearest
existing ancestor and removes that exact directory before returning. It creates
no persistent directory, lock file, manifest or journal; it neither quits nor
launches an app. With existing recovery storage it takes a nonblocking lock on
the existing lock file. It checks available bytes before extraction using
`archive bytes + 2 × expanded bytes + 1 GiB reserve`. Installation rechecks for
the remaining staging allocation after taking its lock. These observations are
estimates, not reserved space or enforced quotas.

The helper checks the archive hash before extraction, contained file/link
layout, quarantine on the archive and bundle, the full identity tuple, strict
deep code-signature verification, typed ad-hoc signature metadata, the resource
seal and matching app/widget architecture slices. ARM64 must be present, either
alone for retained thin builds or alongside x86_64 for universal builds. Unknown,
duplicate or mismatched slices are refused. Recovery records keep the existing
`architecture=arm64` value for thin builds; universal builds record
`architecture=arm64+x86_64`. Required default ad-hoc metadata is:

| Field | Value |
| --- | --- |
| App bundle ID / `JonesAppBundleID` | `com.jonessystems.codexbar` |
| Display name | `CodexBar Jones` |
| State key | `jones` |
| Team metadata | `JONESLOCAL` |
| App group | `JONESLOCAL.com.jonessystems.codexbar` |
| iCloud metadata | `iCloud.com.jonessystems.codexbar` |
| Widget bundle ID | `com.jonessystems.codexbar.widget` |
| Signature kind / TeamIdentifier | ad-hoc / not set |

The currently supported ad-hoc app entitlement set is exactly
`com.apple.security.application-groups=[JONESLOCAL.com.jonessystems.codexbar]`;
the widget adds `com.apple.security.app-sandbox=true`. iCloud identifiers stay
in bundle metadata but **iCloud entitlements are absent** in this local ad-hoc
route. The entire signed entitlement set is checked, including unexpected
iCloud keys; it is compared with the installed app before replacement. An
installed entitlement set outside this known contract is a refusal requiring
root reconciliation, not permission to remove or rewrite entitlements.

Only an existing installed build `135` may lack `JonesSourceRevision`, after
the same identity, architecture and signature checks. It may be retained and
explicitly restored as the previous bundle. This exception never admits a
provenance-incomplete candidate archive. Harness identity/flags are refused.

## Machine-readable result

After Python starts, stdout is one JSON object with schema
`jones-app-install/v1` (except argparse help/usage errors). Successful preflight
returns exit `0`, `status=preflight_ok`, and:

| Field | Meaning |
| --- | --- |
| `target` | Absolute requested installation path |
| `candidate`, `installed` | Validated bundle metadata, identity, architecture, seals, signed entitlements and tree SHA-256; installed is null on first install |
| `archive_sha256`, `archive_bytes`, `expanded_bytes` | Validated input and declared extraction size |
| `required_bytes`, `available_bytes` | Initial disk admission calculation and observation |
| `running` | Only matching target/identity process metadata; no provider or preference data |
| `external_provenance` | `operator_verified_required`; the caller must supply the verified GitHub capsule |

Successful installation/restore returns `status=installed|restored`, the exact
running process bundle/executable path and PID, and `previous_path` (null for a
first install). Refusals/errors return `status=refused|failed`, `code`, `message`
and relevant bounded details. Exit `2` identifies an input/validation refusal;
exit `3` identifies an operational/recovery failure; a handled cancellation
uses `128 + signal`. Do not infer installation from a preflight result or an
exit code without the returned status and bundle readback.

Useful refusal codes include `hash`, `provenance`, `identity`, `entitlements`,
`quarantine`, `not_newer`, `capacity`, `other_running_copy`, `still_running`,
`busy`, `pending_transaction` and `unknown_state`. `scratch_cleanup_error`
preserves the original failure and names the exact scratch path for disposition.

## Installation, journal and retention

After a successful preflight and the required root authorization/resource slot,
run the same command without `--preflight`. All validations run again. No network
download, build, signing, notarization or provider probe is performed.

The installer creates an owner-only adjacent directory named
`.codexbar-jones-install-<target-path-digest>.noindex`. It lies outside application
state. Its `owner.json` binds schema, target, bundle ID and UID; `lock` serializes
that target; `manifest.json` records exact directory device/inode, complete
bundle fingerprints and the single retained previous bundle. A foreign directory,
unrecorded entry, changed bundle or pending journal causes refusal. Unknown
pending Jones siblings outside this directory are left untouched.

The candidate is copied with system `ditto` into a unique same-volume stage and
verified again. The installer requests a normal quit only after matching both
the running bundle path and ID, plus the executable path. It uses
[NSRunningApplication's normal termination API](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate%28%29?language=objc),
then rechecks completion. It sends no name-based or forced termination. Another
running Jones copy or a target that still runs after bounded waiting is a
refusal. Finish the app's interaction and quit the identified copy normally.

Journal phases are `staging`, `prepared`, `will_move_previous`, `will_install`,
`installed_uncommitted`, `will_commit`, and `committed`. The old target moves by
rename to a new `previous-<transaction>.app`; the verified stage moves into the
target location. A durable completed manifest is the commit boundary. Only then
may the previous manifest's explicitly recorded obsolete backup be removed.
Success retains exactly one previous bundle, or zero on first install. Existing
backups already reduce free-space observations; rename does not duplicate them.

Errors and handled INT/TERM/HUP before commit restore known preimages using
captured directory identities. Owned stage/scratch is cleaned on success,
failure and handled cancellation. The original error remains primary if scratch
cleanup also fails. After a failed attempt the prior app can remain quit; byte
restoration does not imply a relaunch. SIGKILL, machine loss, an unknown directory
change, failed rollback or failure after the commit boundary can leave recovery
evidence. **Do not delete the journal, sweep `.noindex` directories or blindly
rerun.** A new invocation never resumes a journal, even a recognizable phase.
The root must reconcile its exact paths, bytes and prior effects first.

Once committed, the helper opens only the exact installed app and checks the
running bundle/executable, brief survival and installed fingerprint. This is
ordinary app startup, with its ordinary account and provider behavior; it is
reserved for an actual authorized installation. Synthetic HOME is not isolation.
A Gatekeeper/consent/launch failure returns `installed_launch_unverified` and
retains the completed manifest. It does not silently roll back after launch may
have written application data. No quarantine attribute, Gatekeeper decision,
Keychain designated requirement, login-item permission or other native grant
is rewritten or bypassed.

## Explicit restore

```bash
bash Scripts/jones_install_app.sh --restore \
  --target "$HOME/Applications/CodexBar Jones.app"
```

Restore accepts no archive/hash/revision/preflight flags. It requires a completed,
known manifest and exact unchanged current and previous bundles. It takes the
same target lock, verifies identity/seals, quits only the exact target, swaps the
known prior bundle into place and retains the displaced current bundle as the
one previous copy. It then opens and checks the installed copy. The numeric
version gate is intentionally bypassed only on this explicit route. An unknown
journal or externally changed installation is not a restore authorization.

Restore affects **binary bytes only**. Preferences, account state, schemas and
data written by the newer version remain in place; a previous version may be
unable to read them. Restoring also does not suppress future update offers or
change automatic-update preferences. Assess compatibility and re-update behavior
before recovery; data migration or configuration changes need their own scope.

## Bootstrap versus authenticated updates

Channel `none` has no feed/public key and truthfully reports updates unavailable.
An ad-hoc CI candidate is a bootstrap artifact, not evidence that automatic
updates have been activated. Channel `stable` requires the separately validated
Jones HTTPS feed/public key, signed appcast metadata, archive verification before
extraction and zero signed-feed-failure expiry in the application controller.
The installer verifies package identity/provenance; it does not exercise or
activate the feed, and a `stable` label alone is not live-update proof.

For the Jones ad-hoc channel, **EdDSA is the sole update trust anchor**. Loss of
the key requires manual reinstall; compromise permits code execution as the
owner. There is no promised code-signature rotation fallback or weakening of
the designated requirement for Keychain continuity. Real private-key custody,
public release publication and trusted-channel activation remain held until the
root supplies their exact authorized release operation. This helper supplies no
key, secret lookup, public-signing or release path.

Native Keychain, app-data, login-item or App Management consent can recur on
ad-hoc updates. Preserve those dialogs and normal macOS handling. Sparkle owns
its download/cache/preparation/replacement lifecycle; this helper never sweeps
Sparkle storage. Sparkle's replacement recovery is not a promise of post-launch
rollback, and it does not retain this helper's previous bundle. If Sparkle or
another installer changes the managed target, the helper's old manifest becomes
stale and requires reconciliation before another helper transaction.

## Portable verification contract

Affected check group `jones-local-installer`:

```bash
python3 -B Scripts/test_jones_install_app.py
# Optional caller-owned disk directory:
python3 -B Scripts/test_jones_install_app.py --scratch-parent /absolute/owned/workspace
```

The suite creates a unique outer fixture beneath the repository (or supplied
parent), with per-test child fixtures. It uses fake signature, architecture,
quarantine, disk, `ditto`, process and launch adapters; it never runs a real
Jones-identity executable, native tool, Mac operation or credential/private-state
read. Temporary fixtures are removed on normal exit, failures and handled
signals, with no shared `/tmp` use. Unconditional process/host loss cannot run
cleanup. Failure scenarios include archive/identity/provenance refusals,
preflight effects, replacement/restore transitions, rename and copy failures,
unknown journal preservation, cancellation, retained-copy ownership, lock
contention and postlaunch failure without automatic rollback.

These direct tests cover the new flow; there was no existing deterministic
failing-before seam. Python 3.9 compatibility, the system-command adapter and
real bundle/launch behavior require their named environment checks; fake-adapter
passes alone cannot qualify them. Source delivery also requires the repository's
`make check`, `make test` and current-head CI contract, with unavailable checks
reported separately.

## Isolated native update proof

The candidate uses GitHub's standard `macos-26-intel` runner and the existing
universal packaging path. The 14 GB Intel runner provides more memory than the
7 GB ARM64 runner without requiring a larger paid runner in this public
repository. [GitHub runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
The existing full Swift test shards remain on `macos-26` ARM64. Candidate
admission keeps the same CPU, 3 GiB available-memory, normal-pressure and compiler
limits. Its conservative additional allocation estimate includes 16 GiB for both
build slices, 4 GiB scratch/artifacts, 2 GiB user caches and a 2 GiB reserve per
filesystem (24 GiB when all share one device). Actual capacity is sampled before
each serial command; these estimates reserve no resources.

Every default ad-hoc candidate/harness Mach-O, including the unchanged Sparkle binaries, must contain
exactly ARM64 and x86_64. Candidate provenance records those verified slices;
missing or unknown slices fail qualification. Hosted resource and updater tests
exercise the Intel slice. The native result records its host architecture, and
the exact exported fixtures still require root-scheduled ARM64 execution before
owner installation. Intel proof and ARM64 source tests do not establish that
artifact's ARM64 updater behavior.

Before archiving, candidate packaging probes both the app and bundled CLI with
the source checkout denied by the sandbox. Its owned package scratch lives under
the hosted runner's `RUNNER_TEMP`, outside that checkout, and is removed on
success, failure or handled cancellation. The smoke checker refuses scratch
inside the denied checkout before launching a probe. Portable fixtures exercise
the actual workflow shell and this placement/cleanup contract; only the native
candidate run proves resource loading under the real macOS sandbox.

The candidate workflow builds the actual app, then makes two fixture bundles
from that executable. They use only `com.jonessystems.codexbar.update-harness`,
have no production state key, app group or iCloud metadata/entitlements, and
omit product helpers/widgets. The fixture entry point runs before ordinary app
initialization; malformed fixture markers fail closed. It constructs the same
Jones updater controller and contacts only its sealed `127.0.0.1` feed.

Hosted CI compiles `jones_update_fixture_signer.swift` with one compiler job. Its
throwaway Ed25519 key exists only in memory for the preparation process; it
never calls Keychain APIs. Only `A.zip`, `B.zip`, `feeds.json` and `fixture.json`
are exported. `fixture.json` records source, public key, port, archive hashes,
complete bundle trees and disk estimates. The six native cases require unsigned
and wrong-key feeds to fail before downloading, an oversized signed item to fail
admission, a changed archive to fail before readiness, and real replacement for
normal quit and immediate install/relaunch. Installed bytes, build, bundle path
and a new process ID are checked. This is synthetic update proof, separate from
production signing custody, live feed readiness or installed owner-app proof.

For a root-scheduled Mac run, authenticate the exact Actions run, source and
artifact hash first, then unpack only those public fixtures into a new owned
directory. Estimate download, unpacked fixtures, run peak and reserve from the
actual artifact. The recorded loopback port must be free; the runner never
selects another port or re-signs fixtures on the Mac. After fresh host admission:

```bash
python3 -B Scripts/jones_update_harness.py run \
  --fixture /absolute/owned/public-fixture \
  --scratch-parent /absolute/owned/native-scratch \
  --expect-revision VERIFIED_40_CHARACTER_LOWERCASE_SOURCE_REVISION \
  --result /absolute/owned/native-result.json
```

The fixture needs a writable, canonical scratch parent and absent fixture-only
defaults/cache/HTTP storage/saved-state/log paths. An exclusive fixture lock
prevents concurrent runs for the same user. Existing fixture state is a refusal,
never cleanup permission. Ordinary completion and handled cancellation drain
only processes whose executable is within the exact invocation/cache roots,
then remove owned fixture state and scratch. There is no broad process-name
termination. If native process drain or cleanup cannot be proved, the exact
state, lock and scratch are retained for reconciliation; never sweep them or
re-run blindly. Hosted runner teardown supplies a final lifetime bound on CI.

The app's privacy manifest declares local capacity admission (`E174.1`), elapsed
timer calculations (`35F9.1`) and app/app-group preferences (`CA92.1`, `1C8F.1`).
Capacity and uptime observations are not transmitted by the updater. These
reasons follow [Apple's required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

## Explicit Developer ID inspection and transition hold

CB-SIGN-R1 adds `--signing-mode developer-id` to the installer. The default stays
`adhoc`, including existing API callers and build-135 handling. In Developer ID
mode the candidate must explicitly seal `JonesSigningMode=developer-id`, team
`2CUPSQS986`, and group `2CUPSQS986.com.jonessystems.codexbar`; app, widget,
display name, state key, archive bounds, arm64, canonical-main provenance,
monotonic build and hash requirements remain unchanged. Explicit Developer ID
packaging remains ARM64-only for Jones products; only binaries within the pinned
Sparkle framework may retain its existing ARM64 or ARM64/x86_64 slices. No vendor
bytes are thinned or rewritten. Missing, duplicate and unknown slices are refused.
Selection comes from the validated explicit signing mode, never host architecture
or untrusted artifact claims. Provenance reports the actual validated product
slices separately from each Mach-O's actual slices; a universal Sparkle does not
label an ARM64 Developer ID product universal. The native adapter
requires strict/deep code verification, Developer ID authority chain, exact team,
hardened runtime, secure timestamp, sealed resources, exact app/widget signed
entitlements, matching unexpired embedded profiles, an accepted stapled ticket
and Gatekeeper assessment. Signing metadata alone is insufficient.

The production app entitlement set includes its exact application/team IDs,
shared group, CloudKit service/container and Production environment. The widget
includes its own application ID, the same team/group and sandbox=true. Unknown signed
entitlements fail closed. Profiles may authorize the exact signed group with
`2CUPSQS986.*`; foreign-team and unconstrained wildcard grants fail closed.
Real profile availability is unknown.

The source permits an explicitly selected first installation or same-identity
replacement after external artifact verification and applicable authorization.
Ordinary installation **refuses an installed `JONESLOCAL` → `2CUPSQS986`
transition**, including preflight, before quit or swap. Restore cannot cross that
boundary either. The separate explicit bootstrap below requires a validated data
receipt; it is not a generic identity override. Removing an old app to evade the
ordinary check is not a supported migration procedure.

Production channel `none`, empty feed/key, and all automatic-update settings false
are mandatory. Do not publish these bootstrap ZIPs into a live legacy update feed.
Apple signing does not replace the separate Jones Ed25519 feed/archive signature.
No update activation, publication, installation, private-store migration or
Keychain change has been executed by this source work. It does not prove data
continuity. Binary rollback
retains its existing limits; it is not application-data rollback.

## CB-SIGN-R1 affected checks

The existing group manifests are extended in place; no new test module is added.

| Group | Exact invocation | Added coverage |
| --- | --- | --- |
| `jones-update-metadata` | `python3 -B Scripts/test_jones_update_metadata.py` | Explicit production metadata; profiles/certificate/expiry; runtime/timestamp/resources; main-only dispatch; secret-free argv and cleanup success/failure/cancellation with fake operations |
| `jones-candidate-artifact` | `python3 -B Scripts/test_jones_candidate_artifact.py` | Explicit signing mode, production metadata, dispatch SHA/workflow binding, held channel, mode-specific architecture validation and archive-roundtrip reporting |
| `jones-local-installer` | `python3 -B Scripts/test_jones_install_app.py` | Explicit adapter mode, legacy transition refusal before mutation, first-install preflight and held feed |
| `jones-identity-overlay` | `bash Scripts/test_jones_identity_overlay.sh` | Production identity selection, release/identity-only mode and required profiles; retains original upstream hashes |
| `jones-update-trust` | `bash Scripts/test.sh --filter JonesUpdateTrustPolicyTests` | Runtime production identity and channel hold; existing harness/feed trust cases |
| `jones-update-harness` | `python3 -B Scripts/test_jones_update_harness.py` | Universal app/vendor validation, host architecture reporting and existing six-scenario regression contract |

`make check` and `make test` remain required and are delegated to hosted CI when
local compiler execution is unavailable. The signing workflow's `source-checks`
job compiles the Security.framework import helper without credentials. The
protected signing job never runs on a PR. Pure profile fixtures and fake native
operations do not prove Apple acceptance, actual signing, provisioning,
notarization, installation, native app-state preservation, or a live feed.

New feature: failing-before evidence was not manufactured by signing or installing
an old app. The available local seams cover the added contract directly. Touched
comments/docstrings are kept near code for identity, secret handling, scratch
ownership and cleanup boundaries; prior ad-hoc-only descriptions are corrected
here and in the identity/release guides.


## Explicit owner bootstrap (CB-MIGRATION-R1)

This source-only route supports exactly the ad-hoc `JONESLOCAL` Jones app to
Developer ID team `2CUPSQS986`, retaining bundle ID `com.jonessystems.codexbar`,
state key `jones`, and channel `none`. Execution requires separate exact approval
for the named private-store reads/writes, signed artifact, installation and launch.
Production CloudKit capability/schema readiness must be established before normal
launch. Unchanged container strings do not prove record continuity.

The signed app's `--jones-bootstrap` command is intercepted before the harness,
resource smoke, `CodexBarApp`, AppDelegate, SettingsStore, UsageStore, providers or
CloudSyncEngine. It disables process-local Keychain access before inspecting any
store and exits after its operation. It never calls CloudSyncPersistence.load,
exports credentials, edits Keychain ACLs, or changes standard preferences/config.

The native adapter resolves the destination using the entitlement-aware App Group
container API, with no fallback. It independently proves source filesystem access
and uses exact persistent preference domains, excluding global, registration and
argument defaults. Permission, decoding, synchronization and I/O errors stop the
operation. An inaccessible group is not an empty group. Native old-group access
may require consent and remains unproved.

Only these data are copied, with all items preflighted before any data write:

- Shared `debugDisableKeychainAccess`, `widgetSelectedProvider`, and
  `providerAccentColors`. Existing local Keychain preference takes precedence;
  an old shared-only disable remains effective before normal initialization.
- `widget-snapshot.json`, considering both the old group and
  `~/Library/Application Support/CodexBar Jones/`. Two different snapshots require
  `--snapshot-source old-group` or `--snapshot-source fallback`; timestamps do not
  choose the source. Equal destinations are no-ops; different values stop.

The old group, fallback, standard domain, `~/.codexbar-jones/config.json`, Keychain
items/ACLs and `CodexBar Jones/sync/engine-state.json` are retained. The destination
uses supported CFPreferences writes, checked synchronization, and a fresh helper
process for readback. No preference or snapshot payload is printed.

The separately approved sequence uses the existing verified archive, SHA-256,
source revision and exact target arguments plus `--signing-mode developer-id`:

1. Quit the exact old Jones app. Add `--bootstrap-prepare` to validate the artifact,
   write the private request/intent, prepare allowlisted data and invoke a fresh
   verification process. The result returns only the receipt path/hash and
   transaction ID. `--bootstrap-resume` reuses that exact request after interrupted
   preparation; source drift, changed candidate or unknown effects refuse.
2. Consume the reviewed `--bootstrap-receipt PATH --receipt-sha256 HASH` with the
   same artifact arguments. The installer checks UID, target, old bundle tree,
   candidate archive/tree, source revision, identities, plan hash and receipt hash,
   then repeats data verification under quiescence immediately before the swap.
   It stops at `installed-not-launched` and returns a new receipt hash.
3. Use `--bootstrap-launch --bootstrap-receipt PATH --receipt-sha256 HASH` with
   the same target and signing mode, without archive arguments, only when the
   normal-launch approval and CloudKit readiness are satisfied. A durable
   `launch-attempted` marker precedes launch. Failure cannot trigger automatic
   rollback. Ordinary updates/restore are blocked until this explicit boundary.
   The early normal-entry guard also refuses manual opening while the private
   bootstrap marker is incomplete or installed; it reads only generated installer
   metadata and performs no migration. First installations without bootstrap
   storage retain their normal entry behavior.
4. Before any normal launch, the exact alternative is `--bootstrap-rollback`
   with that installed receipt/hash. It restores the proved old bundle, retains
   the production bundle and prepared destination data, and consumes the rollback
   path. It does not launch either app or restore application data.

The private bootstrap directory is a deterministic sibling of the installer's
existing recovery directory, ending `.noindex.bootstrap`. Directory mode is 0700;
request/receipt/locks and install markers are 0600. The versioned receipt binds
transaction, UID, target, bundle fingerprints, archive, revision, resolved paths,
and per-item source/preimage/postimage SHA-256 or proven absence. Its canonical
plan is hashed; the outer receipt hash is supplied explicitly to each consuming
operation. Hashes bind evidence, not approval. Unknown schemas and replay refuse.

Journal phases are `incomplete`, `prepared`, `data-verified`, `installed` and
`launch-attempted`. Intent precedes data writes; interrupted preparation accepts
only recorded preimages or postimages. Missing journals, interrupted durable
commit, interrupted rollback and uncertain renames require exact reconciliation,
not journal deletion or blind rerun. Data are not deleted on a bundle rollback.
Locks prevent concurrent installer/helper writes; external source changes still
cause a fresh readback refusal.

The bootstrap's original `legacy.app` lives outside the rotating production
`previous` slot. The v1 installer manifest remains readable. Bootstrap creates a
v2 manifest preserving any v1 previous bundle in `bootstrap_previous`; later
same-identity updates and restores retain it and the separate legacy copy. No
cleanup/retirement of those retained bootstrap artifacts is implicit.

### CB-MIGRATION-R1 affected checks

| Group | Exact invocation | Contract |
| --- | --- | --- |
| `jones-bootstrap-migration` | `bash Scripts/test.sh --filter JonesBootstrapMigrationTests` | Dictionary-backed source/destination, no ambient defaults/files, conflict/error no-write, snapshots, policy, interruption/resume, drift/schema checks |
| `jones-bootstrap-launch` | `bash Scripts/test.sh --filter CodexBarLaunchModeTests` | Explicit routing and Keychain disable before the injected operation |
| `jones-local-installer` | `python3 -B Scripts/test_jones_install_app.py` | Receipt bindings, replay, quiescence, locks, rollback boundaries, v1/v2 compatibility, separate legacy retention and ordinary signed update/restore |
| `jones-update-metadata` | `python3 -B Scripts/test_jones_update_metadata.py` | Exact signed entitlement with documented team-scoped profile grant |
| `jones-update-trust` | `bash Scripts/test.sh --filter JonesUpdateTrustPolicyTests` | Automatic cross-team update remains disabled |
| `jones-bootstrap-compatibility` | `bash Scripts/test.sh --filter 'SettingsStoreKeychainPreferenceTests|AppGroupSupportTests|JonesStateRootTests'` | Existing policy, upstream migration and Jones isolation contracts |

Also retain the `jones-candidate-artifact`, `jones-update-harness` and
`jones-identity-overlay` groups above. `make check` and `make test` remain required;
Swift compilation and these native tests use hosted CI under the local compiler
restriction. Portable fixtures cannot establish actual source-group consent,
profile availability, native preferences durability, CloudKit record/schema
continuity, login-item behavior or installed-owner-app recovery. Those remain
protected execution gates. See the [fork ledger](bootstrap-migration-ledger.md).
