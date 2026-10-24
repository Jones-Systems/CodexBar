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
- Initial exclusions cover `.github/**`, CI sharding/campaign scripts,
  build_jobs.py, shared harness/artifact scripts and signing/bootstrap work. Root
  transferred the 17 patch01 application paths below to this coordinator; every
  other CI exclusion remains. No signing/bootstrap contract is changed.

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

Root transferred the frozen sibling patch01 application scope at 2:41:56 PM EDT
on October 24, 2026 (message `codexbar-patch01-application-ownership-20261024-v1`),
confirmed the sibling freeze, and reiterated authorization at 2:52:28 PM EDT.
Coordinator verified SHA256
`8ffcef255af71270e4d555692e5e5407867c7bd8f20d8955356947c0141a649b`, the exact
17-path manifest, current branch/HEAD and a clean `git apply --check`, then applied
only patch01. The transferred paths are `.github/workflows/{ci,release-cli}.yml`,
`Scripts/{ci_path_gate.sh,install_lint_tools.sh,lint.sh,package_app.sh,regenerate-plugin-js.sh,regenerate-provider-manifests.sh,regenerate-sucrase-bundle.sh,test_test_profiles.py,test_verify_packaged_app_launch.py,test_verify_packaged_relocation.sh,transpile-plugin-ts.mjs,verify_packaged_app_launch.sh,verify_packaged_relocation.sh}`,
`docs/DEVELOPMENT.md` and `tsconfig.plugins.json`. Four obsolete plugin-tool files
are deleted. The CI workflow hunk only removes TypeScript lint installation;
packaging and relocation distinguish removed Core resources from legacy builds.
Signing/bootstrap functions, entitlements and widget provisioning remain intact.
Root additionally transferred `Scripts/test_ci_path_gate.sh` at 2:58:02 PM EDT
for the stale plugin inventory contract. The active shared-source set is empty,
and its fixture requires no remaining symlink inventory, including a fresh checkout
without a TestsPlugin directory. The five removed shared suites are
`ProviderPluginDetailsParityTests`, `ProviderPluginExtensionParityTests`,
`ProviderPluginParityTests`, `ProviderPluginRuntimeTests` and
`Sub2APIPluginGoldenTests` under `Tests/CodexBarTests` (each `.swift`). Their paths
remain in an explicitly historical gate set so modified/deleted/renamed old inputs
still select macOS and Linux. Every existing historical-trigger assertion and
aggregate/unknown-path gate remains; required job selection is unchanged.
Patch02 is held until root integrates the qualified compile-once descendant;
patch01 alone leaves the old manual full-JSC workflow consumer obsolete. Neither
full-route qualification nor real packaged-app proof is claimed. Root retains
nightly and compile-once integration. No duplicated PR38 matched campaign was
started. Live publication preflight rechecked
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
The final authorized Sol Max review completed against the source commit with that
explicit generated-only disposition. Seven findings were addressed in source commit
`43b9ae226e05f6850da3a0f5bb866135fe8a5a00`: actor isolation, two dangling CLI
declarations, one obsolete Cursor-helper test and three invalid fixture/oracle ports.
No further reviewers ran; native validation of the fixes remains pending.

The transferred cleanup and gate repair are committed as
`f1bae83de761ee383e5845111993671f1ed308cb`. Existing provider manifest regeneration
changed only one generated Swift doccomment; its line count and implementation
are unchanged. Final generator and path-gate checks pass, along with four profile,
17 launch and 18 relocation fixtures; package path/strip/stub-signing/plist/checksum
checks pass. Nine changed shell scripts pass syntax checks, all 179 local document
links and the llms index pass. These fixtures execute only owned synthetic children;
they prove no real app, signing identity or native macOS sandbox behavior. Required
local commands were reattempted after integration: `make check` exits 2 for absent
plutil and `make test` exits 2 for absent Swift. Every test start used fresh admission
below 85% CPU and the nonblocking benchmark lock; owned fixture scratch was removed
and absence verified. No install, live probe or extra review agent ran.

Hosted follow-up at `3e93ca222b70c5ce6c438375ba3ca5b7f3413ca2`,
[run 40123429893](https://github.com/Jones-Systems/CodexBar/actions/runs/40123429893):
both Linux architectures compile, then fail three CLI renderer tests with four
issues. The footer fixtures had stale Cursor/Grok expected names after their
inputs were ported to Claude; only expected provider names change. The original
credit-description integration selected Kilo, whose removed descriptor at the
base explicitly set `primaryDescriptionIsDetail: { _ in true }` (line 88).
Neither retained descriptor enables that policy. Remove only that deleted-feature
case from both native and Linux mirrors (36 lines each), preserving shared footer,
reset-style and terminal-width assertions. The width fixture now uses an equally
long Claude account title. No product formatter or source behavior changes.

The same run's actual lint failure is job 120959693184: the site checker required
a legacy universal-provider banner literal in README while site copy still
advertised 69. Root transferred `Scripts/check-site-locales.mjs` at 3:06:30 PM EDT
for a truthful count and explicit provider-ID inventory contract. All 23 localized
product descriptions, headings and hero titles now name Codex/Claude; 35 obsolete
provider/authoring cards and 28 social tiles are removed. README and visible site
and social inventories must exactly match UsageProvider IDs, including uniqueness;
all independent locale/token/key/asset checks remain. Historical restoration notes,
author attribution and original assets remain. The outdated social banner is no
longer embedded, and social metadata uses the existing 512-pixel app icon. No site
was published. Exact locale checking passes (23 locales, 138 message keys), plus
13 contained actual-checker fixture cases: valid product and historical notes;
missing/extra README IDs; missing/stale/unmarked/duplicate visible cards;
missing/stale social tiles; stale locale count, token drift and missing asset.
The cases prove rejection behavior without a duplicate regex implementation.
Repair commit `b0e2069e515ffecd72de920f0aca96547750ab55` passes the exact node
checker and both changed JavaScript syntax checks, all 178 current local document
links and the generated llms check. Required local commands were reattempted under
fresh admission and the shared lock: `make check` exits 2 for missing plutil;
`make test` exits 2 for missing Swift. Owned fixture/check scratch is removed after
process drain and absence is verified. No manual hosted rerun is dispatched.
This follow-up does not change product source/build-size metrics. It removes two
lexical test declarations; hosted native qualification remains pending.

Root reported completed run `40124736394` at exact
`41b9f8af54d3c989c74e7abb0e96d20d0ead251f`: Linux x64, Linux ARM64 and musl
all succeeded. This qualifies the renderer fixture repair on both Linux architectures;
the aggregate failed only known lint, and draft macOS skips remain unqualified.
The direct lint job `120963638168` log lists exactly 38 SwiftLint errors: five
obsolete suppression rules, 28 long lines and five multiline-argument violations.
Repair `ad4aea4f101ba50a48f38e285d683359f8e81672` removes only the named rules
(and the matching golden-test enable), wraps existing expressions and preserves
all assertion tokens, fixture literals, scanner/persistence limits and declarations.
No renderer behavior changed and no new rule was disabled. Removing source comments
shifts 11 existing catalog line anchors by one; all 312 entries, fingerprints,
counts, anchors, reasons and scanner bytes otherwise remain identical.

Bounded lexical inspection against `41b9f8a` passes for all 12 formatted/comment
files, including exact string-literal byte sequences and balanced code delimiters.
All 312 recorded catalog anchors match. These files have new Git blobs; token
preservation is not exact-blob or new-head compiler/SwiftLint qualification. The
60 cost-suite blobs and four critical history/identity/catch-up suites still match
the original base exactly, and no shared fixture changed. Existing parser-hash
`--check` passes unchanged. Fresh per-command CPU samples were below 85% and each
serial command acquired the nonblocking shared lock. Required `make check` and
`make test` were attempted: plutil and Swift respectively are absent (exit 2), so
no native formatter/test pass is claimed and no tools were installed. Initial
scratch-catalog, fixture-parent and index-command setup errors were corrected;
none ran native tests or prompted product/assertion changes. Details and the final
passing static results are in the comparison record. Owned scratch is removed
after process drain. Root retains the CI watch; no manual run or extra agent is
started. Exact new-head lint/native qualification and the existing draft hold remain.

Exact committed-blob [comparison](../engineering-specs/slim-codex-claude-comparison.json):

| Inventory | Base | Product candidate |
| --- | ---: | ---: |
| Product Swift files / lines | 1,201 / 307,271 | 651 / 193,236 |
| Product C/header files / lines | 21 / 79,719 | 1 / 1 |
| Test Swift files / lines | 1,059 / 368,064 | 734 / 252,279 |
| Lexical Swift Testing declarations | 10,575 | 6,544 |

330 test paths were removed and 5 added, including shared-suite renames; these are
not runtime case counts. Package targets `CQuickJS` and `CodexBarPluginTests`, core
JavaScript resources and JavaScriptCore linkage are gone; no external package was
removed. Provider enum cases go from 69 to 2. Git-blob checks preserve 60 cost
regression suites, 7 shared process files, 4 critical history/identity/catch-up
suites and 19 shared fixtures exactly. In the remaining cost suite, only the
Cursor remote-adapter day-boundary helper test was removed; all other 12 shared
day/currency tests are byte-identical. No scanner limit or persistence-scale proof changed. The lexical removal sweep covers 1,144
retired top-level declaration names with zero remaining product/test references.
Architecture scanner code is unchanged; 312 catalog entries match 651 shipped
Swift files with zero source-inspection findings. None of these replace compilation.

Comparable executable/bundle sizes and cold-build times are unavailable. Root's
next gate is qualified compile-once/patch02 integration followed by exact comparable hosted
macOS builds with the same toolchain, architecture, configuration and dependency/cache
conditions, then required macOS/Linux coverage for the final source. Source counts
are not build-time or binary-size estimates. Draft state prevents a readiness claim;
the Linux/musl successes at `41b9f8a` and draft macOS skips do not qualify the new head.
<!-- codex-section:end work.slim-codex-claude-product#evidence -->
