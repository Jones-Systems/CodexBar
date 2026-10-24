# Codex and Claude Product Work Note

Artifact ID: work.slim-codex-claude-product
Kind: Work Note
Authority effect: none
Owner: CodexBar product implementation coordinator

<!-- codex-section:begin work.slim-codex-claude-product#continuity -->
## Task and authority

Owner authorized actual product source removal and PR publication. Root thread
`7116f0d2-eb93-407b-9a19-08f15c670ac8` owns merge and cross-lane CI coordination.
This child does not merge or update installed apps. No sudo, credentials, live
provider probes, signing, release, deployment or tool installation is authorized.
Explicit model override: gpt-6.1-sol / max / default service tier; inherited
high_intelligence personal_default revision 8 remains unchanged.

Worktree: `/home/malcolmjones/.t3/worktrees/Jones-CodexBar/work-slim-codex-claude-product-20261024`.
Branch: `work/slim-codex-claude-product-20261024`.
Sole Git owner: product implementation coordinator (this child). Initial clean
HEAD `91bd5fb4af704da9181212bea636d527a058e615`, verified against live PR39.
Stack base: PR39 `work/test-value-bar-pass2-20261024`; its predecessor PR38 head
was `515334773b60c8ff278710d96738d6055ed1a2b0` before the recorded main merge. PR39's five test-removal changes and
empty review/comment results were inspected before base use. PR26 signing and
bootstrap source are excluded; any necessary same-file lifecycle edit is sent
to root as an exact boundary before mutation.

Current Graphify snapshot predates this base; use it only as a navigation hint
and verify relationships in current source. Existing research plus direct source
inspection establishes removal scope; no external provider research is needed.
Native goal ownership stays with root rather than creating a competing child goal.
<!-- codex-section:end work.slim-codex-claude-product#continuity -->

<!-- codex-section:begin work.slim-codex-claude-product#ownership -->
## Write ownership and coordination

- Core leaf: `Sources/CodexBarCore/**` and `Sources/CQuickJS/**`, excluding
  `Sources/CodexBarCore/JonesBootstrapMigration.swift` and `Sources/CodexBarCore/Jones/**`.
  Its integration test scope is `Tests/CodexBarTests/Provider*.swift`, plus
  `ConfigValidationTests.swift`, `BrowserCookieOrderLabelTests.swift` and
  `TokenAccountEnvironmentPrecedenceTests.swift` in that directory.
- App leaf: `Sources/CodexBar/**`, `Sources/CodexBarWidget/**`, `WidgetExtension/**`,
  excluding `Sources/CodexBar/CodexbarApp.swift`, `Sources/CodexBar/Jones/**` and
  `Sources/CodexBar/JonesBootstrapCommand.swift`. Its integration tests are
  `Tests/CodexBarTests/{Menu*,Status*,SettingsStore*,SessionEquivalentForecast*,UsageStore*}.swift`,
  plus `CodexBarWidgetProviderTests`, `PreferencesSelectionTests`,
  `PreferencesPaneSmokeTests`, `ShareStatsTests`, `PaceVisibilityTests`,
  `IconRendererHideCrittersTests`, `IconRendererScreenshotRenderTests`,
  `MetricTextUpdateLayoutTests`, `PredictivePaceWarningTests`, `PopupLocalizationTests`,
  `InlineCostHistoryDashboardLabelTests` and `UserFacingLocalizationCoverageTests`.
  Each named test basename includes `.swift` in the same directory.
- Coordinator: all remaining tests/fixtures, `Sources/CodexBarCLI/**`, Package.swift,
  Scripts/test_profiles.json, feature docs and these artifacts; owns cleared cloud
  and resource-smoke lifecycle hunks in CodexbarApp. Only coordinator stages,
  commits or publishes. Global test transformations finished before transferring
  the exact core/app test scopes; no coordinator writes those scopes while leaves own them.
- Nobody in this worktree changes `.github/**`, CI sharding/campaign scripts,
  build_jobs.py, shared harness/artifact scripts or signing/bootstrap work.

Both implementation leaves completed their source/test cones and returned ownership
to the coordinator. They shared this worktree with disjoint scopes, launched no
descendants, executed no tests/formatters and performed no Git mutations. Coordinator accounts for package
membership and formatter/build effects. Scratch stays in workspace-owned storage;
no /tmp data is needed. Local test starts require fresh telemetry and successful
nonblocking acquisition of
`/home/malcolmjones/.cache/test-runtime-portfolio-20261023/benchmark.lock`.
<!-- codex-section:end work.slim-codex-claude-product#ownership -->

<!-- codex-section:begin work.slim-codex-claude-product#evidence -->
## Evidence and remaining gates

Plan: [Engineering Spec](../engineering-specs/slim-codex-claude-product.md).
Keep spend/history and high-limit scanner/persistence regressions pending root's
separate fleet measurement decision. Before/after source and test accounting,
local tool availability, hosted compilation and comparable app-size/build evidence
will be recorded here as obtained. No binary-size or speed claim is made yet.

Root cleared the cloud-only CodexbarApp edits after inspecting PR26 head
`fe03150aa02651dccd190452e2dc0105c955b4be`: its bootstrap guards are confined
to the entrypoint near lines 21–30, disjoint from cloud lifecycle/state hunks.
Root also cleared deletion of the independent obsolete plugin-resource smoke block,
without touching any Jones bootstrap admission guards. Coordinator alone removes
cloud construction/start/stop/activation and updates
local fleet-state injection, preserving bootstrap/update code. PR38 subsequently
merged as main `7c7acb59f2c49e7a217ce01455df80fb236ca602`; this child keeps
its existing PR39 stack unchanged.

Baseline at `91bd5fb4af704da9181212bea636d527a058e615`: 1201 product Swift
files / 307271 lines, 21 C/header files / 79719 lines, 1059 test Swift files /
368064 lines. Counts include source outside the normal test profile.

Root device audit (installed `72b26fb939e79c68652bf7d69aa36410d053e44b`, not
this source base) found Codex history near the existing 1500-file fixture and
usage-row volume above a 20000-row fixture, with differing windows. This supports
retaining scale proof; no private account content is used by this lane.
The 365-day dashboard catch-up request is a follow-on candidate, outside scope.

Both required local commands were attempted under the shared nonblocking lock
with fresh telemetry (CPU 20.38%, available RAM 34.05 GiB). `make check` stopped
with missing `plutil` (`ENOENT`) before any installer; `make test` stopped with
missing `swift`. Its owned fixture parent was removed and absence verified.
Swift, SwiftFormat and SwiftLint are unavailable; no tools were installed.
Normal/full profile manifest validation, documentation links and llms index
checks pass. A lexical delimiter audit found no new mismatch in the current
changed/new Swift files; it is not compiler evidence.

CI sibling owns these product-dependent contracts: plugin lint/TypeScript and
profile harness assumptions; `Scripts/package_app.sh`,
`Scripts/verify_packaged_app_launch.sh`, `.github/workflows/release-cli.yml`
obsolete core-resource bundle requirements; and the two obsolete runtime/plugin
comment templates in `Scripts/regenerate-provider-manifests.sh`. The latter
currently causes generated-manifest checking to fail only on comments. Packaging
has not been verified. Root will integrate the exact sibling cleanup before
hosted qualification. No duplicated PR38 matched campaign was started. Live publication preflight rechecked
PR39 at the expected head with no reviews/comments, PR26 unchanged at the cleared
head, the canonical repository ID, and absence of an existing product branch/PR.

Shared test fixtures use Codex/Claude and distinct account IDs where the subject
is currency, partial spend, persistence, isolation or refresh ownership. Removed
Mistral/Vertex/Cursor billing adapter and multiple-independent-provider routing
cases have no retained route; generic monetary truth, widget provenance, Claude
365-day history, Codex batch revalidation, publication coalescing, concurrency and
all scanner/persistence scale regressions remain. The Kiro-named shared TTY suites
remain; parser assertions are replaced only where the deleted Kiro parser was
not the cleanup contract. Two shared arithmetic/publication suites were renamed
away from the deleted Antigravity fixture producer. Codex dashboard fixture
`Fixtures/Providers/OpenAI/pro-normal.html` stays, as do CostUsage/PiFamily and
shared process fixtures. The two overview Claude nil-selection assertions still use
an empty synthetic token store; they do not depend on the removed Cursor dormancy
policy. Removed Kiro preference localization assertions leave the shared System
localization checks intact.

Published [draft PR41](https://github.com/Jones-Systems/CodexBar/pull/41), stacked on
PR39. Source removal commit: `39ebae79e3f0dd31e4afc9d2bb2f4dba5a4ac808`.
The first hosted lint job caught a stale parser hash before reaching the pending
CI-sibling contracts. Existing `Scripts/regenerate-codex-parser-hash.sh --write`
and `--check` produced and verified `56738678d8c0245c`; generated-only repair
commit `e0575c44592208fa16d0ac71d7b14044c0b49418` changes no generator semantics.
The final authorized Sol Max reviewer is checking the source commit with that
explicit generated-only disposition. No further reviewers are authorized here.

Exact committed-blob [comparison](../engineering-specs/slim-codex-claude-comparison.json):

| Inventory | Base | Product candidate |
| --- | ---: | ---: |
| Product Swift files / lines | 1,201 / 307,271 | 651 / 193,233 |
| Product C/header files / lines | 21 / 79,719 | 1 / 1 |
| Test Swift files / lines | 1,059 / 368,064 | 734 / 252,333 |
| Lexical Swift Testing declarations | 10,575 | 6,547 |

330 test paths were removed and 5 added, including shared-suite renames; these are
not runtime case counts. Package targets `CQuickJS` and `CodexBarPluginTests`, core
JavaScript resources and JavaScriptCore linkage are gone; no external package was
removed. Provider enum cases go from 69 to 2. Git-blob checks preserve 61 cost
regression suites, 7 shared process files, 4 critical history/identity/catch-up
suites and 19 shared fixtures exactly. The lexical removal sweep covers 1,144
retired top-level declaration names with zero remaining product/test references.
Architecture scanner code is unchanged; 312 catalog entries match 651 shipped
Swift files with zero source-inspection findings. None of these replace compilation.

Comparable executable/bundle sizes and cold-build times are unavailable. Root's
next gate is product-contract integration followed by exact comparable hosted
macOS builds with the same toolchain, architecture, configuration and dependency/cache
conditions, then required macOS/Linux coverage for the final source. Source counts
are not build-time or binary-size estimates. Draft state prevents a readiness claim;
the first automatic run's draft macOS skip and failed lint do not qualify this head.
<!-- codex-section:end work.slim-codex-claude-product#evidence -->
