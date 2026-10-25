# Work Note — Hosted runtime compatibility

The CI/harness lane owns this source change in
`work/mac-build-once-test-shards-20261024`, based on local diagnostic checkpoint
`0862c61d967dfaab2d995567d6a0b1ab572d038b`. The coordinator reviewed exact inactive
checkpoint `5f6469e2cc6b314902b9b9b86495cd14e7dc484c` and approved activation and
normal publication to PR #40. The native compatibility flag is now true. Native
behavior remains hosted-unverified. No independent campaign, local Mac execution,
installation, signing or provider access occurred.

## Intent and affected checks

The successful producer and shard 1 on run `40120003093` share one image revision;
shard 0 rejects a newer image before restore. Equal OS/build and version strings
alone are insufficient. The [engineering spec](../engineering-specs/compiled-test-native-compatibility.md)
records primary Apple/SwiftPM sources, actual artifact header evidence, the native
context, complete declared dependency closure, permitted roots and caps.

Retain all source/run/attempt/profile/manifest/package/lock/workflow/workspace/
toolchain/architecture/image-OS checks and independent artifact integrity. Permit
different image revisions only after equal native host identity and equal staged
runtime closure, before installing the tree or running Swift test discovery.
Missing or unsupported evidence retains the full original exact-image check.
Known loader/toolchain injection is a rejected request. Complete mismatches fail
even on matching images. There is no compile fallback or image-pair allowlist.

Affected checks are the portable artifact/native/evidence fixtures, isolated
command fixtures, documentation links and the required make entrypoints. The
coordinator retains hosted producer/shard/aggregate watching and qualification.
Native API signatures, malformed/fat Mach-O, all transferred images, cycles,
weak/reexport/dylinker commands, escaping/ambiguous/unresolved paths, byte/context
changes, caps and both fallback outcomes have meaningful contained fixtures.

## Local result and limits

Fresh admission was below 85% CPU (14.24% for the fixture run); the portfolio lock
was acquired nonblockingly. One serial process passed 115 artifact/native/evidence/
isolated-command tests in 13.098 seconds. The wrapper removed its owned fixture
parent and verified absence. Documentation validation passed 300 local links;
`git diff --check` passed. Required `make test` and `make check` were attempted and
both exit 2: Swift and plutil are absent respectively. No tools were installed.

Linux fixtures do not prove native APIs, Xcode layout, resolver completeness for
the actual installed test environment, collection overhead or two-shard success.
The previous hosted run is partial proof only. No savings or full qualification
claim follows from it. Native host/closure durations and verified/rejected modes
are emitted separately for the next coordinator-authorized hosted candidate.

Transferred product cleanup paths and durable patch bytes remain untouched by
this checkpoint. The separately recorded normal-profile nightly schedule uses
exact source `0110a56430470106ad7ffed6c96707d3eb5cc636`.

After source review approved activation, the combined activation/schedule
candidate passed 116 portable tests in 13.061 seconds, existing path-gate and
aggregate fixtures, and 302 local documentation links. The first combined run
identified an outdated exact concurrency assertion, which was updated to retain
manual uniqueness and require the separate nightly branch. Final scratch cleanup
was proved. Native availability, full closure and collection cost remained pending
the coordinator's hosted run observation.

## Resolver repair intent before mutation

Resume at exact `c358e0ffc73c8bf9619200249d4e974e54fea86c`. Completed run
`40128626857` compiled/exported successfully but native closure was unavailable
with `ambiguous-runtime-dependency` and no diagnostic. Both workers correctly
rejected strict-image fallback before tests. Linux/lint, including musl, passed.
The previous FAT-layout error is gone; the exact ambiguous candidates remain
unknown and must not be presented as a proven real loader ambiguity.

Artifact `12574008330` was independently ZIP/manifest/archive-hash verified and
streamed without extraction or execution. Its 23 loadable images have the same
three non-system install-name shapes (Sparkle, Testing, XCTestSwiftSupport), and
distinct per-file rpaths; five other header candidates are nonloadable dSYMs.
Task-owned archive scratch was removed. Exact headers and hashes are retained
in `.evidence-compiled-tests-20261024/fat-layout-run40128626857.json`.

Apple's [Loader.cpp](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/Loader.cpp)
walks each requestor's ancestor rpath stack in load-command order, and
[DyldProcessConfig.cpp](https://github.com/apple-oss-distributions/dyld/blob/main/dyld/DyldProcessConfig.cpp)
tries environment overrides before raw paths. SwiftPM's existing cited
TestingSupport constructs that environment for test subprocesses, not every
ordinary Swift/Xcode tool. The failing preimage's global rpath set and indiscriminate
override union are therefore overly broad. Preserve every ARM64 variant's order
and audit bounded launch/ancestor contexts, exact selected library bytes and
all transferred loadable images. Conflicting loaded install-name bindings,
unresolved paths, unsupported contexts and budget failures stay incomplete.

Add closed, capped resolver diagnostics with logical loader/install-name,
resolved rpath contexts and canonical candidate paths/kinds/hashes. Redact
outside-root/private paths; never use diagnostic metadata to select host files
or commands. Run the same collector over selected tools and their dependencies
before compilation, logging early unsupported evidence while preserving strict
same-image fallback. Recompute full product closure after build and in staging.

Affected proof includes per-executable isolation, ordered rpaths, test-only
overrides versus system cache, inherited chains, conflicting bindings, alternate
ARM64 variants, cycles, every resolver failure diagnostic/redaction/cap,
preflight-before-compilation order, retained fallback, and existing artifact/
evidence/isolation/aggregate contracts. Root owns native watching; no manual
campaign, new agents, Mac execution, SDK change or host mutation is authorized.

## Resolver implementation and evidence

The repair removes the global search-root union. Each executable and ARM64 slice
keeps its ordered rpaths; recursive dependencies receive only their requestor and
ancestor contexts. Test overrides follow the selected SwiftPM platform order and
optional testing path, separately from ordinary tools. The XCTest bundle is
audited under both selected launchers; transferred helpers are audited with plain
and inherited test environments. Every other loadable image retains an audit
without guessed parents. Whole-file hashes, canonical containment, cache UUID,
all original artifact identities and strict fallback remain unchanged. A
cross-chain @rpath binding conflict retains both candidate identities and rpaths
and stays incomplete instead of guessing loaded-name precedence.

All resolver failures carry bounded closed diagnostics, including missing files,
unsupported roots, symlink escapes and budgets. Logical build/Xcode tokens and
outside-root SHA256 markers avoid private absolute paths. Original Mach-O file
header/slice diagnostics remain nested data. New caps bound context/chain/edge
growth and search candidates. No diagnostic value chooses a host path or command.

The producer runs the same tool-only collector before compilation and logs host
and external-closure duration separately. Unsupported evidence appears early;
the established exact-image fallback still governs qualification. A fresh full
host/product collection remains mandatory after compilation, and workers still
verify before extraction and recompute in staging before any Swift discovery.
This adds no job, dispatch, retry, image allowlist or worker build fallback.

First focused checkpoint: 56 artifact/native checks pass in 1.061 seconds under
fresh 17.35% CPU admission and the nonblocking portfolio lock. Scratch was removed
and absence verified. Further affected-union and unchanged before/after results
are recorded below when complete. This is Linux parser/contract evidence only;
native completeness and overhead still need the root-owned hosted observation.

Final affected union: 140 artifact/native/evidence/isolated-command checks pass
in 13.395 seconds, plus existing path-gate/aggregate fixtures and 302 local
documentation links. The native tests are imported once through the artifact
entrypoint. Fresh admission was 24.21% CPU, 48.70 GiB available RAM; one used core
is 6.25% of host capacity. One serial process acquired the nonblocking portfolio
lock, and the wrapper verified exact fixture-parent cleanup. Required `make test`
and `make check` were attempted separately under fresh admission/lock; both exit
2 because Swift and plutil are absent. No tooling was installed.

An unchanged contained reproduction in
`.evidence-compiled-tests-20261024/resolver_regression.py` runs identical synthetic
Mach-O inputs against exact preimage `c358e0ffc73c8bf9619200249d4e974e54fea86c`
and candidate source. The preimage fails with `ambiguous-runtime-dependency`;
the candidate proves each launch selects its own different Shared.dylib. The
durable JSON result binds input/source/check SHA256 values and confirms cleanup.
Check SHA256: `9fedd951594f9db802daea31296f35400039c8d2e3c1d4e10e4e8dc20c9d01e4`.
Native candidate SHA256: `e3d70b7b92bde765c9e7a3fa1b40abf091c7bab8ec7f81b302caec222bf8f89d`.

Self-inspection preserved every ARM64 variant, selected tool and transferred
loadable file. The former global-union ambiguity fixture is superseded by a
within-launch conflicting-binding fixture with both exact hashes/rpaths, plus
positive ordered/context-isolation cases. This is an intentional resolver-model
correction, with unresolved/outside/escaping/malformed/injection negatives retained.
The workflow, nightly schedule, aggregate, package/product/test sources and
frozen handoff patches have no changes in this repair. The nine previously
transferred packaging/doc residuals remain unstaged and outside this commit.

At the resolver checkpoint, an unavailable tool preflight emitted early evidence
and continued to the existing fallback path; it could not reject every unavailable native collector
without also removing the allowed same-image fallback before worker images are
known. Full post-build and staged proofs remain mandatory for different images.
No native completeness, new hosted runtime result, API/layout proof or savings
claim follows from these local fixtures. Root owns the next automatic candidate's
observation and any final integration decision; no extra campaign was dispatched.

## Selected test launch and CoreDevice repair intent

Resume at `a61c4c6c2c36e62f188d5ec0686a4c9887a37228`. Run `40135413579`
reports `runtime-path-outside-approved-roots` before and after compilation in
plain-mode xctest → XCTest → XCUIAutomation. The diagnostic install-name SHA256
`b731e0a584599aaffe55a2567d1c3a7330227073f2e4bfa9ff32042e271017e0`
matches exactly `/Library/Developer/PrivateFrameworks/CoreDevice.framework/Versions/A/CoreDevice`.
This is an identified declared edge, not evidence that its closure is complete.

Hosted Apple Swift is 6.2.4. Its primary
[test command](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/Commands/SwiftTestCommand.swift)
and [test environment](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/Commands/Utilities/TestingSupport.swift)
launch xctest, the XCTest discovery helper, and the Swift Testing helper with
the constructed test environment. Their extra plain launch was invented by this
collector. Retain ordinary tool plain launches and all transferred image audits;
cover test bundles under all three actual helpers. The selected
[UserToolchain](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2.4-RELEASE/Sources/PackageModel/UserToolchain.swift)
chooses the first executable Swift Testing helper from toolchain bin, then
libexec/swift/pm. Include that selected helper's identity and recursive closure.

Root approved exactly the CoreDevice framework root, including canonically
contained nested runtime files reached by dependency traversal. Require the root
itself canonical, reject sibling and escaping symlink paths, retain full hashes
and all budgets, and do not enumerate its parent or execute runtime binaries.
Other external roots stay unsupported. No existing artifact contains CoreDevice
headers, so further closed-framework imports remain unproved; no speculative
CoreDeviceUtilities/Mercury admission follows from third-party reports.

Affected checks will prove the exact failing-before launch shape, selected-helper
search/absence/containment, all three bundle contexts, exact CoreDevice/nested
bytes and changed-byte rejection, sibling refusal, root/leaf symlink escapes,
and retained artifact/fallback/isolation/aggregate contracts. The coordinator
retains native watching; there is no new agent, campaign, SDK or host mutation.

Root also approved an early producer gate: complete native host evidence with
an incomplete selected-tool closure fails before compilation, after emitting the
bounded diagnostic. This supersedes producer fallback only for that case.
Unavailable host/API evidence retains original exact-image fallback, as do the
existing post-build/worker incomplete-evidence paths. The affected harness proof
uses a compiler sentinel and separately verifies unavailable-host continuation.

## Selected runtime repair result and limits

The implementation admits only the approved CoreDevice framework and hashes
its declared recursive closure, including reached nested images. The root itself
must be canonical. Selected Swift Testing helper lookup follows the first
executable candidate in the two source-defined locations; its path/bytes join
host identity and full closure. All three test launchers use only the constructed
test environment. Ordinary tools and transferred-image coverage remain intact.
The producer emits host status and build admission separately, stopping before
the compiler when complete host evidence exposes unsupported selected-tool
dependencies. Unavailable-host, post-build and worker fallback remain exact-image
only. No additional external root is inferred or admitted.

The final deduplicated union passed 147 artifact/native/evidence/isolated-command
checks in 14.293 seconds, existing path-gate/aggregate fixtures, and 302 local
documentation links. Fresh admission was 25.79% CPU and 48.64 GiB available RAM;
one serial process held the nonblocking portfolio lock. Exact fixture-parent
cleanup was verified. Required `make test` and `make check` were attempted under
fresh admission/lock and both exit 2 for missing Swift and plutil respectively.
One earlier make-check admission found the portfolio lock busy and did not run;
source inspection proceeded before the later admitted attempt. No tools were
installed.

The unchanged contained launch regression in
`.evidence-compiled-tests-20261024/prove_test_launch_repair.py` fails on exact
`a61c4c6c2c36e62f188d5ec0686a4c9887a37228` with
`runtime-path-outside-approved-roots` and passes the candidate on the same fixture.
Its SHA256 is `477ede2abaac5e027845733bbd5985c406a7ffe098382952ac47e67dc6b94295`;
the native candidate SHA256 is
`8f67385258f6ce3b9ba8c7baa72964021e2805c315aa65ff8084c369cd3dee40`.
The durable result binds both source hashes, the fixture hash and exact scratch
cleanup. These are synthetic parser/contract proofs, not real CoreDevice or Mac
loader proof. Further external imports can still fail the early producer gate;
native completeness, collection overhead and both-shard qualification remain
hosted gaps owned by the coordinator's existing watch.

The workflow, daily 05:00 America/New_York schedule, required aggregate, product
sources and frozen handoff bytes are unchanged. Nine known packaging/doc residuals
remain outside this six-file repair. No extra campaign or native execution ran.

## CoreDeviceUtilities repair intent

Resume at `4a9391a4028c18152a8d807f010a7f034285b53e`. Run `40137926192`
stopped before compilation, correctly reporting complete host evidence and
unsupported selected-tool closure. CoreDevice's ARM64e subtype `2147483650`
requires an install name whose SHA256 is
`973e5c84a39179f721aa6c147de99567c903fbf222419dec01fe26107a17722e`.
It matches exactly
`/Library/Developer/PrivateFrameworks/CoreDeviceUtilities.framework/Versions/A/CoreDeviceUtilities`,
after both source-defined Xcode framework candidates were missing. The owner
conditionally approved that exact framework root; the verified match satisfies
the condition. Apply the same canonical-root, contained declared nested closure,
full-file hash/equality, byte/time budgets and sibling/symlink refusal as CoreDevice.

For bounded diagnostic batching, snapshot unapproved absolute install-name
declarations from already parsed and hashed permitted images on failure. Prioritize
the current loader and reached approved developer frameworks. Cap records at 64,
inspected declarations at 4,096 and elapsed work by the existing collection budget.
Record logical loader/hash, ARM64 subtype, redacted declaration and weak/dylinker
flags in a closed optional diagnostic field. This reads no new target or directory,
does not resolve candidates or admit roots, and can never produce compatibility
success. It can expose several candidate imports together, but cannot inspect an
unread rejected subtree or prove an environment override would not satisfy a
declaration. Preserve the actual resolver's failure and exact-image/early-gate
policy. No speculative Mercury or parent-directory boundary is authorized.

Affected checks cover both framework roots' nested-byte changes, sibling and
canonical-root/leaf symlink refusal, unchanged early compiler sentinel/fallback,
and inventory batches/redaction/schema/byte and time caps without further I/O.
The coordinator retains hosted watching; workflow/schedule and frozen product
handoff scopes remain untouched.

## CoreDeviceUtilities repair checks

The unchanged contained ARM64e edge fixture fails against exact `4a9391a` with
`runtime-path-outside-approved-roots` and passes with the second explicit root.
Durable regression evidence binds the prior collector SHA256
`8f67385258f6ce3b9ba8c7baa72964021e2805c315aa65ff8084c369cd3dee40`,
candidate collector SHA256
`2a895f7ffc8daf14866a71035f1688fd3d3c9cde501f7fa28bbe4b4f62f11d58`,
and unchanged regression script SHA256
`65c61a210a27e4dd7e76964dc9dc5ab65fef95cde4b569eb2026d2ae2de87b46`.
The mapped public roots preserve each revision's exact policy. This is synthetic
parser/contract evidence, not native API or Apple framework execution.

The deduplicated artifact/native/evidence/isolated-command union passes 150 checks
in 13.366s with zero skips. It includes both roots' changed nested bytes and
sibling/root/leaf symlink refusal, closed diagnostic metadata, all three launchers
and the existing early compiler sentinel/unavailable-host fallback. Inventory
fixtures prove 64-record, 4,096-inspection and shared-time caps, private-path
redaction and no additional location/cache/hash/parser/file/stat/symlink/directory
queries. Existing path-gate/aggregate fixtures and 302 local documentation links
pass. Fresh admission measured CPU 14.73% and 48.86 GiB available RAM; execution
held the nonblocking portfolio lock with one serial process. Owned scratch was
removed and its absence verified.

Required `make test` and `make check` each exit 2: Swift and `plutil`, respectively,
are unavailable locally. No tools were installed. Real native completeness,
further recursive imports, both-shard qualification and measured savings remain
unproved, with hosted watching retained by the coordinator. The five-file repair
preserves daily 05:00 America/New_York, nine known packaging/doc residuals and
both frozen handoff patches; no extra campaign or native execution ran.

## Mercury repair intent

Resume at `ae59e4509595390808c2052d81dfbaf8058bc127`. Completed run
`40139096386` stops before compilation: host evidence is complete in 11.076s,
tool closure fails in 8.021s, shards skip and the required aggregate fails.
Lint and all three Linux jobs pass. Its nontruncated declaration snapshot binds
the same rejected ARM64e import to both already hashed CoreDevice and Utilities.
The install-name SHA256
`2d3223142fcf34aa7bb5f17da075c3d3a547856993f899e1f202ce04da702d86`
matches exactly
`/Library/Apple/System/Library/PrivateFrameworks/Mercury.framework/Versions/A/Mercury`.
The initially proposed `/Library/Developer/PrivateFrameworks/Mercury.framework/Versions/A/Mercury`
instead hashes to `c9c9db500eafed73f3a78b3b90f0101d180b22072c00ca31132a9aa8a6a04b67`.
This distinction was verified by hashing 18 public path strings locally, with
no target reads or directory/cache queries. The coordinator accepted the exact
Apple/System framework root in its October 24, 18:40:40 EDT boundary readback.

Add only `/Library/Apple/System/Library/PrivateFrameworks/Mercury.framework`,
under the existing canonical-root/leaf containment, declared nested recursion,
full hashes/equality and file/byte/time budgets. Do not admit its parent, siblings,
or the incorrect Developer/Mercury path. Retain early gating, diagnostic batching,
strict fallback, all actual launchers and complete product auditing unchanged.

Affected checks: an unchanged contained ARM64e shared-import fixture against exact
`ae59e45` and the candidate; inherited changed nested bytes, sibling/root/leaf
escape negatives for all three exact roots; incorrect Developer/Mercury refusal;
and the deduplicated artifact/native/evidence/isolated-command union, existing
path-gate/aggregate fixtures and documentation links. Required make commands may
remain unavailable without local Swift/plutil. No native/API/app execution,
host changes or extra campaign is authorized. Root retains hosted watching;
schedule, frozen handoffs and nine packaging/doc residuals remain unchanged.

## Mercury repair checks

The unchanged shared ARM64e fixture fails on exact `ae59e45` with
`runtime-path-outside-approved-roots` and passes the candidate, including both
observed importing loaders and refusal of Developer/Mercury without target I/O.
Durable regression evidence binds prior collector SHA256
`2a895f7ffc8daf14866a71035f1688fd3d3c9cde501f7fa28bbe4b4f62f11d58`,
candidate collector SHA256
`73ee60fa7c72aa822e9e9a80e63f9045b4e2af6dd58d1d3a7ec6f7ded7ff7521`,
and unchanged regression script SHA256
`c542a0ca548a256d06f6fd9d642804353403d44ba25cd2954a7cf5feab41712f`.
This maps each revision's exact policy into contained synthetic fixture paths;
it does not establish real native APIs or Apple framework execution.

The deduplicated artifact/native/evidence/isolated-command union passes 151 checks
in 14.759s with zero skips. Existing changed nested bytes, sibling/root/leaf escape
negatives now exercise all three exact framework roots. Early compiler sentinel,
unavailable-host fallback, diagnostic batching/no-I/O, launcher and aggregate
contracts remain covered. Existing path-gate fixtures and 302 local documentation
links pass. Fresh admission measured CPU 16.36% and 47.26 GiB available RAM;
one serial process held the nonblocking portfolio lock. Exact owned fixture scratch
was removed and its absence verified.

Required `make test` and `make check` each exit 2 because Swift and `plutil`,
respectively, remain unavailable. No tools were installed. This four-file repair
changes only the proven root, affected fixtures and native spec/work note; the
early gate, batching, strict fallback, workflow, daily 05:00 America/New_York,
nine known packaging/doc residuals and frozen patch bytes are unchanged.
The previous snapshot lists no additional unapproved absolute declarations from
its already parsed images, but Mercury itself was unread. Its further declared closure,
real native completeness, both-shard qualification and measured savings remain
unproved; the coordinator retains sole hosted watching.

## MobileDevice alias diagnostic intent

Resume at `d2e395c15f7843cba9399f050297c0dfbc806c23`. Run `40139845453`
stops before compilation on `runtime-symlink-escapes-root`: complete host evidence
takes 7.948s and selected-tool closure 8.336s. CoreDevice's ARM64e test-launch chain
requires `/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/MobileDevice`,
after both selected-Xcode overrides are absent. The nontruncated declaration batch
is empty. The current error drops the canonical path already computed by
`Host.location`, leaving no exact destination/alias metadata in saved evidence.

Primary Apple [framework structure](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/FrameworkAnatomy.html),
[lstat](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/lstat.2.html),
[readlink](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/readlink.2.html)
and [canonical path](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/realpath.3.html)
documentation explain link metadata and versioned frameworks, but do not establish
this runner's actual MobileDevice package layout. Third-party paths are not
admission evidence. No new framework root or fixed alias is authorized or added.

The authorized diagnostic repair retains the original escape rejection and early
gate. Attach closed, redacted logical/root/already-computed canonical/root-canonical
metadata. Inspect at most 32 exact source prefixes under its admitted root with
the existing shared time budget, stopping at the first symlink. Record only that
link's path, normalized target, raw target SHA256 and relative flag. Never read,
hash, parse, execute or stat the escaped target as part of this metadata walk;
do not enumerate directories or resolve new target paths. The original existing
canonical resolution remains the only destination resolution. Unavailable or
capped diagnostics preserve the original error and mark incomplete metadata.

Affected checks: one unchanged fail-before diagnostic fixture at exact `d2e395c`
and the candidate (both still reject the escape); first-link absolute/relative
metadata, no escaped binary I/O, redaction/closed schema, component/time/readlink
caps and metadata failure; artifact round-trip with strict fallback; existing
deduplicated native/artifact/evidence/isolated-command, path-gate/aggregate and
documentation fixtures. Native alias admission and completeness remain unproved
until the root-owned hosted watch supplies exact metadata. Preserve all three
current roots, schedule, frozen patches and nine packaging/doc residuals.

## MobileDevice diagnostic checks and remaining boundary

The unchanged contained alias fixture fails on exact `d2e395c` because canonical
and first-link diagnostics are absent; it passes the candidate. Both revisions
still reject the escape with `runtime-symlink-escapes-root`. The regression binds
prior collector SHA256
`73ee60fa7c72aa822e9e9a80e63f9045b4e2af6dd58d1d3a7ec6f7ded7ff7521`,
candidate collector SHA256
`2aa767372dff97d55e4d8e780bb809bed8897e0f92d177ddaaaa3cbb174f3e12`
and unchanged regression script SHA256
`c6f3ef7757aae6e188ea079c433bd64f7178f30702d3b1610143ee35d520a0e1`.
This is a synthetic Linux diagnostic contract, not actual runner alias metadata.

The final deduplicated affected union passes 154 tests in 14.647s with zero skips,
plus existing path-gate/aggregate fixtures and 302 local documentation links.
It covers absolute/relative first links, raw filesystem bytes including a non-UTF8
link target, exact source-prefix no-follow metadata, no extra target resolution,
stat/open/hash/parser/directory access, closed/redacted metadata, component/raw-link
byte/time caps and failure retention. Artifact round-trip retains strict image
fallback; existing compiler-sentinel/aggregate/closure negatives still pass.
The initial sentinel incorrectly blocked Python's internal source
`stat(follow_symlinks=False)` dispatch for `lstat`; its trace proved a fixture
error. The corrected sentinel permits only the exact source prefixes with
no-follow semantics. Initial and final logs are retained. Final admission measured
CPU 14.87% and 47.45 GiB available RAM; one serial process held the nonblocking
portfolio lock, and owned scratch removal/absence was verified.

Required `make test` and `make check` each exit 2 because local Swift and `plutil`
remain unavailable. No tools were installed or native APIs/apps executed. The
three admitted framework roots and generic escape rejection remain unchanged.
The actual MobileDevice destination and first alias still require hosted metadata;
no target root, alias exception, provider access or package provenance is inferred.
A future exact fixed alias mapping must validate its source/destination and retain
canonical target containment, recursive full hashes/equality, budgets and negative
controls. This checkpoint preserves the known precompile failure and adds the
evidence needed for that decision. Both-shard qualification and savings remain
unproved; root alone watches CI. The five-file repair preserves the workflow,
schedule, frozen patches and nine known packaging/doc residuals.

## MobileDevice fixed alias activation intent

Root approved this exact source compatibility boundary at 19:11:46 EDT on
October 24, 2026, after run `40141076460`, producer `121012806567`, supplied
actual first-link and complete canonical path metadata. Resume at
`05519fd74561d16156f81de7b19ea9cad8f3485d`. The exact source is
`/System/Library/PrivateFrameworks/MobileDevice.framework`, its raw relative link
bytes are `../../../Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework`,
and its canonical target root is
`/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework`.
The raw-link SHA256 is
`07f8a0bffc980890bdef20b697b173e9cc32e5a01ca0b8d855b25c6003506769`,
normalized target path SHA256 is
`ac888c17d1c5d8148858ac86815997ebd61e036f7c934678bb5574abf8cf8d39`,
and canonical binary path `Versions/A/MobileDevice` SHA256 is
`4f608c6a4ce73221c54703c8537fa301d34df138169be8b329de19d6033cbc16`.
All three match locally reconstructed public strings. The last is a path-string
hash, not a binary-content hash; no escaped target binary was read or hashed.

Implement one fixed alias and that canonical framework root, requiring canonical
source parent, exact symlink/raw bytes/normalized target, canonical target root
and regular contained reached leaves. Retain contained version/nested links,
full recursive native dependency hashes and equality, and all existing budgets.
Exclude aliases from the system-cache shortcut. Keep static mapping policy in
host context and actual independently validated alias records in canonical image
entries, without late host-context mutation. Generic escape rejection, siblings,
alternate roots/spellings, root/leaf escapes and unsupported dependencies remain
closed. No host/runtime mutation or installed-app access is authorized.

Affected checks before publication: one unchanged exact observed-layout fixture
against 05519fd and the candidate; canonical containment, changed nested bytes,
cache-bypass, actual alias binding, closed static policy, no target I/O before
mapping validation, and real-collector fail-before-compiler sentinels. Reuse the
existing deduplicated native/artifact/evidence/isolated-command union,
path-gate/aggregate and documentation checks under fresh CPU/RAM admission and
the nonblocking portfolio lock. Preserve producer early gate, strict incomplete
fallback, pre-extraction host identity, staged closure, schedule, frozen patches
and nine residuals. Real native closure and both shards remain hosted-unverified;
root alone watches the next automatic source candidate.

## MobileDevice alias activation checks and limits

The unchanged observed-layout fixture rejects exact 05519fd with
`runtime-symlink-escapes-root` and passes the repair. It uses the actual relative
link bytes under contained synthetic roots, hashes both canonical and nested
native images, binds the actual alias even when the canonical image was loaded
first, and proves host context stays unchanged. Prior collector SHA256 is
`2aa767372dff97d55e4d8e780bb809bed8897e0f92d177ddaaaa3cbb174f3e12`,
candidate collector SHA256 is
`1ed713ce0ff52643a46b7d2bc754dfddbe6f00ad4a2481bb743095a55a09a87e`,
fixture module SHA256 is
`48ba7e33e7056e607ead7a9f0db665f854436cf4a68603108b25fcc9cc3970df`,
and the unchanged regression script SHA256 is
`e0836cd1255968cd0d56b31e95469154e7d8bbd556b7e7ad49f1cd8b56effd6e`.
These are source/fixture identities, not actual Mac runtime binary hashes.

Seven focused MobileDevice checks pass in 0.277s. The final deduplicated affected
union passes 161 tests in 14.800s with zero skips, plus existing path-gate/aggregate
fixtures and 302 local documentation links. Negative controls cover forged cache
answers, changed alias bytes and equivalent absolute/relative spellings,
noncanonical source parent, source that is not a symlink, target-root and leaf
escapes, missing alias/target, changed nested bytes, alias-record inequality and
unapproved siblings. A real collector drives the compiler/discovery sentinel:
complete host evidence plus invalid alias stops before either command. Existing
unavailable-host and worker fallback/integrity controls still pass.

An interrupted verification logged all assertions passing but lost the outer
process handle before cleanup. After proving that exact invocation absent and
acquiring the portfolio lock without waiting, removed only its empty canonical
owned scratch directory with `rmdir`; retain the interrupted log and recovery
receipt. The subsequent final union returns zero and verifies automatic owned
scratch removal. Fresh final admission measures CPU 17.39%, 48.95 GiB available
RAM and one serial process; one fully used core is 6.25% of this host. No new
hosted campaign was requested.

Required `make test` and `make check` each exit 2 at missing local Swift and
`plutil`. No tools were installed and no native APIs/apps executed. This exact
alias/root implementation remains hosted-unverified: the metadata path hashes
establish layout, not content compatibility, further dependency completeness or
two-shard success. Root alone watches the ordinary source push. Workflow, daily
05:00 America/New_York (EST/EDT) schedule, early gate, fallback/identity/integrity
rules, frozen patches and nine known packaging/doc residuals stay unchanged.

## DeviceInterface and exact weak-file repair intent

Root approved both exact boundaries and conservative weak-load handling at
19:45:15 EDT on October 24, 2026. Resume at
`4d88540d0960a055d881156957296c34f65826a9`. Run `40143266253`, producer
`121019287928`, validates the MobileDevice alias and hashes the actual ARM64e
image to `87490526530f31bc31ee3f981a9b625540996aa67606cc4fb67b019502e4aad8`.
Its nontruncated declaration snapshot contains two weak absolute imports:
`/Library/Apple/System/Library/PrivateFrameworks/DeviceInterface.framework/Versions/A/DeviceInterface`
and `/Library/Apple/usr/appleinternal/lib/libMobileRestoreInternalExtensions.dylib`.
Their independently matched path-string hashes are respectively
`007b89b1d29ed72a2fb9a48c74264545f343b4172db93cacb128c3be46822adb` and
`7b64426e60ed950a9c11fbc008a2006774e7371e561d7d2d2d4ffa9b1e90c4f2`.
Neither import digest proves target contents, presence or alias layout.

Admit only canonical DeviceInterface.framework with the existing contained
declared recursive full-hash policy, plus source-defined exact-file membership
for that one internal-extension dylib. No parent, sibling, child-prefix,
alternate spelling or new alias is admitted. Preserve selected-Xcode ordered
overrides, the sole MobileDevice alias and static host-context policy. Present
selected dependencies retain all native slice/hash/recursive closure checks.

Missing candidates need explicit proof before they can justify an empty weak
edge: genuine ENOENT, canonical/no-escape existing ancestors and negative bounded
cache queries for the exact logical/canonical candidate. Cache-only unsupported
external dependencies and permission/type/policy/unknown errors stay incomplete.
Use the current APIs, shared budgets and exact path metadata only; no scanning,
native artifact execution or host change. Apple primary JustInTimeLoader and
Loader source support optional absence after search, not unconditional omission.

Affected checks: unchanged old-head ARM64e two-import fixture; both present,
one/both absent, cache-only/unknown/access errors, root/ancestor/leaf containment,
exact-file sibling/child/prefix refusal, changed bytes/presence equality,
unsupported third weak import and real-collector early compiler sentinel. Run
the final deduplicated native/artifact/evidence/isolated-command union and existing
path-gate/aggregate/doc checks under fresh admission/nonblocking lock. Keep all
early-gate/fallback/source/integrity rules, schedule, frozen patches and residuals.
No further unread dependency boundary is inferred or admitted.

## DeviceInterface and exact weak-file repair result

Implemented both approved paths as one source repair. DeviceInterface uses the
existing canonical framework/reached nested dependency policy. The internal
extension is exact-file membership with canonical parent, exact canonical regular
leaf and full byte/slice/recursive checking. Parent/sibling/child-prefix paths,
alternate absolute spellings and file aliases reject. The sole MobileDevice
mapping and its independent actual metadata binding stay unchanged.

Every missing resolver candidate now requires genuine ENOENT, canonical root,
bounded existing-directory ancestor validation and negative exact logical and
canonical cache membership. Cache-only/unknown, access, type, dangling/escaping
alias and race cases stay incomplete. Present overrides retain their ordered
precedence and full hashes. Empty weak edges bind absence paths and reviewed
alias metadata; canonical staged paths map back to the original workspace.
Changed presence or contained version-link destination therefore changes the
fingerprint. No new native API, directory scan, rejected-target byte read,
execution or host effect was added.

The unchanged observed two-import fixture rejects exact
`4d88540d0960a055d881156957296c34f65826a9` with
`runtime-path-outside-approved-roots` and passes the candidate. Its durable
regression receipt is
`.evidence-compiled-tests-20261024/mobiledevice-weak-paths-regression.json`.
The final deduplicated artifact/native/evidence/isolated-command union passes
174 checks in 16.335s, zero skips. Existing path-gate/aggregate fixtures pass,
and 302 local documentation links pass. Tests cover both/one present or absent,
cache-only/unknown/access failures, exact policy refusal, changed nested/file
bytes, changed presence, contained-version alias differences, staged equality,
unsupported third weak imports and real-collector early compiler sentinels.
Unavailable-host fallback and existing identity/integrity/aggregate contracts
remain covered. Fresh admission and the nonblocking portfolio lock preceded
serial execution; automatic owned fixture cleanup and absence were verified.

Required `make test` and `make check` each exit 2: Swift is unavailable, and the
app-locales check cannot spawn `plutil`, respectively. No tools were installed.
These Linux fixtures prove parser/contract behavior only. The two actual target
files' presence/bytes, complete native closure across current images, both-shard
qualification, overhead and savings remain hosted evidence gaps. Root alone
watches the next automatic source candidate. Source/run/profile/integrity gates,
early build gate, strict fallback, 05:00 America/New_York schedule, nine frozen
residuals and both durable product patches are unchanged.

## Shared runtime traversal repair intent

Run `40145045507`, producer `121024518196`, at exact
`1c94f73676de7c4b91e08c18ac2f354a8c046702` now stops before compilation
at `native-runtime-edge-budget`: host 9.3542s, closure 29.686634875s,
complete host, no unapproved declarations. The last selected dependency is
cache-resident `/usr/lib/swift/libswiftDispatch.dylib` after a missing selected
platform override, through xctest/XCTest/XCUIAutomation/XCTestCore and the three
Symbolication/DebugSymbols frameworks. Saved log SHA256 is
`30c3b9f57b1ce4142795703ee784fe58290e4997e06b0630664bb251df61876d`.
The event establishes rejection at edge 16,385, not actual duplicate counts.

Current visit identity includes every ancestor image/subtype. Shared dependency
routes can therefore repeat identical candidate searches and complete edges.
Investigate completed-subtree reuse within one process/root variant only,
matching the inherited ordered rpath prefix actually read (full stream if
exhausted), plus ancestor-cycle membership over every attempted subtree variant.
Keep completed @rpath constraints in that same launch's monotone binding map.
Retain full chains for diagnostics and exact byte/hash/target/absence equality;
represent fingerprint edges by actual launch, loader subtype and consulted roots.
Reported this representation boundary to the coordinator before implementation.
No root, alias, API, fallback or resource limit changes are proposed.

Affected proof plan: deterministic shared branching DAG failing exact old head;
small-reference complete semantic edge/result equivalence; distinct rpath order,
required prefix versus unused suffix, weak exhaustion, cycle-support membership,
root variants/test processes and late binding conflicts. Keep actual work under
existing edge/context/time/query limits. Reuse the deduplicated affected union
and required make attempts under fresh admission/nonblocking lock; preserve
schedule, frozen patches and nine residual files. No hosted campaign/watch,
native execution, agent, install or host mutation is part of this repair.

## Shared runtime traversal repair result

Coordinator accepted the exact equivalence and fingerprint representation
boundary at 20:13:20 EDT on October 24, 2026. Completed successes are reused only
inside one explicit launch/root variant or test-bundle process with the same
binding map. Prefix/full-miss equality, attempted-variant cycle support and subtree
depth guard every hit. Full chains remain in failure diagnostics; fingerprints
bind explicit process/loader variant and consulted roots with exact comparison.
All root/alias/API/source/integrity/fallback policies and resource limits remain.

The unchanged five-level/four-way shared DAG rejects exact
`1c94f73676de7c4b91e08c18ac2f354a8c046702` at 16,385 resolved edges and
1,265 route contexts, with 24 parsed images. The candidate completes all the same
nodes/dependency targets with 135 attempted/resolved edges, 24 memo misses,
48 memo hits and four process contexts, at unchanged 16,384-edge/4,096-context
limits. These are fixture counters, not measurements of the hosted workload.
The smaller exhaustive no-reuse walk produces the exact same full fingerprint
as the optimized walk; no fingerprint projection/normalization is used.

The final deduplicated artifact/native/evidence/isolated-command union passes
186 checks in 18.242s, zero skips. Existing path-gate/aggregate fixtures and 302
local documentation links pass. Controls cover ordered prefixes, unused malformed
suffixes, exhaustive weak absence and newly present targets, blocked-cycle
support, late binding conflicts, deeper-chain refusal, end-of-collection deadline,
all root variants and separate bundle processes. Native work counters reach
producer/worker evidence outside proof/identity; malformed observation data
cannot change admission. Existing content, alias, presence, staged equality,
early compiler sentinels and strict-fallback controls remain covered.

Durable final regression and union records are
`.evidence-compiled-tests-20261024/context-reuse-final-regression.json` and
`context-reuse-final-union.log`. Fresh CPU/RAM admission and the nonblocking
portfolio lock preceded serial execution; owned scratch cleanup/absence verified.
Required `make test` and `make check` each exit 2 because local Swift and
`plutil` are unavailable; both attempts verify owned scratch removal. No tools
were installed and no Mac APIs/apps executed. Real graph counters, complete
hosted native closure, two-shard qualification, overhead and savings remain
unproved until parent-owned hosted observation. Schedule, frozen patches and
nine residual files are unchanged; no new campaign or child watcher is started.
