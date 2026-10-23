# Work Note — Swift Test Runtime Optimization

<!-- codex-section:begin id="worknote.swift-test-runtime#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.swift-test-runtime`

Purpose: Record the measured Swift test costs, bounded optimizations, and native qualification limits.

Governing artifact: `spec.test-runtime-portfolio`

Continuity owner: TEST-390 CodexBar implementation specialist

Consumers: CodexBar CI maintainers and the test-runtime portfolio coordinator

Authority effect: none
<!-- codex-section:end id="worknote.swift-test-runtime#ctx.artifact-header.001" -->

## Scope and baseline

The source base is `d1d53b2b24284a70f6ea35b6eb4043ebc7ab9d88` in
`Jones-Systems/CodexBar`. The task branch is
`work/test-runtime-optimization-20261023`, with one Git owner in its dedicated
linked worktree. Publication and hosted qualification are authorized; merge,
installation, signing, and host changes are excluded.

The workflow change is confined to the macOS toolchain/cache steps before the
test/capture steps. PR [#29](https://github.com/Jones-Systems/CodexBar/pull/29),
observed at `4e322d58943ff85e03a8ab12157c30dc44c16719`, owns added reset-capture
steps around `Swift Test`; those hunks remain with that PR. PR
[#28](https://github.com/Jones-Systems/CodexBar/pull/28), observed at
`7418c4008289506d36f851d9d69c3240324c8182`, owns compiler-admission changes and is
not included in this source base.

Successful run [39899148493](https://github.com/Jones-Systems/CodexBar/actions/runs/39899148493)
at `b50e80b04d472978e5821dc486e6b5b94cc08375` provides the representative baseline
supplied by the portfolio audit:

| macOS shard | Entire job (s) | Test step (s) | Discovery/build (s) | Execution (s) | Selected groups |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 of 2 | 2476 | 2302 | 1413 | 878.6 | 131 |
| 1 of 2 | 3025 | 2968 | 1893 | 1061 | 130 |

The runner discovered 1044 selections, split 524/520, with no timeouts or retries.
Discovery/build alone exceeded the 390-second target. These observations are
historical baselines, not a passing same-revision N1/sharded tax comparison.

The directly reread [shard 0 log](https://github.com/Jones-Systems/CodexBar/actions/runs/39899148493/job/120236472431)
shows an exact dependency-key cache hit restoring 1079813210 bytes (1.01 GiB),
followed by discovery at 1413.0 seconds and a cache-save skip on the unchanged
primary key. Cache metadata showed that entry was created on October 18, 2026
in Eastern Time. Source updates therefore could not refresh that entry.

The first execution group occupied about 5.9 seconds while Swift Testing
reported 33 tests in 0.008 seconds and XCTest selected zero tests. This is
evidence of overhead outside the reported test bodies, not an exact attribution
to one component. SwiftPM's [test command source](https://github.com/swiftlang/swift-package-manager/blob/swift-6.2-RELEASE/Sources/Commands/SwiftTestCommand.swift)
shows XCTest enumeration for regex filters and separate XCTest/Swift Testing
launches. Eliminating those launches requires native selection and outcome
parity; this change keeps the existing framework execution path.

## Selected changes and invariants

- Give macOS build caches an exact source key, plus architecture, selected
  Xcode/Swift/SwiftPM identity and dependency manifests. A source miss can restore
  a recent compatible build and save the new source build. Always perform normal
  build-enabled discovery, including on an exact cache hit.
- After the existing narrowly recognized Sparkle missing-library error and
  successful runtime repair, retry discovery with `--skip-build`. The initial
  discovery already reached the built test executable. Other failures retain
  their existing outcome; a failed repair does not attempt skip-build discovery.
- Emit structured discovery identities, selected groups, and per-attempt wall
  time/results into the job log. Keep list-only stdout as selection names.

Keep both shards, groups of four in CI, all supported platform lanes, test
assertions, full Swift Testing and XCTest selection, the existing macOS-only
CLIEntryTests exclusion, timeouts, strict non-timeout failure policy, individual
timeout retries, process birth checks, descendant drain and fixture-parent
cleanup. No direct test-binary invocation or process reuse is introduced.

The cache action remains pinned. The replacement namespace deliberately does not
fall back to an older cache lacking toolchain identity, so its first native run
may build cold. Cache-hit timing gains are predictions until measured. More
source cache entries can evict other entries under the repository's existing
GitHub cache policy; no quota increase or manual deletion is part of this task.

## Local validation

The unchanged focused regression module has SHA256
`8741ae2aeb32e5a8f81b22a1c41b69ca7bd3a4a23530254baf24cbe4ffd18139`.
On source base `d1d53b2b24284a70f6ea35b6eb4043ebc7ab9d88`,
`python3 -B Scripts/test_swift_test_evidence.py` fails the
two intended assertions: the cache key lacks `github.sha`, and repaired discovery
executes a second build-enabled `test list`. The additional new reporting tests
also fail because their API/evidence is not implemented yet; those failures do
not establish an existing reporting defect. The same unchanged module passes all
8 tests on the candidate, including in the final affected sharding group.

These local checks ran serially on Linux/Python 3.13. Every command acquired the
portfolio lock and fresh CPU/RAM admission. The first red sample was 19.36% CPU
with 29.98 GiB available RAM; the final sharding-group sample was 11.01% CPU with
29.83 GiB available RAM. One fully used core is 6.25% of the sampled host capacity.

| Invocation / group | Result |
| --- | --- |
| `python3 -B Scripts/test_swift_test_evidence.py` | 8 passed; same check bytes before and after |
| `bash Scripts/test_swift_test_sharding.sh` | Passed in 45.57 s; includes the 8 new tests, 95 existing cleanup tests with 19 platform skips, and scratch success/failure/HUP/INT/TERM cleanup |
| `./Scripts/test.sh --command bash Scripts/test_ci_path_gate.sh` | Passed |
| `python3 -B Scripts/test_build_jobs.py` with private `TMPDIR` outside the package | 43 passed in 0.606 s; private root removed and absence verified |
| `./Scripts/test.sh --command python3 -B Scripts/test_ci_isolated_commands.py` | 5 passed, 1 failed: simulated macOS admission needs 40 GiB on `/tmp`, but this host exposes only 15.58 GiB available there |
| `make test` | Unavailable: no `swift` executable; command returned nonzero and cleaned its fixture parent |
| `make check` | Unavailable locally: required lint tools absent; its automatic tool installation is outside this task's authority |

An earlier noncanonical invocation of `test_build_jobs.py` through `test.sh`
placed its temporary files below the real `Package.swift`. That broke one
unchanged fixture's assumption that its package search cannot find an ambient
manifest. The canonical invocation above uses an approved, private disk-backed
task root outside the package and passes without changing the fixture or helper.
The isolated-command failure is a distinct existing environment dependency: its
CPU simulation leaves the real storage probe enabled. That test/helper are
unchanged, and their hosted lint result remains required. An initial timing
wrapper also could not start because `/usr/bin/time` is absent; the reported
45.57 seconds uses Bash's `time -p`.

The synthetic discovery fixture's full identity manifest is
`340fc5d0e0f89f70e505236abf4c75d56cd4a611d1f2a72ba2c750251d998900`.
The sharding group also compares the complete fake-discovery selection union
against both shards. These are synthetic parity proofs, not a native test census.

The touched cache comment, recovery comment and synthetic-test module docstring
use the `keep near code` disposition: they preserve cache invalidation,
build-versus-runtime recovery and fixture-safety context. The obsolete cache
claim is corrected. No unrelated comment cleanup is included.

## Evidence ownership and remaining gates

The focused contract group is `Scripts/test_swift_test_evidence.py`. The affected
runner group is `bash Scripts/test_swift_test_sharding.sh`, including the existing
process-cleanup tests and the new contract group. Workflow gate tests remain
`bash Scripts/test_ci_path_gate.sh`. The repository also requires `make test` and
`make check`; unavailable platforms or install-dependent checks must be reported
as unavailable rather than passed.

Local observations and logs belong in the task worktree's ignored
`.t3/test-runtime-optimization/`, bounded to 10 MiB through this qualification
and retained until portfolio handoff. Synthetic fixtures belong to each harness
invocation and are removed on normal success, failure and handled cancellation.
Native evidence remains in GitHub Actions logs and step summaries under the
existing retention policy. Cached build output remains in the existing `.build`
and SwiftPM-cache paths, owned by the repository's existing Actions cache policy.
The build-helper check uses an approved unique private scratch root outside the
Swift package, with a 5 MiB peak estimate on a disk reporting more than 490 GiB
available and a 1 GiB residual reserve. Its creator removes both the unique root
and its empty task-owned parent on success, failure and handled cancellation.

Lines prefixed `Swift test evidence: ` carry JSON with schema
`codexbar.swift-test-evidence/v1`. Discovery includes every raw test identity;
selection records the groups after existing environment filtering/sharding;
attempt records include the filter, retry phase, command result, timeout and
wall duration through process drain. A drain exception has a null result and its
exception type, never a false pass. Digests use sorted identities joined with
newlines and one final newline. The native `source_revision` is `GITHUB_SHA`;
local events use null and need their independently recorded Git binding.
Native pass/skip totals still come from Swift Testing/XCTest output.

No local Swift toolchain or authorized native Mac route is available. Hosted CI
must establish native full-suite results. Current-count, N1, count-plus-one, and
larger-count comparisons remain unmeasured; sharding tax and attainment of the
390-second qualification/job target are unknown. A faster warm discovery step
would not by itself establish either bound.

Contributors: root thread **Cross-Repo Tests Under 6:30**,
`486fcff1-4c33-40b0-9a64-7f4aa4227ccc`, coordination; native subagent
`codexbar_optimize`, implementation and local evidence, with no separately
supplied T3 ID.
