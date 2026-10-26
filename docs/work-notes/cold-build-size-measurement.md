# Work Note — Cold-build/app-size measurement route

<!-- codex-section:begin id="worknote.cold-build-size#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.cold-build-size`

Purpose: Preserve the measurement source lane's binding, authority and validation limits.

Governing artifact: `spec.cold-build-size`

Continuity owner: measurement implementation sub-agent

Consumers: CodexBar root coordinator

Authority effect: none
<!-- codex-section:end id="worknote.cold-build-size#ctx.artifact-header.001" -->

## Binding and authority

The app-created worktree is
`/home/malcolmjones/.t3/worktrees/Jones-CodexBar/work-cold-build-size-measurement-20261025`, branch
`work/cold-build-size-measurement-20261025`, initially clean at
`ba523f60b7161e70a3afd201f87d49dd2b0e37fe`. This lane is sole Git owner/writer. Canonical repository:
`Jones-Systems/CodexBar`, ID `1425008735`, node `R_kgDOVO_oXw`, remote `origin`, base PR41 branch
`work/slim-codex-claude-product-20261024` at that exact SHA.

Native child thread:
`thread:delegated-task:command%3Amcp%3Ae45fd80a-dc8c-4adb-8d56-65b8e6994437%3Adelegate-task%3Acodexbar-cold-build-size-route-solmax-20261025-v1`.
Role: implementation sub-agent. Explicit execution pin: gpt-6.1-sol/max/default tier. The documentation
continuation selects workstream mode blended_frontier_max; personal preference revision 10 was refreshed
separately. Neither mode nor personal preference replaces the exact execution pin.

The original implementation capsule ended at ONE scoped non-draft PR against PR41, with no child merge/install.
That child boundary is historical scope, not an owner hold on root delivery. Root owns source review,
CI qualification and integration. After accepting the concrete source, root dispatched the single observation
recorded below and separately authorized this child's bounded read-only observation and documentation closure.
No additional experiment, child CI watch, merge, install, descendants/reviewers, sudo, protected-data access,
tool installation, signing, app/provider launch, runtime/host changes or PR26 integration is authorized here.
The compile-owner worktree's nine residuals and frozen patches remain untouched.

## Evidence and design decisions

Supplied read-only research is sufficient; no feasibility rerun is needed. The files under the compile-owner
evidence directory verified against their supplied hashes: feasibility JSON
`5b8b7b3404cc3ae5757e4933e6a2d13b147b21c5341a88cb89a6ad0e6819f116` and protocol
`d21003cc761a9e5d93519aff4c2093696022fd2de59b2426a0ba6612b613239f`. Adjacent source inventory and
primary-source records were read. Current canonical repository and open PR heads/overlaps were inspected.
The menu workflow path exists on canonical main. Graphify returned an older truncated snapshot; current
exact Git source establishes the implementation. No new tools were installed.

The original implementation write cone was the project-specific menu workflow, two measurement/adapter
modules, a contained fixture module and this Work Note/Engineering Spec. The separate adapter avoids changing
normal packager defaults or overlapping PR26's protected signing work. Exact historical hash checks and selected-block receipts
make the new harness-to-source mapping reviewable. Product Swift, test-value changes, primary CI and native
handoff compatibility policy are untouched.

## Local implementation verification

Every local test command requires fresh same-host capacity admission and nonblocking acquisition of
`/home/malcolmjones/.cache/test-runtime-portfolio-20261023/benchmark.lock`. No queued waits. Scratch lives
under the repository runner's owned fixture parent, with verified cleanup, rather than shared `/tmp`.

Initial contained fixtures ran 12 tests. Eleven passed; one fixture incorrectly assumed that an inode could
not be reused immediately after deletion. That is not a filesystem guarantee. The test now checks the real
contract: an old phase marker is absent in the newly allocated phase. No implementation behavior or assertion
about cold-state preservation was weakened.

The final focused union passed 31 Python tests (measurement plus existing dependency/widget lifecycle),
six package fixture scripts, and 49 Jones identity checks. It covers both complete historical assembly
layouts, raw/staged byte accounting, identity/channel-none rejection, thin/universal signature observations,
exact source/ref binding, cancellation allocation windows and cleanup/status preservation. Native tool and
short Git-stamp doubles apply only to synthetic assembly fixtures; real measured source is independently
required to be clean at the exact fixed head. Every runner fixture parent was removed with absence verified.
The existing identity script truthfully reports its native Swift proof unavailable because swiftc is absent.

`make test` was attempted and could not compile because `swift` is absent; its fixture parent was removed.
`make check` was attempted and stopped at missing `plutil` (`spawnSync plutil ENOENT`) before any installer.
No tool was installed. Python AST and YAML parse checks, 120-column source checks, specification markers,
181 documentation links and `git diff --check` passed. Normal package_app,
package_widget, Jones metadata, primary CI and native fingerprint bytes match the qualified base exactly.
Native macOS execution remains unavailable locally. The subsequent hosted observation below closes the
initial size/build-time evidence gap; it does not turn unavailable local checks into passes.

## Qualified hosted observation

Root accepted the concrete source at `16ae87423ca9017ef9f42d8a46a18ae6fff2f86a`; its nine required checks
passed in [run 40196388053](https://github.com/Jones-Systems/CodexBar/actions/runs/40196388053).
The separately selected
[measurement run 40199152659](https://github.com/Jones-Systems/CodexBar/actions/runs/40199152659)
succeeded at that exact harness head, attempt 1, workflow `393256428`. It compared only
`91bd5fb4af704da9181212bea636d527a058e615` then `ba523f60b7161e70a3afd201f87d49dd2b0e37fe`.
Later integration heads do not change this historical pair or its helper hashes. One active Mac job took
37m23s; the normal candidate job was skipped. No second dispatch, retry or new campaign was performed.

| Phase | Baseline outer seconds | Product outer seconds |
| --- | ---: | ---: |
| Debug test-products build | 620.658944250 | 498.384087458 |
| Locked dependency preparation | 12.638014959 | 13.590098916 |
| Release build | 376.354822041 | 262.954188000 |
| Release widget | 258.737772625 | 140.462354084 |
| Complete assembly | 4.072669167 | 1.331425959 |
| Per-source command total | 1272.462223042 | 916.722154417 |

Swift internal debug timings were 614.98 → 494.27 seconds; release timings were 374.53 → 260.76 seconds.
Outer timings include fresh resolution/download/planning and process drain. The ten commands totaled
2189.184377459 seconds; driver wall was 2220.684383 seconds, and workflow creation-to-terminal was 2247 seconds.
The observed per-source command total fell 27.96%; this is one baseline-first pair with network, load,
order and OS/SDK page-cache confounds, not a general causal saving or statistical speedup claim.

Exact logical regular-file bytes and product SHA256 values are retained in the frozen JSON inventories:

| Payload | Baseline bytes | Product bytes |
| --- | ---: | ---: |
| Raw release app executable | 65282952 | 39837096 |
| Raw release CLI | 42110984 | 20942904 |
| Raw release watchdog | 58552 | 58552 |
| Stripped staged app executable | 34588120 | 21022168 |
| Stripped staged CLI | 23017464 | 11702008 |
| Stripped staged watchdog | 54440 | 54440 |
| Stripped staged widget executable | 20362176 | 10258896 |
| Complete expanded app bundle | 92034241 | 55578768 |
| Standalone CLI adjacent Core resources | 432040 | 0 |

The expanded bundle fell 87.771 → 53.004 MiB, a 36455473-byte reduction (39.61%). It contains 419 → 227
regular files. Both bundles have nine links with 213 link-payload bytes, excluded from regular-file totals.
The standalone CLI resource row is separate from its binary; build trees, dSYMs and transfer ZIPs are excluded.
Raw and staged rows overlap and must not be added together. Watchdog sizes match but hashes differ.

| Expanded bundle component | Baseline bytes | Product bytes |
| --- | ---: | ---: |
| Frameworks | 2933741 | 2933741 |
| Helpers | 23503944 | 11756448 |
| Main executable | 34588120 | 21022168 |
| Resources | 10192341 | 9588089 |
| Widget | 20813649 | 10275876 |
| Remaining metadata | 2446 | 2446 |

All four phases matched the actual Xcode 26.3 build 17C529 / Swift and SwiftPM 6.2.4 fingerprint
`ba0d494e3bd99ca718c3b866478aecef3929bd982e54bdcc30bc90259845ac4f`. Actual image:
`macos26 / 20261013.0424.1`; macOS 26.6.2 build 25G83; SDK 26.2 build 25C58; arm64 Apple M1 (Virtual).
Both sources retained locked KeyboardShortcuts revision `1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27`,
unchanged Package.resolved and identical preparation/patch hashes. Verification covered 28 historical input
hashes, five harness hashes, four cold-absence assertions, ten command success/drain records, four phase
cleanup absences and final root absence. Both inventories/component totals and all 12 full log hashes matched.

The complete assembly used no new package codesign and launched no app/provider. Nine Mach-O components per
bundle carried existing vendor/linker signature metadata; signature validity was not verified. The assemblies
are non-distributable. Native binary bytes are source-bound harness observations, not independent downloaded
binary rehashes. Test products were built without executing the historical test suites. Successful native
cleanup was observed; full material-build failure/cancellation was not exercised by this successful run.

Durable local evidence is preserved under
`.evidence-cold-build-size-20261025/observation-run40199152659/`: `report.md`, `measurement-summary.json`,
`observation-receipt.json`, `SHA256SUMS` and the verified JSON/text payload. The 31-file manifest SHA256 is
`09628fef308a5acd4a58cab7d7b02bd224f0d06695baf0bf2786abe69f10a8d4`.
GitHub artifact `12602076848` contained 17 JSON/text entries, 3103030 expanded bytes; its ZIP SHA256 was
`cc6e4ff72e419acc96e4b6fe183f32288f723e0f04cb7660cb00ca4e324c62db`.
Digest, entry hashes/CRCs, containment, text/size limits and exact download-scratch cleanup passed.
Frozen evidence remains unchanged. Root owns qualification of the documentation-only successor and integration;
this note makes no claim of PR43 merge, installed-app update or live behavior proof.

## Documentation closure

The bounded successor updates this note/spec and the product, compiled-handoff, native-compatibility and
normal-nightly notes. Historical pending statements are identified as checkpoint evidence; qualified hosted
results supersede their corresponding gates, while unavailable local tools and unobserved schedule triggers
remain explicit. No source, test, workflow, schedule, compatibility policy or helper bytes change.

Documentation links (185), the llms index, three applicable artifact-marker checks and whitespace checks pass.
All 2019 tracked paths outside the six-document scope match the original `16ae874` blob IDs, modes and
symlinks. The frozen 31-file observation manifest verifies unchanged. Fresh per-command admission and the
nonblocking portfolio lock preceded checks; owned scratch absence was verified. `make test` and `make check`
were attempted again and exit 2 at absent Swift and plutil respectively, before native execution or installers.
No tools were installed. Detailed closure checks and publication receipt are retained in
`.evidence-cold-build-size-20261025/documentation-closure-20261026/`.
