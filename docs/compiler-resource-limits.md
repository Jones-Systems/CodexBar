---
summary: "CPU and storage admission for participating macOS build launchers."
read_when:
  - Running local builds or tests
  - Diagnosing compiler CPU usage, storage, or blocked admission
---

# Compiler resource limits

Use the repository's build and test launchers on macOS. They apply a maximum
of **six build jobs** on both a laptop and a Mac Mini, reduced when recent CPU
use leaves less room. The limit also applies on macOS CI; Linux commands keep
their existing behavior.

The shared `Scripts/build_jobs.py` helper owns this policy. Ordinary Makefile
builds, the isolated test runner (including `--command swift test ...`), plugin
tests, repository-sync tests and app packaging call it at the compiler
boundary. Packaging also applies Xcode's job control. Do not bypass the helper
with bare, uncapped SwiftPM or Xcode commands.

Release builds also limit each Swift compiler job to one backend thread.
SwiftPM receives a final `-Xswiftc -num-threads -Xswiftc 1`; Xcode receives
`SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO` together with the literal
`OTHER_SWIFT_FLAGS=$(inherited) -num-threads 1` build setting. The first disables
Xcode's processor-count default; the second explicitly selects one backend
thread while preserving inherited flags, whole-module compilation and per-file
object outputs. Both are needed on toolchains that otherwise omit the thread
option when parallel whole-module optimization is disabled.
Limiting jobs alone leaves Swift's release backend free to use every processor.

Participating commands share a per-user lock across worktrees. After obtaining
it, the helper measures a fresh 30-second CPU window and its final five-second
interval. It uses the busier value and reserves nominal 20% headroom, with at
most six jobs. On twelve processors, 20%, 50%, 70% and 75% CPU use permit six,
three, one and zero jobs respectively. Diagnostics report the measurements and
selected budget. This controls job concurrency; it is not an OS CPU quota.

If no jobs fit, the helper waits and measures again. Lock waiting and admission
are bounded together; missing or invalid CPU evidence starts no compiler.
Cancellation while waiting starts nothing. Existing CPU/memory preflight
requirements still apply. A valid `CODEXBAR_BUILD_JOBS` value can lower the
budget, but cannot raise it. Excessive or duplicate job flags cannot raise it
either. Unsupported compiler-level concurrency overrides are rejected.

Immediately after CPU admission, while still holding the shared lock, the helper
checks available storage before writing the in-progress record or starting a
child. The provisional ordinary-operation budget is a **30 GiB residual reserve
plus 10 GiB estimated additional peak allocation**, requiring **40 GiB available**.
These are conservative initial estimates, not measured workload bounds. Equality
passes using integer bytes; existing output size is not subtracted again.

`CODEXBAR_BUILD_RESERVE_BYTES` and `CODEXBAR_BUILD_PEAK_BYTES` may explicitly
increase their respective defaults. Empty, malformed, zero, negative or smaller
values fail closed. Multi-architecture builds, packaging/staging and other larger
operations must declare a larger additional peak covering transient overlap.
The estimate covers the combined outputs on each filesystem, not a separate
allowance per directory. The check is a snapshot, not a quota or reservation
against unrelated writers.

SwiftPM output selection follows `--package-path` and `--scratch-path`, including
`--option=value` forms. It also checks explicit cache/config/security and xUnit
output paths. Xcode selection includes `-derivedDataPath`, `-archivePath`, result
and package-cache destinations. Defaults include the package's `.build` (the
current directory's `.build` at the package root; nested working directories
follow SwiftPM's upward `Package.swift` search), the standard shared caches,
Xcode DerivedData/Archives as applicable, and temporary storage. Nonexistent
outputs resolve to their nearest existing ancestor without creating them.
Unresolved path expressions, unsupported destination overrides and opaque compiler
output flags are rejected. The diagnostic names the output, measured ancestor,
available bytes, reserve and additional peak; unavailable or insufficient evidence
starts no child and performs no cleanup. Compiler-free `--skip-build` commands
retain the storage check because tests can still allocate output.

Build outputs and shared caches retain their existing owners and lifetimes. This
admission change does not impose retention bounds or authorize deleting existing
`.build`, cache, packaging, installed or rollback artifacts. Packaging retention
and its existing cleanup behavior remain separate work.

The shared lock file also retains a minimal in-progress record until owned
child cleanup is proved. An abandoned or unknown-cleanup record prevents a new
build; the diagnostic identifies its evidence file. Do not delete that file or
clear it because a PID disappeared. Reconcile the recorded owned work first,
then clear that exact record while holding the lock. There is no automatic
recovery or bypass setting.

The chosen budget stays fixed for the command. Compiler-free `--skip-build`
test groups do not need another 30-second compiler measurement. The helper
does not stop existing work or throttle an already-running compiler.

Coverage is limited to participating launchers in updated source. Old
worktrees, direct compiler commands, unrelated repositories and other users
are outside its lock. Single-input `swiftc` fixture proofs do not fan out
through SwiftPM. Using updated source on the Mac Mini applies the same policy;
a laptop observation alone does not verify that host's adoption.
