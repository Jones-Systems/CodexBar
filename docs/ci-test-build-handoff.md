# Compiled macOS test handoff

Selected macOS CI runs compile once in `swift-build-macos`, then run the existing
`swift-test-macos (0, 2)` and `swift-test-macos (1, 2)` checks from that build.
All three selected checks and `lint-build-test` must pass. Draft deferral still
leaves qualification incomplete. No check or compiler coverage becomes advisory.

The producer runs the isolated `Scripts/test.sh --export-build <directory>` path:
normal SwiftPM build, test discovery, and a complete `.build` archive. Only this
job restores/saves the existing source/toolchain/profile-qualified build cache.
SwiftPM validates cached inputs normally. There is one cache writer per run.
Swift formatting and locale checks run on the producer. The macOS Xcode selection
uses `DEVELOPER_DIR` and does not change the runner's global selected Xcode.

Each worker downloads the producer's immutable artifact ID from the current run
and invokes `Scripts/test.sh --use-build <directory>`. Before Swift test execution,
it verifies the producer manifest hash passed through job outputs, the archive's
SHA256 and size, source commit, Package.swift/Package.resolved/profile-manifest
hashes, selected profile, workflow run/attempt/ref, toolchain, ARM64 architecture,
runner compatibility, and canonical checkout path. Discovery must exactly match the
producer's complete test-ID list. Invalid or missing handoff data fails; there is
no worker compilation fallback. Invocations without either handoff flag retain
the existing conservative build and Sparkle discovery recovery.
Use **rerun all jobs** after a failure: a worker-only rerun cannot accept the
producer's artifact from an earlier attempt.

Runner image revisions are retained as provenance. Different revisions require
matching native OS build and dyld shared-cache UUID, selected SDK/toolchain/helper
hashes, and the complete declared runtime dependency closure. The worker checks
native host context before extraction and recomputes closure in its owned staging
tree before installation or Swift test discovery. Unsupported/incomplete evidence
retains the original exact-image gate; a complete fingerprint mismatch fails even
on equal images. Known loader/toolchain overrides are rejected. Mode and native
collection durations are logged separately. See the [native compatibility contract](engineering-specs/compiled-test-native-compatibility.md)
for fixed APIs, contained roots, parser/collection limits and current proof gaps.
Implementation and portable fixtures do not establish native hosted success.

The complete build tree preserves SwiftPM descriptions and dependency state,
XCTest products, built CLI/probe/replay tools, resources, dynamic frameworks, and
internal symlinks. Absolute internal links are normalized to relative links in
the archive. This is a **same-path handoff**, not a generally relocatable XCTest
distribution. Requiring the same path preserves absolute SwiftPM and generated
resource-accessor paths, plus source-relative fixtures. A future toolchain or
runner layout mismatch requires a new successful producer; it must not be ignored.

Archive extraction accepts only contained `.build` regular files, directories,
and relative symlinks. It rejects traversal, duplicate paths, links outside the
build tree, hard-link headers, devices, privileged modes, and members below links.
Files are written into a new workspace staging directory; symlinks come last.
The verified tree is installed only when the worker's `.build` is absent.
Metadata is never evaluated as commands.

Transfer roots and extraction staging are unique workspace children. Transfer
roots use a visible `swift-test-build-` prefix because the artifact action excludes
hidden directory ancestors. Upload selects only the owned `manifest.json` and
`build.tar.gz`, with hidden files excluded; no workspace-wide glob is used. Archive
limits are 4 GiB compressed, 12 GiB expanded, 200,000 members, and 16 MiB manifest;
packaging/restoring checks available disk space with a 2 GiB residual reserve.
These are conservative admission limits, not measured runtime sizes. Producer
archive staging and worker downloads are removed by unconditional job cleanup.
Workers remove their owned restored build after test descendants drain; an
unproved drain or changed directory identity fails cleanup and preserves it for
runner teardown. A failed test retains its original exit status if cleanup also
fails. Uploaded build artifacts expire after one day. Producer `.build` remains
owned by the existing bounded GitHub cache and hosted runner lifecycle.

Normal/full profile controls and manual group/shard/cache controls are preserved.
Full-profile JavaScriptCore goldens, while plugin resources exist, run on shard 0
with the same `--skip-build` products before build cleanup. Their separate native
campaign evidence scope is preserved. The daily 05:00 America/New_York (EST/EDT)
normal nightly uses the same producer and shard route with separate concurrency;
scheduled triggering becomes effective on the default branch.

The build and shard summaries/logs distinguish test-build, discovery, archive
packaging/restore, and execution seconds. GitHub job-step timestamps supply
upload and download time separately. Sum the producer and both workers' actual
job durations for macOS runner-minutes; measure the producer-to-final-worker
critical path and queue intervals separately. A historical baseline at a different
revision is not a controlled same-source cache or speedup measurement.
