# Repository Guidelines

## Scope and routes

This is the independent Jones Systems CodexBar repository. SwiftPM uses Swift
tools 6.2 and targets macOS 14+. The app is macOS-only; shared core and CLI code also support Linux.
Source support does not establish installed-binary behavior or live provider availability.

- `Sources/CodexBar`: app state, menu bar, settings, and rendering.
- `Sources/CodexBarCore`: shared provider, parsing, configuration, and usage logic.
- `Sources/CodexBarCLI`, `Sources/CodexBarWidget`, and `WidgetExtension`: CLI and widgets.
- `Tests/CodexBarTests` and `TestsLinux`: native and portable coverage.
- `Scripts`: build, test, packaging, and release helpers.

Read the relevant sections before acting:

- Source/test changes: [coding conventions](docs/DEVELOPMENT.md#coding-conventions-and-tests)
  and [verification and handoff](docs/DEVELOPMENT.md#verification-and-handoff).
- Build/run or UI validation: [development quick start](docs/DEVELOPMENT.md#quick-start)
  and [runtime validation](docs/DEVELOPMENT.md#runtime-validation-and-command-effects).
- Local builds and tests: [compiler resource limits](docs/compiler-resource-limits.md).
- Claude menu changes: [profile menu map](docs/ui-map/claude-profile-menu.md).
- Credential/session tests: the applicable fixture section in the
  [development guide](docs/DEVELOPMENT.md).
- Provider changes: [provider authoring](docs/provider.md).
- Fork onboarding and provenance: [fork quick start](docs/FORK_QUICK_START.md).
- Credential prompts: [Keychain boundaries](docs/keychain-prompts.md).
- Release work: [release process](docs/RELEASING.md).

Keep changes small and reuse existing helpers. Use SwiftPM and the provided scripts;
do not add dependencies or tooling without confirmation. Root zips and appcast files
are generated release artifacts; avoid editing them outside release work.
`CLAUDE.md` remains a symlink to this file.

Always run `make test` before handoff. After any code change, run `make check` and fix
every reported format/lint issue. Report unavailable or failed checks truthfully.

## Delivery and local app updates

M Jones authorizes routine requested CodexBar changes through source completion,
PR publication, applicable CI repair, merge, and the local Jones app update.
Do not stop at an open green PR or ask for separate routine merge or installation
confirmation. An explicit later review-only or no-merge instruction overrides this
finish line. Preserve real native consent, failed checks and unknown-effect gates.

The standing merge binding is `Jones-Systems/CodexBar`, repository ID `1425008735`,
node `R_kgDOVO_oXw`, base `main`, using merge commits from `work/`, `docs/` or
`t3code/` branches. It applies to PR #7 and subsequent routine requested changes;
the migration's historical PR #1–#5 limit does not restrict this binding.
Before merging, verify the exact open non-draft head, mergeability, changed-path
scope, current native review requirements, and resolution of every review thread.
No independent review is required by default. Retain documented finding deferrals.

Require successful applicable checks from GitHub Actions app ID `15368`, workflow
ID `388934113`, for the exact candidate: `changes`, `lint`, both
`swift-test-macos (0, 2)` and `swift-test-macos (1, 2)`,
`build-linux-musl-cli`, `build-linux-cli (linux-x64, ubuntu-24.04)`,
`build-linux-cli (linux-arm64, ubuntu-24.04-arm)` and `lint-build-test`.
Missing, cancelled or old-head checks do not pass. Send the full qualified head
through GitHub's expected-head guard, without bypass or branch deletion; verify
the merged PR, merge parents and inclusion in canonical `main`. Preserve the
legacy remote and use the verified canonical remote for local synchronization.

### Required and advisory CI checks

`changes`, `lint`, and `lint-build-test` are required on every non-draft PR.
The two `swift-test-macos` shards, two `build-linux-cli` architecture jobs,
and `build-linux-musl-cli` are required when their checked-in path gates select
them. An explicit matching gate may permit a skipped platform job; a missing,
failed, cancelled, or unexplained skipped job never satisfies the aggregate.
The aggregate must validate all selected jobs on the current head. Keep the
GitHub Actions app and workflow identity requirements above. Selected musl PRs
compile debug with the pinned static SDK; main/manual runs compile release.
Both must verify static linkage. Release-only compilation is a main/manual check.

Every other check is advisory, including Jones app/menu candidates, native
workflow proofs, release artifacts, and manual performance campaigns. An
advisory failure needs repair or a tracking issue but does not hold a merge.
These declarations do not change GitHub rulesets or branch protection.

Aim for push-to-required-green median at most ten minutes and p90 at most
twenty minutes, including queues, with each required job at most 390 seconds.
Record measured exceptions and their causes; do not reclassify compiler or
unit coverage as advisory merely to claim the target. Scope macOS PR/push jobs
to the paths they prove, cancel superseded PR runs, and keep packaging opt-in.
Keep the native tier to three to five critical journeys, advisory and opt-in
by label or manual run until a suitable scheduled route is qualified.

Right-size tests by behavior and retained coverage. Remove redundant,
superseded, obsolete, trivial, or disproportionate cases in separate removal
changes with reasons. Diagnose failures before changing a test; never delete,
skip, retry, or weaken one to obtain green. Preserve supported-platform and
provider-isolation contracts.

Normal test execution uses the owner-scoped Codex/Claude profile in
`Scripts/test_profiles.json`; see [test profiles](docs/testing-profiles.md).
Unused-provider, hook, plugin and iCloud test source stays available through
`CODEXBAR_TEST_PROFILE=full` and the manual CI full input, with no automatic
nightly. Preserve shared account, persistence, resource, privacy/security and
relevant regression coverage. CLI-dependent coverage remains normal until its
usage boundary is confirmed. Product/compiler checks retain their required
status above; profile selection does not change job identity or aggregation.

For app changes, build the tested source with the existing local Jones identity
(`com.jonessystems.codexbar`) and verify its bundle, architecture and signature.
Replace only the identified installed Jones app after a normal graceful quit,
retain its previous bundle for rollback, preserve current preferences, open the
installed copy and verify its executable/build identity. Use the inspected
packaging path with its automatic launch smoke skipped, then the exact app open;
do not use broad process-killing wrappers. A documentation-only change needs no
replacement when the installed app's source bytes already match the delivered code.
This authorization does not include stock-app replacement, credential copying,
account switching, live provider probes, tool installation, sudo, public signing,
notarization or release, or propagation to other machines. Keep original trial
limitations and native authentication boundaries intact.

## Safety and isolation

Never run tests/checks or ad-hoc validation that can display macOS Keychain prompts. Live provider probes, browser-cookie imports, `codexbar usage` against real accounts, and real SecItem reads must be explicitly requested; otherwise use parser tests, stubs, test stores, or `KeychainNoUIQuery`.
An isolation flag is not permission for live access.

App-group migration tests must inject dictionary-backed defaults, both snapshot URLs,
a synthetic home, and a contained recording FileManager. UUID defaults suites and
Keychain isolation flags do not isolate defaults search domains or filesystem access.
Ordinary SettingsStore tests must not discover shared defaults or run app-group migration.
Load the development guide's relevant fixture section before credential or session tests.

Prefer CLI/focused tests for provider, parser, and settings behavior that does not need
an app bundle. Build/run wrappers can terminate processes, inspect signing identities,
package, and launch an app; release packaging also invokes a launch smoke check.
Read their documented effects before use. Documentation and script availability do
not authorize process termination, live account access, signing, or publication.

## Provider contracts

Keep provider data siloed: never display identity or plan fields from another provider.

Claude CLI status lines are custom and user-configurable; never use them for usage parsing
by default. An explicit user-enabled statusLine JSON feed is permitted (owner ruling,
#2733): it must be off by default, clearly labeled as sourced from the user's own
statusLine configuration, and fail soft when the format drifts.

Default cookie imports to Chrome-only when possible to avoid other browser prompts;
override through the browser list when needed.
