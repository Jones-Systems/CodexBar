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
Explicit model override: gpt-6.1-sol / max / default service tier. Initial inherited
personal_default was high_intelligence revision 8. The resumed local read observes
temporary blended_frontier_max revision 10; the explicit Sol Max task pin remains
in force and no shared preference or thread selection was changed.

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
  transferred the 17 patch01 application paths and later the exact qualified
  PR40 source plus frozen patch02's seven paths for integration. Those paths are
  recorded in the comparison; all other CI/signing/bootstrap exclusions remain.

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
At the patch01 checkpoint, patch02 was held for qualified compile-once integration;
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

Initially published [draft PR41](https://github.com/Jones-Systems/CodexBar/pull/41), stacked on
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
started. At that checkpoint, exact new-head qualification and the draft hold remained.

Root resumed this lane after qualifying exact PR40
`951c99a96b052e1a70898e75330554403bb643b3` in run `40148474449`: all nine
checks succeeded, including producer `121034849021` and shards `121037780364` /
`121037780442`. Root observed complete-fingerprint verification across runner
images and matching discovery SHA256
`67d0307bbff37082f0df4ff1e1a95181e8bacf43d886e13801fd28f72216a49b`.
This is prerequisite evidence for that exact source, not qualification of PR41.
Root's bounded transfer authorizes ordinary local merge, patch02 consumption,
normal publication and removal of the draft hold; no remote PR merge, install,
extra agent/reviewer or manual campaign is authorized.

Ordinary merge `5f4dc85a5cf8421bb5913ec544c218da56353531` has exact parents
`f134f56e8fee597de1822688eac6530cd01149ed` and qualified `951c99a`. Three
conflicts in AGENTS.md, Scripts/lint.sh and docs/testing-profiles.md preserve the
product removals and compile-once/normal-nightly contracts. The nightly behavior
is already in the qualified descendant; no separate merge of historical nightly
commit `0110a56430470106ad7ffed6c96707d3eb5cc636` is needed.

Frozen `02-after-compile-once.patch` SHA256
`1633958a3be59d768be2afc3722c71146c047a84db27cd043a69ada774af6d77` was
reverified against its retained manifest. Actual merged-tree apply checking found
two expected context collisions: Scripts/test_swift_test_artifact.py and
docs/ci-test-build-handoff.md. Five clean paths apply directly; the full-profile
method and handoff paragraph are adapted narrowly. All surrounding native fixture
bytes and four qualified artifact/native/aggregate implementation/test files stay
identical. The workflow input description now truthfully says both profiles select
retained Codex/Claude tests. Patch02 removes only the retired JSC worker route,
its engine wrapper and four wrapper-only tests. Full still proves exact profile
identity, skip-build discovery/execution and cleanup. Nightly remains 05:00
America/New_York with normal profile and separate concurrency; no schedule is
activated on this task branch. The sibling retains its frozen handoff until root
confirms consumption; this lane does not clean another worktree.

No product Swift, Swift test, Package.swift, dependency, resource or profile-manifest
blob changes during this integration. The spend/history scale, identity, quota,
account/auth, offline fallback and shared TTY protections remain intact. The first
check admission found the shared benchmark lock busy and started no test; ready
source/specification/evidence work continued without waiting on that lock.

Patch02 consumption commit `ab357f8d874326331e6a32c0abe0bc2ce310287b` changes
only its seven declared paths. Read-only source inspection passes for seven
Python AST files, three shell syntax files and workflow YAML using the existing
PyYAML BaseLoader. The parsed job inventory and normal nightly schedule are
preserved; retired JSC runtime entrypoints are absent. Git whitespace inspection
passes. Across three final admissions separated by ready source/evidence work,
the shared benchmark lock remained busy. No affected fixture, generator, profile
validation or make command started in this resumed slice, and no queued wait was
created. These checks are deferred, not passed. Swift/plutil/formatters remain
absent; the prior make attempts and portable passes remain tied to their recorded
older revisions. Coherent source is published for automatic CI with the draft hold
removed; root owns the exact-head watch and subsequent fixes. This transition does
not merge a remote PR, activate nightly scheduling or establish native/app-size
success. Owned check scratch is removed after evidence preservation; the frozen
sibling transfer remains intact.

Root's replacement qualification at `1d9787f8b4075068f3282cb723e42170a6e702c3`
failed SwiftFormat in [run 40151412652](https://github.com/Jones-Systems/CodexBar/actions/runs/40151412652),
producer `121044538055`, before compilation/native preflight. The saved log reports
210 rule diagnostics, 65 of 1346 files requiring formatting and 4 skipped.
Linux `lint-linux` invokes SwiftLint and portable/JavaScript checks, but no
SwiftFormat; the macOS producer's `lint-macos` invokes the pinned SwiftFormat
0.61.1. The saved log confirms that version. There is no evidence of version drift;
Linux lint success did not cover this gate.

Scoped repair `cbada66dac0fd4f844ec594c142f09c67d6e740b` changes only the 65
reported Swift paths: blank lines,
indentation, brace/property/collection wrapping and comment classification, plus
the explicitly reported redundant/hoist rules. No rule/configuration or check gate
changes. Source-only lexical inspection compares full raw/multiline/interpolated
literal tokens and code tokens against `1d9787f8`: 52 files retain every code token;
all function names and 467 edited-file `@Test` declarations remain. All literal
bytes match in 64 files; the only changed literal is the architecture catalog's
relative `codex@5` to `codex@4` offset after removing one blank. The 312 exact
anchors match current source, with 32 line-number updates; scanner code is unchanged.
No assertion, fixture value, numeric limit or provider-isolation branch is changed.

The non-whitespace review is explicit in the comparison: directly return an
unmutated descriptor array; remove one static qualification without shadowing;
use five single-expression implicit returns; delete three empty, nonconforming
extensions; remove unused throws/async effects from two tests whose bodies lack
the corresponding work; and hoist the sole throwing argument's try to its containing
expression without changing arguments, evaluation order or propagation. This is
bounded source evidence, not Swift AST/compiler or native test evidence.

82 paired indent/trailing-space diagnostics refer to already-empty lines inside
CLI help and the RPC test's embedded script. Their raw literal bytes are preserved.
The diagnostics alone do not establish whether these paired reports persist after
surrounding normalization; the next actual pinned formatter run must decide. No
local formatter pass is claimed. Existing unrelated legacy-provider comment wording
near the single-expression returns is outside this formatting-only repair.

Fresh admission permitted one serial process for each command, and the shared
nonblocking lock was acquired. Parser hash and provider generator `--check`, normal
and full profile validation, and Git whitespace checks pass. Required `make check`
and `make test` were attempted and stop at missing plutil and Swift respectively
(exit 2); no installer, compiler or native executable ran. The test runner removed
its owned fixture parent and verified absence. No tools were installed. The
comparison stores the fresh CPU/RAM samples, exact blobs and semantic dispositions.
Sixty cost suites, four critical history suites and seven shared process source
files retain their existing exact-base proof; fixture files are untouched. Reported
TTY test files have whitespace changes, so old whole-file blob identity is not
claimed for those tests. All harness/workflow/native-fingerprint files, scheduling
and frozen consumption records are unchanged in this repair. Root owns the next
normal automatic exact-head CI gate; no extra watcher, manual run, agent, review,
remote merge or host effect is started. App-size/cold-build evidence remains absent.

Root's next saved [run 40153295699](https://github.com/Jones-Systems/CodexBar/actions/runs/40153295699)
at `88d766182` reports only three residual diagnostics in two files, still before
compilation/native preflight. No CLIHelp/RPC literal diagnostics remain; their raw
bytes stay intact. Repair `38d63baa0375809b36f79bd7770a301a78128768` inserts lowercase `self.` on the
existing static cost-forwarding call and outdents two catalog reason values by
four spaces. This matches unchanged `--self insert`, the same-file static
forwarding context and the pinned [redundantSelf rule](https://raw.githubusercontent.com/nicklockwood/SwiftFormat/0.61.1/Sources/Rules/RedundantSelf.swift);
uppercase `Self.` belongs to a separate rule. The enum metatype, method/arguments,
closure, await, all literals and tests are unchanged. Exact source substitution
and all 312 catalog-anchor checks pass; catalog metadata/scanner bytes remain.
Fresh serial admission and the nonblocking lock allowed the affected checks.
`make check`/`make test` again stop at missing plutil/Swift (exit 2), before any
installer/compiler/native executable. No native formatter pass is claimed.
Only these three source lines and existing evidence change; source/test file,
line and declaration counts, all harness/native/schedule/frozen-consumption bytes
remain unchanged. Product/test byte counts change by +5/-8 from qualification
and indentation only. Root retains normal automatic exact-head CI watching.

At PR head `504398c14944516191d9b162135f504634f3deb9`, root's saved
[run 40153719090](https://github.com/Jones-Systems/CodexBar/actions/runs/40153719090),
producer `121050508845`, passes SwiftFormat (0/1346 files, 4 skipped) and complete
native-tool preflight with `build_allowed=true`. Its tested PR merge checkout is
`2cf0e8d9341f19223ce3173ad84fba6eed92dda1`. Compilation then reports two distinct missing
members, repeated across compilation: obsolete Alibaba startup initialization and
the shared enabled-provider-instance predicate. Shards skip because the producer
fails; root reports no separate aggregate defect. This is failing-before compiler
evidence, not successful product compilation.

Repair `ffaebabdba0c0394bc0ebd6fa3a42e53c008763d` removes only the orphaned Alibaba initialization call.
At base `91bd5fb4`, that deleted helper in
`Providers/Alibaba/AlibabaCodingPlanSettingsStore.swift:58` only auto-enabled
Alibaba from its token and wrote its migration marker. The shared instance
predicate lived inside deleted `UsageStore+UserPlugins.swift:7`; its original
Codex/Claude branch called `isProviderAvailable(provider, now: now)`. Restore that
branch in `UsageStore+Accessors.swift`, with an explicit false result for unknown
IDs before any availability/credential lookup. Keep the enabled-list filter and
the complete existing availability/environment/token-account/cache policy unchanged.
A bounded sweep of all nine methods from these two deleted files finds no other
remaining caller; only the restored predicate and existing call remain.

One added parameterized regression covers both retained providers: independently
available providers remain in background work, both stay listed for display,
unknown IDs never consult another provider, and disabling the available provider
excludes it. It uses dictionary-backed defaults, explicit in-memory stores and
contained config/account paths, disabled keychain policy/detection, testing startup,
a unique owned fixture root, watcher shutdown and failure-reporting cleanup. All
pre-existing test source in the coverage suite is byte-identical around this
addition. No test is removed, skipped or weakened. Its execution awaits native CI.
Two catalog line pins move by five; all 312 anchors match, and all other metadata
and scanner bytes remain unchanged. Parser/provider generation checks and both
profile contracts pass. Fresh telemetry/nonblocking serial lock checks pass source
inspection; required make commands stop at missing plutil/Swift (exit 2) before
installer/compiler/native tests. No local native pass or installed tools are claimed.
All harness/native/fingerprint/schedule/frozen-consumption bytes and retained
cost/history/process/fixture proofs remain intact. Root retains automatic exact-head
CI watching; no manual run, extra agent/review, remote merge or host effect occurs.

Exact committed-blob [comparison](../engineering-specs/slim-codex-claude-comparison.json)
at source revision `ffaebabdba0c0394bc0ebd6fa3a42e53c008763d`:

| Inventory | Base | Product candidate |
| --- | ---: | ---: |
| Product Swift files / lines | 1,201 / 307,271 | 651 / 193,218 |
| Product C/header files / lines | 21 / 79,719 | 1 / 1 |
| Test Swift files / lines | 1,059 / 368,064 | 734 / 252,332 |
| Lexical Swift Testing declarations | 10,575 | 6,545 |

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

Comparable executable/bundle sizes and cold-build times are unavailable. Following
source/harness closure and removal of the draft hold, root's next gate is exact-head
automatic macOS/Linux qualification, then exact comparable hosted macOS builds
with matching toolchain, architecture, configuration and dependency/cache conditions.
Source counts are not build-time or binary-size estimates. Prerequisite PR40 success,
old PR41 Linux/musl successes and draft macOS skips do not qualify the new head.

Test-module closure repair starts from verified clean sole-owned head
`7215b63bec5f50e4612da7bda647b4e0b90b0349` and matching open, non-draft PR41.
Root's saved run `40154587231`, producer `121053186896`, passes SwiftFormat
(0/1346 files, four exclusions) and native preflight, then reports 46 unique test
compiler diagnostics across 17 paths. These diagnostics include inference cascades;
no test execution result is established. Root retains hosted watching.

Bounded plan: preserve all Claude metadata/classifier/parser/scanner methods and
fixtures by selecting the retained scanner's explicit Vertex inclusion/exclusion
filter under the Claude cache identity. Four previously exact cost-suite files
will change; refresh the exact-blob proof and preserve method-level assertions,
fixture bytes, limits and the unchanged remainder. Keep the forecast history
fixture pure/nonisolated, the shared Codex/Claude cookie/manual-source and widget
config-churn assertions, native-profile/fleet dispatch, and generic cost styling.
Build localized SPEND screenshots from synthetic retained providers with distinct
IDs. Remove only six individually identified feature-only methods: Copilot fallback
source switching, the plugin pane's Catalan label, the OpenCodeGo estimate capture,
two hook status transport methods, and MiniMax API-region persistence. No retained
quota/auth/TTY/fallback/accounting behavior or scale limit is reduced. The 17 paths
in the saved diagnostic list and this existing spec/note/comparison are the write
cone; no product, harness, native artifact, schedule or signing changes are planned.
Scratch is owned at `.build/slim-product-work/test-compile-7215` and is removed
after durable evidence/publication. No tools, agents or manual campaigns are started.

<!-- codex-section:end work.slim-codex-claude-product#evidence -->
