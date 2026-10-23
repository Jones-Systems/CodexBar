# Jones CodexBar installation and updates

Authority effect: none. This guide describes the APP-UPDATES-20261022 source
contract. Source implementation and synthetic tests do not prove a native
installation, a working feed, or a public release. Keep the existing
[identity and trial limitations](IDENTITY.md) and native consent boundaries.

## Candidate artifact and external verification

The bootstrap artifact is an **ad-hoc sealed, arm64, canonical-main CI bundle**.
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
seal and the arm64 app/widget executables. Required production metadata is:

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
