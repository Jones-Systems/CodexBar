# Work Note — Compiled macOS test handoff

<!-- codex-section:begin id="worknote.compiled-test-handoff#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.compiled-test-handoff`

Purpose: Preserve CI/harness implementation intent, evidence, and delivery limits.

Governing artifact: `spec.compiled-test-handoff`

Continuity owner: CI/harness implementation lane

Consumers: CodexBar coordinator and CI maintainers

Authority effect: none
<!-- codex-section:end id="worknote.compiled-test-handoff#ctx.artifact-header.001" -->

## Binding and authority

The app-selected isolated workspace is `work/mac-build-once-test-shards-20261024`, starting clean at
`515334773b60c8ff278710d96738d6055ed1a2b0`. This lane is its sole Git owner. Scope: CI workflow,
Swift test harness/campaign/artifact helpers and their tests, build-sharing documentation, and the narrow
AGENTS required-producer contract. Root owns integration, CI watching, and merge. No descendants, sudo,
tool installation, app/host updates, credentials, signing, or live providers. Exact current owner instruction
selects gpt-6.1-sol/max/default; inherited preference is high_intelligence/personal_default revision 8.

Native thread: `thread:delegated-task:command%3Amcp%3Ab036eeba-42d1-47f8-9599-19c6443cf03c%3Adelegate-task%3Acodexbar-build-once-solmax-20261024-v1`.
The requested V3 builder intent uses the supplied generic implementation fallback; this runtime has no
app profile selector. No independent review or automated review bot is requested.

Thread registry request `codexbar-build-handoff-registration-20261024-v1` returned
`registration_unavailable`, `effect: none`, `reason: endpoint_unavailable`; no enrollment or repair was attempted.
Root explicitly confirmed the narrow required-producer AGENTS edit. Repository contract only; no ruleset changes.

## Findings and decisions

Graphify's verified snapshot is older than the checkout and its query truncated; current source is the
authority. SwiftPM release source and current Package.swift/harness establish the conservative complete
`.build` handoff in the Engineering Spec. Hosted runtime proof remains required. Local Swift/plutil are
unavailable; no installation is authorized. Existing profile owner retains baseline measurements and the
separate 05:00 Eastern nightly commit; this lane does not overwrite or cherry-pick that worktree.

## Verification and evidence

Before every local test start, take fresh capacity telemetry and acquire the portfolio benchmark lock
nonblockingly. A busy lock means continue source work. Tests run as one serial command below 85% CPU.
Task scratch stays beneath this workspace with exact cleanup. Affected checks are specified in
`spec.compiled-test-handoff#ac.proof.001`; outcomes will be recorded here.

Initial artifact boundary checks passed (11 tests). The first wider harness run executed 179 tests with
19 platform skips and one failure: a workflow contract still expected the cache on each worker and a
separate rebuilding JSC step. The implementation intentionally moves the cache to the producer and runs
JSC goldens inside the restored-build lifetime; assertions were updated to verify those stronger boundaries.
All remaining tests passed, including existing process-containment regressions. A producer inventory review
also caught TarInfo hardlink deduplication; regular-file sizes are now preserved when materializing hardlinks.

Final focused Python set passed, including host/source/toolchain evidence, hardlink materialization, both
skip-build shards, full-profile JSC reuse, corrupt/mismatched handoff refusal, hostile extraction, and cleanup
status preservation. `Scripts/test_swift_test_sharding.sh` passed, including 95 containment/fixture checks
(19 platform skips), all normal sharding cases, and success/failure/cancellation scratch cleanup.
`Scripts/test_ci_path_gate.sh`, documentation links (300 targets), specification marker checks, and
`git diff --check` passed. Every local test command used fresh admission and the nonblocking benchmark lock.

`make test` was attempted and failed at absent `swift`; its fixture root was removed. `make check` was
attempted and failed at `spawnSync plutil ENOENT` before tool installation. No tools were installed.
Native compilation/execution, transfer timings, complete runtime closure, artifact sizes, and comparative
macOS runner-minutes remain unproved until the coordinator returns hosted results.

## Delivery and remaining work

Implement and verify the artifact producer and fail-closed workers, publish a non-draft PR against
`work/used-feature-tests-20261024`, natively link it, and report exact head/base/check limitations to root.
Root alone coordinates CI observation, hosted measurements, integration with the product sibling, and merge.

Additional root-assigned product-dependent consumers are deferred from this checkpoint: the plugin-only
`CodexBar_CodexBarCore.bundle` copy/sign block in `Scripts/package_app.sh`, resource-smoke assumptions in
`Scripts/verify_packaged_app_launch.sh`, and the direct/symlink resource-smoke step in
`.github/workflows/release-cli.yml`. Preserve app/helper launch, identity, signing, frameworks and widget
checks. PR26 signing head was reported as `fe03150aa02651dccd190452e2dc0105c955b4be`; recheck before these
overlapping files are edited and limit package changes to the obsolete resource block/variables.

After product deletion, remove dead `Scripts/regenerate-plugin-js.sh`, its sole
`Scripts/transpile-plugin-ts.mjs` consumer, plugin-only `Scripts/regenerate-sucrase-bundle.sh`,
`tsconfig.plugins.json`, and plugin-only lint/workflow installation inputs. Update obsolete engine-isolation
fixtures only after those features are absent. This checkpoint retains those scripts and all unslimmed
PR38 coverage, conditions plugin generation/typechecking/JSC on actual resources, and accepts an empty
legitimate profile partition without relaxing manifest/discovery validation. The separately owned nightly
commit remains `0110a56430470106ad7ffed6c96707d3eb5cc636` for coordinator integration.
