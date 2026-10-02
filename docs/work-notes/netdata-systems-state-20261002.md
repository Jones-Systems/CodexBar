# Netdata synthetic Systems and refresh state

<!-- codex-section:begin id="worknote.netdata-systems-state#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.netdata-systems-state`

Purpose: Carry the portable supplied-observation presentation and refresh-state checkpoint.

Governing artifact: `spec.netdata-menu-bar#iface.host-observation.001`, `spec.netdata-menu-bar#iface.polling.001`

Continuity owner: Portfolio slot14, under root's exact five-file candidate binding.

Consumers: Netdata client coordinator, future Systems UI and app integration owners.

Authority effect: none
<!-- codex-section:end id="worknote.netdata-systems-state#ctx.artifact-header.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#ctx.scope.001" -->
## Scope and identity

Original T3 task: `718b02d7-0d4b-4670-b05f-57a5db28178d`, Resume NetData Menu Bar Monitoring.
The original successor and parent/parser/client writers retain their existing worktrees.
Slot14 owns only this new candidate and its five additive source, test and note paths.
Root bound an independent task-owned common store and branch
`work/netdata-systems-state-20261002-slot14` at immutable client checkpoint
`1849a8cb0a4235b4e406036cc65316e99f53c0ba`.
The initial full-history local fetch failed on an unavailable promisor object;
direct readback found zero objects, no refs and an empty FETCH_HEAD.
A depth-one local exact-base fetch then succeeded without fetching or advancing
the original common store. This candidate has shallow history and is local only.

No package, lockfile, generated resource, parent UI, settings, app lifecycle,
transport, provider account or shared host file is changed. No publication, native Mac
run, protected endpoint use, shared/system installation or settlement is authorized here.
The prior specialist judgment used the full private capsule. Its retained Sol
qualification covered safe metadata only, not private-body semantic review.
<!-- codex-section:end id="worknote.netdata-systems-state#ctx.scope.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#iface.state.001" -->
## Supplied state and acceptance

`NetdataSystemsState` projects one identity-matched `HubHostObservation` into
explicit CPU percent, available RAM GiB, shared sample time, receipt time,
availability and compact label. Absent values differ from true zero; used memory
is never substituted. Stale compact labels hide values. Cached detail values
retain the original sample timestamp and require an explicitly historical UI.
The legacy observation has one shared sample time, so this adapter does not
invent independent per-metric source timestamps or qualification.

`NetdataRefreshState` makes injected event/time decisions, with one in-flight
request, monotonically increasing request identity, configuration-change and
late-result rejection, failure cache retention, cancellation, suspension and
wake. It returns scheduling dates; it creates no timer, task or request.
Working defaults remain five seconds visible and ten seconds background,
with failure backoff capped at sixty seconds. Cache display ages at thirty
seconds and becomes unavailable after five minutes. These are synthetic
behavior predicates, not a measured native performance budget.

Acceptance for this checkpoint: deterministic synthetic tests cover units,
missing/zero values, host isolation, age boundaries, failure and recovery,
one request, configuration changes, cancellation, sleep/wake and late replies.
Future UI wiring, localization, real polling and protected-route qualification
belong to their exact integration owners. Parent PR2 ownership/overlap remains
the gate for those shared paths, not for these new isolated state files.
<!-- codex-section:end id="worknote.netdata-systems-state#iface.state.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#test.evidence.001" -->
## Verification

The affected synthetic union is the two new suites plus
`ObservabilityHubLinuxTests` and `NetdataLoopbackClientLinuxTests`. At the initial
local checkpoint, the ordinary PATH and conventional executable paths had no
Swift route. Root subsequently authorized necessary unprivileged official pinned
tool acquisition exclusively under the task-owned verification-tools directory,
with an eight-GiB budget and process-scoped paths/cache/scratch. No shared tool,
profile, system package, privileged operation or active pointer is authorized.

The official Swift 6.2 Debian12/x86-64 archive downloaded as 1,007,200,281 bytes,
SHA-256 `7fa0b68b2052228bf19078e35d783253702257176747bf6edd26143f797bc501`.
Its cryptographic signature matches official six-series fingerprint
`52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`, but GPG reports the current key
expired. The official individual key, fresh official collection and documented
keyserver all retain that expiry. Extraction initially stopped at this variance.
Root then clarified immutable release authentication: the actual GPG exit is 0
with `VALIDSIG`; the signed timestamp 1757714412 is inside the key's validity
interval 1726518657 through 1789590657; the signature has no expiration; and
the refreshed official same-key material has no observed revocation. The
[GnuPG status contract](https://github.com/gpg/gnupg/blob/master/doc/DETAILS)
distinguishes cryptographic validity from current key expiry and revocation.
The current official distribution still serves the immutable archive URL with
the same length; this task's actual official download produced the stated hash.
Root permits contained extraction after that qualification, without changing
trust, expiry, signer identity or the clock. The host is Debian13, so actual
compatibility had to be measured independently of the Debian12 release label.
Contained extraction subsequently succeeded: 2,186 members, 39 contained links,
3,353,234,507 regular-file bytes, and 4,670,409,908 total retained tool bytes,
below the eight-GiB limit. Actual loader checks resolve the frontend, Clang and
SourceKit libraries. The Swift driver alone lacks `libncurses.so.6`, so its
version/empty compilation and package tests did not start.
Root extended the same contained envelope to the exact official Debian13/amd64
`libncurses6` package 6.5+20250216-2, SHA-256
`e00cbcc8c0826993f881f492c05f33ba8d79b5375dc5a2ab59c82e0c7b9179a9`.
The signed Debian release, package index and exact package hash subsequently
verified with the installed public Debian keyring. Guarded extraction supplied
the genuine library through a process-local loader path. Actual driver/frontend/
Clang/SourceKit loader checks resolved; Swift 6.2 reported its version, and a
small Foundation program compiled and ran. This proves the used subset on this
host, not blanket Debian13 or native Mac support. No system library was installed
or aliased. Publisher-hashed pinned Linux lint tools and contained supported
checks also continued independently. The official publisher
archive hashes match the repository's pins. SwiftFormat 0.61.1, SwiftLint 0.65.0,
oxlint 1.76.0, oxfmt 0.61.0 and TypeScript 5.9.3 all report the expected versions.
The new four-file SwiftFormat check initially found only wrapping/trailing-comma
formatting in the new Systems test, subsequently corrected within that file.
SwiftLint's actual lint execution failed loading `libsourcekitdInProc.so`;
its verified archive contains executables and licenses, not that library.
The [pinned upstream Linux guidance](https://github.com/realm/SwiftLint/blob/0.65.0/README.md#working-with-multiple-swift-versions)
requires an external SourceKit library, so version success
does not establish lint compatibility.
The first bundled-library invocation still failed because it supplied a library
file, while the pinned SourceKitten loader appends the filename to a directory.
The corrected invocation supplies only the toolchain's `usr/lib` directory.
It loaded SourceKit and identified eight argument-formatting violations only in
the two new tests. Their corrections subsequently passed both four-file
SwiftFormat and strict SwiftLint checks.

The first focused package compilation stopped at missing `sqlite3.h`; none of
the selected tests ran. Root then authorized official Debian13/amd64 development
files matching the installed SQLite runtime, `3.46.1-7+deb13u2`. The same current
signed Debian index authenticated `libsqlite3-dev`, SHA-256
`56e1945d52292b506c1f0bcb77543fea289ccee857c478dcddded40226e1594d`,
and matched `libsqlite3-0`, SHA-256
`0a459adaffd901109f7811ab65f58e7a957b4907d05539cf3d1184efdcde0468`.
The runtime package was actually needed to satisfy the development package's
genuine linker-library symlink inside the contained dependency tree. Both
packages were guarded-extracted there without maintainer scripts or system
installation. A compiled C probe loaded the owned genuine library and reported
matching header and runtime versions, `3.46.1`.

The next focused attempt compiled the core library, both new state files and
CLI, then failed compiling the new Refresh test. Direct mutating calls inside
Swift Testing macros produced immutable-capture errors. The test now evaluates
those calls before asserting their results; all six cases and behavioral
assertions remain. Renewed four-file SwiftFormat and strict SwiftLint both
passed. The corrected focused/regression union then compiled and passed:
32 tests in four suites, including all eleven new tests. The repository-required
`make test` route also passed: 74 discovered and selected selections in seven
first-pass groups, with zero failed groups, retries or timeouts. Its Swift
wrapper delegates to the authenticated compiler with contained SwiftPM
scratch/cache/config/security paths, one build job and the genuine owned SQLite
include and library paths. Synthetic file/session isolation and suppressed
Keychain access were enabled. Neither earlier failed build executed selected
tests. The existing package lockfile remained byte-identical through every
attempt. These Linux results do not establish native Mac behavior.

The required `make check` was attempted and exited 2 at the first locale check:
`plutil` is absent on this Linux host. The native portable/JavaScript subset was
then attempted with the known-unavailable SwiftLint step omitted. Parser hash,
provider manifests, bundled plugin JavaScript, synthetic packaging/release checks,
two Mimo tests, 95 sharding/cleanup tests (19 skipped), and CI-path checks passed.
The subset exited 2 during the existing Homebrew-tap wait fixture, before later
portable and JavaScript checks. This is partial evidence, not a passing full check.
The helper's preflight requires `jq`, absent on the host and on the fixture's
fixed `/usr/bin:/bin` path. The fixture's captured inner diagnostic was removed by
its own cleanup, so that source/path evidence is distinguished from its observed
exit status. Neither existing fixture nor platform dependency was changed.

The remaining supported checks were then run separately: repository size and
its fixtures, syntax of 54 shell files, documentation links, the LLMS index,
site locales/JavaScript syntax, oxfmt, oxlint and TypeScript all passed. The
renewed four-file SwiftFormat lint identified the new test's array-ending brace
style after its first correction; only that brace placement was then adjusted.
The final four-file SwiftFormat lint passed with zero files requiring formatting,
and the affected documentation-link check also passed.
The supported checks and Linux tests do not substitute for a passing full
`make check` or the native client finish.

Acquisition/check receipts remain in the task-owned tool directory's `evidence`
subdirectory. Temporary command scratch and the earlier check-only worktree
`.build` symlink were removed after terminal commands. The contained SwiftPM
build, public dependency cache, scoped SwiftPM config/security directories and
verification wrapper were removed after all child groups were known terminal.
Direct absence checks passed for every declared cleanup path. Retained verified
tools, archives and evidence measure 4689698541 bytes, below eight GiB.
Verified tools and public acquisition assets share that same budget. No shared
cleanup is inferred.
The implicit installer was not invoked for acquisition and no system library,
shared state, profile or unowned scratch was changed.
Source inspection confirms only the five bound paths changed, no new dependency
or transport call, and unchanged legacy parser/client files. Native macOS
compilation/rendering remains independently unverified.

The new Swift fixtures create no files, processes or network requests. Any future admitted
build uses contained workspace scratch with exact-path cleanup, evidence retained
outside that scratch, fresh host admission and one global serial process.
No shared `/tmp` cleanup is allowed. A local commit is a review checkpoint;
the platform-limited full check and native client finish remain separately
unverified.
<!-- codex-section:end id="worknote.netdata-systems-state#test.evidence.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#ctx.remaining.001" -->
## Remaining boundaries

The native client finish is still unmet. The app does not consume this new state.
Source tests do not establish menu rendering, accessibility, native macOS builds,
live metric correctness, protected route/configuration, or owner acceptance.
Opaque native pending input remains unresolved and cannot be cleared here.

`NETDATA-CLIENT-01` remains P2 at
`a7d5e612c86aa0fca23637380554773995776ded`: the old client captures time before
sequential requests. `NETDATA-DOC-01` remains P3 at
`c63696b41bfaa89c8e3004a9c09c932fa90e701f`. Both original files and dispositions
are unchanged. This new projection is no correction or acceptance of that client
freshness defect. Unknown historical runtime/host effects remain unwaived.
<!-- codex-section:end id="worknote.netdata-systems-state#ctx.remaining.001" -->
