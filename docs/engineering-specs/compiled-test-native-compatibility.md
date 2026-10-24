# Engineering Spec — Native compatibility across hosted image rollout

Status: implemented locally, inactive pending coordinator review. PR #40 remote
remains `19749e9e59c41d5a345cfcd8256add571755dbff`. Local diagnostic checkpoint
`0862c61d9` retains strict image equality. The CI/harness lane owns this spec and
the bounded helper/tests; root owns activation review, CI watching and integration.

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
Swift, SwiftPM, XCTest launcher and swiftpm-xctest-helper bytes. Resolve these
through fixed xcrun calls and validate paths inside the selected Xcode bundle.
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
selected Xcode or system-library roots and receive SHA256 identities. Preserve
weak-link absence as explicit evidence; unresolved strong, ambiguous, unsupported
or escaping dependencies make the proof incomplete. Inspect no provider state.
Handle bounded fat32/fat64 ARM64 slices, weak/reexport/upward/lazy library loads,
dylinker commands, loader/executable-relative paths and recursive cycles. Reject
unsupported width/byte order, malformed or unknown required commands, legacy
loader commands, and embedded loader environment commands. Resolve a conservative
union of permitted rpaths to a fixed point: multiple candidates with different
fingerprints are unsupported. This deliberately sacrifices availability rather
than guessing which library wins.

[SwiftPM's test environment](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2-RELEASE/Sources/Commands/Utilities/TestingSupport.swift)
adds selected macOS platform library/framework paths and uses its XCTest helper.
Account for those paths and load-command rpaths. Do not assume XCTest is provided
only by the system or that a version string proves runtime-library bytes.
The [selected toolchain implementation](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2-RELEASE/Sources/PackageModel/UserToolchain.swift)
also identifies compiler/library overrides. Nonempty DYLD variables, custom
Swift/SDK/toolchain/library overrides, or a different Swift entrypoint are rejected
requests, rather than incomplete evidence eligible for fallback.

Cap collection at 90 seconds, 50,000 scanned entries, 512 images, 4,096 cached-path
queries, 4,096 commands and 1 MiB command bytes per image, 512 MiB per hashed file,
and 2 GiB total hashed bytes. Native command subprocesses have at most 30 seconds
and consume the remaining collection budget. File hashes are cached by canonical
path, inode, size and timestamps, with a second metadata check after reading.
Read regular files only with canonical containment checks. No shell, dlopen of
metadata-selected paths, metadata execution, native product execution, signing,
host changes, provisioning, installation or full-system hash is part of collection.

## Activation and affected checks

`ENABLE_NATIVE_COMPATIBILITY=False` keeps live workflow/artifact equality unchanged
until root reviews the exact contract and its limits. A v2 manifest carries the
complete fingerprint or a bounded unavailability reason. A v1 manifest retains
the exact original identity gate. Before activation, exercise malformed/fat Mach-O,
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

The proof covers declared Mach-O dependencies and the known SwiftPM test/manifest
runtime, not arbitrary future dynamic loaders or general binary relocation. A new
runtime root or unsupported loader shape requires an updated contract. Native API
availability, actual Xcode layouts, collection cost and both hosted shards remain
unverified locally; fixture mocks cannot supply that evidence.

Separately integrate exact nightly `0110a56430470106ad7ffed6c96707d3eb5cc636` after
the product patch 01 transfer receipt: daily 05:00 America/New_York, separate
nightly concurrency, normal scheduled profile and retained normal/full manual
choice. Do not mutate the frozen product handoff patches or owner worktrees.
