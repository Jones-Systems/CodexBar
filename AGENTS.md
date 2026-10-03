# Repository Guidelines

## Scope and routes

This is the Jones Systems CodexBar fork. SwiftPM uses Swift tools 6.2 and targets
macOS 14+. The app is macOS-only; shared core and CLI code also support Linux.
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

## Safety and isolation

Never run tests, checks, or ad-hoc validation that can display macOS Keychain prompts.
Live provider probes, browser-cookie imports, `codexbar usage` against real accounts,
and real SecItem reads require an explicit request. Otherwise use parsers, stubs,
test stores, or `KeychainNoUIQuery`. An isolation flag is not permission for live access.

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
