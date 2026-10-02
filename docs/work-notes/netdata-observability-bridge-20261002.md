# Netdata in-memory Observability bridge

<!-- codex-section:begin id="worknote.netdata-observability-bridge#ctx.artifact-header.001" -->
Artifact Type: `work-note`

Artifact ID: `worknote.netdata-observability-bridge`

Purpose: Carry the explicit supplied-client bridge and existing Systems/Overview source checkpoint.

Governing artifact: `spec.netdata-menu-bar#iface.host-observation.001`, `spec.netdata-menu-bar#iface.polling.001`

Continuity owner: Portfolio slot14 under root's exact five-path binding.

Consumers: Original Netdata integration owner and parent Observability hub owner.

Authority effect: none
<!-- codex-section:end id="worknote.netdata-observability-bridge#ctx.artifact-header.001" -->

<!-- codex-section:begin id="worknote.netdata-observability-bridge#ctx.scope.001" -->
## Identity and boundary

Original T3 task: `718b02d7-0d4b-4670-b05f-57a5db28178d`, Resume NetData Menu Bar Monitoring.
Root bound proposal SHA-256 `262c8ebc1eecb9022940a6c6526a3763815921b4e9f908e8549653387bfd54df`
to this isolated candidate at immutable portable checkpoint
`46086a7c55b99342eb77f94582ee12dcd948ab53`, source tree
`34256d634055a5758b56aa810a5dedf7eb85e2b6`.
Slot14 alone owns Git and source on branch `work/netdata-observability-bridge-20261002-slot14`.
An independent task-owned common repository obtained that exact local object with
a depth-one fetch from slot14's own prior common repository. No parent ref or
index was advanced. Canonical origin is `Jones-Systems/CodexBar`.

The writer cone is the new core bridge, its Linux tests, the two existing
Observability view/Providers pane files, and this note. The two app files retain
known source overlap with open parent PR2. Independent preparation does not
transfer that parent's custody or authorize its integration, publication or merge.
No package, lock, configuration schema, localization catalog, provider/account,
parent client/parser, runtime, host or protected file is changed.
<!-- codex-section:end id="worknote.netdata-observability-bridge#ctx.scope.001" -->

<!-- codex-section:begin id="worknote.netdata-observability-bridge#iface.bridge.001" -->
## Explicit source behavior

`NetdataObservabilityBridge` is a main-actor observable adapter with an empty
default binding table. A caller supplies an environment ID and a Sendable fetcher;
the existing `NetdataLoopbackClient` conforms without changing its implementation.
Binding, rendering, reconfiguration and wake do not start a request. An explicit
async refresh delegates to that supplied fetcher. The caller owns scheduling,
transport cancellation and app lifecycle; the bridge creates no timer, task or
watcher. Its cancellation and suspension operations invalidate state publication,
without claiming to stop an uncooperative supplied transport.

Each host retains the accepted pure refresh/cache state, due dates and backoff.
A separate active-fetch identity retains physical per-environment occupancy until
the supplied fetch returns or throws, including after rebinding or sleep/wake.
Invalidating cached state does not authorize a second concurrent fetch.
An additional binding identity rejects replies after replace/remove/re-add even
when fresh local request generations coincide. Host DTO publication uses the
same age/failure projection as Systems, preserving the original shared sample
time, receipt time, missing values and explicit zero. Cached failures are stale;
aged compact text hides metrics. No per-metric timestamps or native qualification
are invented. CAAM status and provider observations cannot gate host refreshes.

The Providers pane optionally accepts this bridge and otherwise owns a new empty
instance. Its existing CAAM refresh task remains unchanged. Systems/Overview
consume the supplied state using their existing layout and evidence treatment;
the existing hub receives `hostsByEnvironmentID`. No new refresh trigger or
dashboard-derived endpoint is added. The compact label is a presentation helper,
not a newly activated menu-bar collector or a localization acceptance receipt.
<!-- codex-section:end id="worknote.netdata-observability-bridge#iface.bridge.001" -->

<!-- codex-section:begin id="worknote.netdata-observability-bridge#test.evidence.001" -->
## Verification

The deduplicated synthetic union passed **42 tests in five suites**: the new
bridge, Systems, refresh, Observability hub and loopback client. This includes
empty/invalid bindings, injected client composition, partial/zero/stale metrics,
cache recovery and due dates, cancellation, rebind/remove/re-add, and physical
single-fetch occupancy through suspend/wake. The supported contained `make test`
route discovered and selected 75 selections in seven groups: all seven passed
on their first run, with no failures, retries or timeouts. Those selections
overlap the focused union and are not added as a unique test total.

The two new Swift files passed formatting. All four changed Swift files passed
strict SwiftLint. The two app files passed syntax parsing only; native Mac
constructor/typecheck/rendering remains independently unverified. Repository
size and its contained fixtures, documentation links, and the LLMS index passed.
Three inherited formatting findings in untouched Observability view text remain
outside this source correction. Final changed-note links require their own
current-input check; unchanged passed source checks are not repeated for prose.

The first focused build compiled the bridge/core and CLI, then failed linking
before tests because Swift 6.2's Linux Observation library required an unexported
core symbol. Only the authenticated genuine Swift 6.2.2 Observation runtime was
extracted from its official immutable signed archive. Original Swift 6.2
compiler/core files remain unchanged. An initial successor attempt still selected
the original library. The genuine positional library input subsequently compiled,
but its initial runtime guard read an incomplete memory map and stopped. A
bounded stream reader then proved the exact library mapping and observable
behavior. SwiftPM's first argument-adapter attempt compiled the test source and
linked the CLI, then test discovery failed because IndexStore was resolved
relative to that adapter. An exact regular copy of the original authenticated
IndexStore library supplied the expected task-owned support path; the subsequent
focused and required groups passed. No failed attempt is reported as a test pass.

The successful mixed tuple is compiler/core **Swift 6.2**, genuine Observation
runtime **6.2.2**, SwiftFormat **0.61.1**, SwiftLint **0.65.0**, genuine Debian
libncurses **6.5+20250216-2**, and matched SQLite **3.46.1-7+deb13u2** headers and
runtime. SourceKit remains the original authenticated toolchain library. Genuine
library paths and compiler selection are process-local. The argument adapter
leaves nonlink arguments unchanged and adds the authentic runtime only for four
literal executable outputs inside owned build scratch. No original compiler,
core, runtime, system file, shared pointer, profile or package lock is replaced.

The official 6.2.2 archive SHA-256 is
`d4817caaf70e95639702b69be24730057f4220f76796573397cdc067a4360041`;
the selected runtime SHA-256 is
`7949ebab341a4cd10c8b542235321fda133f53e2e4bd19066cdce297e9ff5cce`.
The exact IndexStore copy is 1,617,672 bytes, SHA-256
`171142b5e7bdd273a91cb060bd48f0326702d40cf71ffdff87bfe49784a192a1`.
Release signatures verified successfully with the official key, signing times
inside that key's validity period and no observed revocation. Expiry now is
retained separately from valid-at-signing authentication; no clock, trust,
expiry-bypass or signature-suppression change was used.

Public command, input-hash, tool-hash, admission and cleanup receipts remain in
slot14's task-owned verification directory outside this source tree. Focused
execution admitted at 8.78% CPU used and 40.37 GiB available RAM; required groups
at 12.85% and 41.19 GiB. One fully used effective core was 6.25% of host capacity;
one global serial process ran at a time. Every intensive phase had fresh numeric
admission. Peak measured tools, archives, caches and scratch were 6,901,497,970
bytes, below the seven-GiB proactive guard and eight-GiB hard limit. Package lock
SHA-256 remained `8d7387e9eaf0363455c6179275efa996ef445a6cd392d19e48fdbcddce616e9a`.
Per-command temporary scratch was removed after trusted terminals. The producer
owns exact final build/cache/argument-adapter/IndexStore-copy cleanup and its
absence readback, preserving authenticated toolchains, dependencies, lint tools,
archives and evidence. No source `.build` or unrelated tree is a cleanup target.
The synthetic bridge tests create no files, processes or network requests.

Supported synthetic Linux groups are the required check evidence here. The
inherited Linux full-check platform/Homebrew failures and native Mac capability
limits remain recorded, without a full-check or native-success inference.
Previously passed portable-parent tests are separate parent evidence.
<!-- codex-section:end id="worknote.netdata-observability-bridge#test.evidence.001" -->

<!-- codex-section:begin id="worknote.netdata-observability-bridge#ctx.remaining.001" -->
## Original finish still pending

This checkpoint supplies source wiring only. The current configuration has no
Netdata origin, expected machine GUID, qualified route, selected menu host or
lifecycle binding. Those fields are not inferred from CAAM SSH destinations or
dashboard navigation. No default client, network read, private endpoint, tunnel,
CAAM control, host activation or native Mac operation occurs here.
Parent integration, actual native Mac build/render/accessibility, live metric
correctness and owner acceptance remain separate. Opaque native pending input
and unknown historical operational effects remain unresolved. UI84's visual
rejection and the separate Health UI screen hold are unchanged.

`NETDATA-CLIENT-01` P2 at `a7d5e612c86aa0fca23637380554773995776ded` and
`NETDATA-DOC-01` P3 at `c63696b41bfaa89c8e3004a9c09c932fa90e701f` remain
undisposed and unfixed. The old client still captures sample time before its
sequential requests. This bridge neither repairs that issue nor establishes
native freshness acceptance.
<!-- codex-section:end id="worknote.netdata-observability-bridge#ctx.remaining.001" -->
