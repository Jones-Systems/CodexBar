#!/usr/bin/env python3
"""Bound participating macOS compiler commands; see docs/compiler-resource-limits.md."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import ctypes
import fcntl
import json
from fractions import Fraction
import os
from pathlib import Path
import pwd
import re
import signal
import stat
import sys
import time


PLATFORM = sys.platform
MAX_JOBS = 6
ADMISSION_SECONDS = 300
WINDOW_SECONDS = 30
INTERVAL_SECONDS = 5
SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


class AdmissionError(ValueError):
    pass


def positive_integer(value: str) -> int:
    if not re.fullmatch(r"[0-9]+", value) or int(value) < 1:
        raise AdmissionError(f"expected a positive integer, got {value!r}")
    return int(value)


def normalize(arguments: list[str], kind: str, environment: dict[str, str]) -> tuple[list[str], int]:
    limit = MAX_JOBS
    if "CODEXBAR_BUILD_JOBS" in environment:
        limit = min(limit, positive_integer(environment["CODEXBAR_BUILD_JOBS"]))
    result = []
    index = 0
    while index < len(arguments):
        arg = arguments[index]
        if arg == "--":
            raise AdmissionError("opaque argument payload after -- is not supported")
        value_options = {
            "--filter", "--skip", "--configuration", "-c", "--package-path", "--scratch-path",
            "--cache-path", "--config-path", "--security-path", "--arch", "--triple", "--sdk",
            "--toolchain", "--swift-sdk", "--destination", "--product", "--target",
            "--test-product", "--xunit-output", "--parallel-worker-count",
            "-project", "-workspace", "-scheme", "-configuration", "-destination",
            "-derivedDataPath", "-archivePath", "-sdk", "-toolchain",
        }
        if arg in value_options:
            if index + 1 == len(arguments):
                raise AdmissionError(f"missing value for {arg}")
            result.extend(arguments[index:index + 2])
            index += 2
            continue
        value = None
        if arg in ("--jobs", "-j", "-jobs"):
            index += 1
            if index == len(arguments):
                raise AdmissionError(f"missing value for {arg}")
            value = arguments[index]
        elif arg.startswith(("--jobs=", "-jobs=")):
            value = arg.split("=", 1)[1]
        elif re.fullmatch(r"-jobs[0-9]+", arg):
            value = arg[5:]
        elif arg.startswith("-j") and arg != "-json" and not arg.startswith("-jobs"):
            value = arg[2:]
        if value is not None:
            limit = min(limit, positive_integer(value))
        else:
            # Response files and compiler passthrough can hide a second scheduler.
            if arg.startswith("@") or arg.startswith("-Xswiftc=@"):
                raise AdmissionError("opaque response-file arguments are not supported")
            if arg == "-Xswiftc" or arg.startswith("-Xswiftc="):
                payload = arg.split("=", 1)[1] if "=" in arg else (
                    arguments[index + 1] if index + 1 < len(arguments) else "")
                if not payload or payload.startswith(("@", "-j", "--jobs", "-num-threads", "-driver-batch-count", "-driver-batch-size-limit")):
                    raise AdmissionError("compiler concurrency/response overrides are not supported")
            if kind == "xcode" and (arg.split("=", 1)[0].split("[", 1)[0].lstrip("-") in {
                "SWIFT_COMPILATION_MODE", "SWIFT_MAXIMUM_CONCURRENT_COMPILE_TASKS",
                "SWIFT_ENABLE_BATCH_MODE", "SWIFT_NUM_THREADS", "OTHER_SWIFT_FLAGS",
                "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION",
                "OTHER_CFLAGS", "OTHER_CPLUSPLUSFLAGS", "IDEBuildOperationMaxNumberOfConcurrentCompileTasks",
            } or arg in {"-xcconfig", "-parallelizeTargets"}):
                raise AdmissionError("Xcode concurrency/opaque compiler overrides are not supported")
            result.append(arg)
        index += 1
    return result, limit


def cpu_ticks() -> tuple[int, ...]:
    # HOST_CPU_LOAD_INFO returns cumulative user, system, idle, and nice ticks.
    native = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
    native.mach_host_self.restype = ctypes.c_uint
    native.host_statistics.argtypes = (ctypes.c_uint, ctypes.c_int,
                                      ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_uint))
    native.host_statistics.restype = ctypes.c_int
    native.mach_port_deallocate.argtypes = (ctypes.c_uint, ctypes.c_uint)
    native.mach_port_deallocate.restype = ctypes.c_int
    port = native.mach_host_self()
    ticks = (ctypes.c_uint * 4)()
    count = ctypes.c_uint(4)
    try:
        status = native.host_statistics(port, 3, ctypes.cast(ticks, ctypes.POINTER(ctypes.c_int)), ctypes.byref(count))
        if status != 0 or count.value != 4:
            raise AdmissionError("CPU counters unavailable")
        return tuple(ticks)
    finally:
        native.mach_port_deallocate(ctypes.c_uint.in_dll(native, "mach_task_self_").value, port)


def busy_fraction(first: tuple[int, ...], last: tuple[int, ...]) -> Fraction:
    if len(first) != 4 or len(last) != 4 or any(type(x) is not int or x < 0 for x in (*first, *last)):
        raise AdmissionError("invalid CPU counters")
    delta = [b - a for a, b in zip(first, last)]
    if min(delta) < 0 or sum(delta) <= 0:
        raise AdmissionError("CPU counters reset or did not advance")
    return Fraction(sum(delta) - delta[2], sum(delta))


def capacity_jobs(cores: int, average: Fraction, recent: Fraction) -> int:
    if type(cores) is not int or cores <= 0:
        raise AdmissionError("logical processor count unavailable")
    if not 0 <= average <= 1 or not 0 <= recent <= 1:
        raise AdmissionError("invalid CPU utilization")
    return max(0, min(MAX_JOBS, (cores * (Fraction(4, 5) - max(average, recent))).__floor__()))


class Reporter:
    def __init__(self, deadline: float):
        self.deadline = deadline
        self.last = float("-inf")

    def report(self, message: str):
        now = time.monotonic()
        if now - self.last >= WINDOW_SECONDS:
            print(f"build jobs: {message}; remaining={max(0, self.deadline - now):.1f}s", file=sys.stderr, flush=True)
            self.last = now


def sample_window(deadline: float) -> tuple[Fraction, Fraction, float]:
    while True:
        if deadline - time.monotonic() < WINDOW_SECONDS:
            raise AdmissionError("deadline leaves no complete 30-second CPU window")
        started = previous_time = time.monotonic()
        first = previous = cpu_ticks()
        for _ in range(6):
            time.sleep(INTERVAL_SECONDS)
            now = time.monotonic()
            if now >= deadline:
                raise AdmissionError("admission deadline expired")
            if now - previous_time > 10:
                break
            if now - previous_time < INTERVAL_SECONDS:
                raise AdmissionError("invalid CPU sample interval")
            current = cpu_ticks()
            recent = busy_fraction(previous, current)
            previous, previous_time = current, now
        else:
            return busy_fraction(first, current), recent, now - started


def lock_directory() -> Path:
    # Account metadata, not HOME/TMPDIR, keeps different worktrees on one host lock.
    return Path(pwd.getpwuid(os.getuid()).pw_dir) / "Library" / "Caches" / "CodexBar-build-jobs"


def open_lock() -> int:
    directory = lock_directory()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise AdmissionError("unsafe compiler lock directory")
    directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        fd = os.open("compiler.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
    finally:
        os.close(directory_fd)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1:
        os.close(fd)
        raise AdmissionError("unsafe compiler lock file")
    return fd


@contextmanager
def admission(command: list[str], kind: str = "swift", *, cleanup_proved=None):
    if PLATFORM != "darwin":
        yield command
        return
    arguments, limit = normalize(command[1:], kind, dict(os.environ))
    deadline = time.monotonic() + ADMISSION_SECONDS
    reporter = Reporter(deadline)
    fd = open_lock()
    try:
        while True:
            if time.monotonic() >= deadline:
                raise AdmissionError("deadline waiting for compiler lock")
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                reporter.report("waiting for shared compiler lock")
                time.sleep(min(1, max(0, deadline - time.monotonic())))
        os.lseek(fd, 0, os.SEEK_SET)
        if os.read(fd, 4096):
            raise AdmissionError(f"unreconciled compiler execution in {lock_directory() / 'compiler.lock'}; "
                                 "manual reconciliation required")
        # SwiftPM --skip-build executes already-built tests; retain serialization only.
        if kind == "swift" and arguments[:1] == ["test"] and "--skip-build" in arguments:
            jobs = limit
        else:
            cores = os.cpu_count()
            capacity_jobs(cores, Fraction(0), Fraction(0))
            reporter.report("sampling 30-second CPU window")
            while True:
                average, recent, duration = sample_window(deadline)
                jobs = min(limit, capacity_jobs(cores, average, recent))
                reporter.report(f"window={duration:.1f}s average={float(average)*100:.1f}% "
                                f"last5s={float(recent)*100:.1f}% jobs={jobs}")
                if jobs:
                    break
        if time.monotonic() >= deadline:
            raise AdmissionError("admission deadline expired")
        record = json.dumps({"state": "in-progress", "owner_pid": os.getpid(), "jobs": jobs}) + "\n"
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, record.encode())
        os.fsync(fd)
        returned = False
        try:
            # SwiftPM's WMO default precedes Xswiftc flags: keep each admitted job
            # single-threaded while retaining the per-file outputs enabled by positive 1.
            tail = (["--jobs", str(jobs), "-Xswiftc", "-num-threads", "-Xswiftc", "1"]
                    if kind == "swift" else
                    ["-jobs", str(jobs), "SWIFT_USE_PARALLEL_WHOLE_MODULE_OPTIMIZATION=NO"])
            yield [command[0], *arguments, *tail]
            returned = True
        finally:
            # The runner's monotonic cleanup flag also covers cancellation while an
            # earlier exception is propagating. Unknown ownership never clears a fence.
            proved = cleanup_proved() if cleanup_proved is not None else returned
            if proved:
                os.ftruncate(fd, 0)
                os.fsync(fd)
            else:
                print(f"compiler cleanup unproved; admission fenced at {lock_directory() / 'compiler.lock'}",
                      file=sys.stderr, flush=True)
    finally:
        os.close(fd)


def run(command: list[str], kind: str) -> int:
    import ci_swift_test_by_suite as runner

    def cancel(signum, _frame):
        raise SystemExit(128 + signum)

    previous = {sig: signal.signal(sig, cancel) for sig in SIGNALS}
    try:
        with admission(command, kind, cleanup_proved=lambda: runner._scratch_cleanup_safe) as bounded:
            # Reuse the repository's identity-bound descendant drain without entering
            # its fixture lifecycle or recursively acquiring admission.
            result = runner._run_command(bounded)
            return 128 - result if result < 0 else result
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=("swift", "xcode"), default="swift")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a compiler command is required")
    try:
        return run(command, args.kind)
    except (AdmissionError, OSError) as error:
        print(f"build not started: {error}", file=sys.stderr)
        return 75


if __name__ == "__main__":
    sys.exit(main())
