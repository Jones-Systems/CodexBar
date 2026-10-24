# Engineering Spec — Native compatibility across hosted image rollout

Status: implemented and activated after coordinator source review of exact local
checkpoint `5f6469e2cc6b314902b9b9b86495cd14e7dc484c`. Hosted host prechecks now
complete; full closure and both-shard qualification remain pending after the
universal-layout and launch-context resolver repairs described below. Diagnostic checkpoint `0862c61d9` first retained strict image equality.
The CI/harness lane owns this spec and the bounded helper/tests; root owns hosted
CI watching and integration. Complete native closure and two-shard success are not yet proved.

## Evidence and required boundary

Run `40120003093` proves the complete archive works on shard 1: the same 7,358 discovery
identities, 87 successful groups, no compilation, retry or timeout. Producer/shard 1
use image `20261013.0424.1`; shard 0 rejects image `20261021.0445.8`. Both actual job
logs report macOS 26.6.2 build `25G83` and the same Xcode 26.3/Swift 6.2.4 fingerprint.
The failed run is not full qualification or a valid runner-savings comparison.

The exact completed-run artifact `12571152240` was read with ZIP, manifest and
archive SHA256 verification, streaming its tar without extracting or executing
code. Task-owned download scratch was removed. Its 13 product Mach-O images
include XCTest, CLI/probes/replay, app/widget/watchdog and bundled Sparkle helpers.
Their only non-system install names are Sparkle.framework, Testing.framework and
libXCTestSwiftSupport.dylib, all with @rpath. Native header evidence is retained in
the task-owned `.evidence-compiled-tests-20261024/native-load-commands.json`.
The archive contains 23 loadable images in total, including dependency SDK tools
and the lint tool. The collector covers all of them, rather than selecting only
the product directory. An obsolete unused rpath on the lint tool is not probed;
a required dependency with an unsupported rpath makes the proof incomplete.

Run `40125346131` at `9b7a1ef81fbf333ba09118d149d86baf011e4c6f` completed native
host collection on producer and both workers, including the fixed dyld APIs.
Producer closure rejected an unsupported ARM64 fat layout. Independently verified
artifact `12573057357` contains 23 loadable images and five nonloadable Sparkle
dSYM images; every transferred loadable image passed the prior parser. The exact
external rejected file was not logged. This identifies an external dependency as
the failure source, without establishing its filename or subtype. Both workers
correctly rejected image rollout through the strict fallback; no tests ran.

Run `40128626857` at `c358e0ffc73c8bf9619200249d4e974e54fea86c` passes the
ARM64 universal parser and native host checks, but producer closure reports
`ambiguous-runtime-dependency` without candidates. Both workers reject strict
image fallback before tests. The exact artifact `12574008330` was verified and
streamed again: 23 loadable images and five dSYMs, with ordered per-file rpaths.
This evidence does not identify the conflicting external file. Source inspection
does establish that combining all executables' rpaths and applying test overrides
to ordinary tools creates artificial candidate conflicts. The repair replaces
that model; it does not declare the old ambiguity a proved real loader conflict.

Run `40135413579` at `a61c4c6c2c36e62f188d5ec0686a4c9887a37228` identifies a
plain xctest → XCTest → XCUIAutomation dependency outside the original roots.
Its redacted install-name SHA256
`b731e0a584599aaffe55a2567d1c3a7330227073f2e4bfa9ff32042e271017e0`
matches `/Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/CoreDevice`.
The coordinator reports producer, lint/Linux and one worker passed; the other
worker rejected strict image fallback. This is partial restored-build proof,
not two-shard qualification. Existing artifacts contain no external CoreDevice
headers, so further imports cannot be established from those archives. No
speculative sibling frameworks are admitted.

Run `40137926192` at `4a9391a4028c18152a8d807f010a7f034285b53e` proves
the early gate stops before compilation: host evidence completes in 10.972s,
tool closure fails in 11.976s, and no shard runs. Its CoreDevice ARM64e import
has install-name SHA256
`973e5c84a39179f721aa6c147de99567c903fbf222419dec01fe26107a17722e`,
matching exactly
`/Library/Developer/PrivateFrameworks/CoreDeviceUtilities.framework/Versions/A/CoreDeviceUtilities`.
Both source-defined Xcode override candidates were missing. This establishes
the second reviewed framework root, not its complete recursive runtime proof.
Lint/Linux checks passed; the required aggregate rejected producer failure and
skipped shards. No independent product/test failure was observed.

Run `40139096386` at `ae59e4509595390808c2052d81dfbaf8058bc127` stops
before compilation after complete host evidence (11.076s) and unsupported tool
closure (8.021s). The nontruncated batch binds one external ARM64e import to both
CoreDevice and CoreDeviceUtilities. Its install-name SHA256
`2d3223142fcf34aa7bb5f17da075c3d3a547856993f899e1f202ce04da702d86`
matches exactly
`/Library/Apple/System/Library/PrivateFrameworks/Mercury.framework/Versions/A/Mercury`.
Both selected-Xcode override candidates were absent. The proposed Developer/Mercury
path has a different hash and remains unapproved. The coordinator explicitly
approved the exact Apple/System Mercury framework root; no parent or sibling is
admitted. Lint and all three Linux jobs passed; the aggregate rejected producer
failure/skipped shards. Recursive Mercury runtime completeness remains unproved.

Run `40139845453` at `d2e395c15f7843cba9399f050297c0dfbc806c23` stops
before compilation with `runtime-symlink-escapes-root` for CoreDevice's ARM64e
import `/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice`.
Host evidence takes 7.948s; tool closure takes 8.336s. The selected-Xcode overrides
are absent and the declaration batch is empty/nontruncated. Existing diagnostics
omit the canonical destination and exact alias metadata. Neither an unverified
destination framework nor an alias is admitted; rejection and early gating remain.

Keep repository, source, run/attempt, workflow, profile/manifest, package/lock,
workspace, toolchain, runner OS/architecture and image OS exact. Image versions
remain recorded provenance. A different version can pass only with a complete,
equal native compatibility identity independently collected on producer/worker.
Incomplete evidence preserves the original full identity check, including image
version; it never triggers compilation. A detected complete fingerprint mismatch
fails even when image versions match.

## Native identity and runtime closure

Collect actual sw_vers product/build and arm64; canonical selected Xcode path and
version; selected macOS SDK path/version/build and SDKSettings SHA256; selected
Swift, SwiftPM, XCTest launcher, swiftpm-xctest-helper and swiftpm-testing-helper
bytes. Resolve tools through fixed xcrun calls and source-defined helper paths;
validate canonical paths inside the selected Xcode bundle.
For Swift Testing, reproduce UserToolchain's first executable match in the host
toolchain's usr/bin, then usr/libexec/swift/pm, rejecting canonical escapes.
Include SwiftPM's ManifestAPI runtime and installed configuration, because package
parsing can still occur with skip-build. Admit the actual Swift entrypoint only
when it is the selected tool or Apple's `/usr/bin/swift` shim; include its bytes
and dependencies too.
Do not derive commands or host roots from artifact metadata. Reject injected
DYLD or custom SDK/toolchain overrides for compatibility mode.

Apple's [private dyld header](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_priv.h)
declares `bool _dyld_get_shared_cache_uuid(uuid_t)` for the current process.
The [public dyld header](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld.h)
declares `bool _dyld_shared_cache_contains_path(const char *)`. The fixed ctypes
signatures use a 16-byte unsigned-byte output buffer, C booleans and a UTF-8 C
string. Resolve only these symbols from the already loaded process with
`CDLL(None)`; never load a metadata-selected library. Missing symbols, false UUID
result, zero UUID, or an unsupported architecture/platform make proof unavailable.
The membership API accounts for libraries removed from disk into the active
cache. Require matching actual OS build and cache UUID. System dependencies
must be members of that cache, or individually byte-hashed on disk under approved
system library roots. API absence or unknown data makes evidence incomplete.

Read bounded ARM64 Mach-O headers using Apple's
[load-command definitions](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h).
Audit every regular loadable file below the complete `.build`, including
framework/helper children and dependency tools, plus the selected native launchers. Follow declared
dependencies recursively. Bundled dependencies stay below .build and are also
covered by archive integrity; external dependencies must resolve inside the
selected Xcode, system-library roots or the four explicitly reviewed Apple
framework roots and receive SHA256 identities. The additional roots are
`/Library/Developer/PrivateFrameworks/CoreDevice.framework`,
`/Library/Developer/PrivateFrameworks/CoreDeviceUtilities.framework`,
`/Library/Apple/System/Library/PrivateFrameworks/Mercury.framework` and
`/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework`; require each
root itself canonical and each reached runtime file canonically contained. Include
only declared dependencies and their nested framework/dylib closure, with full
hashes and existing file/byte/time limits. Do not enumerate the framework or its
parent, admit sibling frameworks, follow symlink escapes, or accept host roots
from metadata. Missing or unsupported further dependencies stay incomplete. Preserve
weak-link absence as explicit evidence; unresolved strong, ambiguous, unsupported
or escaping dependencies make the proof incomplete. Inspect no provider state.

Run `40141076460` provides bounded actual MobileDevice alias metadata. Admit
exactly `/System/Library/PrivateFrameworks/MobileDevice.framework` with raw relative
link bytes `../../../Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework`
to the fixed canonical MobileDevice framework root above. Require a canonical
source parent, that exact source symlink and raw bytes, its exact normalized
target, a canonical nonescaping target root, and regular canonically contained
reached leaves before file reads/hashes/parsing. Contained version/nested links
retain normal containment checks. No equivalent absolute spelling, alternate
framework, parent, sibling or generic system-root escape is admitted. Bypass no
alias validation or full-file hash via system-cache membership. Recurse only
declared native dependencies under the same existing budgets. Keep static mapping
policy in host context and independently validated alias records in canonical
image entries; recompute on both hosts and require complete fingerprint equality.
Observed canonical-path SHA256 identifies the public path string, not binary
contents. This approved implementation still requires real hosted closure proof.

Handle bounded fat32/fat64 ARM64 slices, weak/reexport/upward/lazy library loads,
dylinker commands, loader/executable-relative paths and recursive cycles. Reject
unsupported width/byte order, malformed or unknown required commands, legacy
loader commands, and embedded loader environment commands.

Apple's [Loader.cpp](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/Loader.cpp)
resolves @rpath through the requestor and its actual ancestor chain, preserving
each image's load-command order. Its
[path overrides](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/DyldProcessConfig.cpp)
precede raw paths. Select the first supported existing candidate in that proven
order; never combine unrelated executable paths. Preserve every ARM64 variant's
ordered commands. Audit each transferred executable separately in plain and
inherited test environments. Audit xctest, XCTest discovery and Swift Testing
helpers only in the source-proved SwiftPM test environment, and audit each test
bundle under all three selected launchers. Ordinary tools retain plain launches.
Audit remaining loadable libraries without inventing parents. Every recursively
selected external image receives its canonical path, whole-file SHA256 and slice
identity; cache members remain bound to the native cache UUID. Record launch,
mode and ancestor subtype chain on dependency edges. A conflicting @rpath binding
within one launch is `runtime-binding-order-unproven`, with both candidate
identities, rather than an arbitrary choice. Unsupported required roots, absent
strong loads and unsupported loader shapes remain incomplete. Unvisited later
rpaths are neither probed nor used as roots.

Apple's [universal loader](https://github.com/apple-oss-distributions/dyld/blob/main/mach_o/Universal.cpp),
[architecture definitions](https://github.com/apple-oss-distributions/dyld/blob/main/mach_o/Architecture.cpp)
and [grading rules](https://github.com/apple-oss-distributions/dyld/blob/main/mach_o/GradedArchitectures.cpp)
allow distinct ARM64 variants and different launch/load preferences. Cover the
union of every supported generic, v8, old ARM64e and versioned user-space ARM64e
slice, preserving full subtype ABI bits and the whole-file SHA256. Never guess a
selected slice. Follow each variant's dependencies and rpaths in their own order.
A missing alternate-variant
strong dependency remains incomplete. Reject future/kernel ABI variants,
duplicate normalized architectures, mismatched table/header identities, overlaps,
invalid alignment/bounds, reserved fat64 data, and mixed payload classes. Apple's
fat32 legacy extra generic ARM64 descriptor receives the same bounds and overlap
checks; fat64 does not gain this interpretation. Known object, core, linker-stub,
dSYM and static-archive payloads are nonloadable. A foreign-only loadable image is
unsupported rather than silently excluded. Command budgets apply across all
ARM64 variants of one file.

[SwiftPM's test environment](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/Commands/Utilities/TestingSupport.swift)
uses its XCTest helper and adds overrides only for test subprocesses. Reproduce
the [platform paths](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2-RELEASE/Sources/PackageModel/SwiftSDKs/SwiftSDK.swift)
in order: Developer/Library/Frameworks, Developer/Library/PrivateFrameworks, and
Developer/usr/lib for libraries. Verify the platform path through fixed xcrun
output against the selected SDK. Preserve the optional toolchain testing path
before platform paths using UserToolchain's fixed derivation and extension test.
Match Apple's framework-leaf rule; a nested framework Libraries child uses library
overrides. The dylinker is not a library-path override. Do not assume XCTest is
provided only by the system or that a version string proves runtime-library bytes.
The [selected toolchain implementation](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/PackageModel/UserToolchain.swift)
also identifies compiler/library overrides. Nonempty DYLD variables, custom
Swift/SDK/toolchain/library overrides, or a different Swift entrypoint are rejected
requests, rather than incomplete evidence eligible for fallback. Reject nonempty
`SWIFTPM_PLATFORM_PATH_*` overrides too.

The hosted toolchain reports Apple Swift 6.2.4. Its
[test command](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/Commands/SwiftTestCommand.swift)
constructs the test environment in runTestProducts and passes it to TestRunner,
which chooses xctest or getSwiftTestingHelper before launching. XCTest discovery
also calls constructTestEnvironment. Therefore an additional plain launch of
these helpers is outside this harness's actual path. This corrects context
selection without omitting any selected helper, transferred image or dependency.

Cap collection at 90 seconds, 50,000 scanned entries, 512 images, 4,096 cached-path
queries, 4,096 launch/ancestor contexts, 32-image chains, 16,384 edges, 128 search
candidates per dependency, 4,096 commands and 1 MiB command bytes per image,
512 MiB per hashed file, and 2 GiB total hashed bytes. Native command subprocesses have at most 30 seconds
and consume the remaining collection budget. File hashes are cached by canonical
path, inode, size and timestamps, with a second metadata check after reading.
Read regular files only with canonical containment checks. No shell, dlopen of
metadata-selected paths, metadata execution, native product execution, signing,
host changes, provisioning, installation or full-system hash is part of collection.

## Activation and affected checks

`ENABLE_NATIVE_COMPATIBILITY=True` activates the reviewed contract. A v2 manifest
carries the complete fingerprint or a bounded unavailability reason. All resolver
failures, including file access and budget failures, carry closed diagnostics:
logical loader/install name, launch/mode, subtype chain, tried rpaths and candidate
canonical paths/kinds/hashes. Lists stop at 64 entries and strings at 512 escaped
characters, with explicit truncation. Build/Xcode roots use logical tokens;
outside-root paths are redacted to SHA256 markers. Unsupported Mach-O files also
retain size, header/table SHA256 and at most 33 bounded slice descriptors. These closed-schema diagnostics
are log/provenance data: they never select a file, command or compatibility rule.

On failure, optional `unapproved_declarations` batches absolute install-name
declarations outside approved roots from already parsed and whole-file-hashed
admitted images. Prioritize the current loader and reached developer frameworks,
then other admitted images. Each closed record binds logical loader/SHA256,
ARM64 subtype, redacted install name, weak flag and dylinker flag. Inspect at most
4,096 declarations, retain at most 64 records and stop at the existing shared time
budget, setting the diagnostic's truncation flag. The inventory performs no new
file read/hash/stat, directory enumeration, symlink resolution or cache query.
These declarations may still be satisfied by overrides; they neither prove a
missing runtime nor admit a target. Unread rejected subtrees remain unknown.
The actual resolver failure and early gate remain authoritative; the inventory
never creates a fingerprint or relaxes qualification.

An escaping path may carry optional closed `location` diagnostics: logical path,
matched root, already computed canonical path/root and metadata status. A bounded
source-prefix walk uses [lstat](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/lstat.2.html)
and [readlink](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/readlink.2.html)
to record at most the first symlink, its normalized target, raw target SHA256 and
relative flag. Hash the raw filesystem link bytes, capped below 4 KiB. Status is
one of `first-link`, `no-link`, `metadata-unavailable` or `budget`.
Inspect at most 32 exact source prefixes, within the shared time
budget; stop at the first link without querying its target or enumerating any
directory. Reuse existing canonical resolution; do not resolve another target,
open/hash/parse/execute escaped bytes, or stat the escaped destination. Redact and
cap all path fields by the same rules as other diagnostics. Metadata failure or
budget exhaustion preserves the original escape rejection; mark capped work as
truncated. This data cannot admit a root or alias and is excluded from fingerprints.
The sole MobileDevice mapping above uses actual source/destination metadata and
an explicitly reviewed source rule. Diagnostics admit no further alias exception;
generic symlink escape rejection stays intact.

A v1 manifest retains the exact original identity gate. Portable fixtures exercise malformed/fat Mach-O,
recursive dependencies, allowed paths, weak/missing dependencies, hash changes,
native context changes, cache UUID changes, override refusal and budgets. The
collector is unsupported on this Linux host; native APIs/SDK/loader behavior need
hosted evidence and cannot be claimed from mocks.

Activation must bind the compatibility payload to the independent manifest hash.
Verify base identity/integrity first, native context before restore, and complete
runtime closure in the safely extracted owned stage before Swift/discovery. A
worker recomputes its own paths/closure rather than executing manifest instructions.
Preserve producer/both-shards/aggregate required-check semantics and cleanup.
Emit host-precheck and closure durations separately, plus verified/rejected status
and `complete-fingerprint` versus `exact-image-fallback`. Complete fingerprint
inequality fails even on equal images. Incomplete evidence can pass only the
original full identity check. Identical image versions are provenance and the
legacy fallback boundary; they do not prove that every installed image tool matches.

Before producer compilation, run this same bounded collector over selected tools
and their external dependencies without scanning `.build` or executing any native
artifact. Emit `native-tool-preflight` host/closure timing, `host_status`,
`build_allowed` and actionable capped diagnostics. With complete host evidence,
an incomplete selected-tool closure fails before compilation. This explicitly
narrows producer fallback to avoid compiling while a known tool-only dependency
is unsupported. Unavailable host/API evidence retains the original exact-image
fallback; post-build and worker incomplete-evidence paths retain it too. Different
images still require complete proof. Preflight never substitutes for the full
product proof. Recollect a fresh host and full closure after compilation so the
native time budget cannot span the
build. Workers retain host admission before extraction and staged full closure
before installation/discovery. No extra campaign or workflow job is introduced.

The proof covers declared Mach-O dependencies and the known SwiftPM test/manifest
runtime, not arbitrary future dynamic loaders or general binary relocation. A new
runtime root or unsupported loader shape requires an updated contract. Actual
host prechecks took 15.742 seconds on the producer and 10.377/11.049 seconds on the
workers in run `40125346131`; the incomplete producer closure took 8.639 seconds.
Complete closure, supported external layouts, final collection overhead and
two-shard success remain hosted proof gaps. Fixture mocks cannot supply that evidence.

The separate schedule commit integrates exact nightly intent from
`0110a56430470106ad7ffed6c96707d3eb5cc636` after the product patch 01 transfer
receipt: daily 05:00 America/New_York (EST/EDT), separate nightly concurrency,
normal scheduled profile and retained normal/full manual choice. Frozen product
handoff patches and owner worktrees remain untouched.
