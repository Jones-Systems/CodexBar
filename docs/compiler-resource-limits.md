---
summary: "Load-aware macOS compiler job limits and participating build launchers."
read_when:
  - Running local builds or tests
  - Diagnosing compiler CPU usage or blocked admission
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
