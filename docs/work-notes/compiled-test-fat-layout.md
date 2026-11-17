# Work Note — Universal native runtime layout

Artifact Type: `work-note`

Artifact ID: `work.compiled-test-fat-layout`

Purpose: Repair supported universal Mach-O layouts without weakening runtime identity.

Specification owner: CI/harness implementation lane

Integration owner: CodexBar coordinator

Authority effect: none

Repair base is exact PR #40 head `9b7a1ef81fbf333ba09118d149d86baf011e4c6f` in
the CI/harness lane's sole-owned worktree. Preserve the normal nightly schedule,
original identity/integrity constraints, complete runtime closure and strict
fallback. Root owns hosted watching. No extra agents, manual campaign, Mac
execution, installation, signing or musl source change is part of this repair.

## Evidence and intent before mutation

Run `40125346131` producer `120965512496` compiled and exported successfully but
native closure was unavailable with `unsupported-fat-arm64-slices` after 15.742
seconds host precheck and 8.639 seconds closure. Both workers completed their host
prechecks, then correctly rejected differing image versions before discovery.
The aggregate failed. The separate musl SDK installation crashed before compiling
app code; root superseded its planned old-head retry with this necessary repair.

Exact artifact `12573057357` was streamed under fresh admission and the portfolio
lock, with independent ZIP/manifest/archive hashes and all 22,022 entries and
3.51 GiB of payload verified. All 23 loadable images parse successfully;
20 fat files each contain one ARM64 subtype 0 alongside x86_64 subtype 3. Five
additional fat members are nonloadable Sparkle dSYM files (MH_DSYM 10). The exact
external failing filename and subtype are not present in this artifact or logs.
Download scratch was removed and absence verified. Durable header evidence is
`.evidence-compiled-tests-20261024/fat-layout-run40125346131.json`.

Apple's [universal loader implementation](https://github.com/apple-oss-distributions/dyld/blob/main/mach_o/Universal.cpp)
supports distinct CPU/subtype pairs, rejects duplicates/overlaps, and recognizes
one legacy extra generic ARM64 descriptor after the declared fat32 table.
[Architecture definitions](https://github.com/apple-oss-distributions/dyld/blob/main/mach_o/Architecture.cpp)
distinguish ARM64, ARM64-v8, old ARM64e and versioned ARM64e; the full subtype high
byte matters. [Loader grading](https://github.com/apple-oss-distributions/dyld/blob/main/mach_o/GradedArchitectures.cpp)
can choose different variants for launch versus library loading. A single
arbitrarily selected ARM64 slice is therefore insufficient.

Parse every distinct supported ARM64 variant, keep the full-file hash, and follow
the conservative union of their dependencies/rpaths. Reject unknown subtype ABI,
duplicate pair, mismatch between table/header, overlap, unsupported/mixed payload
and malformed bounds. Preserve ambiguity rejection when candidate libraries
differ. Never claim a particular variant was the runtime's selected slice. Known
object/debug/archive payloads are nonloadable; a loadable non-ARM-only file stays
unsupported, rather than being silently discarded. Bound per-file diagnostics to
the already inspected path/header/size/table, with no additional host scan.

## Affected check plan and limits

Add exact observed Sparkle fat/dSYM layout fixtures, distinct ARM64/ARM64e and
legacy-extra-descriptor cases from primary loader rules, malformed/ambiguous
negative cases, dependency closure of both variants, and diagnostic admission/
logging tests. Run the deduplicated artifact/native/evidence/isolated-command
union, path-gate/aggregate fixtures and documentation links under fresh admission
and nonblocking lock. Attempt required make entrypoints; local Swift/plutil remain
unavailable. This is a functional supported-layout repair plus diagnostics, not
native proof or an exact external-layout observation. Hosted qualification and
overhead remain root-owned.

## Implementation and verification

The parser now covers the union of supported ARM64 variants, retains full ABI
subtypes and whole-file hashing, and recognizes Apple's one extra generic fat32
descriptor. It rejects malformed, overlapping, mismatched, duplicate and unknown
ABI layouts. Command budgets remain cumulative per file. Nonloadable archives,
objects and dSYMs are explicitly distinct from foreign-only loadable images.
Optional unsupported-file diagnostics contain only a bounded inspected path,
size, header/table hash and slice inventory; manifest admission validates their
closed schema. They never select host files or commands or change compatibility.

An unchanged layout regression was replayed against exact preimage `9b7a1ef` and
the candidate. All six ARM64/ARM64e/fat32/fat64 subcases fail on the preimage with
`unsupported-fat-arm64-slices`, then pass on the candidate. Durable evidence in
`.evidence-compiled-tests-20261024/fat-layout-regression.json` binds both source
SHA256 values, the unchanged check-source hash, Python version and results.

Fresh admission measured 15.00% CPU used and 31.95 GiB available (one core is
6.25% of capacity). Under the existing nonblocking portfolio lock, the deduplicated
artifact/native/evidence/isolated-command union passed 127 tests in 12.726 seconds;
the path-gate/aggregate fixtures and 302 local documentation links also passed.
The wrapper removed its owned scratch and verified absence. Focused editing
checks had passed 47 tests in 0.492 seconds. `git diff --check` passes.

Fresh admission before required make entrypoints measured 31.03% CPU and
29.64 GiB available. Both commands were attempted serially under the lock:
`make test` exits 2 because Swift is absent, and `make check` exits 2 because
plutil is absent. No tools were installed; no product/native app was run. This
does not establish complete hosted compatibility, final transfer overhead,
two-shard qualification or macOS runner savings. The prior musl SDK signal 11
is a separate prebuild failure; SDK and test scope remain unchanged.

Frozen handoff patch 01/02 and their manifest/readme checksums are unchanged.
This repair does not change workflow scheduling, product cleanup, signing,
package membership or test-profile selection. Root owns the next automatic
hosted candidate and integration readback.
