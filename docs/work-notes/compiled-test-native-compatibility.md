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

Limit: an unavailable tool preflight emits early evidence and continues to the
existing fallback path; it cannot reject every unavailable native collector
without also removing the allowed same-image fallback before worker images are
known. Full post-build and staged proofs remain mandatory for different images.
No native completeness, new hosted runtime result, API/layout proof or savings
claim follows from these local fixtures. Root owns the next automatic candidate's
observation and any final integration decision; no extra campaign was dispatched.
