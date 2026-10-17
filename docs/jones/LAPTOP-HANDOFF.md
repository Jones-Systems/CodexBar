# Laptop native verification and continuity handoff

Authority effect: none. Source stays on VPS. Laptop thread
`506fc1fd-d94f-4616-84f4-7751eda0aec8`, environment
`8750edf7-486b-41ac-81ce-cd50dfeb71eb`, owns continuity, native verification,
trial disposition and eligible merges. No live authentication, installation or switching
operation is granted by this handoff.

## Interim compile/unit candidate is available independently

Use the exact full published SHA in the accompanying interim handoff. Its integrated
source checkpoint is `45ac35cc586449f59976652f0f4b059c1a09073e`; later commits change
documentation only. It contains the two direct Swift compiler corrections, with all67
changed-source hashes in final-source-native-candidate.json (including TestsLinux).
Relative to failed84c, only ClaudeNativeProfileIntegrationTests.swift and
JonesProviderScratchTests.swift changed among Swift unit inputs. The throwing load is
outside #expect; diagnosed task closures use explicit Sendable captures. Assertions
remain intact. Formatter passed61 integrated Swift files; native compile is still unrun.

The production `make test` route uses Scripts/test.sh and does not invoke the Python
collector. Laptop may bind this INTERIM exact head for the accepted isolated serial
compile/unit verification, keeping its checkout immutable until terminal. Collector
normal-completion repair is separate and remains HELD: do not run ownership live or
scratch-parent collector scripts. VPS continues that source work in its isolated
worktree; later final qualification must reconcile exact unit-input hashes. Do not
wait for collector completion to start this independent unit lane. No extra reviews,
installation or live operations are needed/granted. Existing fixture admission,
one-parent scratch lifecycle, resource gating and honest full/partial reporting apply.

Failed84c remains historical: make test exit2after1057.89s, zero selections/retries;
macro batch-cascade remains inference, not proved. Identity46 passed oldhashes;
provider compile failed missing package-scoped TestProcessSafety, now source-addressed
along with the sibling Codex child. Those standalone proofs may be considered separately
under their accepted native-fixture lane; no collector rerun is requested. Prior child
explicit inner reap remains unproved, but outer known-child drain/no-live-writer and
old parent cleanup have been reconciled. No oldPID action is authorized.

The original source-ready text and commands below describe historical/full qualification;
the interim scope above controls until replaced. Collector-linked commands remain held.

## Exact candidate and ownership

Source is ready for native verification. Use the **exact published PR12 head in the
accompanying VPS source-ready message**, whose source checkpoint is
`75c03d065bc14c641228da117724f88734cb6027`; subsequent commits contain documentation only.
PR12: https://github.com/Jones-Systems/CodexBar/pull/12,
branch `work/codexbar-trial-identity-20261016`, base `work/fleet-auth-discovery-20261016`.
Its exact PR11 parent is `c0f7ffa78afb8d5016404461495ec9a469cf8232`, base fork main.
PR11: https://github.com/Jones-Systems/CodexBar/pull/11.

Verify ancestry, cleanliness and every source hash in
`docs/review-evidence/final-source-native-candidate.json` before advancing the dedicated
non-main laptop checkout. Root remains sole Git owner of declared VPS worktrees; no
laptop source edits or duplicate builders. Preserve historical 55197235, 21c3456 and
44a43f59 evidence and existing worktrees. This is not merge, installation or runtime success.

## Included source and evidence

The candidate includes Authfleet discovery/System Account copy, auth cancellation/drain,
account order and CAAM removal; coherent collapsed active account and five initial
Codex accounts in both flat and workspace-grouped menus; trial TIR001/TIR002 repairs;
MiMo reader/writer agreement, retained diagnostics and provider scratch ownership;
Gemini Sendable cleanup correction; Claude native service/cache/profile routing;
Authfleet Claude discovery/persisted settings selection and nonpersistent WebKit fixtures.

The installed AFCL source relay at release `7aba0e03524bddd042cd538cf138e7e50f079caa`
shows native subscription usage companions after inference login. The native selector
can reuse that companion when present, without a new CodexBar login lifecycle. Default
`config_dir: null` leaves directory overrides UNSET; explicit `~/.claude` remains a
different secure-storage/cache identity. Jace uses its named profile. CLI ownership is
retained for native refresh; CodexBar does not invoke `auth login --claudeai`. Actual
companion presence, readiness, usage scope and refresh success remain unknown.
Automation-token usage-endpoint support remains separately unproved; this is not evidence
that AFCL lacks a native companion. See `afcl-installed-companion-source.json`.

NFP-COR-001 original P1 (delegated refresh falling back outside enrolled CLI) is
source-remediated at `eb9bb9683f6b226c672876e88e493987663995bc` and independently
confirmed. Valid passive OAuth does not require CLI availability. Both availability
and `/status` resolve the selected enrolled executable and fail closed when unavailable.
FSP-PROC-001 original P1 (reaped leader then recycled-PGID signaling) is source-remediated
at `b9d2ca08a923c03b972de5f607b8963a06f8a498` and independently confirmed. WNOWAIT keeps
leader identity until every group signal completes, then the sole reap occurs. Never run
the historical unsafe version. Original finding identities/severities/blocking claims
remain in the component ledgers; source confirmation does not prove native behavior.

Deferred and unrepaired: NFP-COR-002 P2 identityless successful CLI results can reopen
previous sticky account history; FSP-PROC-002 P2 nonblocking signal-handler restoration
window. The excluded AFCS001/AFCS002 patch remains untouched and outside these PRs.
No finding severity was reduced or runtime debt silently accepted.

VPS checks: final scoped SwiftFormat0.61.1 passed all59 affected Swift files; diff check
passed. Builder Linux/Python3.13.5 passed20 ownership tests (16 mock +4 live synthetic)
and all50 scratch lifecycle cases; prior30 real-source portable identity checks used
compiler stubs. These are not native Swift evidence. No redundant unchanged rerun.
Swift is unavailable on VPS. `make check` remains held for missing tools/install effects.

Component evidence lives in `docs/review-evidence/`: final-source-native-candidate.json,
claude-native-gui-ab73cbaa.json, fixture-scratch-parent-c5454c8b.json,
webkit-synthetic-eecd20ac.json, gemini-cleanup-sendability-8effc1ec.json,
grouped-presentation-50a67106.json and the earlier exact finding/path ledgers.

## Native verification

Use fresh Mac admission and accepted serial fixture-isolated runner mechanics. Create
ONE invocation-owned canonical workspace scratch parent, export both
`CODEXBAR_TEST_SCRATCH_PARENT` and `TMPDIR` to it, preserve required logs outside it,
and finally remove exactly that owned parent. Never delete the caller parent inside a
nested script. No tool installation or broken Homebrew Node repair is authorized.

First verify the Python interpreter exposes `waitid`, `P_PID`, `WEXITED`, `WNOHANG`,
`WNOWAIT`, and `CLD_EXITED`; on macOS this requires Python3.13+. Unsupported capability
fails before spawning. Report an unavailable interpreter instead of installing one or
reintroducing PID-existence signaling. Then, within the existing parent lifetime:

```bash
export CODEXBAR_TEST_SCRATCH_PARENT="$owned_workspace_parent"
export TMPDIR="$CODEXBAR_TEST_SCRATCH_PARENT"
python3 -B Scripts/test_fixture_process_ownership.py --live "$CODEXBAR_TEST_SCRATCH_PARENT"
python3 -B Scripts/test_fixture_scratch_parent.py "$CODEXBAR_TEST_SCRATCH_PARENT"
bash Scripts/test_jones_identity_overlay.sh
bash Scripts/test_provider_session_file_isolation.sh
```

Use the admitted interpreter consistently for `python3` in nested scripts. Shell checks
require actual Swift paths on Mac. The16 native identity rejected cases and provider
proof are still unrun until executed; stub source-list proof is not native proof.

Preserve `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1`, Codex-file/session isolation,
exclude live/fixture grants, disable non-timeout retries, and keep credential/history
suite synthetic overrides. Run compile/discovery and the deduplicated affected union in
final-source-native-candidate.json, including the12 original account recovery/drain
suites, new Claude selection/refresh cases, Gemini scratch/login, grouped menus, and
WebKit cache/identifier fixtures. Report absent suite names as absent, not passed.

The known persistent WebKit fixture hazard is now removed at source-routing level by
`eecd20acf44717c6e6114be223b01337ad1c3598`: instance-owned production cache logic takes
mandatory injected constructors; all four affected fixtures use nonpersistent stores
and assert recorded constructor UUIDs, retaining35 existing declarations/110 expectations/
30 CI guards and adding3 tests. Native compile/runtime is unproved. Laptop may qualify
this contained seam and run the admitted full suite under accepted isolation; any
remaining concrete unsafe group must be held and reported precisely, without silent
skips or a fabricated full pass. Synthetic cache proof does not qualify production
persistent WebKit or shared HTTP containment.

Report exact candidate SHA, manifest match, commands, discovery/test counts, failures,
skips, unavailable/held checks, scratch cleanup, and source/index status. Return source
failures to VPS. Static installed-desktop compatibility is already complete; stock
behavior is owner observation, not candidate installation proof.

## Historical native evidence

Baseline `21c34561387b26f76d0a27e9f00d1538fbc0926f`: compilation/discovery PASS attempt1,
exit0 after1876.72s;10,371 identifiers/1,015 runner selections, zero unknown lines and
ZERO behavior tests. Scratch removed, source/index unchanged, cache retained.
Interim `44a43f5928154e08b4ce14724c2a1231b88143a9`: FAIL exit1 after128.77s, only Gemini
FileManager120/126 Sendable diagnostics; zero discovery/tests. Scratch removed,
source/index clean, cache retained, no live process. Gemini source8effc1ec fixes the
capture with a locked cleanup capability retaining the injected manager, native pending.
Three synthetic MiMo Python tests passed on laptop44a; affected code is unchanged,
so no unchanged rerun is needed. None of this qualifies the new candidate.

## Remaining gates and delivery

Both PRs remain OPEN/non-draft with checks[] at latest readback. Fork Actions UI states
workflows paused due to usage scale, repoID1356759930. Active/API-enabled metadata does
not clear it. No setting was changed. Preserve upstream-monitor disabled_fork. Exact
owner approval or authenticated owner UI initiation is needed to lift pause; laptop
prepares that separate gate. Do not re-enable/dispatch/change settings from this handoff.
Local native results cannot waive required CI or `ac.trial-gates`.

Extraction remains read-only until BOTH PR11 and identity PR12 merge to fork main or
M Jones explicitly releases `ac.custom-base-settled.001`; coordinator takeover does not
waive this owner-only predicate. VPS does not merge behind the laptop coordinator.
PR632/658 are already merged; they do not establish product completion.

All seven trial categories retain their source/native dispositions in IDENTITY.md and
the final manifest: retained diagnostics, MiMo tracker activation, scratch failure/
termination qualification, framework/shared HTTP containment, unbundled/copied CLI,
explicit/provider-owned paths and native/release qualification. Native app/widget/CLI
containment, ordinary desktop switching/external refresh interaction and signing/
package/release/install/launch remain unqualified with their separate operation gates.
No live auth/config/binding/Keychain reads, credential copies, account switches,
provider/usage/browser calls, app lifecycle/smoke, signing/package/install/release,
launchctl/sudo or fleet propagation is authorized by this verification handoff.

The registered VPS bridge targets a different environment; no laptop send was attempted.
Consume this Git handoff and exact source-ready message through the already authorized
laptop-to-VPS route. Receipt is not native success.
