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
was proved. Native availability, full closure and collection cost remain pending
the coordinator's hosted run observation.
