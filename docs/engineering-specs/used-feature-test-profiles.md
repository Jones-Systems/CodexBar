# Engineering Spec — Used-feature test profiles

Artifact Type: `engineering-spec`
Artifact ID: `spec.codexbar-used-feature-tests`
Purpose: Select owner-used app coverage at compile/discovery/execution boundaries.
Authority effect: none

Owner direction is the second CodexBar pass on October 24, 2026. Base is
`fec59ff9e6258140126139f518f44a9cf306ed1b`; PRs #31–37 and their evidence remain.
The initial Frontier Max Astra/max plan is captured in the task evidence.

Research found the former discovery timer included test compilation; each Mac
shard repeats it. Execution-only selection leaves that dominant cost intact.
Package.swift test-target membership excludes whole unused files, while test-only
compilation guards handle mixed suites. Product targets, dependencies, resources,
source and test bodies remain unchanged. Shared helper definitions stay compiled.

The [profile guide](../testing-profiles.md) defines the normal/full interface,
reasons and restoration. Unsupported explicit profiles and invalid paths fail.
Normal is the PR/push default. Full is explicit/manual only; no schedule changes.
CLI-dependent coverage stays until the owner’s usage boundary is known.

Root owns Git, manifest, package, harness, documentation and fan-in. A builder
owns the listed mixed test files; a CI builder owns the workflow/cache/lint cone.
Read-only inventory and manifest audits identify shared exceptions. Separate
write cones share one root Git owner; fresh host telemetry admits each wave/test.

Qualification splits test build, no-build discovery and execution at process
boundaries while preserving isolation, child drain, cleanup, retries and shards.
Focused synthetic checks cover invalid selection, source partition/guards, cache
identity, build failure, shard invariants and the Linux parallel route. Exact
normal/full identities and native outcomes are compared without weakening the
existing equal-coverage campaign comparator. Measurement arms must match source,
runner/toolchain, build configuration and cache treatment to be called controlled.
Historical samples are labeled unpaired; runner minutes exclude queues.

One final sensitive-area Astra/xhigh bulk review covers all groups/guards and the
identity partition. Apply restorations/gaps. Publish non-draft scoped PRs, require
current-head applicable checks, merge with expected-head guards and verify main.
No product changes, installs, live probes, credentials, sudo, releases, signing,
branch deletion, PR26 edits or schedule-timing mutations are authorized here.
