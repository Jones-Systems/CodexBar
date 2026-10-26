# Engineering Spec — Cold builds and expanded app size

<!-- codex-section:begin id="spec.cold-build-size#ctx.artifact-header.001" -->
Artifact Type: `engineering-spec`

Artifact ID: `spec.cold-build-size`

Purpose: Define one reproducible, advisory build-only comparison and a complete non-distributable assembly.

Governing artifact: supplied cold-build/app-size protocol

Specification owner: measurement implementation lane

Integration owner: CodexBar root coordinator

Consumers: source reviewer, hosted measurement operator and results reviewer

Authority effect: none
<!-- codex-section:end id="spec.cold-build-size#ctx.artifact-header.001" -->

<!-- codex-section:begin id="spec.cold-build-size#req.scope.001" -->
## Source and dispatch boundary

The single supported pair is pre-product `91bd5fb4af704da9181212bea636d527a058e615` followed by product
`ba523f60b7161e70a3afd201f87d49dd2b0e37fe`. The former already includes five right-sized test files;
substituting `951c99a` would add that earlier change to test-compilation attribution. No third build is needed.

The existing default-branch workflow path `.github/workflows/jones-menu-candidate.yml` gains a manual
`mode=cold-build-size`. `candidate` remains the default and retains every existing candidate step and PR
condition. Required CI, compile-once producer/two-shard handoff, aggregate, native compatibility fingerprint,
schedules, signing/bootstrap and installed apps are untouched. This observation is advisory.

GitHub requires the workflow path on the default branch and a branch/tag dispatch ref. A future operator
selects the reviewed task branch, sets `baseline_sha`/`candidate_sha` to the pair above, and supplies the full
reviewed harness commit as **both** `harness_sha` and `expected_sha`. Before compilation the driver requires
both values, checkout HEAD, `GITHUB_SHA`, and `GITHUB_WORKFLOW_SHA` to agree; the native workflow ref and
dispatch event/repository must also agree. No `GITHUB_*` provenance is fabricated. Rerun attempts are refused;
another observation requires a fresh, separately selected dispatch. Source implementation/publication does
not authorize this dispatch. Root reviews the concrete source first.

One `macos-26` ARM64 slot has a 180-minute cap. There is no matrix, cache restore/save, binary artifact import,
test discovery/execution, shard, replay, full-suite campaign or automatic retry in the measurement. Portable
contract fixtures run first. Ordinary source-PR CI is additional: unknown/global harness paths conservatively
select nine required jobs, including three macOS jobs with 80-minute caps. With a later observation this is
up to ten jobs and 420 nominal macOS runner-minutes of configured caps, not predicted runtime or billing.
The original source-only capsule dispatched or observed no workflow. Root later reviewed and dispatched the
single observation recorded below; a separate bounded observer capsule collected its terminal evidence.
<!-- codex-section:end id="spec.cold-build-size#req.scope.001" -->

<!-- codex-section:begin id="spec.cold-build-size#iface.phases.001" -->
## Fixed phases and cold-state definition

`Scripts/ci_cold_build_size.py` clones full local Git history without hardlinks or compiled output into new,
equal-length `sample-a` and `sample-b` roots. Each source must be clean, exact, and free of local dependency
overrides. The common harness remains a separate commit. Native GitHub variables retain that harness identity.

Select the existing `/Applications/Xcode_26.3.app/Contents/Developer`; fail without installation or fallback
unless Xcode 26.3 build 17C529 and the Swift/SwiftPM 6.2.4 version fingerprint
`ba0d494e3bd99ca718c3b866478aecef3929bd982e54bdcc30bc90259845ac4f` match. Record OS/image, CPU,
architecture, SDK path/version/build and tool bytes. Recheck the same complete observation for every phase.
This version fingerprint is a measurement binding; it does not substitute for the existing native handoff proof.

Each source has two independently absent `.build` roots in sequence. Assert absence, then allocate owned
cache/config/security, fixture/TMPDIR, module caches and Xcode state beneath it. The fixture parent is borrowed
by the historical `Scripts/test.sh`; the driver owns final removal. Explicit SwiftPM paths and Xcode
DerivedData/package paths isolate project/dependency state. The login HOME is not reassigned. OS/SDK page
caches and shipped system modules remain uncontrolled; baseline-first order and network/load noise remain.

Phase A uses `Scripts/test.sh --command swift build --build-tests --configuration debug --arch arm64 --jobs 2`
with explicit fresh cache/config/security paths and the normal profile. It compiles test products without
listing or running tests. The existing fixture, file/Keychain isolation and process-drain lifecycle remain.
Drain and remove the complete phase root, verify absence, then begin release with fresh state.

Phase B records separate commands/timers for locked dependency preparation, the default-product release
SwiftPM build, Release widget, and assembly. Preparation preserves the exact historical safe-bundle patch,
force-resolved versions, pinned KeyboardShortcuts revision, patched Utilities.swift hash and unchanged
Package.resolved. Release uses `swift build --configuration release --arch arm64 --jobs 2`, with no product
graph narrowing. The tracked widget project/scheme retains production Release flags, `CODE_SIGNING_ALLOWED=NO`,
unique DerivedData, private package caches and explicit `-jobs 2`. Hosted wrappers pass commands through;
`CODEXBAR_BUILD_JOBS` alone would not constrain them.

Every command records argv, an outer monotonic wall in nanoseconds (including wrapper, resolution/download,
planning and descendant drain), Swift's internal `Build complete!` seconds separately, exit status and drain
proof. These are different clocks/scopes. There is no confidence interval, statistical speedup, general build
latency claim, installed-app behavior or Linux size result from one pair.
<!-- codex-section:end id="spec.cold-build-size#iface.phases.001" -->

<!-- codex-section:begin id="spec.cold-build-size#iface.assembly.001" -->
## Complete measurement assembly and historical adapter

`Scripts/cold_build_size_adapter.py` accepts only two exact historical `package_app.sh` SHA256 values:

| Source | Historical packager SHA256 |
| --- | --- |
| pre-product | `2969c6c6d3fc3e039a5f107e7eac4c91951911ed757510caf607daa8690d09f9` |
| product | `2936801eea2a84a46b661d2d0f4e0efb1e234f17d34a959a7e4abab86233df20` |

It renders reviewed non-signing blocks, recording line ranges, original/rendered hashes and every substitution.
It is a **new common adapter**, not a flag supported by historical source. It never edits historical tracked
bytes or invokes the ordinary packager. Ordinary `adhoc|identity` behavior remains byte-for-byte unchanged;
PR26's identity/signing/bootstrap/widget semantics are not imported or modified.

Selections cover locked KeyboardShortcuts preparation; identity; product path/staging functions; complete
app layout, entitlements and Info.plist; binary install/strip functions; product installation; Sparkle/rpath;
**all** resource/attribute work; and widget Jones metadata. The latter two blocks originally followed the
first package signing operation, so stopping the old script before signing would be incomplete.

Adaptations are limited to explicit fresh resolve paths/two jobs, a generated Jones identity overlay in owned
scratch, a prevalidated SwiftPM bin path, a separately built widget copy, and scratch icon conversion. The
historical metadata tool composes its normal Jones channel-none fields from the exact clean source using
`origin=local` and empty build-run. It does **not** claim ci-main/ci-pr candidate provenance. Separate receipt
fields bind the actual GitHub measurement run and common harness. The adapter preserves local trial identity
and first-parent build-number composition.

The stage includes stripped app/CLI/watchdog/widget (`strip -x`), Sparkle including nested components, rpath,
icons and every app/SwiftPM resource, KeyboardShortcuts, and both Core copies where the old source requires
them. Stale candidate Core output is excluded by its source contract. No provisioning profile, codesign,
signature stub/removal, linker-signing override, signature-dependent package proof, launch/resource smoke,
updater fixture, notarization, install, release, or final installed-app replacement runs. The result is a
**non-distributable unsigned assembly with no new package signature**. Vendored and linker outputs can carry
existing signatures. Thin/universal Mach-O load-command/CodeDirectory/CMS-slot observations record their
presence/flags without verifying trust or claiming all components are signature-free.
<!-- codex-section:end id="spec.cold-build-size#iface.assembly.001" -->

<!-- codex-section:begin id="spec.cold-build-size#iface.adapter-map.001" -->
## Source review map

This source checkpoint has driver SHA256
`4a39afcf65a4a4b896636b383b753272be014b98d50cf08388f3a3d62761a5fb` and adapter SHA256
`75089b0f3a08384fbadf8f783715112767fa8e2359aabf7e833043279746f4c0`.
Each receipt independently records actual harness commit, helper hashes, block hashes and rendered
script hashes. These are new common harness bytes applied to two historical sources, not historical behavior.
The selected blocks below are at the exact packager revisions/hashes above; line ends are inclusive.

| Selected historical block | Pre-product lines | Product lines |
| --- | --- | --- |
| locked KeyboardShortcuts preparation | 180–285 | 180–285 |
| identity and provenance functions | 12–101 | 12–101 |
| product path/staging functions | 289–335 | 289–335 |
| layout, entitlements and app metadata | 341–466 | 341–466 |
| binary install/strip functions | 468–534 | 468–534 |
| product installation | 609–619 | 609–619 |
| framework and rpath | 622–626 | 622–626 |
| all resources and attributes | 647–694 | 647–709 |
| widget metadata | 706–718 | 721–733 |

Only the resource block's original bytes differ between the pair. The adapter's explicit substitutions
describe fresh resolve/cache paths, scratch overlay/icon paths and prebuilt widget installation. Its literal
glue selects release/arm64, supplies already-verified metadata/bin paths and validates Sparkle layout. It does
not execute the omitted signing or final launch blocks. Both complete synthetic layout fixtures execute the
rendered adapter and check the normal source/packager bytes remain intact.
<!-- codex-section:end id="spec.cold-build-size#iface.adapter-map.001" -->

<!-- codex-section:begin id="spec.cold-build-size#iface.evidence.001" -->
## Size, storage, evidence and cleanup

Reuse only the existing pure `tree_manifest` containment semantics: relative contained links, no traversal,
regular files, modes, bytes and SHA256. Existing ad-hoc `inspect_bundle`/artifact admission remains unchanged.
Report raw release app/CLI/watchdog bytes/hashes separately from stripped staged app/CLI/watchdog/widget.
Expanded `.app` size is the sum of logical regular-file bytes, with no followed links; link count/payload
bytes are separate. Component totals cover frameworks, widget, resources, helpers and main executable.
Standalone CLI binary bytes and the old required adjacent Core resource payload are distinct metrics.
Build trees, dSYMs and compressed transfer archives are excluded from app size.

One owned `.cold-build-size-*` root under the workspace contains clones and all disposable outputs. Before
cloning and each phase, require available storage >= 30 GiB residual reserve + 25 GiB estimated additional
peak on that filesystem. This conservative estimate includes clones, release/strip staging, widget outputs
and logs, without binary transfer archives; it is not a measured allocation bound or reservation.

Evidence is a new `cold-build-size-evidence/` directory outside disposable scratch: only JSON and text log
tails, at most 32 MiB total, seven-day retention. Individual tails are at most 2 MiB with original byte count,
full-log hash and truncation flag. Inputs bind revisions, profile/Package/lock/project/helper hashes, native
environment, command/timing records, selected adapter block hashes, inventories and cleanup. No binary or
GB build archive is uploaded. Unexpected preexisting evidence/state is refused, never swept.

The existing birth/session-aware process owner drains each command; nested widget active markers and
explicit historical drain failures also fail qualification. Remove each exact owned phase/root only with
its captured device/inode identity, canonical path and proved drain; verify absence. A failed nested identity
check also forbids parent deletion. Success, failure and handled HUP/INT/TERM share cleanup. Cleanup failure
cannot turn the primary command failure into success. Unknown drain/identity preserves outputs, fails the
observation and records the hosted-runner teardown limitation. SIGKILL/VM loss cannot execute a cleanup handler;
runner teardown is the final backstop, not ordinary cleanup proof.
<!-- codex-section:end id="spec.cold-build-size#iface.evidence.001" -->

<!-- codex-section:begin id="spec.cold-build-size#ac.proof.001" -->
## Acceptance and review points

Contained portable fixtures exercise dispatch drift/refusal, fixed commands/job limits, unchanged normal
candidate/packager bytes, complete baseline/candidate assembly including post-signing resources/metadata,
stale Core exclusion, stripping/rpath calls, inventory containment/link accounting, raw/staged sizes, thin/fat
signature observations, cold absence/independence, exact cleanup, failure/timing/log budget and handled cancellation.
Native tool doubles do not establish Mac assembly or compiler compatibility. Existing package/signing/identity
fixtures remain separate checks. Run `make test` and `make check` when admitted; report absent tools honestly.

Root's concrete source review must assess the block/substitution mapping, the complete resource/widget layout,
local-vs-GitHub metadata separation, cold-state/cache coverage, byte definitions and cancellation/cleanup/evidence
behavior before selecting any hosted experiment. Those were pre-run acceptance gates; the separately reviewed
run below supplies actual compilation, widget/cache, dispatch, size/timing, signature-metadata and successful
macOS cleanup evidence for its exact inputs. A green ordinary source PR alone does not prove measurement
success. Local Swift/plutil remain unavailable, and this successful run does not exercise full-build
failure/cancellation or establish installed-app behavior or signature validity.
<!-- codex-section:end id="spec.cold-build-size#ac.proof.001" -->

<!-- codex-section:begin id="spec.cold-build-size#ctx.observation.001" -->
## Accepted observation

[Run 40199152659](https://github.com/Jones-Systems/CodexBar/actions/runs/40199152659), workflow `393256428`,
attempt 1, succeeded with reviewed harness `16ae87423ca9017ef9f42d8a46a18ae6fff2f86a` and the fixed pair
`91bd5fb4af704da9181212bea636d527a058e615` → `ba523f60b7161e70a3afd201f87d49dd2b0e37fe`.
One active Mac job took 37m23s. It observed expanded regular-file app bytes 92034241 → 55578768
(87.771 → 53.004 MiB, −39.61%), with nine links / 213 link-payload bytes separately on both sides.
Debug outer seconds were 620.658944250 → 498.384087458; Swift internal seconds were 614.98 → 494.27.
Five sequential commands per source totaled 1272.462223042 → 916.722154417 seconds (−27.96%).
These are observed elapsed values from one baseline-first pair, confounded by network, load, order and
OS/SDK page caches. They establish no general causal speedup or billed-runner saving.

All four phase observations matched the required toolchain fingerprint and actual image
`macos26 / 20261013.0424.1`, macOS 26.6.2 build 25G83, SDK 26.2 build 25C58, arm64 Apple M1 (Virtual).
Four fresh-state absence checks, ten successful command/drain receipts, four phase cleanup absences and
final root absence passed. Both Package.resolved files stayed unchanged; locked preparation/patch hashes
matched. Complete inventories and all retained log hashes verified. No new package signing or app/provider
launch occurred; vendor/linker signature metadata was retained without trust verification.

The [measurement Work Note](../work-notes/cold-build-size-measurement.md#qualified-hosted-observation)
records every phase, raw/stripped product and component totals, and remaining proof limits. Frozen local
evidence lives at `.evidence-cold-build-size-20261025/observation-run40199152659/`; its verified 31-file
manifest SHA256 is `09628fef308a5acd4a58cab7d7b02bd224f0d06695baf0bf2786abe69f10a8d4`.
Later source integration does not change the historical pair, helper hashes or the accepted run's identity.
No additional measurement is authorized by this documentation closure.
<!-- codex-section:end id="spec.cold-build-size#ctx.observation.001" -->
