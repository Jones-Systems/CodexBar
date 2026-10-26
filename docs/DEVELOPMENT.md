---
summary: "Development workflow: build/run scripts, logging, and keychain migration notes."
read_when:
  - Starting local development
  - Running build/test scripts
  - Troubleshooting Keychain prompts in dev
---

# CodexBar Development Guide

The partial [UI map](ui-map/README.md) records reset timing surfaces and fixture
journeys, including their interaction coverage limits.

## Quick Start

The package declares Swift tools 6.2 and macOS 14+. macOS app packaging also builds
the widget extension through Xcode. Linux supports shared-core and CLI work; it
cannot validate the macOS menu bar app.

### Source Build and Tests

```bash
# Build source without packaging or launching the app
swift build

# Run the isolated, sharded normal profile (Codex/Claude and shared app coverage)
make test

# Include the four terminal-only CLI suites with all retained offline test source
CODEXBAR_TEST_PROFILE=full make test

# Required after code changes
make check
```

For focused tests, preserve the isolation described under
[Codex credential fixtures](#codex-credential-fixtures) and
[provider session fixtures](#provider-session-fixtures). Never enable live Keychain
or account access to make routine verification pass.

### Bundle Validation

Use bundle validation when the changed behavior requires it and the task covers its
runtime effects. `Scripts/compile_and_run.sh` builds, packages, relaunches, and verifies
the app; tests run only with `--test`.

Read [runtime validation and command effects](#runtime-validation-and-command-effects)
before using compile/run, launch, packaging, or related Makefile targets. They can
terminate existing processes, inspect signing identities, or launch an app.

### Development Workflow

1. Make a focused change in the owning app, core, CLI, widget, or test module.
2. Verify through parser, model, CLI, or isolated fixture seams where possible.
3. Run `make test` before handoff and `make check` after code changes.
4. When runtime validation is needed and authorized, validate the freshly built bundle
   and verify the actual running bundle identity.
5. For intentional runtime diagnosis, use Console.app filtered by “codexbar”.
   Debug → Logging → “Enable file logging” writes
   `~/Library/Logs/CodexBar/CodexBar.log`; its default verbosity is “Verbose”.

### Runtime Validation and Command Effects

Prefer `swift build` or `swift build -c release` and isolated tests for source
verification. CLI-testable provider/parser/settings work does not require
`Scripts/package_app.sh` or `Scripts/compile_and_run.sh`.

Use `Scripts/compile_and_run.sh` only when UI/runtime behavior needs bundle-level
validation and its effects are covered by the task. It terminates existing CodexBar
instances and matching Claude probes, can inspect signing identities, packages,
relaunches, and checks that the app stays running. It runs the sharded tests only
with `--test`. Its termination patterns can affect processes outside this checkout.

`Scripts/launch.sh` also terminates existing instances before launching this checkout's
bundle. `make start`, `make start-debug`, and `make restart` invoke the compile/run wrapper.
`make stop` and `make start-release` use broad process termination; `make start-release`
also retains a maintainer-specific absolute path. Removing old documentation snippets
does not change these executable effects.

`Scripts/package_app.sh` defaults to release packaging. Release packaging invokes
`Scripts/verify_packaged_app_launch.sh`, which can launch a copied app under a sandbox.
The check may be skipped without `sandbox-exec` or inconclusive without an Aqua session.
Packaging success alone does not prove interactive UI behavior. `make release` invokes
release packaging, not the complete publication workflow.

Validate UI/runtime behavior against the freshly built bundle. Verify the actual running
bundle after an authorized restart so a stale or different installed copy cannot supply
the evidence. Before menu bar automation, capture the target screen and confirm the
CodexBar icon is visibly onscreen. Reject `click-extra` success when its coordinates
fall outside display bounds; hidden menu extras are not click proof.

For Widget/Tahoe UI issues, use a Parallels macOS VM with screenshots/clicks for autonomous
verification when that environment and operation are authorized.

These commands and documentation do not grant permission to terminate unrelated
processes, access live accounts or credentials, sign, or publish.

### Native workflow proofs

`Scripts/verify_packaged_relocation.sh` has two explicit source-qualified modes.
The default `resources` mode applies to builds retaining tracked Core resources.
It exercises the packaged resource entrypoints (CB-N6): copied helper, symlinked
helper, and app resource smoke, followed by all three missing-bundle negative
controls. These probes set `CODEXBAR_RESOURCE_SMOKE=1` and force Core plugin loads.
The `cli-relocation` mode applies only when the qualified source has removed Core
resources. It runs only copied and symlinked helper `--help`, without the deleted
smoke flag or ordinary app startup, and reports app resource proof unavailable.
Wrong mode/source combinations fail before execution. Neither mode executes the
survival phase in `verify_packaged_app_launch.sh`, needs Aqua, or proves menu,
window, provider, installed-app, or full native UI behavior.

Before running, qualify the exact disposable build against its source and review
the selected entrypoints plus their transitive initialization. Resource mode requires
`--resource-entrypoints-reviewed`; CLI mode separately requires
`--cli-entrypoints-reviewed`, including review of `--help` initialization. A review
flag records that prerequisite; it cannot prove provenance by itself. The script
requires the exact checkout root, clean tracked source, and HEAD matching the supplied
full SHA, checks the bundle's embedded commit prefix, and records copied executable
hashes. Build qualification, architecture/signature checks, and any build
commands belong to the caller. Do not supply an installed app or build via an
automatic launch wrapper. When packaging is authorized separately, use the existing
`CODEXBAR_SKIP_LAUNCH_SMOKE=1` option to suppress its ordinary launch smoke.

```bash
bash Scripts/verify_packaged_relocation.sh \
  --app /absolute/path/to/qualified/CodexBar.app \
  --checkout /absolute/path/to/source-checkout \
  --scratch-parent /absolute/path/to/existing-owned-proof-parent \
  --qualified-source-commit FULL_40_CHARACTER_SOURCE_SHA \
  --resource-entrypoints-reviewed
```

For a qualified slim build with Core resource inputs removed, use the separate mode:

```bash
bash Scripts/verify_packaged_relocation.sh \
  --app /absolute/path/to/qualified/CodexBar.app \
  --checkout /absolute/path/to/source-checkout \
  --scratch-parent /absolute/path/to/existing-owned-proof-parent \
  --qualified-source-commit FULL_40_CHARACTER_SOURCE_SHA \
  --mode cli-relocation --cli-entrypoints-reviewed
```

This proves CLI help relocation only. App resource-load proof is unavailable and
application lifetime is not tested. `verify_packaged_app_launch.sh` separately
retains bounded normal app liveness. Its `CODEXBAR_LAUNCH_SMOKE_RESOURCE_ONLY=1`
mode runs only the selected resource probes or slim CLI help probes and explicitly
does not test application lifetime. Ordinary liveness does not force lazy resource
loads. Core smoke never forced KeyboardShortcuts or app-icon loads; their existing
strict package presence checks remain, without a claim of deterministic runtime
consumption. App/CLI packaging selects Core bundle membership from tracked source
inputs and excludes stale Core bundles when those inputs have been removed.

Use an existing canonical, disk-backed scratch parent outside the denied checkout
and bundle. The caller owns that parent. The verifier allocates one private child,
copies the bundle, and removes only that child after its exact direct process drains.
HUP, INT, TERM, failures and timeouts use the same cleanup. An unproved process drain
or changed root identity preserves scratch and fails; unconditional process/host
termination cannot guarantee cleanup. Distinct invocations retain distinct roots.
Each command has a 20-second deadline inside a 180-second run budget; copy/setup
time counts toward that budget, checked before each command. Cleanup has a separate
five-second child-drain bound. There are no behavior retries.

The sandbox denies by default, allowing system-library reads and owned scratch while
explicitly denying checkout reads. It allows reading the literal root directory for
dyld startup; that grant does not allow reading descendant file contents. It grants no network, preference/Keychain Mach
service access, or child forks. A readable control and a denied checkout read must
both succeed before either mode's entrypoints run. Legacy resource builds selected
plugin engines through `UserDefaults.standard`; slim CLI initialization also needs
its own reviewed boundary. Synthetic `HOME` alone does not isolate defaults. If a
restricted probe cannot initialize, report failure and investigate; do not weaken
it to access live defaults or providers.
Only exit 1 with the exact missing-bundle diagnostic counts as a negative control;
timeouts, crashes, signing failures and other startup errors do not.

Capture stdout/stderr outside disposable scratch through the caller's evidence
mechanism. JSON lines preserve source/build identity, phase outputs/timings, primary
failure and cleanup readback. A final status of zero is required; an intermediate
resource pass followed by cleanup failure is a failed run. Missing macOS or
`sandbox-exec` is unavailable (exit 2), never a skipped pass. Synthetic lifecycle
regressions are run separately with
`bash Scripts/test_verify_packaged_relocation.sh`; they use fake resource/help responses
and owned Python children, not a real bundle, TCC, live stores, or providers.

G-CB1 is a separate, bounded no-prompt query:

```bash
bash Scripts/verify_packaged_relocation.sh --ax-trust-probe
```

It calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt=false`
through the system frameworks, records the boolean and executing Python process,
parent, binary hash, OS and architecture, and exits 3 when untrusted. It neither
requests consent nor changes TCC. A false result holds CB-N1/CB-N3 on an owner-only
Accessibility grant; it is not a failing resource proof. A true result is scoped to
that execution context: a later AX driver must check its own trust without prompting.

`StatusMenuProviderNativeProofTests` and `CodexWorkspacesNativeProofTests` remain
opt-in fixture hosts. Their external-driver journeys require that trust gate and
native visible-action/state evidence. They must use synthetic state and never touch
the installed app, live defaults, Keychain, authentication or provider accounts.
Ordinary CI or resource-smoke success does not establish those journeys. Run local
checks/probes only after the coordinating owner's CPU/test-slot admission; required
delivery checks remain `make test` and `make check`.

## Keychain Prompts (Development)

### First Launch After Fresh Clone
CodexBar does not run a prompt-capable startup Keychain migration. Unified config migration reads retired stores and
clears them only after every source was readable and the new config was persisted. If a source is unreadable, cleanup
and migration completion are deferred to a later launch.

### Subsequent Rebuilds
Ad-hoc development builds can still prompt for browser or provider-owned items because their code-signing identity is
not stable. Use a consistently signed packaged bundle for intentional live credential validation. Routine tests must
use the repository's suppression-safe test harness and never query the real Keychain.

### Why This Happens
- Keychain access control checks the executable's code signature and designated requirement.
- Ad-hoc builds and changed identities may no longer match an existing grant.
- Chromium and provider apps can rotate or recreate their foreign-owned items, replacing prior grants.
- `ThisDeviceOnly` accessibility controls item availability and syncing; it does not repair a code-signature ACL
  mismatch or prevent authorization prompts.

See [Keychain prompts](keychain-prompts.md) for the current user-facing boundary and safe troubleshooting.

## Augment Cookie Refresh

### How It Works
CodexBar checks Augment through the provider fetch pipeline. Auto mode tries the Augment CLI first, then the
browser-cookie web path. The web path reuses cached cookies when possible and imports from supported browsers when
the cache is missing or rejected.

### Refresh Frequency
- Fresh-install default: Adaptive, between 2 and 30 minutes (configurable in Preferences → General). Existing installs
  without a stored cadence retain the legacy 5-minute fallback.
- Minimum: 1 minute
- Cookie import happens automatically when cached cookies need refresh

### Supported Browsers
- Safari, Chrome variants, Edge variants, Brave, Arc variants, Dia, and Firefox.

### Manual Cookie Override
If automatic import fails:
1. Open Preferences → Providers → Augment
2. Change "Cookie source" to "Manual"
3. Paste cookie header from browser DevTools

## Project Structure

Key source, test, and packaging paths (not exhaustive):

```
CodexBar/
├── Sources/CodexBar/          # Main app (SwiftUI + AppKit)
│   ├── CodexbarApp.swift      # App entry point
│   ├── StatusItemController*.swift  # Menu bar icon, menu rendering, and actions
│   ├── UsageStore*.swift      # Usage refresh, caching, widgets, and history
│   ├── SettingsStore*.swift   # User preferences and config persistence
│   ├── Providers/             # App-side provider settings/runtime glue
│   └── Resources/             # Assets and localized strings
├── Sources/CodexBarCore/      # Shared business logic used by app, CLI, and widgets
│   ├── Config/                # Config file model, reader, writer, and validation
│   ├── Providers/             # Provider descriptors, fetchers, parsers, and status probes
│   ├── OpenAIWeb/             # OpenAI dashboard integration helpers
│   ├── WebKit/                # Web session helpers
│   └── Vendored/              # Embedded support code
├── Sources/CodexBarCLI/       # Bundled codexbar command-line tool
├── Sources/CodexBarWidget/    # WidgetKit support
├── WidgetExtension/           # Xcode wrapper for the packaged widget extension
├── Tests/CodexBarTests/       # macOS app/core test suite (XCTest + Swift Testing)
├── TestsLinux/                # Portable and Linux-specific CLI/core tests (target exists on macOS too)
└── Scripts/                   # Build and packaging scripts
```

## Common Tasks

### Add a New Provider
See the canonical [provider authoring guide](provider.md#adding-a-new-provider) for the complete flow.

1. Add the provider identity to `Sources/CodexBarCore/Providers/Providers.swift`.
2. Add the descriptor and the fetcher, parser, settings-reader, or status-probe pieces the provider needs under
   `Sources/CodexBarCore/Providers/YourProvider/`.
3. Register the descriptor from `Sources/CodexBarCore/Providers/ProviderDescriptor.swift`.
4. Add an app-side `ProviderImplementation` under `Sources/CodexBar/Providers/YourProvider/`; implementations can use
   protocol defaults when no custom UI or macOS integration is needed.
5. Add the provider's exhaustive switch case to
   `Sources/CodexBar/Providers/Shared/ProviderImplementationRegistry.swift`.
6. Add icon assets under `Sources/CodexBar/Resources/`.
7. Add focused tests under `Tests/CodexBarTests/` and, for CLI/core behavior that must run on Linux, `TestsLinux/`.

### Debug Cookie Issues

Begin with provider parser tests, stubs, and isolated session fixtures. Browser-cookie
imports and live provider probes require an explicit request; rebuilding the app
does not supply that permission.

For an authorized live reproduction, enable Debug → Logging → “Enable file logging”
or raise the configured verbosity, verify the running bundle, and inspect Console.app
with `subsystem:com.steipete.codexbar category:augment`. Importer messages include
the `[augment-cookie]` prefix. See [Keychain prompts](keychain-prompts.md) before
credential-related diagnosis.

### Debug Menu Bar Placement

Status-item creation checks the item's saved preferred position and its matching legacy key before assigning the
autosave name. Malformed, non-finite, non-positive, and out-of-bounds positions are removed; unrelated items are
untouched. When no display bound is available, finite positive positions are preserved. Isolated placement tests
cover this cleanup without creating status items or changing the user's saved preferences. Passing these tests does
not establish the cause of a position that changes again after launch; that requires runtime placement evidence.

### Run Tests Only
```bash
make test
```

The runner prepares one canonical fixture parent strictly inside this worktree, exports
`CODEXBAR_TEST_WORKSPACE_ROOT`, `CODEXBAR_TEST_SCRATCH_PARENT`, and `TMPDIR`, and removes its owned
parent only after its commands drain. It verifies absence after removal. If process drain or directory
identity cannot be proved, it preserves the parent and reports failure. A parent supplied through
`CODEXBAR_TEST_SCRATCH_PARENT` is borrowed: the runner validates it but never removes it. Its caller
owns final cleanup after all owned children drain. A supplied workspace root must identify this worktree.

For an aggregate command that must keep its original selection and parallelism, use
`./Scripts/test.sh --command swift test --parallel`. This mode runs the command once,
without discovery, sharding, or retries, inside the same fixture-parent and process-drain
lifecycle. It keeps the enclosing CI job's deadline rather than the per-shard timeout.
It rejects discovery/shard selectors. This command mode inherits the same file/Keychain
isolation as the ordinary test runner and does not depend on environment left by a
previous CI step. Removed plugin-engine scripts are not a supported product route.

Direct `swift test` commands require both variables naming existing canonical directories: workspace
root and a strict workspace-descendant fixture parent. Prepare that parent through the invoking
harness, preserve evidence, and remove only that exact owned parent after child-drain proof. Missing,
nonexistent, aliased, or escaping parents fail before fixture allocation; direct tests have no ambient
temporary-directory fallback. Keep the Keychain, Codex-file and session-file isolation flags enabled
for synthetic verification, and remove inherited live/fixture grants as the runner does.

`TestFixtureScratch` supplies allocation bases across all three test targets, including `TestsLinux`
and `TestsPlugin` on macOS, and source defaults that select test isolation. Explicit fixture overrides
and injected in-memory filesystems retain their semantics. Isolated Codex support-directory selection
uses the validated parent; a `TMPDIR` override is retained only when it is an existing canonical path
at or below that parent. An inherited external `TMPDIR` selects the parent instead. Ordinary runtime
path selection is unchanged. This routes repository fixture allocations; compiler, SwiftPM and framework
internal scratch need separate evidence and are not proved contained by these variables alone.

Suite commands retain the default 180-second deadline, including SwiftPM startup and discovery.
The runner reports elapsed time and owned PIDs every 30 seconds even when test output is buffered.
It tracks process birth identities and descendants, including helpers that create separate process
groups or sessions, and drains them before retrying. Separate sessions are allowed: the shell runner
uses them to protect controlling-terminal ownership. The direct command remains unreaped until cleanup
finishes (`waitid` with `WNOWAIT`), preventing reuse of its PID/session. Observed descendant session
leaders can establish ownership of orphaned session members only while a matching live or unreaped
birth identity still anchors that session. Known descendants retain their identities after reparenting;
empty completed sessions retire. If an observed session loses its anchor while unaccounted live members
remain, observation may retain that session as pending only while the direct command is still wait-owned
and running. A nested runner can then finish draining its own child: its unreaped wait handle is not
signal authority for the outer observer, and macOS may hide the exited leader's metadata. Pending members
remain birth-checked even if they change sessions. Uncertainty also follows observed descendants and peers
of a live matching pending session leader, with compatible birth ordering; those identities remain pending
after reparenting or session migration. Unreadable pending metadata fails closed; confirmed exits or replaced
pending births retire without claiming replacements. Pending status grants no ownership or signal authority.
Command exit and every cleanup path require session continuity and fail if uncertainty remains; a detected
replacement session-leader birth still fails immediately, even during observation.
No observation or cleanup deadline is extended. Unavailable metadata for a
known identity also fails cleanup; an unreadable unrelated peer does not abort enumeration.
For the direct child, confirmed metadata absence (ESRCH/ENOENT) can precede a waitable exit on
Darwin. Its unreaped wait handle retains ownership while ordinary polling continues within the
original command deadline. Pending wait status is not completion; permission and I/O errors still
fail. Direct-child cleanup signals require retained wait ownership, even if no birth metadata was
captured. Other PIDs continue to require verified birth identities.

Cleanup sends TERM to verified individual identities, escalates after three seconds, and requires the
owned set to drain within five seconds. Error paths make a final bounded attempt against readable known
identities and reap the direct child, then propagate failure instead of starting another suite/retry.
Initialization failures similarly TERM/KILL/reap the still-owned direct child. Linux treats a zombie
leader with other threads as running. Other PIDs require birth checks before signals, with pidfds used
on Linux when available. macOS descendant signals use `proc_signal_with_audittoken`: a combined native
BSD/unique-identity read must match the tracked birth, then the kernel binds the signal to that PID's
generation while checking the caller's normal signal permissions. A stale generation (including an
exec race) is not signaled; later cleanup attempts can refresh it after matching birth again. Missing
native signal support, permission failures, and I/O errors fail cleanup without a numeric-PID fallback.

This is a bounded metadata polling tracker, not a daemon sandbox. A new session whose leader and attached
ancestry both disappear entirely between observations cannot be discovered reliably. Snapshot enumeration
is not atomic, and unreadable, never-observed descendants cannot be attributed. Initial `swift test list`
discovery/build and Sparkle metadata commands use the same owned-process drain before fixture-parent
cleanup. The 180-second bound applies to each suite/group command, including its startup. `Scripts/test_swift_test_sharding.sh` includes synthetic containment tests; they do not launch
Swift, the app, or provider probes. Its native pthread regression runs only on Linux and uses the system C
compiler; macOS runs the corresponding metadata unit tests and reports the native case as skipped.
macOS also runs native audit-token fixtures: deliberately wrong generations leave owned children alive,
matching identities TERM/KILL and reap them, and unrelated sentinels survive. These fixtures use stop
files and self-expiry, with final cleanup restricted to their unreaped direct children.

Process-cleanup fixtures keep ancestry alive until the real ownership refresh observes matching ready
child identities (and the session-tree grandchild), then acknowledges a private fixture gate before drain.
The direct `waitid` fixture uses the same handshake without reaping its root. Success/failure fixtures keep
their five-second command budget; timeout fixtures keep two seconds. A virtual-clock readiness test proves
one-second startup adds no fixed ancestry sleep. Gate waits are bounded and stop-file aware; helper
self-expiry remains 20 seconds.
The nested failure regression gates the inner drain and controls outer snapshots: the outer observer
sees a live session leader first, then its previously unseen orphan with the exited leader hidden.
Only the inner wait owner drains that orphan; the outer runner must complete without claiming it.
Contract tests also require unresolved sessions to fail at cleanup and reject reused leader births.

Cost performance and fair-scheduling corpora use exclusive initial fixture creation: the scanner only
reads after setup has closed each file. This avoids per-file atomic publication and durability work
without changing corpus contents or scan budgets. The shared atomic fixture writer remains available
for replacement and publication tests.

### Cost scanner CPU regressions

`CostUsageJsonl` finds complete physical LF spans with bounded libc `memchr` on Darwin, Glibc, and
Musl, using the same span algorithm with scalar LF search elsewhere. Borrowed pointers stay inside
the current `withUnsafeBytes` call; search counts and distances fit the existing 256 KiB read chunk.
Complete spans keep the original prefix-copy and flush path. Unfinished chunk suffixes still run the
original scalar JSON tail updater, preserving exact resumable state and EOF validation. CR bytes,
empty-line offsets, independent prefix/max limits, budgets, and cancellation/stop ordering are unchanged.

Persisted Codable checkpoints are a compatibility boundary, including unusual decoded counters.
Skipping tail updates requires a nonnegative line count, safe container-depth arithmetic for the span,
and nonnegative literal indices. Otherwise the same scalar updater runs before the existing flush;
this preserves its checked operations and state when the flush does not reset a negative line count.
Do not replace this guard with checkpoint normalization or a new corrupt-cache recovery policy.

`CostUsageJsonlDifferentialTests` in the portable `TestsLinux` target compares exact bytes, offsets,
sorted full Codable state, callback order, and error domain/code with the frozen e236a21b scalar scanner.
Its bounded default matrix covers every short-input split, threshold/chunk boundaries, mutations,
cross-version resumes, and safe unusual checkpoints. Keep that oracle frozen and the older scanner
oracle independently useful. Full optimized scratch parity must copy the final production source;
prototype results alone do not carry forward through formatting or edits. Scanner parity does not
establish pipeline performance; signed optimized builds and synthetic pipeline timing are separate proof.

The shared scanner remains a parser-hash input. Published `e0b0319de43e22d7` is the immediate tested
compatible predecessor because LF-span scanning preserves persisted semantics, including the priority
cursor changes in #3318. The earlier `7e293e8fc9e25700` and existing predecessors remain supported.
Native adoption retains rows and checkpoints while invalidating old connection receipts.
Pi/OMP still reparses once when the hash changes,
with and without a catalog; subsequent unchanged reads use the current cache. No pricing-key alias is added.

Profile the cost-scan queue separately from the main thread. A busy background scan that later settles
does not establish an infinite loop. Native timestamp conversion uses Foundation's modern ISO parser
for strict RFC3339 input, retaining the previous formatter's millisecond truncation and rounding.
Historical spellings and malformed input keep the formatter fallback. Claude reuses the parsed date
for local day projection only on the strict path.

`CostUsageTimestampTests` compares exact dates with the prior formatter and checks local days, DST,
deduplication, and dated pricing. `CostUsageTimestampOrderTests` and `CostUsageStoreCutoverTests` count
timestamp comparisons: a known ordered prefix needs only the append boundary and new events; unknown
prefixes get one cancellable validation. Keep these assertions deterministic rather than timing gates.
Run these alongside scanner, cancellation, bounded-progress, fork, and performance-gate suites with
the test harness's Keychain and credential-file isolation enabled.

An optimized synthetic check on 2026-08-30 compared main `5a18e8ee9` with this change: three cold
Claude scans of 20,000 messages (5,237,780 bytes) had median CPU time of 3.430 → 1.273 seconds and
wall time of 5.838 → 2.107 seconds, with identical emitted token/cost totals and daily output. This
measures ingestion through the public fetcher, not idle-app CPU or the entire Codex scan pipeline.

Native Codex scans carry an opaque receipt from load to save. `CostUsageStore` owns one decoded persisted
baseline and compact file/count metadata, releasing it on save, superseding loads, mutations, failures,
or scan exit (including cancellation and debounce). Abandoned receipts also release through the actor.
No raw historical SQL snapshot or transaction stays alive across JSONL scanning. Filesystem/device,
anchor, and pending catch-up reconciliation rerun for comparisons; decoded reuse never freezes them.

Reuse requires the same connection generation and database inode, SQLite's open-file identity check,
same-connection `data_version`, own `total_changes`, and schema/parser metadata. Observations bracket
a successfully committed short read transaction. Save checks again under `BEGIN IMMEDIATE`, after
unchanged-path retention; external changes request a rescan without overwriting current content.
Retention that rewrites identical metadata requires a fresh locked semantic comparison. Existing callers
without a receipt read a fresh baseline at save and cannot establish freshness back to an earlier load.

`CostUsageStoreReadWorkTests` counts full load/save cycles: an uncontended unchanged receipt cycle reads
one full snapshot and decodes each usage row once, with one freshness write and no aggregate grouping
visits. Synthetic interleavings cover writer races, mutations, retention, replacement and receipt lifetime.
Initial decoding, semantic equality, filesystem reconciliation, report generation and priority aggregation
still cost work proportional to retained history. These counters do not measure installed-app idle CPU;
refresh cadence, scan budgets, timestamp parsing and incremental-order validation are unchanged.

Claude/Vertex metadata classification searches decoded ASCII strings with case-folded bytes, keeping
the original Foundation lowercase/substring predicate for non-ASCII or noncontiguous strings. Check
the whole string for ASCII before matching; combining characters after a marker can affect the old
predicate. The recursive dictionary/array walk visits dictionaries inside arrays without recursing into nested arrays.
`CostUsageClaudeVertexClassifierTests` compares with the frozen old predicate and checks complete filtered
rows, persisted daily tokens/costs, and reports, including decoded JSON escapes, Unicode boundaries,
nested arrays, and false/numeric metadata flags.

`ClaudeJSONObject` shares a shallow decoded-container view between field extraction and classification;
the parser reuses its message view for primary detection and usage extraction. On Darwin, ASCII-keyed
objects retain immutable Foundation containers and use scoped CF bulk access and type dispatch. Only
JSONSerialization results and their decoded descendants enter that path; arbitrary objects and coerced
entries use Swift casts. CF bridging is Darwin-only, and retained owners outlive all borrowed pointers
and temporary allocations.
Empty containers require no pointer arithmetic. Unicode-keyed objects use the actual conditional
`[String: Any]` coercion at each object boundary, preserving canonical-key collapse and whole-object
mixed-key rejection. The walker visits only the resolved entries. Independent coercions can choose
different collision winners, so tests assert resolved-entry behavior rather than a deterministic winner.
Linux uses the same view and walker with portable Swift coercions, with no CF bridging or separate
pricing path. `ClaudeJSONObjectTests` also belongs to the portable CLI/core test target.

Claude parsing returns only rows and parsed bytes. The scan owns reconciliation across streaming chunks,
parent files and subagents, then builds persisted days from the stored row model; there is no discarded
parser-day aggregation or second normalization. Daily tests exercise the real cache/report boundary.
Removing the unused field in the shared scanner changes the generated native parser hash, while Codex
semantics remain unchanged. Published `494eee446bb2e5f9` is a tested compatible predecessor; existing
predecessors and store receipt logic remain intact. Pi/OMP pricing keys include this hash and therefore
reparse once under the existing invalidation contract, also tested with and without a catalog.

A second optimized synthetic check against main `354191af9` used three fresh-cache scans per provider
with 32–128 KiB text bodies. Median CPU decreased by 3–18% across Claude/Vertex cases (the 3% case is
small); a separate long-provider-string stress case decreased by 73–75%. The isolated decoded metadata
predicate used about half the CPU on ordinary nested metadata. Every daily token component and cost
matched, including the existing unset public request counts. Fixture generation was outside timing;
wall time was recorded separately under host load. These results do not measure idle-app CPU.

Claude and Vertex scans share one synchronous invocation-owned pricing resolver across full/append file
parsing, row normalization, and report repricing. It lazily snapshots the catalog, including an empty
sentinel for unavailable artifacts, at the existing changed-file and nonempty-report preparation points.
An exact report memo hit and an empty inventory with no rows do not load it. The internal standalone
parser now owns one snapshot per parse, optionally supplied explicitly; the cancellable parser takes
that owner directly. It does not reread pricing artifacts between rows.

Normalization and positive/negative catalog lookup memos use exact decoded UTF-8 keys, preserving
Unicode spelling, dated raw versus stored identities, and non-idempotent normalization. Each memo
retains at most 1,024 entries per invocation; after saturation, uncached inputs still resolve normally.
This bounds entry growth, not model-string bytes or scan work. Every row still selects its own dated
tariff and context tier and runs the existing monetary arithmetic. Historical pricing short-circuits
before model lookup. Independent scalar Pi/Cursor/direct pricing retains its uncached resolution path.
Both callers share one private tariff-selection helper whose nonescaping lazy lookup closure runs only
after historical selection. The scalar calls the original normalizer and lookup directly; the scan
resolver supplies memoized resolution. Both use the original monetary calculation.

DEBUG Claude scan metrics count normalization cache misses and actual catalog-model lookups with
positive/negative outcomes; the first lookup still normalizes internally. `repricedRows` continues to
count all rows. Measure through the synchronous scoped recorder because the public dispatch queue
does not inherit TaskLocal instrumentation. Resolver and scanner memo tests exercise cross-file reuse,
snapshot replacement, saturation, exact spelling, and report-only repricing against synthetic fixtures.
The shared pricing source changes the generated Codex parser hash, but Codex algorithms are unchanged;
`6366caa15c925349` remains an explicitly tested compatible predecessor.

### Adaptive refresh fixtures

Heuristics and timer tests seed disabled providers through `testSettingsStore(config:)`, which saves the
file-backed config before settings initialization. They do not replay a synchronous config write for each
provider toggle during setup. The seed preserves provider defaults and explicitly keeps OpenAI web access
off; an existing config would otherwise enable it. Reset-boundary tests then enable only the stubbed Codex
provider. Timer intervals, polling deadlines, and production persistence behavior remain unchanged.

### Claude session fixtures

Profile/reuse and overlapping-capture tests wait for the fixture's expected `Account:` response with idle
completion disabled; PTY command echo alone is not functional completion. The profile/reuse test keeps both
immediate responses and a controlled 0.5-second response delay, beyond the former 0.1-second idle window.
Capture budgets remain two seconds for profile/reuse and five seconds for overlap. Account, environment,
launch-count, isolation, and stale-artifact assertions remain independent of the completion condition.

### Codex credential fixtures

Ordinary tests deny Codex credential-file access at the Codex-owned I/O boundaries, before reads,
existence probes, or writes. Detection uses the actual process name/environment, independently of
the credential environment under test. `HOME`, `CODEX_HOME`, `XDG_DATA_HOME`, and
`CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS` do not authorize files. The disabled live-account test remains
disabled; neither `LIVE_TEST` nor Keychain permission alone bypasses this boundary.

Use `CodexCredentialFileAccess.withFixtureScope(.init(files: [...], roots: [...]))` for an explicitly
owned fixture. Synchronous and asynchronous forms restore the previous scope on return or throw.
Roots use path components, reject symlinks within the fixture, and never implicitly authorize all
of `/tmp`. The `CodexCredentialFixtures` test trait creates and cleans up one owned root per test;
credential/account fixtures allocate their homes under `CodexCredentialFixtures.root`. Promotion
and scoped-refresh containers share that helper. The trait also binds the existing dashboard-cache
URL override to its owned root, so cache reads, writes, and clears stay local to the test.
`_loadForUsageForTesting` adds only its explicit
home fixture to the current scope; configured external roots still need explicit authorization.
Pure parsers and `fingerprint(data:)` need no scope. Default managed-account and workspace-cache
stores use fresh paths below the validated invocation parent in tests; explicit file overrides retain their existing behavior.

Task-local scopes inherit through structured tasks, but not detached work. Capture the immutable
`fixtureScope` and explicitly re-enter it in a detached task when fixture access is required; lost
context fails closed. Never authorize a path just because it appears in an environment dictionary.

`Scripts/test.sh` exports `CODEXBAR_TEST_CODEX_FILE_ISOLATION=1` and removes inherited fixture grants.
Direct test commands that launch children should export the same signal. A child needing files must
receive `FixtureScope(files: ..., roots: ...).childEnvironment(base: ...)` naming only that child's
fixtures; this replaces any inherited grants without changing global environment state. The signal,
scope decoding, and denial are compiled in release builds too. `bash Scripts/test_codex_file_isolation_child.sh`
compiles the actual policy and detector with optimization and without `DEBUG`, then checks denied,
scoped-child, and non-test decisions against synthetic temporary files. It does not build or exercise
the complete release CLI, refresh a real account, or establish isolation for other providers.

The same runtime and inherited Codex-file isolation signal also redirects the scanner's default priority trace
database to a process-local, nonexistent temporary path before consulting the user home. Supplying a fixture
session root alone does not select a trace database. Tests exercising priority metadata should pass an explicitly
owned `codexTraceDatabaseURL`; these overrides and the production `~/.codex/logs_2.sqlite` default are unchanged.
The optimized child-policy proof above also verifies this fallback, independently of Keychain opt-ins.

### Provider session fixtures

Cursor, Augment, Factory, and Notion session stores select a process-local directory below the validated fixture parent under Swift Testing
or XCTest, before creating directories, loading saved files, or repairing permissions. The runtime guard is also
compiled in release builds; allowing real Keychain access does not disable this file isolation. Production filenames
and owner-only persistence remain unchanged.

Persistence tests should construct stores with an explicitly owned `fileURL` and clean up that fixture. Use fresh
writer/reader instances to prove disk reloads. The sharded runner exports `CODEXBAR_TEST_SESSION_FILE_ISOLATION=1`
for child processes; direct test commands that launch children should export it too. This covers these four default
session stores, not arbitrary file access or provider-owned credential databases.

`bash Scripts/test_provider_session_file_isolation.sh` compiles the actual path policy and runtime detector with
optimization and without `DEBUG`, then verifies inherited child isolation and unchanged production-relative paths
against fake Application Support files. It does not launch the app, read real sessions, or exercise a full release CLI.

### WebView ownership regressions

`OpenAIDashboardWebViewCacheTests` uses explicit nonpersistent stores and a DEBUG preparation seam to suspend
acquisitions without navigation. Controlled continuations exercise eviction/replacement, stale completion, timeout
retry, store-scoped invalidation, and lease cleanup after cache loss. Host assertions check one cleanup request and
registration with `WebKitTeardown`; they do not establish WebContent process termination or diagnose CPU/RSS incidents.
The existing headless CI guards remain in place for these AppKit tests. Store-factory fixtures inject nonpersistent
constructors into instance-owned production cache logic and record requested UUIDs to verify legacy identifiers and
profile separation. These synthetic assertions do not qualify actual persistent storage or runtime containment.

### CI Aggregate Contract

The `lint-build-test` check in `.github/workflows/ci.yml` keeps its existing name and requires successful
`changes` and `lint`, plus every platform selected by `Scripts/ci_path_gate.sh`. Its three entrypoints expose
explicit macOS, Linux glibc and Linux musl flags. A selected job must succeed; an unselected job must report
`skipped`. Failure, cancellation, empty, missing or unknown evidence fails verification. Required macOS tests
may defer for a draft, but that still leaves the aggregate incomplete. Whole-workflow cancellation retains
`always() && !cancelled()`, so the verifier does not run in that case.

| Pull-request changed paths | Required compiler/test coverage |
| --- | --- |
| macOS app, widget, native-only executables/resources, native tests | Both complete macOS shards |
| Shared core/CLI/other source, C modules, `Package.swift`, `Package.resolved` | macOS, both glibc architectures, musl |
| `TestsLinux` and adaptive replay test directories | macOS and both glibc architectures |
| Documentation/site assets and explicitly listed portable scripts/workflows | Portable lint |
| Unknown paths, global build/test harnesses or policy changes | All platforms |

The classifier's explicit portable allowlist is the source of truth. It processes deletions and both sides of
renames/copies, unions overlapping requirements, rejects malformed evidence and selects all platforms for an
empty diff. Manual runs and unavailable PR/push bases also select all platforms. Main pushes use the same
platform gates against the previous main head, running the normal profile on each selected platform. Source resources are
classified before Markdown suffixes. Changes to the classifier, aggregate verifier and primary CI workflow
select all platforms. The path partition selects platforms; the [test profile](testing-profiles.md) selects
normal or full compatibility names for the same retained source.

Selected macOS runs require `swift-build-macos` before both shards. It compiles once and distributes a
verified same-run build artifact; workers fail closed on an invalid handoff and execute with `--skip-build`.
See [compiled test handoff](ci-test-build-handoff.md) for runtime compatibility, storage, and cleanup.
The existing selected checks retain their names: `swift-test-macos (0, 2)`, `swift-test-macos (1, 2)`,
`build-linux-cli (linux-x64, ubuntu-24.04)`, `build-linux-cli (linux-arm64, ubuntu-24.04-arm)` and
`build-linux-musl-cli`. Both glibc architectures run the selected profile’s complete portable suite and CLI smoke assertions.
Ordinary PRs build and smoke-test the debug CLI, sharing compilation with debug tests. Main and manual runs
retain the release CLI with static Swift standard-library linking. Selected musl PR builds use debug
configuration with the same pinned compiler, static SDK, target triple and static SQLite; main/manual musl
builds retain release configuration. Both configurations reject dynamic-loader or library dependencies.
Release-only branches and optimizer/link behavior are therefore checked on main/manual runs. Existing Linux campaign step IDs retain their historical `release` label; consult the recorded
CLI build configuration when comparing PR measurements with older runs. macOS retains two complete shards of the selected profile
and groups of four. Portable source/script integrity checks run in lint. Provider plugins, JavaScriptCore integration and QuickJS were removed.

`Scripts/test_ci_path_gate.sh` checks platform partitions, malformed changes, rename/deletion behavior,
result combinations and the workflow's explicit glibc gate/result arguments.

### Native and packaging tier

Native UI, end-to-end and packaging checks are advisory and opt-in. Jones app candidates run by manual dispatch
or the `codexbar-package` PR label; menu candidates run by manual dispatch or `codexbar-menu-candidate`.
PR candidates require a same-repository, non-draft PR and the workflow's existing path filter. Labels remain
active on subsequent source synchronization. Neither workflow runs automatically on main pushes. Candidate
jobs share a packaging concurrency group. A newer eligible PR event cancels that PR's superseded run;
skipped events use unique cancellation groups and cannot cancel an active candidate. Different PRs and
manual candidates do not cancel one another while active. GitHub may replace an older pending candidate
when another candidate queues.

Keep native end-to-end coverage focused on three to five critical user journeys; use parser, state/model and
portable fixtures for the remaining behavior. The existing resource smoke and signed-update fixtures remain
available in the app candidate; the menu candidate retains synthetic menu capture. Resource/package validation
proves bundle identity and entrypoints, not visible native UI behavior. `StatusMenuProviderNativeProofTests`
and `CodexWorkspacesNativeProofTests` remain opt-in and need their separately qualified driver and consent
boundaries described in [Native workflow proofs](#native-workflow-proofs). Advisory failures still need a fix
or tracked issue; they do not silently become required merge checks.

### Coding Conventions and Tests

Keep changes small and reuse existing helpers. Favor typed structs/enums, descriptive
symbols, and the existing `MARK` organization. Use four-space indentation and
120-character lines. Explicit `self` is intentional; do not remove it.

Prefer modern SwiftUI/Observation: `@Observable` models, `@State` ownership, and
`@Bindable` views. Avoid `ObservableObject`, `@ObservedObject`, and `@StateObject`.
Prefer modern macOS 15+ APIs over legacy or deprecated equivalents when refactoring,
with availability handling that preserves the package's macOS 14 minimum.

Treat sibling `async let` tasks as a review red flag when one child is required and
another is optional or best-effort. Prefer sequential awaits or a drained
`withThrowingTaskGroup` that surfaces required failures and contains optional failures.
Crash stacks mentioning `swift_task_dealloc` or
`asyncLet_finish_after_task_completion` require an audit of nearby `async let` usage.

Mirror new logic with focused tests. XCTest files belong under
`Tests/CodexBarTests/*Tests.swift`, with `FeatureNameTests` and
`test_caseDescription` methods. For Swift Testing, prefer backticked sentence names,
not camelCase. Add portable coverage under `TestsLinux` where appropriate.
Use released or clearly fictitious model names in source and tests; never expose
unreleased names.

Headless macOS CI is brittle around live AppKit status/menu tests. Prefer stable
state/model seams such as `MenuDescriptor`, `ProvidersPane`, and
`CodexAccountsSectionState` over live `NSStatusBar` or `NSMenu` construction.
Exercise AppKit wiring directly only when that wiring is the behavior under test.

Formatting commands:

```bash
swiftformat Sources Tests
swiftlint --strict
```

### Verification and Handoff

Root `AGENTS.md` requires `make test` before handoff and `make check` after code changes,
with all reported format/lint issues fixed. `make test` uses the sharded normal-profile runner;
`CODEXBAR_TEST_PROFILE=full make test` explicitly restores all offline suites. See
[test execution profiles](testing-profiles.md) for selection and re-enable instructions.
Add focused `swift test --filter ...` runs for parser/provider fixes when possible;
preserve the runner's Keychain, Codex-file, and provider-session isolation in direct
commands. Never enable live access merely to make a check pass.

Use the existing [runner containment](#run-tests-only),
[adaptive refresh](#adaptive-refresh-fixtures),
[Claude session](#claude-session-fixtures),
[Codex credential](#codex-credential-fixtures), and
[provider session](#provider-session-fixtures) contracts for the affected tests.
The cost-scanner sections own scanner correctness and performance requirements.

If a required toolchain or platform is unavailable, report the checks as unavailable,
not passed. Do not substitute a live probe or app launch.

Keep commits scoped and use short imperative messages, such as “Improve usage probe”
or “Fix icon dimming”; match the existing commit tone. PRs and patches must state the
change, commands run and their outcomes, screenshots/GIFs for UI changes, and relevant
issues or references.

## Distribution

`Scripts/package_app.sh` creates `CodexBar.app` with ad-hoc signing by default.
It defaults to release mode, whose smoke check can launch a copied app; treat this
as runtime validation, not just compilation.

`Scripts/sign-and-notarize.sh` builds and signs distribution artifacts and submits
them for notarization. With the default universal architecture set, its outputs are
`CodexBar-macos-universal-<version>.zip` and
`CodexBar-macos-universal-<version>.dSYM.zip`; `Scripts/release_artifacts.sh` owns
architecture-specific naming.

`make release` only invokes release packaging. Full publication uses the external
helper behind `Scripts/release.sh`. The checked-in release target still names
upstream `steipete/CodexBar`; it does not establish a Jones Systems distribution.
Read [the release process](RELEASING.md) and resolve the target and authority before
signing, notarization, appcast updates, or publication.

## Troubleshooting

### App Won't Launch
```bash
# Check crash logs
ls -lt ~/Library/Logs/DiagnosticReports/CodexBar* | head -5

# Check Console.app for errors
# Filter: process:CodexBar
```

### Keychain Prompts Keep Appearing
Confirm the prompt's requested item and requesting binary, then check for another running or installed CodexBar copy.
Do not validate a fix by querying the real Keychain from routine tests. See [Keychain prompts](keychain-prompts.md).

### Cookies Not Refreshing
1. Check the browser is supported by the Augment provider metadata
2. Verify you're logged into Augment in that browser
3. Check Preferences → Providers → Augment → Cookie source is "Automatic"
4. Enable debug logging and check Console.app

### Main-Thread Hangs

Debug builds start the hang watchdog automatically. To diagnose a release build,
enable it explicitly and restart CodexBar:

```bash
defaults write com.steipete.codexbar debugMainThreadHangWatchdog -bool true
```

Hangs are written to the app log. Hangs over two seconds also request a process
sample under `~/Library/Logs/CodexBar/`. Disable the release opt-in with:

```bash
defaults delete com.steipete.codexbar debugMainThreadHangWatchdog
```

## Architecture Notes

### Menu Bar App Pattern
- No dock icon (LSUIElement = true)
- Status item only (NSStatusBar)
- SwiftUI for preferences, AppKit for menu
- Hidden 1×1 window keeps SwiftUI lifecycle alive

### Cookie Management
- Automatic browser import via SweetCookieKit
- Keychain cache for some imported browser cookies and OAuth/device-flow credentials
- `~/.codexbar/config.json` for provider settings, manual cookies, and stored API keys
- Manual override for debugging
- Browser-cookie import when cached sessions need refresh

### Usage Polling
- Background timer (configurable frequency)
- Parallel provider fetches
- First failure can be suppressed when prior data exists
- WidgetKit snapshot for macOS widgets
