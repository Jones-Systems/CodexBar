#!/usr/bin/env python3
"""Run widget compilation with bounded diagnostics and the shared compiler/drain policy."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import stat
import sys
import threading
import time

import build_jobs
import ci_swift_test_by_suite as runner


TAIL_BYTES = 64 * 1024
SCAN_ENTRIES = 8192
PHASE = re.compile(r"^(?:CompileSwift|SwiftCompile|SwiftEmitModule|SwiftDriver|CompileC|Ld|"
                   r"Copy|Touch|ProcessInfoPlistFile|GenerateDSYMFile|CodeSign|\*\* BUILD|"
                   r"Build Timing Summary)(?:\s|$)")


def bounded_tail(path):
    with path.open("rb") as handle:
        size = os.fstat(handle.fileno()).st_size
        handle.seek(max(0, size - TAIL_BYTES))
        data = handle.read(TAIL_BYTES)
    return size, data


def compiler_outputs(root, limit=SCAN_ENTRIES):
    """Bound the generated-file census and skip observed symlinks."""
    pending = [root]
    visited = count = size = newest = 0
    complete = True
    while pending:
        directory = pending.pop()
        try:
            if not stat.S_ISDIR(directory.stat(follow_symlinks=False).st_mode):
                complete = False
                continue
            with os.scandir(directory) as entries:
                for entry in entries:
                    if visited >= limit:
                        return dict(files=count, bytes=size, newest_mtime_ns=newest, complete=False)
                    visited += 1
                    try:
                        info = entry.stat(follow_symlinks=False)
                        if stat.S_ISDIR(info.st_mode):
                            pending.append(Path(entry.path))
                        elif stat.S_ISREG(info.st_mode) and entry.name.endswith((".o", ".swiftmodule", ".pcm")):
                            count += 1
                            size += info.st_size
                            newest = max(newest, info.st_mtime_ns)
                    except FileNotFoundError:
                        complete = False
        except FileNotFoundError:
            complete = False
    return dict(files=count, bytes=size, newest_mtime_ns=newest, complete=complete)


class Progress:
    def __init__(self, log, products, output, *, interval=30):
        self.log, self.products, self.output = log, products, output
        self.interval = interval
        self.started = self.last_output = time.monotonic()
        self.previous_bytes = 0
        self.latest = None
        self.error = None
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.monitor, name="widget-build-progress", daemon=True)

    def sample(self):
        now = time.monotonic()
        size, data = bounded_tail(self.log)
        if size != self.previous_bytes:
            self.last_output = now
        phases = [line[:240] for line in data.decode("utf-8", errors="replace").splitlines()
                  if PHASE.match(line)]
        record = dict(schema="jones-widget-progress/v1", observed_at=datetime.now(timezone.utc).isoformat(),
                      elapsed_seconds=round(now - self.started, 1),
                      log_bytes=size, log_growth_bytes=max(0, size - self.previous_bytes),
                      log_reset=size < self.previous_bytes,
                      seconds_since_output=round(now - self.last_output, 1),
                      latest_observed_phase=phases[-1] if phases else None,
                      compiler_outputs=compiler_outputs(self.products))
        self.previous_bytes = size
        self.latest = record
        line = json.dumps(record, sort_keys=True)
        print("widget progress: " + line, file=sys.stderr, flush=True)
        self.output.write(line + "\n")
        self.output.flush()

    def monitor(self):
        try:
            while not self.stop.wait(self.interval):
                self.sample()
        except Exception as error:
            self.error = error

    @contextmanager
    def observing(self):
        self.sample()
        self.thread.start()
        try:
            yield
        finally:
            self.stop.set()
            self.thread.join(timeout=5)
            if self.thread.is_alive():
                self.error = RuntimeError("widget progress observer did not stop")
            elif self.error is None:
                try:
                    self.sample()
                except Exception as error:
                    self.error = error


def timeout_value(raw):
    if not re.fullmatch(r"[0-9]+", raw) or not 1 <= int(raw) <= 7200:
        raise ValueError("widget timeout must be an integer from 1 through 7200 seconds")
    return int(raw)


def run(command, log, products, timeout, *, interval=30):
    def cancel(signum, _frame):
        raise SystemExit(128 + signum)

    previous = {sig: signal.signal(sig, cancel) for sig in build_jobs.SIGNALS}
    result = None
    progress = None
    active_marker = None
    started = time.monotonic()
    try:
        # Admission remains independently bounded. The execution deadline starts
        # after admission, inside the runner that proves owned descendant drain.
        with build_jobs.admission(command, "xcode", cleanup_proved=lambda: runner._scratch_cleanup_safe) as bounded:
            log.parent.mkdir(parents=True, exist_ok=True)
            marker = log.with_name("widget-build-active")
            with marker.open("x") as owned_marker:
                active_marker = marker
                owned_marker.write("Preserve products until owned compiler drain is proved.\n")
            with log.open("wb", buffering=0) as output, log.with_name("widget-progress.jsonl").open("w") as events:
                progress = Progress(log, products, events, interval=interval)
                with progress.observing():
                    result = runner._run_command(bounded, timeout=timeout, stdout=output, stderr=output)
            if progress.error is not None:
                print(f"Widget progress unavailable: {type(progress.error).__name__}", file=sys.stderr)
                result = result or 1
            if result == 124:
                print(f"ERROR: Timed out building CodexBarWidget extension after {timeout}s execution", file=sys.stderr)
            return 128 - result if result < 0 else result
    except runner.CommandDrainError as error:
        result = error.returncode
        raise
    except SystemExit as error:
        result = error.code if isinstance(error.code, int) else 1
        raise
    finally:
        propagating_error = sys.exc_info()[0] is not None
        try:
            if progress is not None:
                _, tail = bounded_tail(log)
                log.with_name("xcodebuild-tail.log").write_bytes(tail)
                summary = dict(schema="jones-widget-build/v1", execution_timeout_seconds=timeout,
                               elapsed_including_admission_seconds=round(time.monotonic() - started, 1),
                               exit_code=result, completed=result == 0 and runner._scratch_cleanup_safe,
                               cleanup_proved=runner._scratch_cleanup_safe,
                               progress_error=type(progress.error).__name__ if progress.error else None,
                               latest_progress=progress.latest)
                log.with_name("widget-build-result.json").write_text(json.dumps(summary, indent=2) + "\n")
                if result != 0:
                    print(tail.decode("utf-8", errors="replace"), file=sys.stderr)
        except Exception as error:
            print(f"Widget diagnostics failed: {type(error).__name__}", file=sys.stderr)
            if not propagating_error and result == 0:
                raise
        finally:
            try:
                if active_marker is not None and runner._scratch_cleanup_safe:
                    active_marker.unlink(missing_ok=True)
            except OSError as error:
                print(f"Widget drain marker cleanup failed: {error}", file=sys.stderr)
                if not propagating_error and result == 0:
                    raise
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--timeout", type=timeout_value, default=900)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("an Xcode command is required")
    try:
        return run(command, args.log, args.products, args.timeout)
    except runner.CommandDrainError as error:
        print(f"Widget compiler drain failed: {error}", file=sys.stderr)
        return 128 - error.returncode if error.returncode < 0 else error.returncode or 1
    except (OSError, build_jobs.AdmissionError) as error:
        print(f"Widget build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
