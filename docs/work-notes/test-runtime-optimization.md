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

## Default-off Linux input timestamp experiment

This additive preparation starts from published `1795cbf98de48638d2561c4732876b0e381bcdb8`.
The coordinator owns the existing manual cohort and any future publication or
dispatch. Its three-dispatch budget is exhausted; this preparation grants no new
campaign. No native source/test body, test selection, compiler flag or binary
invocation changes are included.

Coordinator-supplied warm evidence is retained under
`/home/malcolmjones/test-runtime-portfolio-20261023/codexbar-linux-campaign-1795cbf/`:
`warm-arm64-sanitized.log`, `warm-x64-sanitized.log` and
`warm-linux-qualification.json`. The latter binds warm run `39952016772` to the
exact published source and per-architecture seed cache entry, image, toolchain
and dependency identities. ARM/x64 warm jobs took 507/568 seconds; release builds
still took 362.09/382.69 seconds, debug builds 84.14/125.37 seconds, and the main
Swift Testing runs about 10.11/13.31 seconds. Restore receipt windows were only
4.53/5.03 seconds. The accepted framing also recorded seed jobs of 548/708 seconds
and off jobs of 578/725 seconds. These complete jobs still miss 390 seconds.

The saved warm logs show package-owned CQuickJS/Core/CLI release recompilation
and Core/Linux-test debug recompilation, while cached dependency compilation is
absent. Checkout input mtimes are the strongest current explanation, with medium
confidence; they are not a proven cause or a predicted speedup. The earlier
inventory estimate was 2,454 regular package inputs, about 35.94 MB, plus five
contained test-source symlinks. The experiment must measure its own actual set.

The manual option is `linux_timestamp_mode: off|record|replay`, default `off`.
Ordinary CI forces `off`. `record` requires Linux `seed` and an exact key that was
not already restored, so the qualified manifest can accompany a new cache entry.
`replay` requires Linux `warm`, a verified exact restore and matching producer
source. Untreated warm uses `off` against the same recorded seed entry. The CLI
phase is `python3 Scripts/ci_swift_test_campaign.py linux-cache input-timestamps`;
its existing JSON context carries the validated option. All standard SwiftPM
release, debug-test and CLI smoke commands still execute unchanged.

The bounded manifest is `.build/.codexbar-input-timestamps.json`. It covers the
complete tracked `Package.swift`, `Package.resolved`, `Sources/`, `Tests/`,
`TestsLinux/` and `TestsPlugin/` trees, including resources. These are the input
roots of the inspected package manifest; they are bound in the receipt, not
inferred from file extensions. Committed and index inventories must agree;
new untracked inputs are rejected, including ignored files inside these roots.
The checkout SHA must still match. Each entry records path, Git type/object,
actual mode, content SHA256 and integer nanosecond mtime; symlinks additionally
record their literal and contained target. Streaming content checks also verify
the committed Git blob identity. Same-size edits cannot pass a timestamp match.

Limits are 8,192 paths, 64 MiB input bytes, 4 MiB metadata and a sampled 20-second
processing bound per phase. Metadata lives inside the existing 2 GiB cache
envelope; existing storage reserves, cache keys, transfer limits and all guards
remain. One temporary manifest of at most 4 MiB is written alongside the final
file and atomically replaced; exact-name cleanup runs in `finally`. An interrupted
hosted job retains uncertain diagnostics until its ephemeral runner is torn down.
No shared cache, source content or external metadata directory is removed.

Recording precedes the build; successful save admission rereads the entire input
set and requires unchanged content, type/mode and mtimes through all producer
commands before changing the manifest state to `qualified`. Replay verifies that
complete qualified manifest, repeats the complete read-only snapshot and requires
equal entries and fingerprints before its first timestamp update. It checks each
input again while updating, then rechecks the complete result. File reads and updates
use no-follow descriptors and checked directory ancestry. Contained direct
symlinks receive link timestamps without following their leaf; absolute,
escaping, chained or unsupported targets fail closed. File identity, size, mode,
mtime and ctime checks detect observed read/replay races. Two reads are not an
atomic filesystem snapshot: changes after the last pre-update observation can
still fail after earlier files received timestamps. A failure after any
attempted update records possible partial replay, attempted/applied counts and
the last path, fails the treatment and preserves its manifest. There is no silent
rollback or claim that a partially applied treatment is off.

Receipts retain producer binding and manifest digest, before/after timestamp
matching counts, input count/bytes, verification passes and elapsed processing
time. Replay performs four bounded streaming passes; after-command validation
adds one separately. The second pre-update scan adds at most 64 MiB of input reads
and 8,192 input records; its cost is unmeasured and the shared 20-second phase guard
is unchanged. Existing native `Build complete!` summaries and job-step durations
remain the source for actual compiler/command walls; existing receipt windows
are upper bounds. These records identify a candidate treatment, not cache
authenticity, producer ownership or proven binary equivalence.

Qualification requires a new frozen source and an authorized, causally matched
record-seed → untreated-warm → replay-warm campaign, with identical architecture,
image, toolchain, dependencies and macOS/group/shard controls. Missing manifests,
existing immutable seed keys, native capabilities or matching identities fail
the experiment rather than weakening its controls. No future dispatch is implied.

## Native event-output admission repair

The coordinator reported that seed run `39947460547`, job `120393602535`, failed
before Swift started: `unsupported output destination override: --event-stream-output-path`.
The first group returned 75 in 0.007 seconds; there were zero successful groups,
one failed group and no timeout. Native support, execution/parity and cleanup
remain unproved; the operator retains the original log/artifact. No retry or
cancellation belongs to this lane.

Source inspection traced the exact generated `run_group` command into
`build_jobs.output_destinations`. The explicit event path is not registered and
therefore reaches its unknown-output guard. The coordinator extended this lane's
scope only for two registration lines in `Scripts/build_jobs.py`: both event
flags become value options, and the output-path flag becomes a Swift output
destination. Admission, storage, concurrency and hosted-runner guards stay intact.
The three additive command fixtures exercise the actual generated private path,
its independent low-space refusal, and unknown/unresolved/duplicate destination
rejection. They retain the original failure as the cheap red-before seam.

Collision evidence: open PRs 18/25/26/29/30 contain no compiler-helper/test-helper
edits. PR29 head `c855bb563cab72e2f227936bb94c7947b696d8dd` has the identical
compiler helper blob `849c836cd4f7271e009b2a769a4a331711aa8b72` as this branch;
its workflow changes own only reset-capture preparation/upload/cleanup. Main
`aa17d050e2e3d50e598c74f1aba20c6b272b0a02` has the same output parser and the
separate hosted-runner exemption from merged PR28 (`a7d7c90`). That exemption is
absent from the frozen manual source and is not imported by this repair. Open
heads and the local helper blob were revalidated before the scope extension.

The combined affected-check plan is the three new command fixtures against the
unchanged helper, the exact registration repair, all 65 evidence tests, the 43
existing compiler fixtures, the canonical path gate, and AST/YAML/diff checks.
The coordinator granted one nonblocking shared-lock acquisition and an aggregate
180-second envelope with fresh admission per serial group. Compiler-fixture
scratch uses a secure task-owned child outside the Swift package, capped at a
1 GiB estimate plus 4 GiB reserve, with exact cleanup/absence verification; logs
and manifests are capped at 128 KiB. Native Swift and tool installation remain
excluded. New input/race comments use `keep near code` for their containment and
failure contracts.

The first bounded check stopped after 3.736 seconds. The unchanged helper failed
the two intended event-output fixtures while the unknown-output guard passed;
after the exact registration, all three passed within the evidence suite. That
suite reported 64/65 passes: the initial-scan race fixture expected zero timestamp
attempts but observed two. Both enclosing fixture parents and external scratch
were removed, process drain was proved and the mutex released. Compiler, path
and static checks did not start. The original logs and source-bound receipt remain
unchanged under `.t3/test-runtime-optimization/timestamp-event-20261023-*`.

The accepted repair retains the zero-attempt assertion and makes its early race
deterministic by normalizing only A.swift's observed ctime to its captured value.
It still writes changed same-size bytes and restores the actual nanosecond mtime.
The fixture records initial-snapshot/read ordinals and real versus observed
fingerprints; this models limited metadata precision, not a diagnosis of this
host's filesystem. The second full scan must catch that persistent mutation
before replay. A new race during the second scan deliberately demonstrates the
remaining observation boundary: fatal status, two attempted/applied Package
updates, explicit possible partial replay, unchanged A.swift mtime, preserved
changed bytes and retained manifest. The existing `(attempted, applied) = (2, 1)`
update-error fixture remains unchanged. The focused repair/check producer is
limited to one nonblocking mutex acquisition, 180 seconds, fresh admission per
group and the same storage/cleanup bounds; new receipts have a seven-day retention
bound. No commit, publication or dispatch is claimed.

The repair/check producer completed in 8.664 seconds with enclosing exit status
zero. Its deterministic pre-fix case failed in 0.019 seconds with injection at
initial snapshot 1/read 1, equal observed fingerprints and `(attempted, applied)
= (2, 2)`. The identical test bytes passed after the second-scan source fix with
zero attempts. The early/late/update-error union passed all three cases in
0.038 seconds, retaining the second-scan `(2, 2)` and update-error `(2, 1)`
boundaries. These fixtures model ctime observation precision; they do not diagnose
the original uninstrumented run's exact fingerprint values or host filesystem.

On the cumulative candidate, the canonical evidence command
`PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command python3 Scripts/test_swift_test_evidence.py -v`
passed all 66 tests in 1.060 seconds. With the unique external scratch as `TMPDIR`,
`python3 -B Scripts/test_build_jobs.py` passed all 43 unchanged compiler fixtures
in 0.702 seconds. The canonical
`PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command bash Scripts/test_ci_path_gate.sh`
passed. No compiler/storage gate was bypassed. Python AST, PyYAML, exact workflow
preservation, the exact two-line helper registration, five-path scope and
`git diff --check` passed. All 49 evidence method bodies from `1795cbf` were
unchanged. Removing only the accepted timestamp input/environment/step/context
additions reproduced that revision's complete parsed workflow, including normal
commands, groups/shards, cache limits, qualification steps and macOS/musl jobs.

Six fresh samples admitted one serial process each: CPU 16.51–25.39%, available
RAM 32.90–33.31 GiB and one core at 6.25% of capacity. The four enclosing fixture
parents and unique external scratch were absent after cleanup; process drain was
proved and the shared mutex released. New logs/receipts totaled 71.9 KiB before
the final documentation/hash receipt, below the 128 KiB cap. There was no output
truncation. Native Swift, `make test`, `make check`, macOS parameter parity and
`actionlint` remain unavailable on this host; no installation or hosted dispatch
was attempted. Native timing benefit and the 390-second target remain unproved.

Receipts: `.t3/test-runtime-optimization/timestamp-second-scan-20261023-` with
`red.log`, `race-green.log`, `evidence.log`, `compiler.log`, `path.log`, six
admission JSON files and `receipt.json`. The latter binds exact commands, source
hashes, real/observed fingerprints, cleanup and the 66-method manifest SHA256
`3cef633faa4fe8dc1d820bdb1f32e8bfe82f30cec137f3612c29d87c71a857ca`.
The evidence-file SHA256 remained
`fbe37fefbfafbdd33e9b4c994db2eaa41a582bac0c89b255fede80d562497122`
across red/green. Source publication and a new matched native campaign remain
coordinator-owned next steps, requiring their separate checkpoint grant.

## Manual Linux cache family

This repair starts from `0c0df6f341d598c2054a81e7490c86b1d73cdf62`. Ordinary
and manual jobs previously selected the same application-cache family. An
ordinary immutable exact-source entry could therefore prevent a manual record
seed from producing the manifest required for its matched timestamp comparison.
The accepted change selects `codexbar-linux-glibc-campaign-v1-` only from a
validated `workflow_dispatch` context. Push/PR keys remain byte-identical under
`codexbar-linux-glibc-build-v1-`. Architecture, image, toolchain, dependency and
actual-source suffixes and the action cache version remain unchanged.

Manual seed/record, warm/off and warm/replay share one key and restore prefix;
treatment, cache mode, run and attempt never enter that key. Existing family and
exact-source checks refuse ordinary/manual cross-family matches before metadata
access. Requested warm still fails qualification, and record still refuses an
already-restored exact entry. No arbitrary namespace option, workflow/helper
change, cache deletion or cancellation is included.

Four additive cases cover full ordinary push/PR keys, equality across the three
manual arms with different run/attempt identities, cross-family refusal before
metadata, and valid manual seed-to-warm reuse with identity and record guards.
All 66 existing method bodies and assertions are retained. The bounded check
plan is one discriminating pre-fix case, the cache-family/LinuxCache/LinuxTimestamp
union after the repair, then the complete evidence file once. The 43 unchanged
compiler fixtures need no repeat. The producer has a 120-second bound, one
nonblocking portfolio-mutex acquisition, fresh admission per group, a private
1 GiB scratch estimate plus 4 GiB reserve, exact drain/cleanup, and at most
128 KiB new receipts retained for seven days. Native parity, performance and the
390-second target remain unproved.

The producer completed in 5.520 seconds with enclosing status zero. The new
manual-treatment identity case failed against the unchanged production source
in 0.002 seconds because it selected `build-v1` instead of `campaign-v1`. With
the exact event-family selection applied, the unchanged case passed in the
31-case `LinuxCacheFamilyTests LinuxCacheTests LinuxTimestampTests` union
(0.212 seconds). The final canonical evidence-file invocation passed all 70
tests in 1.053 seconds:
`PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command python3 Scripts/test_swift_test_evidence.py -v`.
No candidate tests failed or skipped. AST/diff checks verified the exact two-line
production repair, all 66 prior method bodies, the three-path scope, and unchanged
workflow/compiler-helper/runner bytes. No compiler or native Swift work ran.

Four fresh samples admitted one serial process: CPU 6.29–16.51%, available RAM
33.15–33.30 GiB and one core at 6.25% of capacity. Three enclosing fixture parents
and the unique external scratch were absent after cleanup; process drain was
proved and the mutex released. New bounded receipts used 38.5 KiB before final
documentation/hash bookkeeping, without truncation. They are retained under
`.t3/test-runtime-optimization/linux-cache-family-20261023-` as `red.log`,
`focused.log`, `evidence.log`, four admission JSON files and `receipt.json`.
The latter records the exact commands and 70-method manifest SHA256
`57b46d7215fcd50b35b7cf5d5534334d622295b7d8be1b8eb370146f977caf50`.
Test bytes were identical across red/green, SHA256
`80605026ea68e9ef13e0407f4d09ebc9b1b0933ca4c82fad1b976066ecdf3229`.
Publication is authorized through PR30; the new frozen-source manual comparison
remains a separate coordinator-owned dispatch, with no cache removal implied.

## Hosted compiler admission backport

This continuation starts from clean `ffe942dd89b5e33f6722761bd870ff3599545077`.
It backports PR28 (`7418c4008289506d36f851d9d69c3240324c8182`, merged as
`a7d7c90bb11c9606eff7f1c4c9fcb045bd67ae8d`) into the PR30 branch. Non-Darwin
commands and the exact joint identity `GITHUB_ACTIONS=true` plus
`RUNNER_ENVIRONMENT=github-hosted` yield the original command before local
normalization, locking, CPU sampling or storage admission. Local, incomplete
and self-hosted identities retain the six-job ceiling, compiler flags, storage
guard and owned-child cleanup fence. The newer event-stream option registrations
remain intact. No unrelated main changes were imported.

This corrects branch-based manual campaigns. The inspected ordinary PR merge
checkout `5e4fc814700c9d23fdc5613e2eb191b95c520b1f` already contains the bypass;
this is not evidence that its ordinary merged-PR run used capped concurrency.
Open PRs 18, 25, 26 and 29 had no changed-path overlap with the three backported
files; PR29 was at `72b26fb939e79c68652bf7d69aa36410d053e44b` when checked.

The three PR28 regression methods and RealLock environment isolation are
retained, with one added assertion that hosted admission performs no storage
query. Before the helper edit, the unchanged hosted-command case failed in
0.005 seconds: all five command shapes reached local normalization and rejected
the deliberately invalid local-only jobs value. The corrected helper passed
the complete `python3 -B Scripts/test_build_jobs.py -v` group: **46 tests in
1.187 seconds**, including all 43 prior methods with byte-identical bodies.
The tests prove unchanged hosted Swift/Xcode argv, no local lock/sampling/storage,
preserved child status 37, and retained local/self-hosted limits and lifecycle.

The unchanged canonical evidence group passed **70 tests in 1.087 seconds**:
`PYTHONDONTWRITEBYTECODE=1 ./Scripts/test.sh --command python3 Scripts/test_swift_test_evidence.py -v`.
The canonical path gate passed through the same launcher. AST/diff checks passed;
workflow, campaign, runner, evidence, sharding and isolated-command fixture bytes
are unchanged. Ordinary group 4/two shards, qualification commands, cache limits,
default-off timestamp controls and timeout/recovery behavior remain intact.
The helper docstring and fixture-isolation comment are kept near code; the
compiler guide now states the hosted exception, including storage admission.

The single nonblocking-mutex producer completed in 7.479 seconds with enclosing
status zero. Six fresh samples reported CPU 21.56–34.49%, available RAM
33.95–34.44 GiB and one core at 6.25%; each admitted one serial test process.
Both enclosing fixture parents and the private external scratch were absent
after proved drain, and the mutex was released. The 120-second envelope,
1 GiB scratch estimate plus 4 GiB reserve and 128 KiB receipt limit were retained.
Exact commands, native statuses, method manifest, hashes and cleanup evidence
are in `.t3/test-runtime-optimization/hosted-bypass-20261023-` receipts with
seven-day retention. No candidate test failed or skipped.

Native Swift/macOS, required `make test`, and the lint/format dependencies of
`make check` remain unavailable locally. The original native Mac event-output
failure and all earlier performance limitations remain preserved. This
publication changes no campaign budget: no manual dispatch, cancellation,
installation, main merge or performance qualification is included. Native
parity and the complete-run 390-second/tax target remain unproved.

## Canonical main integration after conflict notice

The explicit integration capsule authorizes a normal merge of verified canonical
main `aa17d050e2e3d50e598c74f1aba20c6b272b0a02` into the task branch at
`0077a65b1f397f0cfb8e3f445c4c3e77f2f418e0`, without merging the PR into main.
Fork URL, both live refs, branch, clean status and sole Git ownership were
revalidated. Their common ancestor is
`d1d53b2b24284a70f6ea35b6eb4043ebc7ab9d88`.

The no-commit merge reported exactly two content conflicts:
`Scripts/test_build_jobs.py` and `docs/compiler-resource-limits.md`. Both were
the additive hosted storage assertion/description already verified in the
backport. Resolution retains `self.disk.assert_not_called()` and the documented
storage-admission exception. The helper merged automatically, preserving PR28's
hosted bypass and both event-stream option registrations. No regression methods
were removed or duplicated. Main's 18 other paths, including its merged System
Account source, Swift tests, workflow and documentation, were imported unchanged.

On the merged tree, the three hosted/local identity methods plus `RealLockTests`
passed **6 tests in 0.560 seconds**, using `python3 -B Scripts/test_build_jobs.py`
with those exact selectors and `-v`. Parent comparison proved all 46 compiler
methods and the complete helper/test files byte-identical to `0077a65b1`.
The prior 46-compiler/70-evidence/path-gate passes therefore remain bound to
unchanged implementation bytes; those full groups were not repeated. AST,
duplicate-method, both workflow YAML and whitespace checks passed. Every path
changed by either parent matched its intended parent exactly before this
receipt append: ten PR30 paths and eighteen canonical-main paths. The ordinary
CI workflow, group 4/two shards, cache/timestamp controls and runner lifecycle
are unchanged. The inherited menu-candidate workflow is canonical-main content,
checked using the Jones GitHub Actions skill; no shared workflow was changed.

The nonblocking-mutex producer completed in 1.924 seconds, native and enclosing
status zero. Fresh samples were CPU 27.67/26.98%, available RAM 33.53/33.39 GiB,
one core 6.25%; each admitted one serial process. Owned scratch was absent after
proved drain and the mutex was released. Bounds remain 120 seconds, 1 GiB new
scratch plus 4 GiB reserve and 128 KiB receipts retained for seven days.
Exact selectors, parent/file hashes and cleanup are retained under
`.t3/test-runtime-optimization/main-integration-20261023-`.

The imported native Swift tests and required native `make test`/`make check`
remain unavailable locally and require current-head hosted CI. No test failure
or skip occurred in the selected local group. The parent retains the native PR
watch; no child watcher, manual dispatch, cancellation, installation, rebase,
force push or PR merge is part of this integration. Performance qualification
and the original 390-second target remain unproved.
