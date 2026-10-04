---
summary: "Jones Systems fork onboarding, source boundaries, and verification routes."
read_when:
  - Onboarding to the Jones Systems fork
  - Distinguishing fork source from upstream releases
  - Finding development and provider documentation
---

# Jones Systems CodexBar fork

The source repository is [Jones-Systems/CodexBar](https://github.com/Jones-Systems/CodexBar),
a fork of [steipete/CodexBar](https://github.com/steipete/CodexBar).
The [CAAM environment work note](work-notes/caam-environment-control.md) records the
Jones Systems fork foundation and its evidence. Older fork setup and roadmap documents
may describe earlier owners or plans; they do not establish current delivery status.

Source support, automated test evidence, installed binaries, and live provider behavior
are separate claims. Upstream downloads and package-manager installations do not by
themselves prove that Jones Systems changes are present. Verify a running bundle or
CLI's provenance before using it as evidence.

## Start with source verification

Read root `AGENTS.md` and the development guide's
[coding conventions](DEVELOPMENT.md#coding-conventions-and-tests) and
[verification requirements](DEVELOPMENT.md#verification-and-handoff).
The package declares Swift tools 6.2 and macOS 14+. App packaging also uses Xcode for
the widget extension; Linux supports shared-core and CLI work.

```bash
swift build
make test
make check
```

`make test` runs the isolated sharded suite. Run it before handoff, and run `make check`
after code changes. Focused tests must preserve the repository's fixture and child-process
isolation; see the [development guide](DEVELOPMENT.md).

Routine tests and ad-hoc checks must not display Keychain prompts. Live account probes,
browser-cookie imports, real SecItem reads, and `codexbar usage` against real accounts
require an explicit request. CodexBar is not guaranteed to be prompt-free: signing changes
and provider/browser-owned items can still cause prompts. See
[Keychain boundaries](keychain-prompts.md).

## Find the owning module

| Area | Source |
| --- | --- |
| App state, menu bar, and preferences | `Sources/CodexBar` |
| Shared configuration, providers, parsers, and usage logic | `Sources/CodexBarCore` |
| CLI commands | `Sources/CodexBarCLI` |
| Widgets and their packaging wrapper | `Sources/CodexBarWidget`, `WidgetExtension` |
| Native and portable tests | `Tests/CodexBarTests`, `TestsLinux` |

Use the [architecture overview](architecture.md), [provider authoring guide](provider.md),
[provider inventory](providers.md), [CLI guide](cli.md), and [plugin guide](plugins.md)
for the relevant source surface. A provider entry or command definition is not proof
of current account access or live service availability.

The fork contains CAAM environment configuration and snapshot-refresh foundations.
Those models and controls do not establish live remote account switching.
The existing Codex `Active` account selects usage observation; `System` promotes
the default local auth account. Neither label proves that an already-running Codex
process has switched credentials. Consult the
[CAAM work note](work-notes/caam-environment-control.md) for the boundary.

## When an app bundle is needed

Use bundle validation only for behavior that requires it and when its runtime effects
are authorized. `Scripts/compile_and_run.sh` terminates existing CodexBar instances
and matching Claude probes, can inspect signing identities, packages, relaunches,
and checks survival. Tests run only with `--test`.

`Scripts/launch.sh` also terminates existing instances. Release packaging through
`Scripts/package_app.sh`, including its default invocation and `make release`, invokes
a smoke check that can launch a copied app. Some Makefile targets still contain broad
termination commands and a maintainer-specific absolute path.

Read [runtime validation and command effects](DEVELOPMENT.md#runtime-validation-and-command-effects)
before using these wrappers, and verify the freshly built running bundle. A package smoke
check does not replace interactive UI or live provider evidence.

## Releases and contributions

The checked-in release manifest still targets upstream `steipete/CodexBar` and its
signing/feed configuration. Jones Systems source ownership does not turn that into
a Jones Systems publication route. Resolve the intended target, external release
helper, matching signing configuration, and authority through the
[release guide](RELEASING.md) before release work.

Keep changes and commits scoped, preserve unrelated work, and include commands and
outcomes in the handoff. UI changes need screenshots/GIFs. Verify the intended repository
and base before opening a contribution; do not infer them from historical fork examples.
