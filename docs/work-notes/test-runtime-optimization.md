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

The published cache change affects the macOS toolchain/cache steps before the
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

These receipts describe the published cache/recovery checkpoint. The local
campaign continuation has its separate cumulative receipts below.

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
existing retention policy; the local campaign continuation below adds bounded
manual-run artifacts. Cached build output remains in the existing `.build`
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

## Local controlled campaign continuation

PR [#30](https://github.com/Jones-Systems/CodexBar/pull/30) remains frozen at
`b5685a87c2c3cceca0008e89be138fb5a79bf86a` for the coordinator's observations.
The continuation is local only: no push, dispatch, or duplicate CI observation.
Its governing contract is
`spec.test-runtime-portfolio#iface.codexbar-campaign.001` at V3 revision
`1d28ba0ef683a5fc26ccd5e103cfc81cb599b5ed`. Its exact writer scope is this note,
`.github/workflows/ci.yml`, `Scripts/ci_swift_test_by_suite.py`,
`Scripts/ci_swift_test_campaign.py`, `Scripts/test_swift_test_evidence.py`, and
`Scripts/test_swift_test_sharding.sh`. No compiler helper, `test.sh`, Swift source,
or PR 29 capture step is changed. PR 29 was revalidated at the same head above
before editing; reporting/artifact steps follow the existing shard summary.

Ordinary push/PR execution still resolves to group four and two shards, with the
same check names, fixture isolation, exclusion, 120-second command deadlines,
strict non-timeout failures, isolated timeout recovery, 70-minute test-step cap,
80-minute job cap, and every macOS/Linux/musl/lint/plugin/smoke qualification.
Manual inputs accept only group four/twelve, N1/N2/N3, an exact lowercase source
SHA matching the checked-out ref, and seed/warm/cold treatment. Each group still
launches a fresh `swift test --skip-build --no-parallel --filter` process through
the existing compiler admission and descendant drain. No direct binary path or
process reuse is introduced.

Seed permits compatible cache restoration or a miss. Warm requires an exact
source/toolchain/dependency cache hit. Cold bypasses the cache action, including
save, and requires absent `.build` output without deleting anything. Cold means
an absent application build plus no Actions restore; it does not assert that
every operating-system cache is cold. Build-enabled discovery remains mandatory.
The primary cache key, hit result, selected toolchain hash, runner image/OS/arch,
source, run/attempt, and all controls are bound into each receipt. Seed runs are
preparation, not a warm baseline. A warm miss fails instead of being relabeled.

Capture is enabled only in the main Swift Test step, so plugin-engine aggregate
commands retain their existing path. The actual selected toolchain must advertise
both event-stream options before discovery. Every attempt, including recovery,
gets a separate directory containing native Swift Testing JSON v0 and complete
stdout/stderr, including XCTest output. Console files are replayed after process
drain; live 30-second process diagnostics remain. The raw event files are retained
unchanged. Process receipts carry PID and birth, session, full command, selected
isolation environment, drain outcome, and the fixture parent's device/inode,
allocation, and verified removal. Missing process metadata fails qualification.

The validator checks the complete raw discovery digest, exact selected partition
and union, the deliberate macOS-only CLIEntryTests exclusion, both framework
outcomes, skips, known/unknown issues, filter, invocation, timeout, serial fresh
processes, and fixture cleanup. Recovery evidence is retained but cannot qualify
a clean first-pass comparison. Cross-arm comparison uses multisets, including
multiplicity, rather than totals. It requires every shard and matching source,
cache treatment, toolchain, architecture and runner image. This establishes
equivalence between complete observations; it is not a new independent native
test census inferred from counts.

Swift Testing's [JSON v0 schema](https://github.com/swiftlang/swift-testing/blob/swift-6.2-RELEASE/Documentation/ABI/JSON.md)
provides opaque function IDs and optional display information, without a required
parameter-case ID. Its [native encoding](https://github.com/swiftlang/swift-testing/blob/swift-6.2-RELEASE/Sources/Testing/ABI/Encoded/ABI.EncodedTest.swift)
also has an optional, non-schema `_testCase` ID/display extension, and the
[argument-message producer](https://github.com/swiftlang/swift-testing/blob/swift-6.2-RELEASE/Sources/Testing/Events/Recorder/Event.HumanReadableOutputRecorder.swift)
can supply a comparable representation. The validator accepts these observed
native fields without claiming they are round-trippable selectors. It retains native
test declarations and every available case-start field, with all terminal fields
also preserved in raw events. It does not invent case IDs or selectors. Missing,
generic, repeated/ambiguous, or changed parameter representations prevent a full
parity claim; function-level results and raw evidence remain available. The small
source-backed synthetic v0 fixture proves that empty case fields cannot silently
compare equal. Actual toolchain support and native parity remain unproved locally.

The evidence producer allocates one secure workspace directory separate from
fixture scratch. Its allocation estimate is 128 MiB plus a 512 MiB residual
reserve, checked on the actual workspace filesystem. A sampled byte check during
command polling stops and drains a producer that exceeds the evidence budget;
this is an admission/observation bound, not a filesystem quota. Evidence is checked
again between attempts. Uploads retain the exact raw tree for seven days, including
failed validation, then remove only the uploaded, identity-matched root after
proved command drain. Missing completion, unproved drain, or failed upload retains
the job-owned root until hosted-runner teardown. Ordinary fixtures keep their
existing creator-owned cleanup; unconditional runner termination remains outside
Python's signal/finally guarantees. Neither evidence nor fixture roots are cached.

The new module's CLI docstring, native-schema comments, console/drain comments,
workflow default comment, and source-backed fixture comment use `keep near code`:
they describe the command, protocol limitation, lifecycle, default, or fixture
provenance needed at that boundary. The old literal matrix assertion is replaced
structurally by direct ordinary-event matrix tests plus the workflow connection
check. The old matrix comments' amortization and cold-build budget rationale moves
to this note's baseline and cap discussion (`move to durable context`); matrix
and cap tests protect the preserved defaults. The Linux observer docstring uses
`keep near code` for its read-only/status-preservation contract. The existing
selection, retry and cleanup comments retain their meaning.

### Local continuation checks

The two unchanged new-feature activation assertions failed on the frozen
`b5685a87c2c3cceca0008e89be138fb5a79bf86a` workflow/runner, then passed after the
controls and opt-in capture were added. This is activation evidence, not a claim
that the old source already had a campaign defect. Development checks caught an
XCTest active-case bookkeeping error and the Linux observer treating an absent
pre-build directory as an unavailable scan; both were corrected, and their same
assertions pass in the final group.

| Final cumulative check | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 bash Scripts/test_swift_test_sharding.sh` | Passed in 46.98 s; 36 evidence/control/measurement tests and 95 existing containment tests, with 19 platform skips; scratch success/failure/HUP/INT/TERM cleanup passed |
| `PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command bash Scripts/test_ci_path_gate.sh` | Passed; fixture parent removed and absence verified |
| `bash -n Scripts/test_swift_test_sharding.sh`; Python AST parse of the three changed modules; PyYAML workflow parse; `git diff --check` | Passed |
| `node Scripts/check-documentation-links.mjs` | Passed, 277 local links |
| `PYTHONDONTWRITEBYTECODE=1 make test` | Unavailable: Swift absent; make returned 2 and the owned fixture parent was removed |
| `make check` | Unavailable: Swift lint/format tools absent; automatic installation remains outside scope |
| Hosted Actions validation / native case parity / same-revision tax | Not run by this local continuation; parent owns publication and dispatch |

Every local test/check used the shared portfolio lock and fresh same-host
admission. Final sharding: CPU 21.88%, available RAM 26.39 GiB; path gates:
23.36%/30.29 GiB; static group: 11.36%/30.28 GiB. One fully used core was 6.25%
of sampled capacity. All admitted one serial command. No test remains running.

The final evidence-module SHA256 is
`f37d05640746d4e87ba24a6cca64cd15f49927ef1860da6f222b097096d782ef`.
The synthetic six-arm fixture contains 28 raw discovery IDs, digest
`14023b101a05539e0abf5af97ff10be6b1cc94f73df86cf0ec67849cf2a0515e`, and 27
selected units after the deliberate exclusion, digest
`0f10c615a13d3ea7f6a67752bbb4ccc8f5773dd6f5266a338796b9a6dfa629c5`.
All six synthetic G4/G12 × N1/N2/N3 unions and native-shaped outcome multisets
compare exactly. Those fixtures are synthetic; they do not replace hosted native
inventory. Detailed local logs and `campaign-manifest.json` remain under the
existing task-owned 10 MiB evidence allowance through coordinator handoff.

### Campaign observations and dispatch prerequisites

Historical run 39899148493 has 261 group-four launches, 1939.2 seconds of summed
execution and 718.47 seconds of reported Swift Testing bodies. The residual is
1220.73 seconds, or 4.68 seconds per group; it includes more than startup alone.
Holding that residual per launch constant predicts an 813.82-second reduction
when grouping 1044 selections into 87 groups of twelve. This is a model, not
native group-twelve evidence:

| Group size | Ideal summed execution (s) | Ideal N2 wall (s) | Ideal N3 wall (s) |
| --- | ---: | ---: | ---: |
| 4 | 1939.20 | 969.60 | 646.40 |
| 12 | 1125.38 | 562.69 | 375.13 |

The modeled group-twelve/N3 execution leaves only 14.87 seconds below 390 before
discovery, setup, teardown, shard-zero formatting/goldens, or start stagger.
Historical shard-zero extra checks cost roughly 138–171 seconds. No arm is
predicted to satisfy the whole-job/graph target from this model.

The coordinator must first release the PR30 head freeze, publish one candidate,
and bind all arms to that new exact branch SHA. The existing Actions workflow
identity is the hosted route; its new branch dispatch capability is unverified
until the authorized dispatch succeeds. There is no available local Swift/Mac
route, and the previous Mini authentication failure authorizes no alternate route.
Manual branch caches must be seeded at the candidate source: PR merge-ref keys
and the frozen PR30 source are not interchangeable with a new branch candidate.
Run a seed before warm arms, require exact hits, then run sequential same-source
G4/N1,N2,N3 and G12/N1,N2,N3 controls as authorized. Preserve cold arms separately.
Use `python3 Scripts/ci_swift_test_campaign.py compare --baseline <N1 receipt.json>
--candidate <each shard receipt.json>` after downloading complete artifacts.
Compare G4/G12 native outcomes as well as each group's N1/sharded arms.

Use completed GitHub job timestamps for complete-job runner-seconds, start
stagger and wall time; include macOS, both glibc Linux jobs, musl, lint and the
aggregate gate. Report queue time separately. Compute each group's tax as summed
passing sharded job seconds divided by passing N1 job seconds minus one, on the
same source/cache treatment/runner class and coverage. The helper intentionally
does not substitute process-loop timings for completed-job tax. Failed/time-out
arms and missing/ambiguous identities cannot provide its denominator. The
390-second and 10% bounds remain unknown until these native observations exist.

### Completed Linux observation and next cache proposal

Completed job logs from [run 39921416999](https://github.com/Jones-Systems/CodexBar/actions/runs/39921416999)
were read once without CI status polling:

| Job | Complete job (s) | Checkout (s) | Toolchain restore (s) | Install/setup (s) | Release build (s) | Test step (s) | Native test build (s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Linux x64, 120307703163 | 603 | 3 | 25 | 48 | 366 | 155 | 142.19 |
| Linux ARM64, 120307703267 | 597 | 3 | 14 | 17 | 425 | 135 | 124.04 |

Both toolchain caches hit. Application outputs were uncached in that run, so the
release build and second, debug test build dominate. Native output reported
8 cases plus 566 cases (574 total), with 0.424/12.040-second x64 and
0.370/9.893-second ARM64 body summaries. These totals are not complete raw-identity
coverage proof. Both complete jobs exceed 390 seconds; macOS-only improvements
cannot satisfy the complete-run objective.

Read-only proposal for coordinator disposition: add a `.build` cache only in the
existing glibc `build-linux-cli` job, after selected Swift installation and before
the unchanged release build. Bind its namespace to Linux runner image/OS/arch,
actual `swift --version` and `swift package --version`, dependency manifests, and
source SHA. Permit only the identical image/toolchain/arch/dependency family as a
restore prefix. Always run release build, debug `swift test --parallel`, and the
existing release CLI smoke; SwiftPM must validate restored source output. Do not
cache fixture parents, home, evidence, or the musl SDK tree. The compiler helpers
and PR29's macOS capture hunks have no overlap with this Linux hunk.

Before implementing that proposal, bind storage admission to the existing build
root: measure cold/warm `.build` size per architecture, declare restore plus build
peak and reserve, and identify GitHub cache entry/repository retention bounds.
Do not claim the existing approximately 1 GiB toolchain archives measure app
output size. A source miss saves a new validated source build; an exact hit never
skips validation. Cold misses retain their current build cost. Qualification
requires full same-source cold/warm Linux jobs, raw native identities where
available, both architecture outcomes, cache contents excluding fixture paths,
and whole-job/graph timing. Affected checks are the cache workflow contract in
the existing evidence module, path/aggregate gates, and hosted release/debug/
smoke lanes. The measurement checkpoint did not implement or dispatch application caching.

The coordinator first accepted measurement. Three metadata-only receipts
surround the existing glibc release build and debug tests: before release, after
release and after tests. They print source-bound logical bytes, regular-file and
symlink counts, available workspace bytes, the proposed `[".build"]` cache-path
manifest, fixture-parent absence and fixture/evidence references inside `.build`.
They read no file contents, follow no directory symlinks, and change no files.
Each walk stops at 200,000 entries or a sampled ten-second bound. Errors produce
an `unavailable` receipt with a zero observer exit status, preserving all original
build/test failure and skip behavior. The after steps run even on failures. No
additional build/test invocation or application-cache action was introduced in that checkpoint.
These checkpoint sizes are observations, not proof of the transient build peak;
the eventual peak/reserve estimate and cache retention disposition still need
native evidence and coordinator acceptance. The bounded trial accepted next is described below.

## Guarded Linux application-cache continuation

This continuation starts at `794790c030d93d246a5c3fdd59cc685771a69f44`, after the
one-file isolated-command fixture dependency repair. Its writer scope is only
the workflow, campaign helper, existing evidence-test module, and this note.
The parent accepted Astra Max's guarded cache design and owns native watching
and manual campaign dispatch. Publication to PR30 is an intermediate checkpoint;
no merge, installation, shared cleanup, or hosted dispatch belongs to this lane.

The coordinator supplied later completed log observations from
[run 39936979761](https://github.com/Jones-Systems/CodexBar/actions/runs/39936979761),
published head `87d202d533462e35cb3a9f8782f7b853dedd3282`, actual PR merge checkout
`63ae14dc6bafcddc7e2e6bca5dd670dd75ff3b0d` (main `a7d7c90` plus that head).
These are coordinator-read receipts, not another read by this implementation lane:

| Job | Complete job | Release checkpoint bytes / files / symlinks | After-test checkpoint bytes / files / symlinks | Debug build | Runner image |
| --- | ---: | --- | --- | ---: | --- |
| x64 [120358808376](https://github.com/Jones-Systems/CodexBar/actions/runs/39936979761/job/120358808376) | 723 s | 650905263 / 4324 / 10 | 1480685495 / 12765 / 11 | 197.24 s | 20261012.334.1 |
| ARM [120358808442](https://github.com/Jones-Systems/CodexBar/actions/runs/39936979761/job/120358808442) | 596 s | 661250116 / 4324 / 10 | 1483688472 / 12659 / 11 | 123.65 s | 20261012.149.1 |

Raw log SHA256: x64
`756442a48cd4eed7f376cd156c4dd30e0ba63c352d2eab34e16715501fea0f50`;
ARM `bd43e3be74428f687a27f7b664e001773dca56bfa475494d945dd4512d90f1f0`.
The roughly 1.48 GB after-test trees justify a bounded cache trial. These sampled
sizes are not build peaks, compressed archive sizes, warm speedups, or proof of
the complete-job/graph target.

Only glibc Linux `.build` is eligible. The primary namespace is
`codexbar-linux-glibc-build-v1-<arch>-<image-hash>-<toolchain-hash>-<dependency-hash>-<actual-checkout-SHA>`.
Hashes bind the raw runner architecture/label and ImageOS/ImageVersion, actual
`swift --version` and `swift package --version` output, and both dependency
manifest contents. Receipts retain those identities and the actual/event/expected
SHA, run, attempt, ref, group/shard controls, independent Linux/macOS modes,
requested/matched keys and producer source. The sole restore prefix stops after
dependency identity. Missing identities disable ordinary caching; requested warm
qualification fails. Every glibc Linux job validates the actual manual checkout
before even its existing toolchain-cache step. Ordinary jobs use miss-tolerant
`auto`; manual `linux_cache_mode` is independently `off`, `seed`, or `warm`, with
`off` the default. The existing `cache_mode` remains macOS-only.

Lookup-only resolves a candidate without downloading it. A repository-scoped
Actions cache metadata GET then requires one unambiguous exact key/version/ref
entry with a positive compressed size no greater than 2 GiB. The reader takes one
page of at most 100 entries, rejects pagination/truncation, bounds response bytes
to 256 KiB and the HTTP timeout to ten seconds, and never logs its token. Only
the glibc job receives `actions: read`. The split restore/save actions retain
the existing full action pin. Restore uses the approved full key without another
fallback; returned key, metadata readback and complete postrestore scan must agree.
Ordinary/seed refusal before download runs the original cold commands. A failed,
partial, changed, absent or invalid restored tree fails the job; nothing deletes
it or silently relabels it cold.

Each complete `.build` metadata scan allows at most 2 GiB logical regular-file
bytes, 200,000 combined workspace/build entries, and a sampled ten-second scan.
The root must be canonical and not a symlink. Symlink targets must remain inside
`.build`; special files and fixture/evidence paths are ineligible. Fixture parents
must be absent. Before restore and save, the workspace and archive staging
filesystem need 8 GiB available when shared, or 6 GiB workspace plus 4 GiB staging
when different. Restore/save steps each have 120-second caps and a 60-second
segment download timeout. These are admission estimates and sampled checks,
not reservations. **The stock action has no maximum-byte extraction input; these
preflight/postrestore checks are not hard extraction-size or peak-disk guarantees.**

All release/debug/test/smoke commands still execute; none is conditioned on cache
hit. Saving requires their successful outcomes, unchanged dependency manifests,
a complete final scan and storage admission, and no primary-key restore. Save
success is followed by an exact metadata readback. Missing readback remains
unavailable; an observed entry proves availability, not which concurrent producer
published it. No repository quota, retention duration, cross-ref reuse, or future
cache hit is promised. Existing toolchain, macOS and musl cache behavior is retained.

Linux receipts remain bounded JSON in job logs and step outputs (128 KiB per
receipt); there is no new evidence directory or local cache producer. Existing
metadata observations remain status-neutral. Their timestamps and surrounding
phase receipts report command/cache step-window upper bounds, including dispatch
overhead, rather than claiming exact command CPU/body times. Native job steps
remain the source for exact hosted durations. Existing native raw identities,
fresh group processes, recovery/drain, fixture cleanup and evidence retention are
unchanged. New scan/metadata/restore comments and the corrected observational
docstring use `keep near code` for their API, storage and unknown-effect contracts.

Manual workflow concurrency now includes workflow/ref/run ID/attempt and has
`cancel-in-progress: false`. Ordinary events retain their previous workflow/ref
group and cancellation behavior. Group four/two shards, existing check names,
120-second group deadlines, 70/80-minute caps and all qualification steps remain.

The affected local group is `Scripts/test_swift_test_evidence.py`, followed by
the canonical path-gate command and AST/YAML/diff validation. New synthetic cache
fixtures create unique workspace-owned children, nested in the enclosing fixture
parent when present, and remove them through `TemporaryDirectory`; byte-limit
tests shrink the synthetic limit instead of allocating multi-gigabyte files.
No Swift installation or unavailable `make test`/`make check` repeat is included.
The unchanged simulated-mac compiler test's 40 GiB `/tmp` gate remains a separate
local platform limitation. Same-source off/seed/warm native jobs on both Linux
architectures, native identity coverage and the full graph remain required before
claiming speedup, the 390-second limit, or the 10% sharding-tax limit.

Final local validation used one shared benchmark-lock acquisition after the
preceding V3 producer released it, with fresh admission before each serial group:

- `PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command python3 Scripts/test_swift_test_evidence.py -v`:
  all 49 tests passed in 0.893 seconds, including the 13 new Linux cache tests.
- `PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command bash Scripts/test_ci_path_gate.sh`:
  passed. Both enclosing fixture parents were removed and absence verified.
- Python AST and PyYAML parsing passed. Direct comparison with `794790c03`
  verified unchanged non-Linux jobs, all original Linux command bodies and
  qualification conditions, matrix/timeouts, complete action pins, unique step
  IDs and the exact four-path scope. `git diff --check` passed. `actionlint` was
  unavailable and was not installed.

Admission sampled CPU at 37.35%, 29.62% and 26.03%, with 32.58, 32.21 and
32.13 GiB available RAM; one core was 6.25% of host capacity. Each sample admitted
one serial process. The shell returned zero, all three native status files are
zero, and the benchmark lock was explicitly released. The 49-method manifest
SHA256 is `c00ff007e069f4b3625bbf9c1a5078079aaa5600bf2fb23e2f68e07088bed8e7`.
Local receipts are under `.t3/test-runtime-optimization/`:
`linux-cache-evidence-final.log`, `linux-cache-path-final.log`,
`linux-cache-static-final.log`, corresponding admission/status files, and
`linux-cache-final-manifest.json` with source-file hashes and exact method IDs.

The earlier `linux-cache-evidence-first.log` also reported 49 passes in
0.883 seconds and its native status file was zero, but its enclosing tool result
was one. That discrepancy remains retained and unexplained; it is not counted as
a passing wrapper invocation. The final replay above separately establishes
both native and enclosing-shell success on the final code. These new features
use synthetic adverse-input checks, not a claim of pre-fix native reproduction.
The fixture repair's earlier six-case red/green evidence and native limitations
remain as recorded above. No native cache transfer, build-speed claim or hosted
campaign was performed by this lane.

Contributors: root thread **Cross-Repo Tests Under 6:30**,
`486fcff1-4c33-40b0-9a64-7f4aa4227ccc`, coordination; native subagent
`codexbar_optimize`, implementation and local evidence, with no separately
supplied T3 ID.
