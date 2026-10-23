#!/usr/bin/env python3
"""Resource admission on the hosted macOS candidate runner; never a VPS/Mac slot.

CPU percentages describe the whole host; 100 / logical CPUs is one core's
share. Memory availability is the conservative free + inactive page estimate.
Storage estimates are additional allocation, not a quota or a reservation.
"""

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import sys
import time

import build_jobs
from jones_candidate_artifact import CandidateError, GIB, command, require


MIN_MEMORY_BYTES = 3 * GIB
RESERVE_BYTES = 2 * GIB
# Hosted-job lifetime only, without persisted caches. Include nested producers.
OUTPUT_BUDGETS = (("build-and-products", 8 * GIB), ("scratch-and-artifact", 4 * GIB), ("user-caches", 2 * GIB))


def sample_cpu():
    # Reuse the compiler wrapper's Mach counters; top's decimal display is ambiguous.
    started = time.monotonic()
    try:
        first = build_jobs.cpu_ticks()
        time.sleep(1)
        last = build_jobs.cpu_ticks()
        elapsed = time.monotonic() - started
        require(1 <= elapsed <= 10, "cpu-unknown", "Invalid CPU sample interval")
        return float(100 * build_jobs.busy_fraction(first, last))
    except (build_jobs.AdmissionError, OSError) as error:
        raise CandidateError("cpu-unknown", "CPU counters unavailable or inconsistent") from error


def parse_memory(text, total_bytes):
    match = re.search(r"page size of ([0-9]+) bytes", text)
    require(match is not None, "memory-unknown", "Missing vm_stat page size")
    page_size = int(match[1])
    require(page_size in (4096, 16384), "memory-unknown", "Unexpected vm_stat page size")
    pages = []
    for name in ("free", "inactive"):
        match = re.search(rf"^Pages {name}:\s+([0-9]+)\.$", text, re.MULTILINE)
        require(match is not None, "memory-unknown", f"Missing Pages {name}")
        pages.append(int(match[1]))
    available = sum(pages) * page_size
    require(type(total_bytes) is int and total_bytes > 0 and available <= total_bytes,
            "memory-unknown", "Inconsistent memory sample")
    return available


def existing_ancestor(path):
    path = path.absolute()
    while not path.exists():
        require(path != path.parent, "storage-unknown", "No existing storage ancestor")
        path = path.parent
    require(path.is_dir(), "storage-unknown", "Storage destination is not a directory")
    return path.resolve()


def storage_observations(workspace, scratch, user_cache):
    volumes = {}
    for destination, (kind, budget) in zip((workspace, scratch, user_cache), OUTPUT_BUDGETS):
        ancestor = existing_ancestor(destination)
        device = ancestor.stat().st_dev
        free = shutil.disk_usage(ancestor).free
        require(type(free) is int and free >= 0, "storage-unknown", "Unknown free storage")
        entry = volumes.setdefault(device, {"device": device, "available_bytes": free,
                                             "estimated_additional_peak_bytes": 0, "reserve_bytes": RESERVE_BYTES,
                                             "destinations": []})
        entry["available_bytes"] = min(entry["available_bytes"], free)
        entry["estimated_additional_peak_bytes"] += budget
        entry["destinations"].append({"kind": kind, "path": str(destination.absolute()),
                                      "measured_ancestor": str(ancestor), "estimated_bytes": budget})
    return list(volumes.values())


def decide(cpu, cores, total_memory, available_memory, pressure, volumes, requested_jobs):
    require(type(cpu) in (int, float) and math.isfinite(cpu) and 0 <= cpu <= 100,
            "cpu-unknown", "Unknown CPU usage")
    require(type(cores) is int and cores > 0, "cpu-unknown", "Unknown logical CPU count")
    require(type(total_memory) is int and type(available_memory) is int and 0 <= available_memory <= total_memory
            and total_memory > 0, "memory-unknown", "Unknown memory availability")
    require(type(pressure) is int and pressure in (1, 2, 4), "pressure-unknown", "Unknown memory pressure level")
    require(type(requested_jobs) is int and 1 <= requested_jobs <= 6,
            "compiler-jobs", "Compiler jobs must be between one and six")
    require(type(volumes) is list and bool(volumes), "storage-unknown", "Storage observations are required")
    reasons = []
    if cpu >= 85:
        reasons.append("cpu-at-or-above-85-percent")
    if available_memory < MIN_MEMORY_BYTES:
        reasons.append("less-than-3-GiB-available-memory")
    if pressure != 1:
        reasons.append("memory-pressure-not-normal")
    for volume in volumes:
        for name in ("available_bytes", "estimated_additional_peak_bytes", "reserve_bytes"):
            require(type(volume.get(name)) is int and volume[name] >= 0,
                    "storage-unknown", "Invalid storage observation")
        if volume["available_bytes"] < volume["estimated_additional_peak_bytes"] + volume["reserve_bytes"]:
            reasons.append("insufficient-storage")
    return {
        "schema": "jones-candidate-admission/v1", "status": "held" if reasons else "admitted",
        "start_ceiling": 0 if reasons else 1, "compiler_jobs": min(cores, requested_jobs),
        "cpu_used_percent": cpu, "cpu_percent_basis": "whole-host", "logical_cpus": cores,
        "one_core_whole_host_percent": 100 / cores, "memory_total_bytes": total_memory,
        "memory_available_estimate_bytes": available_memory, "memory_pressure_level": pressure,
        "memory_pressure": {1: "normal", 2: "warning", 4: "critical"}[pressure],
        "storage": volumes, "hold_reasons": reasons, "reservation": False,
    }


def sample(workspace, scratch, environment, requested_jobs):
    require(sys.platform == "darwin" and platform.machine() == "arm64", "runner-platform", "arm64 macOS is required")
    require(environment.get("GITHUB_ACTIONS") == "true" and environment.get("RUNNER_ENVIRONMENT") == "github-hosted",
            "runner-identity", "Admission is limited to GitHub-hosted CI")
    cpu = sample_cpu()

    def sysctl(name):
        raw = command(["/usr/sbin/sysctl", "-n", name]).stdout.decode("ascii").strip()
        require(bool(re.fullmatch(r"[0-9]+", raw)), "telemetry-unknown", f"Invalid {name}")
        return int(raw)

    cores = sysctl("hw.logicalcpu")
    total = sysctl("hw.memsize")
    pressure = sysctl("kern.memorystatus_vm_pressure_level")
    available = parse_memory(command(["/usr/bin/vm_stat"]).stdout.decode("ascii"), total)
    user_cache = Path.home() / "Library/Caches"
    result = decide(cpu, cores, total, available, pressure,
                    storage_observations(workspace, scratch, user_cache), requested_jobs)
    result["sampled_at"] = datetime.now(timezone.utc).isoformat()
    result["output_lifetime"] = "owned scratch cleanup plus hosted runner teardown; no saved build cache"
    return result


def sample_until_admitted(workspace, scratch, environment, requested_jobs, wait_seconds):
    require(type(wait_seconds) is int and 0 <= wait_seconds <= 180,
            "admission-wait", "Admission wait must be between zero and 180 seconds")
    started = time.monotonic()
    deadline = started + wait_seconds
    transient = {"cpu-at-or-above-85-percent", "less-than-3-GiB-available-memory",
                 "memory-pressure-not-normal"}
    attempts = 0
    while True:
        # Unknown telemetry raises immediately; only measured pressure can be retried.
        result = sample(workspace, scratch, environment, requested_jobs)
        attempts += 1
        now = time.monotonic()
        result["admission_attempts"] = attempts
        result["waited_seconds"] = round(now - started, 3)
        if (result["start_ceiling"] == 1 or now >= deadline
                or not set(result["hold_reasons"]).issubset(transient)):
            return result
        delay = min(30, deadline - now)
        print(json.dumps({"status": "waiting", "start_ceiling": 0,
                          "hold_reasons": result["hold_reasons"], "next_sample_seconds": delay,
                          "cpu_used_percent": result["cpu_used_percent"],
                          "one_core_whole_host_percent": result["one_core_whole_host_percent"],
                          "memory_available_estimate_bytes": result["memory_available_estimate_bytes"],
                          "memory_pressure": result["memory_pressure"]}), file=sys.stderr, flush=True)
        time.sleep(delay)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--scratch", type=Path, required=True)
    parser.add_argument("--compiler-jobs", type=int, default=6)
    parser.add_argument("--wait-seconds", type=int, default=0,
                        help="Wait up to 180 seconds for known transient CPU/memory holds; gates never change")
    parser.add_argument("--github-env", type=Path)
    parser.add_argument("--jobs-output", type=Path)
    args = parser.parse_args(argv)
    try:
        result = sample_until_admitted(args.workspace, args.scratch, os.environ, args.compiler_jobs,
                                      args.wait_seconds)
        print(json.dumps(result, sort_keys=True, indent=2))
        if result["start_ceiling"] != 1:
            return 1
        if args.jobs_output:
            with args.jobs_output.open("x", encoding="ascii") as handle:
                handle.write(f"{result['compiler_jobs']}\n")
        if args.github_env:
            with args.github_env.open("a", encoding="utf-8") as handle:
                handle.write(f"CODEXBAR_BUILD_JOBS={result['compiler_jobs']}\n")
        return 0
    except CandidateError as error:
        code, reason = error.code, str(error)
    except (OSError, UnicodeError, ValueError) as error:
        code, reason = "telemetry-unknown", type(error).__name__
    print(json.dumps({"status": "held", "start_ceiling": 0, "code": code, "reason": reason}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
