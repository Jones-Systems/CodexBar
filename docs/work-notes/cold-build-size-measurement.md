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
Role: implementation sub-agent. Explicit workstream pin: gpt-6.1-sol/max/default tier; personal
blended_frontier_max revision 10 is inherited background preference and does not replace that pin.

Finish line: ONE scoped non-draft PR against PR41, no merge/install. Root owns continuity, source review,
CI watching and any future hosted experiment. No workflow dispatch/watch/poll, descendants/reviewers, sudo,
protected-data access, tool installation, signing, app/provider launch, runtime/host changes or PR26 integration.
The compile-owner worktree's nine residuals and frozen patches were not read as canonical, edited or staged.

## Evidence and design decisions

Supplied read-only research is sufficient; no feasibility rerun is needed. The files under the compile-owner
evidence directory verified against their supplied hashes: feasibility JSON
`5b8b7b3404cc3ae5757e4933e6a2d13b147b21c5341a88cb89a6ad0e6819f116` and protocol
`d21003cc761a9e5d93519aff4c2093696022fd2de59b2426a0ba6612b613239f`. Adjacent source inventory and
primary-source records were read. Current canonical repository and open PR heads/overlaps were inspected.
The menu workflow path exists on canonical main. Graphify returned an older truncated snapshot; current
exact Git source establishes the implementation. No new tools were installed.

The write cone is the project-specific menu workflow, two new measurement/adapter modules, a new contained
fixture module and this Work Note/Engineering Spec. The separate adapter avoids changing normal packager
defaults or overlapping PR26's protected signing work. Exact historical hash checks and selected-block receipts
make the new harness-to-source mapping reviewable. Product Swift, test-value changes, primary CI and native
handoff compatibility policy are untouched.

## Verification

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
Native macOS proof and the paired measurement remain unavailable/unrun locally; there are no new size or
build-time results. Root alone owns source review, CI observation and any later experiment.
