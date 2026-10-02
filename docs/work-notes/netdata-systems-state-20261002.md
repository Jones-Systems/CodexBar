# Netdata synthetic Systems and refresh state

<!-- codex-section:begin id="worknote.netdata-systems-state#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.netdata-systems-state`

Purpose: Carry the portable supplied-observation presentation and refresh-state checkpoint.

Governing artifact: `spec.netdata-menu-bar#iface.host-observation.001`, `spec.netdata-menu-bar#iface.polling.001`

Continuity owner: Portfolio slot14, under root's exact five-file candidate binding.

Consumers: Netdata client coordinator, future Systems UI and app integration owners.

Authority effect: none
<!-- codex-section:end id="worknote.netdata-systems-state#ctx.artifact-header.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#ctx.scope.001" -->
## Scope and identity

Original T3 task: `718b02d7-0d4b-4670-b05f-57a5db28178d`, Resume NetData Menu Bar Monitoring.
The original successor and parent/parser/client writers retain their existing worktrees.
Slot14 owns only this new candidate and its five additive source, test and note paths.
Root bound an independent task-owned common store and branch
`work/netdata-systems-state-20261002-slot14` at immutable client checkpoint
`1849a8cb0a4235b4e406036cc65316e99f53c0ba`.
The initial full-history local fetch failed on an unavailable promisor object;
direct readback found zero objects, no refs and an empty FETCH_HEAD.
A depth-one local exact-base fetch then succeeded without fetching or advancing
the original common store. This candidate has shallow history and is local only.

No package, lockfile, generated resource, parent UI, settings, app lifecycle,
transport, provider account or host file is changed. No publication, native Mac
run, protected endpoint use, installation or settlement is authorized here.
The prior specialist judgment used the full private capsule. Its retained Sol
qualification covered safe metadata only, not private-body semantic review.
<!-- codex-section:end id="worknote.netdata-systems-state#ctx.scope.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#iface.state.001" -->
## Supplied state and acceptance

`NetdataSystemsState` projects one identity-matched `HubHostObservation` into
explicit CPU percent, available RAM GiB, shared sample time, receipt time,
availability and compact label. Absent values differ from true zero; used memory
is never substituted. Stale compact labels hide values. Cached detail values
retain the original sample timestamp and require an explicitly historical UI.
The legacy observation has one shared sample time, so this adapter does not
invent independent per-metric source timestamps or qualification.

`NetdataRefreshState` makes injected event/time decisions, with one in-flight
request, monotonically increasing request identity, configuration-change and
late-result rejection, failure cache retention, cancellation, suspension and
wake. It returns scheduling dates; it creates no timer, task or request.
Working defaults remain five seconds visible and ten seconds background,
with failure backoff capped at sixty seconds. Cache display ages at thirty
seconds and becomes unavailable after five minutes. These are synthetic
behavior predicates, not a measured native performance budget.

Acceptance for this checkpoint: deterministic synthetic tests cover units,
missing/zero values, host isolation, age boundaries, failure and recovery,
one request, configuration changes, cancellation, sleep/wake and late replies.
Future UI wiring, localization, real polling and protected-route qualification
belong to their exact integration owners. Parent PR2 ownership/overlap remains
the gate for those shared paths, not for these new isolated state files.
<!-- codex-section:end id="worknote.netdata-systems-state#iface.state.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#test.evidence.001" -->
## Verification

The affected synthetic union is the two new suites plus
`ObservabilityHubLinuxTests` and `NetdataLoopbackClientLinuxTests`. No Swift build
or test process has started: `swift`, `swiftformat` and `swiftlint` are absent
from the ordinary PATH, and four conventional Swift executable paths are absent.
Readiness has no already-qualified Swift 6.2 pointer in its current receipts.
This establishes a route gap, not absence of every possible installation.
The package requires Swift 6.2. Compilation, the focused/regression union and
repository-required `make test` therefore remain **unavailable**, not passing.

`make check` is also **not executed**: its existing wrapper automatically
bootstraps missing tooling and runs scratch-producing checks. This task has no
tool installation or unqualified scratch/bootstrap authority. No alternate
compiler, runtime, host or account is selected to bypass these limits.
Source inspection confirms only the five bound paths changed, no new dependency
or transport call, and unchanged legacy parser/client files. Native macOS
compilation/rendering remains independently unverified.

Fixtures create no files, processes or network requests. Any future admitted
build uses contained workspace scratch with exact-path cleanup, evidence retained
outside that scratch, fresh host admission and one global serial process.
No shared `/tmp` cleanup is allowed. A local commit is a review checkpoint;
unavailable checks prevent claiming verified source delivery.
<!-- codex-section:end id="worknote.netdata-systems-state#test.evidence.001" -->

<!-- codex-section:begin id="worknote.netdata-systems-state#ctx.remaining.001" -->
## Remaining boundaries

The native client finish is still unmet. The app does not consume this new state.
Source tests do not establish menu rendering, accessibility, native macOS builds,
live metric correctness, protected route/configuration, or owner acceptance.
Opaque native pending input remains unresolved and cannot be cleared here.

`NETDATA-CLIENT-01` remains P2 at
`a7d5e612c86aa0fca23637380554773995776ded`: the old client captures time before
sequential requests. `NETDATA-DOC-01` remains P3 at
`c63696b41bfaa89c8e3004a9c09c932fa90e701f`. Both original files and dispositions
are unchanged. This new projection is no correction or acceptance of that client
freshness defect. Unknown historical runtime/host effects remain unwaived.
<!-- codex-section:end id="worknote.netdata-systems-state#ctx.remaining.001" -->
