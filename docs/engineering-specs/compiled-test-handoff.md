# Engineering Spec — Compiled macOS test handoff

<!-- codex-section:begin id="spec.compiled-test-handoff#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.compiled-test-handoff`

Purpose: Compile the selected macOS test products once and run both existing shards from that exact build.

Governing artifact: none

Specification owner: CI/harness implementation lane

Integration owner: CodexBar coordinator

Consumers: macOS producer, isolated test shards, aggregate CI gate

Authority effect: none
<!-- codex-section:end id="spec.compiled-test-handoff#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.compiled-test-handoff#req.behavior.001" -->
## Requirements

One path-gated hosted macOS producer runs the existing isolated build and discovery. Both ordinary shards retain
their names, groups, selection, assertions, retries, process containment, and fixture cleanup, and use only
`swift test ... --skip-build`. Default local/test invocations still build conservatively. Explicit handoff
failures never compile on a worker. The selected producer, both shards, and aggregate must succeed.

Preserve normal/full profile controls and the separately owned normal-profile nightly intent. Do not modify
product sources, package membership, signing, installed apps, hosts, or provider access.
<!-- codex-section:end id="spec.compiled-test-handoff#req.behavior.001" -->

<!-- codex-section:begin id="spec.compiled-test-handoff#dec.runtime.001" -->
## Runtime evidence and decision

The current Package.swift builds app-linked macOS tests, portable tests, CLI/crash-probe/replay dependencies,
and resource bundles. The runner's `repair_sparkle_test_runtime` proves that an XCTest bundle alone is
insufficient: Sparkle also needs its framework and `PackageFrameworks` link.

[SwiftPM's release source](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2-RELEASE/Sources/Commands/SwiftTestCommand.swift)
passes skip-building through build parameters and locates built test products through its build system.
[TestingSupport](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2-RELEASE/Sources/Commands/Utilities/TestingSupport.swift)
also invokes the selected toolchain's XCTest helper. Preserve the complete `.build` tree, including dependency
state/checkouts, descriptions, tools, resources, and frameworks, as the conservative first handoff. Do not
claim a standalone or relocatable XCTest package. Require the same canonical workspace path and toolchain
on all jobs; this also preserves source-relative fixtures and absolute resource-accessor paths.

Use an immutable same-run GitHub artifact, selected by producer artifact ID. The manifest binds source commit,
package/lock/profile manifest hashes, selected profile, workflow run and attempt, runner image/architecture,
toolchain, workspace, full discovered test IDs, payload size, and SHA256. Pass the manifest SHA256 independently
through job outputs. Verify it and the archive before extraction or invoking Swift.
[GitHub documents](https://docs.github.com/en/actions/tutorials/store-and-share-data) artifact digest validation;
the [pinned downloader](https://github.com/actions/download-artifact/blob/9000827ccba6bdab643e8b6fd33ac0654aef8333/action.yml)
also supports explicit `digest-mismatch: error`. The repository verifies manifest, payload, and build identity independently.
<!-- codex-section:end id="spec.compiled-test-handoff#dec.runtime.001" -->

<!-- codex-section:begin id="spec.compiled-test-handoff#iface.archive.001" -->
## Archive and lifecycle boundary

Use a bounded compressed tar plus JSON manifest. Accept only regular files, directories, and contained relative
symlinks below `.build`; reject absolute/traversal/duplicate paths, hard links, devices, escaping links, and
members below symlinks. Extract regular content manually into a new owned workspace directory, add symlinks
last, then install only when `.build` is absent. Do not evaluate metadata or execute archive-provided commands.
Validate discovered test IDs exactly before partitioning. Never restore a cross-run or old-attempt artifact.

Only the producer uses the existing toolchain/profile/package-qualified `.build` cache; SwiftPM validates
that cache with its normal build. Workers restore no build cache. Transfer/archive staging lives beneath
the workspace, has explicit byte/entry bounds and storage admission, and is cleaned on success, failure,
and handled cancellation. Uploaded build artifacts expire after one day. Runner teardown is the final
backstop for host loss. Preserve existing cache ownership and fixture/evidence cleanup.
<!-- codex-section:end id="spec.compiled-test-handoff#iface.archive.001" -->

<!-- codex-section:begin id="spec.compiled-test-handoff#ac.proof.001" -->
## Acceptance and affected checks

Exercise same-run identity and byte-integrity rejection, safe extraction, complete runtime preservation,
cleanup, consumer build prohibition, default build fallback, and producer/shard aggregate result combinations
with synthetic Python/shell fixtures. Run the existing sharding, evidence, isolated-command, and path-gate
checks; run `make test` and `make check` when admitted and report absent tools honestly.

Hosted proof must show one test compilation followed by two successful skip-build shards with identical
discovery and complete partition coverage. Record producer build/package/upload, worker download/restore/run,
all three macOS runner durations, and critical path, including queues separately. Compare against the supplied
normal historical baseline: 49.6333 macOS runner-minutes excluding queues, 26m27s longest job, 26.5767 minutes
of duplicate test compilation. This is a historical comparison, not a controlled same-source benchmark.
The 390-second per-job goal remains unchanged; report measured exceptions.
<!-- codex-section:end id="spec.compiled-test-handoff#ac.proof.001" -->
