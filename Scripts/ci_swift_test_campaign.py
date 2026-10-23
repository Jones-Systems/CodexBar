#!/usr/bin/env python3
"""Validate campaign receipts and run explicit Linux cache/input-timestamp phases."""

from __future__ import annotations

import argparse
from collections import Counter
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


ENV_KEY = "CODEXBAR_TEST_EVIDENCE_DIR"
SCHEMA = "codexbar.swift-test-campaign/v1"
MAX_BYTES = 128 * 1024 * 1024
RESERVE_BYTES = 512 * 1024 * 1024
ISOLATION = {"CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1", "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
             "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1"}
LINUX_CACHE_BYTES = 2 * 1024 ** 3
LINUX_SCAN_ENTRIES = 200000
LINUX_SCAN_SECONDS = 10
LINUX_METADATA_BYTES = 256 * 1024
FIXTURE_PREFIXES = (".test-fixtures-", ".swift-test-evidence-", ".test-sharding.", ".test-campaign-",
                    ".test-storage-", ".test-linux-cache-")
LINUX_INPUT_ROOTS = ("Package.swift", "Package.resolved", "Sources", "Tests", "TestsLinux", "TestsPlugin")
LINUX_INPUT_PATHS = 8192
LINUX_INPUT_BYTES = 64 * 1024 ** 2
LINUX_INPUT_METADATA_BYTES = 4 * 1024 ** 2
LINUX_INPUT_SECONDS = 20
LINUX_INPUT_MANIFEST = ".codexbar-input-timestamps.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(values):
    return hashlib.sha256(("\n".join(sorted(values)) + "\n").encode()).hexdigest()


def resolve_plan(event, group_size="", shard_count="", expected_sha="", source_sha="", cache_mode="",
                 linux_cache_mode="off", linux_timestamp_mode="off"):
    if event != "workflow_dispatch":
        group_size, shard_count, cache_mode = "4", "2", "ordinary"
    else:
        require(group_size in ("4", "12"), "group_size must be 4 or 12")
        require(shard_count in ("1", "2", "3"), "shard_count must be 1, 2 or 3")
        require(cache_mode in ("seed", "warm", "cold"), "cache_mode must be seed, warm or cold")
        require(linux_cache_mode in ("off", "seed", "warm"), "linux_cache_mode must be off, seed or warm")
        require(linux_timestamp_mode in ("off", "record", "replay"), "unknown Linux timestamp mode")
        require(linux_timestamp_mode == "off" or
                (linux_timestamp_mode, linux_cache_mode) in (("record", "seed"), ("replay", "warm")),
                "timestamp record requires Linux seed; replay requires Linux warm")
        require(re.fullmatch("[0-9a-f]{40}", expected_sha or ""), "expected_sha must be an exact lowercase commit")
        require(expected_sha == source_sha, "expected_sha differs from the checkout")
    return {"include": [
        {"shard-index": index, "shard-count": int(shard_count), "group-size": int(group_size),
         "cache-mode": cache_mode, "campaign": event == "workflow_dispatch"}
        for index in range(int(shard_count))
    ]}


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    with path.open("x") as stream:
        stream.write(encode(value) + "\n")


def bounded_root(raw):
    root = Path(raw)
    require(root.is_absolute() and root.resolve(strict=True) == root and root.is_dir(),
            "evidence root must be an existing canonical directory")
    total = 0
    for path in root.rglob("*"):
        require(not path.is_symlink(), "evidence must not contain symlinks")
        if path.is_file():
            total += path.stat().st_size
    require(total <= MAX_BYTES, "campaign evidence exceeded the 128 MiB budget")
    return root


def prepare(environment, checkout_sha):
    workspace = Path(environment["GITHUB_WORKSPACE"]).resolve(strict=True)
    require(environment["RUNNER_OS"] == "macOS" and environment.get("GITHUB_ACTIONS") == "true",
            "native campaign evidence requires the hosted macOS route")
    require(checkout_sha == environment["GITHUB_SHA"], "checkout differs from GITHUB_SHA")
    matrix = resolve_plan(
        "workflow_dispatch", environment["CAMPAIGN_GROUP_SIZE"], environment["CAMPAIGN_SHARD_COUNT"],
        environment["CAMPAIGN_EXPECTED_SHA"], checkout_sha, environment["CAMPAIGN_CACHE_MODE"],
    )["include"]
    index = int(environment["CAMPAIGN_SHARD_INDEX"])
    require(0 <= index < len(matrix), "invalid campaign shard index")
    mode = environment["CAMPAIGN_CACHE_MODE"]
    require(mode != "warm" or environment.get("CAMPAIGN_CACHE_HIT") == "true",
            "warm treatment requires a proved exact cache hit")
    require(mode != "cold" or not (workspace / ".build").exists(),
            "cold treatment requires absent application build output; nothing was deleted")
    require(shutil.disk_usage(workspace).free >= RESERVE_BYTES + MAX_BYTES,
            "insufficient storage for bounded campaign evidence")
    context = {
        "schema": SCHEMA, "source_revision": checkout_sha, "group_size": int(environment["CAMPAIGN_GROUP_SIZE"]),
        "shard_count": len(matrix), "shard_index": index, "timeout_seconds": 120,
        "retry_non_timeout_failures": False, "cache_mode": mode,
        "cache_hit": environment.get("CAMPAIGN_CACHE_HIT", ""),
        "cache_key": environment["CAMPAIGN_CACHE_KEY"], "toolchain_id": environment["CAMPAIGN_TOOLCHAIN_ID"],
        "runner_os": environment["RUNNER_OS"], "runner_arch": environment["RUNNER_ARCH"],
        "image_version": environment.get("ImageVersion", ""), "image_os": environment.get("ImageOS", ""),
        "run_id": environment["GITHUB_RUN_ID"], "run_attempt": environment["GITHUB_RUN_ATTEMPT"],
        "github_ref": environment["GITHUB_REF"], "workspace": str(workspace),
        "cold_application_build_absent": mode == "cold", "max_evidence_bytes": MAX_BYTES,
    }
    root = Path(tempfile.mkdtemp(prefix=".swift-test-evidence-", dir=workspace))
    try:
        info = root.stat()
        context["root_identity"] = [info.st_dev, info.st_ino]
        validate_context(context)
        write_json(root / "context.json", context)
    except BaseException:
        shutil.rmtree(root)
        raise
    return root


def validate_context(context):
    require(context["schema"] == SCHEMA, "unsupported campaign context")
    require(re.fullmatch("[0-9a-f]{40}", context["source_revision"]), "invalid source revision")
    require(context["group_size"] in (4, 12) and context["shard_count"] in (1, 2, 3)
            and 0 <= context["shard_index"] < context["shard_count"], "invalid campaign partition")
    require(context["timeout_seconds"] == 120 and context["retry_non_timeout_failures"] is False,
            "campaign timeout/retry contract changed")
    mode = context["cache_mode"]
    require(mode in ("seed", "warm", "cold"), "invalid cache treatment")
    require(mode != "warm" or context["cache_hit"] == "true", "warm treatment lacks an exact hit")
    require(mode != "cold" or (context["cache_hit"] == "" and context["cold_application_build_absent"] is True),
            "cold treatment did not bypass application cache")
    require(context["runner_os"] == "macOS" and context["runner_arch"] == "ARM64", "unsupported native runner")
    for key in ("cache_key", "toolchain_id", "image_version", "image_os", "run_id", "run_attempt", "github_ref"):
        require(isinstance(context[key], str) and context[key] and "\n" not in context[key], f"missing {key}")
    require(context["cache_key"].endswith("-" + context["source_revision"])
            and context["toolchain_id"] in context["cache_key"], "cache key is not source/toolchain bound")


def cleanup(root, environment):
    root = bounded_root(str(root))
    context = read_json(root / "context.json")
    workspace = Path(environment["GITHUB_WORKSPACE"]).resolve(strict=True)
    require(root.parent == workspace and root.name.startswith(".swift-test-evidence-"), "unowned evidence root")
    require(context["workspace"] == str(workspace) and context["source_revision"] == environment["GITHUB_SHA"]
            and context["run_id"] == environment["GITHUB_RUN_ID"]
            and context["run_attempt"] == environment["GITHUB_RUN_ATTEMPT"], "evidence owner changed")
    require(read_json(root / "completion.json")["cleanup_proved"] is True,
            "retain evidence until job teardown when command drain is unproved")
    info = root.stat()
    require(context["root_identity"] == [info.st_dev, info.st_ino], "evidence root identity changed")
    shutil.rmtree(root)
    require(not root.exists(), "evidence cleanup failed")
    print(f"Uploaded campaign evidence removed; absence verified: {root}")


class Capture:
    def __init__(self, root):
        self.root = bounded_root(str(root))
        self.context = read_json(self.root / "context.json")
        validate_context(self.context)
        workspace = Path(self.context["workspace"])
        require(self.root.parent == workspace.resolve(strict=True), "evidence root must belong to the workspace")
        require(self.context["source_revision"] == os.environ.get("GITHUB_SHA"), "campaign source changed")
        self.records = (self.root / "runner.jsonl").open("x")
        self.attempt_number = 0
        self.process_number = 0
        self.attempt_id = None
        self.native_support = False
        self.completed_bytes = 0

    @classmethod
    def from_environment(cls):
        raw = os.environ.get(ENV_KEY)
        return cls(Path(raw)) if raw else None

    def record(self, record):
        self.records.write(encode(record) + "\n")
        self.records.flush()

    def validate_invocation(self, args):
        require(sys.platform == "darwin" and os.environ.get("GITHUB_ACTIONS") == "true",
                "native campaign capture requires macOS Actions")
        require(args.command is None and not args.list_only and args.limit_groups is None,
                "campaigns require complete suite execution")
        require((args.group_size, args.shard_index, args.shard_count, args.timeout, args.retry_non_timeout_failures)
                == (self.context["group_size"], self.context["shard_index"], self.context["shard_count"], 120, False),
                "campaign invocation differs from its validated controls")
        require(args.swift_command == "swift" and not args.swift_command_arg,
                "campaign requires the selected SwiftPM toolchain")
        environment = self.process_environment()
        require(all(environment.get(key) == value for key, value in ISOLATION.items())
                and not environment["live_or_fixture_grant"], "campaign test isolation differs from CI")

    def process_environment(self):
        keys = (*ISOLATION, "CODEXBAR_TEST_WORKSPACE_ROOT", "CODEXBAR_TEST_SCRATCH_PARENT", "TMPDIR")
        return {**{key: os.environ.get(key) for key in keys},
                "live_or_fixture_grant": bool(os.environ.get("CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS")
                                              or os.environ.get("CODEXBAR_TEST_CODEX_FILE_FIXTURES"))}

    def check_fixture(self, path):
        require(path != self.root and path not in self.root.parents and self.root not in path.parents,
                "native evidence and fixture scratch must have separate lifetimes")

    def next_process(self):
        self.process_number += 1
        return self.process_number

    def begin_attempt(self, phase):
        bounded_root(str(self.root))
        require(self.attempt_id is None, "campaign attempts must be serial")
        require(phase in ("first", "group-retry", "selection-retry"), "unknown retry phase")
        self.attempt_number += 1
        self.attempt_id = f"{self.attempt_number:04d}-{phase}"
        directory = self.root / self.attempt_id
        directory.mkdir()
        return directory

    def check_budget(self):
        current = self.root / self.attempt_id if self.attempt_id else None
        paths = [self.root / "runner.jsonl"]
        if current is not None:
            paths.extend(current.iterdir())
        size = self.completed_bytes + sum(path.stat().st_size for path in paths if path.is_file())
        require(size <= MAX_BYTES, "campaign evidence exceeded the 128 MiB budget")

    def end_attempt(self, directory):
        self.completed_bytes += sum(path.stat().st_size for path in directory.iterdir() if path.is_file())
        self.attempt_id = None

    def finish(self, result, cleanup_proved):
        self.records.close()
        write_json(self.root / "completion.json", {
            "result": result, "cleanup_proved": cleanup_proved, "native_support": self.native_support,
        })
        bounded_root(str(self.root))


def native_outcomes(text):
    """Keep opaque native IDs and native case fields; never manufacture case IDs."""
    tests, suites, states, outcomes, cases, issues, limitations = {}, set(), {}, [], [], [], []
    started = ended = 0
    for line in text.splitlines():
        record = json.loads(line)
        require(record.get("version") == 0, "unsupported Swift Testing event version")
        payload = record["payload"]
        if record["kind"] == "test":
            require(ended == 0, "native declaration follows run completion")
            if payload["kind"] == "function":
                identifier = payload["id"]
                require(identifier not in tests, "duplicate native test declaration")
                tests[identifier] = payload
                require(isinstance(payload.get("isParameterized"), bool), "native parameter capability is missing")
                states[identifier] = {"started": False, "finished": False, "case": None, "issues": [],
                                      "case_fields": set(), "case_count": 0}
            elif payload["kind"] == "suite":
                suites.add(payload["id"])
            else:
                raise ValueError("unknown native test declaration kind")
            continue
        require(record["kind"] == "event", "unknown native record kind")
        kind, identifier = payload["kind"], payload.get("testID")
        if kind == "runStarted":
            require(started == ended == 0, "duplicate native run start")
            started += 1
        elif kind == "runEnded":
            require(started == 1 and ended == 0, "native run ended before starting")
            ended += 1
        elif kind in ("valueAttached", "testDiscovered", "planStepStarted", "planStepEnded", "iterationStarted", "iterationEnded"):
            continue
        elif identifier not in tests:
            require(identifier in suites and kind in ("testStarted", "testEnded", "testSkipped"),
                    "unbound native outcome or issue")
        else:
            require(started == 1 and ended == 0, "native outcome outside run boundaries")
            state = states[identifier]
            messages = payload.get("messages", [])
            if kind == "testStarted":
                require(not state["started"] and not state["finished"], "duplicate native test start")
                state["started"] = True
            elif kind == "testCaseStarted":
                require(state["started"] and not state["finished"] and state["case"] is None,
                        "ambiguous or overlapping native case lifecycle")
                # v0 does not require a case ID. Preserve the observed native
                # _testCase extension or argument message; never invent an ID.
                fields = {key: value for key, value in payload.items()
                          if key not in ("kind", "instant", "testID") and value not in (None, [], {})}
                if tests[identifier]["isParameterized"]:
                    native_case = fields.get("_testCase", {})
                    argument_messages = [message["text"] for message in messages
                                         if re.fullmatch(r"Test case passing [1-9][0-9]* arguments? .+ to .+ started\.",
                                                         message.get("text", ""))]
                    representation = (("native", native_case["id"]) if isinstance(native_case.get("id"), str)
                                      and native_case["id"] else ("arguments", encode(argument_messages)))
                    if not native_case.get("id") and not argument_messages:
                        limitations.append(f"no comparable parameter representation for {identifier}")
                    elif representation in state["case_fields"]:
                        limitations.append(f"ambiguous repeated parameter representation for {identifier}")
                    state["case_fields"].add(representation)
                state["case"] = {"test_id": identifier, "native_fields": fields, "issues": []}
                state["case_count"] += 1
            elif kind == "issueRecorded":
                require(state["started"] and not state["finished"], "issue outside native test lifecycle")
                issue = payload["issue"]
                require(isinstance(issue.get("isKnown"), bool), "native issue lacks known/unknown disposition")
                item = {"test_id": identifier, "issue": issue, "messages": messages}
                issues.append(item)
                state["issues"].append(item)
                if state["case"] is not None:
                    state["case"]["issues"].append(item)
            elif kind == "testCaseEnded":
                require(state["case"] is not None, "native case ended without a unique start")
                case = state["case"]
                if "_testCase" in payload:
                    require(payload["_testCase"] == case["native_fields"].get("_testCase"),
                            "native case relationship changed before completion")
                case["status"] = issue_status(case["issues"])
                cases.append(case)
                state["case"] = None
            elif kind in ("testEnded", "testSkipped"):
                require(not state["finished"] and state["case"] is None, "incomplete or duplicate native test outcome")
                require(kind == "testSkipped" or state["started"], "native test ended without starting")
                state["finished"] = True
                status = "skipped" if kind == "testSkipped" else issue_status(state["issues"])
                if kind == "testEnded" and tests[identifier]["isParameterized"] and not state["case_count"]:
                    limitations.append(f"no parameter case events for {identifier}")
                outcomes.append({"framework": "swift-testing", "id": identifier, "status": status,
                                 "native_test": tests[identifier], "skip": messages if kind == "testSkipped" else []})
            else:
                raise ValueError(f"unsupported native event: {kind}")
    require(started == ended == 1, "missing or duplicate native run boundary")
    require(all(state["finished"] for state in states.values()), "native test outcome is missing")
    return {"functions": outcomes, "cases": cases, "issues": issues, "limitations": sorted(set(limitations))}


def issue_status(issues):
    if any(not item["issue"]["isKnown"] for item in issues):
        return "failed"
    return "passed-with-known-issue" if issues else "passed"


def xctest_outcomes(text):
    active, outcomes = {}, []
    for line in text.splitlines():
        match = re.search(r"Test Case '([^']+)' (started|passed|failed|skipped)(?: \([^)]*\))?\.", line)
        if match:
            identifier, status = match.groups()
            if status == "started":
                require(identifier not in active, "duplicate XCTest start")
                active[identifier] = []
            else:
                require(identifier in active, "XCTest terminal outcome lacks a start")
                details = active.pop(identifier)
                outcomes.append({"framework": "xctest", "id": identifier, "status": status,
                                 "skip": details if status == "skipped" else []})
        elif "skipped" in line.lower() and active:
            require(len(active) == 1, "ambiguous XCTest skip reason")
            next(iter(active.values())).append(line)
    require(not active, "XCTest outcome is incomplete")
    totals = re.findall(r"Executed (\d+) tests?,", text)
    require(totals and int(totals[-1]) == len(outcomes), "XCTest total does not match its native outcomes")
    require(re.search(r"Test Suite 'Selected tests' (passed|failed)", text), "missing XCTest run completion")
    return outcomes


def selection_name(identifier):
    if re.fullmatch(r"[^.]+\.(?:\x60.+\x60|[^()/]+)\(\)", identifier):
        return identifier
    require("/" in identifier and "." in identifier.split("/", 1)[0], "unknown discovery identity")
    return identifier.split("/", 1)[0]


def selected_inventory(discovery):
    return sorted({selection_name(item) for item in discovery
                   if selection_name(item) != "CodexBarTests.CLIEntryTests"})


def selection_pattern(names):
    filters = []
    for name in names:
        top = re.fullmatch(r"([^.]+)\.(?:\x60(.+)\x60|([^()/]+))\(\)", name)
        filters.append(rf"{re.escape(top[1])}\..*{re.escape(top[2] or top[3])}" if top else rf"^{re.escape(name)}/")
    return "(" + "|".join(filters) + ")"


def read_records(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def verify(root):
    root = bounded_root(str(root))
    context = read_json(root / "context.json")
    validate_context(context)
    records = read_records(root / "runner.jsonl")
    completion = read_json(root / "completion.json")
    require(completion == {"result": 0, "cleanup_proved": True, "native_support": True},
            "native execution/support/cleanup was not proved successful")
    require(records and all(item["source_revision"] == context["source_revision"] for item in records),
            "runner receipt source mismatch")
    support = [item for item in records if item["event"] == "native-support"]
    require(len(support) == 1 and support[0]["advertised_options"] is True
            and support[0]["exit_code"] == 0 and support[0]["event_stream_version"] == 0,
            "native event capability was not established")
    help_text = (root / "native-help.txt").read_text()
    require(all(flag in help_text for flag in ("--event-stream-version", "--event-stream-output-path")),
            "native capability output is missing")
    discovered = [item for item in records if item["event"] == "discovery"]
    selected = [item for item in records if item["event"] == "selection"]
    require(len(discovered) == len(selected) == 1, "missing or duplicate discovery/selection receipt")
    discovery, selection = discovered[0]["test_ids"], selected[0]
    require(len(discovery) == len(set(discovery)), "duplicate raw discovery ID")
    require(discovered[0]["sha256"] == digest(discovery), "discovery digest mismatch")
    inventory = selected_inventory(discovery)
    size, index, count = context["group_size"], context["shard_index"], context["shard_count"]
    groups = [inventory[offset:offset + size] for offset in range(0, len(inventory), size)]
    groups = [group for number, group in enumerate(groups) if number % count == index]
    require(selection["groups"] == groups and selection["shard_index"] == index
            and selection["shard_count"] == count, "selected partition differs from complete discovery")
    require(selection["sha256"] == digest(name for group in groups for name in group), "selection digest mismatch")
    fixtures = [item for item in records if item["event"].startswith("fixture-")]
    require(len(fixtures) == 2 and fixtures[0]["event"] == "fixture-prepared" and fixtures[0]["owned"]
            and fixtures[1]["event"] == "fixture-removed", "owned fixture lifecycle is incomplete")
    require((fixtures[0]["path"], fixtures[0]["identity"]) == (fixtures[1]["path"], fixtures[1]["identity"]),
            "fixture parent identity changed")
    fixture = Path(fixtures[0]["path"])
    require(Path(context["workspace"]) in fixture.parents and fixture != root
            and fixture not in root.parents and root not in fixture.parents,
            "fixture/evidence lifetimes overlap or escape the workspace")
    active, identities, launches = {}, set(), {}
    fixture_live = False
    for item in records:
        event = item["event"]
        if event == "fixture-prepared":
            fixture_live = True
        elif event == "fixture-removed":
            require(not active, "fixture removed before command drain")
            fixture_live = False
        elif event == "process-start":
            identity = (item["pid"], tuple(item["birth"]))
            require(fixture_live and not active and identity not in identities and any(item["birth"])
                    and item["launch_id"] not in launches and item["session"] == item["pid"],
                    "fresh process birth or serial fixture containment is unproved")
            environment = item["environment"]
            require(all(environment.get(key) == value for key, value in ISOLATION.items())
                    and environment["live_or_fixture_grant"] is False
                    and environment["CODEXBAR_TEST_WORKSPACE_ROOT"] == context["workspace"]
                    and environment["CODEXBAR_TEST_SCRATCH_PARENT"] == str(fixture)
                    and environment["TMPDIR"] == str(fixture), "process fixture/isolation environment changed")
            identities.add(identity)
            active[item["launch_id"]] = identity
            launches[item["launch_id"]] = item
        elif event == "process-drained":
            require(active.pop(item["launch_id"], None) == (item["pid"], tuple(item["birth"])),
                    "process drain identity mismatch")
        elif event == "process-drain-failed":
            raise ValueError("process drain failed")
    require(not active and not fixture_live, "native process or fixture lifecycle is incomplete")
    attempts = [item for item in records if item["event"] == "attempt"]
    require([item["selections"] for item in attempts] == groups, "attempts omitted, duplicated or retried selections")
    functions, cases, issues, limitations = [], [], [], []
    for item in attempts:
        require(item["attempt"] == "first" and item["exit_code"] == 0 and item["error"] is None
                and item["timeout_seconds"] == 120, "first-pass failure/recovery cannot qualify clean parity")
        matching = [launch for launch in launches.values() if launch["attempt_id"] == item["attempt_id"]]
        require(len(matching) == 1, "attempt lacks one fresh process receipt")
        directory = root / item["attempt_id"]
        require(re.fullmatch(r"[0-9]{4,}-first", item["attempt_id"]), "invalid first-pass attempt ID")
        require(directory.parent == root and directory.resolve(strict=True) == directory, "unsafe attempt evidence path")
        command = matching[0]["command"]
        expected = ["swift", "test", "--skip-build", "--no-parallel", "--filter", selection_pattern(item["selections"]),
                    "--event-stream-version", "0", "--event-stream-output-path", str(directory / "swift-testing.jsonl")]
        tail = command[len(expected):]
        compiler_tail = (len(tail) == 6 and tail[0] == "--jobs" and re.fullmatch("[1-9][0-9]*", tail[1])
                         and tail[2:] == ["-Xswiftc", "-num-threads", "-Xswiftc", "1"])
        require(command[:len(expected)] == expected and (not tail or compiler_tail)
                and item["filter_pattern"] == expected[5], "native invocation or evidence path changed")
        native = native_outcomes((directory / "swift-testing.jsonl").read_text())
        console = (directory / "stdout.txt").read_text() + "\n" + (directory / "stderr.txt").read_text()
        xctest = xctest_outcomes(console)
        require(native["functions"] or xctest, "selected group produced no native outcomes")
        functions.extend(native["functions"] + xctest)
        cases.extend(native["cases"])
        issues.extend(native["issues"])
        limitations.extend(native["limitations"])
    require(all(item["status"] != "failed" for item in functions), "native failed outcome")
    return {"schema": SCHEMA, "context": context, "discovery": discovery,
            "selections": [name for group in groups for name in group],
            "functions": functions, "cases": cases, "issues": issues,
            "limitations": sorted(set(limitations)), "complete_identity": not limitations}


def arm(receipts):
    require(bool(receipts), "no shard receipts supplied")
    context = receipts[0]["context"]
    count = context["shard_count"]
    require(sorted(item["context"]["shard_index"] for item in receipts) == list(range(count)),
            "arm does not contain every shard exactly once")
    binding = ("source_revision", "group_size", "shard_count", "cache_mode", "cache_hit", "cache_key",
               "toolchain_id", "runner_os", "runner_arch", "image_version", "image_os")
    for receipt in receipts:
        validate_context(receipt["context"])
        require(receipt["schema"] == SCHEMA and receipt["complete_identity"], "native parameter identity is unproved")
        require(all(receipt["context"][key] == context[key] for key in binding), "mixed arm identity or cache treatment")
        require(receipt["discovery"] == receipts[0]["discovery"], "discovery differs between shards")
    selections = [name for receipt in receipts for name in receipt["selections"]]
    require(sorted(selections) == selected_inventory(receipts[0]["discovery"]), "arm selection union is not exact")
    return {key: Counter(encode(value) for receipt in receipts for value in receipt[key])
            for key in ("functions", "cases", "issues")}


def compare(baseline, candidate):
    left, right = arm(baseline), arm(candidate)
    for key in ("source_revision", "cache_mode", "cache_hit", "cache_key", "toolchain_id",
                "runner_os", "runner_arch", "image_version", "image_os"):
        require(baseline[0]["context"][key] == candidate[0]["context"][key], f"incomparable {key}")
    require(baseline[0]["discovery"] == candidate[0]["discovery"], "raw discovery inventory changed")
    require(left == right, "native identity/outcome multiset changed")
    return {"schema": SCHEMA, "equivalent": True, "source_revision": baseline[0]["context"]["source_revision"],
            "function_outcomes": sum(left["functions"].values()), "case_outcomes": sum(left["cases"].values())}


def linux_cache_source(environment, checkout_sha):
    manual = environment.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
    mode = environment.get("LINUX_CACHE_MODE", "off") if manual else "auto"
    timestamps = environment.get("LINUX_TIMESTAMP_MODE", "off") if manual else "off"
    expected = environment.get("CAMPAIGN_EXPECTED_SHA", "")
    if manual:
        resolve_plan("workflow_dispatch", environment.get("CAMPAIGN_GROUP_SIZE", ""),
                     environment.get("CAMPAIGN_SHARD_COUNT", ""), expected, checkout_sha,
                     environment.get("CAMPAIGN_CACHE_MODE", ""), mode, timestamps)
        require(checkout_sha == environment.get("GITHUB_SHA"), "manual Linux checkout differs from event SHA")
    return {
        "schema": "codexbar.linux-build-cache/v1", "phase": "source", "actual_sha": checkout_sha,
        "event_sha": environment.get("GITHUB_SHA", ""), "expected_sha": expected,
        "event": environment.get("GITHUB_EVENT_NAME", ""), "run_id": environment.get("GITHUB_RUN_ID", ""),
        "run_attempt": environment.get("GITHUB_RUN_ATTEMPT", ""), "ref": environment.get("GITHUB_REF", ""),
        "repository": environment.get("GITHUB_REPOSITORY", ""), "linux_cache_mode": mode,
        "linux_timestamp_mode": timestamps,
        "macos_cache_mode": environment.get("CAMPAIGN_CACHE_MODE", "") if manual else "ordinary",
        "group_size": int(environment["CAMPAIGN_GROUP_SIZE"]) if manual else 4,
        "shard_count": int(environment["CAMPAIGN_SHARD_COUNT"]) if manual else 2,
        "cache_path_manifest": [".build"], "enabled": False, "restore": False, "save": False,
        "requested_key": "", "lookup_matched_key": "", "restored_key": "", "producer_source": None,
        "hard_extraction_byte_limit": False, "logical_byte_limit": LINUX_CACHE_BYTES,
        "compressed_byte_limit": LINUX_CACHE_BYTES, "entry_limit": LINUX_SCAN_ENTRIES,
        "scan_seconds": LINUX_SCAN_SECONDS, "action_timeout_seconds": 120, "segment_timeout_seconds": 60,
        "phase_timings": {},
    }


def linux_directories(environment):
    paths = []
    for name in ("GITHUB_WORKSPACE", "RUNNER_TEMP"):
        raw = environment[name]
        path = Path(raw)
        require(path.is_absolute() and str(path) == raw and path.resolve(strict=True) == path and path.is_dir(),
                f"{name} must be an existing canonical directory")
        paths.append(path)
    return paths


def linux_storage(workspace, staging):
    same = workspace.stat().st_dev == staging.stat().st_dev
    workspace_free, staging_free = shutil.disk_usage(workspace).free, shutil.disk_usage(staging).free
    workspace_need, staging_need = (8, 8) if same else (6, 4)
    receipt = {"same_filesystem": same, "workspace_available_bytes": workspace_free,
               "staging_available_bytes": staging_free, "workspace_required_bytes": workspace_need * 1024 ** 3,
               "staging_required_bytes": staging_need * 1024 ** 3}
    receipt["eligible"] = (workspace_free >= receipt["workspace_required_bytes"]
                           and staging_free >= receipt["staging_required_bytes"])
    return receipt


def linux_build_scan(workspace):
    """Metadata admission only: stock cache extraction has no enforced maximum-byte input."""
    started = time.monotonic()
    build = workspace / ".build"
    receipt = {"complete": False, "exists": False, "logical_bytes": 0, "entries": 0, "workspace_entries": 0,
               "regular_files": 0, "symlinks": 0, "fixture_parents_absent": False}
    try:
        require(not build.is_symlink(), "build root is a symlink")
        with os.scandir(workspace) as children:
            for child in children:
                receipt["workspace_entries"] += 1
                require(receipt["workspace_entries"] <= LINUX_SCAN_ENTRIES
                        and time.monotonic() - started <= LINUX_SCAN_SECONDS, "build scan exceeded entry/time bound")
                require(not child.name.startswith(".test-fixtures-"), "fixture parent is still present")
        receipt["fixture_parents_absent"] = True
        if build.exists():
            require(build.is_dir() and build.resolve(strict=True) == build, "build root is not a canonical directory")
            receipt["exists"] = True
            pending = [build]
            while pending:
                with os.scandir(pending.pop()) as children:
                    for child in children:
                        receipt["entries"] += 1
                        require(receipt["entries"] + receipt["workspace_entries"] <= LINUX_SCAN_ENTRIES
                                and time.monotonic() - started <= LINUX_SCAN_SECONDS,
                                "build scan exceeded entry/time bound")
                        require(not child.name.startswith(FIXTURE_PREFIXES), "fixture/evidence path in build")
                        path = Path(child.path)
                        info = child.stat(follow_symlinks=False)
                        if stat.S_ISLNK(info.st_mode):
                            target = path.resolve(strict=True)
                            require(target.is_relative_to(build) and not any(
                                part.startswith(FIXTURE_PREFIXES) for part in target.relative_to(build).parts),
                                "build symlink leaves cache containment")
                            receipt["symlinks"] += 1
                        elif stat.S_ISDIR(info.st_mode):
                            pending.append(path)
                        elif stat.S_ISREG(info.st_mode):
                            receipt["regular_files"] += 1
                            receipt["logical_bytes"] += info.st_size
                            require(receipt["logical_bytes"] <= LINUX_CACHE_BYTES, "build exceeds logical byte limit")
                        else:
                            raise ValueError("special file in build")
        require(time.monotonic() - started <= LINUX_SCAN_SECONDS, "build scan exceeded time bound")
        receipt["complete"] = True
    except (OSError, ValueError, RuntimeError) as error:
        receipt["reason"] = str(error)
    receipt["elapsed_seconds"] = round(time.monotonic() - started, 6)
    return receipt


def linux_dependencies(workspace):
    result = {}
    for name in ("Package.swift", "Package.resolved"):
        path = workspace / name
        require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 1024 * 1024,
                "missing or unbounded dependency manifest")
        with path.open("rb") as stream:
            data = stream.read(1024 * 1024 + 1)
        require(len(data) <= 1024 * 1024, "dependency manifest exceeded bound")
        result[name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    return result


def linux_version(command):
    result = subprocess.run(command, capture_output=True, timeout=10, check=True)
    require(len(result.stdout) <= 16384 and len(result.stderr) <= 16384, "toolchain identity output exceeded bound")
    text = result.stdout.decode("utf-8")
    require(text.strip(), "empty toolchain identity")
    return text


def linux_cache_plan(context, environment, version_reader=None):
    context.update(enabled=False, restore=False, save=False)
    try:
        require(environment.get("RUNNER_OS") == "Linux" and context["repository"] == "Jones-Systems/CodexBar",
                "unsupported cache runner/repository")
        require(re.fullmatch("[0-9a-f]{40}", context["actual_sha"] or "")
                and context["actual_sha"] == context["event_sha"], "unproved checkout identity")
        for name in ("run_id", "run_attempt", "ref"):
            require(context[name], f"missing {name}")
        image = {name: environment.get(name, "")
                 for name in ("RUNNER_ARCH", "LINUX_RUNNER_LABEL", "ImageOS", "ImageVersion")}
        context["image"] = image
        require(all(isinstance(value, str) and value.strip() and len(value) <= 4096 for value in image.values()),
                "missing runner image identity")
        require(image["RUNNER_ARCH"] in ("X64", "ARM64"), "unsupported Linux architecture")
        workspace, staging = linux_directories(environment)
        version_reader = version_reader or linux_version
        versions = context["toolchain"] = {}
        for name, command in (("swift", ["swift", "--version"]), ("swiftpm", ["swift", "package", "--version"])):
            versions[name] = version_reader(command)
        require(all(isinstance(value, str) and value.strip() and len(value) <= 16384 for value in versions.values()),
                "missing toolchain identity")
        dependencies = linux_dependencies(workspace)
        hashes = {name: hashlib.sha256(encode(value).encode()).hexdigest()
                  for name, value in (("image", image), ("toolchain", versions), ("dependencies", dependencies))}
        prefix = f"codexbar-linux-glibc-build-v1-{image['RUNNER_ARCH']}-" + "-".join(hashes.values()) + "-"
        context.update(workspace=str(workspace), staging=str(staging), image=image, toolchain=versions,
                       dependencies=dependencies, identity_hashes=hashes, restore_prefix=prefix,
                       requested_key=prefix + context["actual_sha"],
                       storage_before_lookup=linux_storage(workspace, staging),
                       scan_before_lookup=linux_build_scan(workspace))
        require(context["scan_before_lookup"]["complete"] and not context["scan_before_lookup"]["exists"],
                "cache restore requires an absent build tree and complete fixture scan")
        require(context["storage_before_lookup"]["eligible"], "insufficient cache staging/workspace space")
        context["enabled"] = context["linux_cache_mode"] != "off"
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        context["refusal"] = str(error)
        context["fatal"] = context["linux_cache_mode"] == "warm"
    return context


class CacheMetadataNoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, *_args, **_kwargs):
        raise ValueError("cache metadata redirects are not permitted")


def linux_cache_metadata(environment, key):
    """Read one bounded repository metadata page; never download cache content here."""
    require(environment.get("GITHUB_REPOSITORY") == "Jones-Systems/CodexBar", "unexpected cache repository")
    token = environment.get("GH_TOKEN", "")
    require(token, "cache metadata token unavailable")
    url = "https://api.github.com/repos/Jones-Systems/CodexBar/actions/caches?" + urllib.parse.urlencode({
        "key": key, "per_page": 100,
    })
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
        "Authorization": "Bearer " + token, "X-GitHub-Api-Version": "2022-11-28"})
    with urllib.request.build_opener(CacheMetadataNoRedirect()).open(request, timeout=10) as response:
        require(not response.headers.get("Link"), "cache metadata pagination is ambiguous")
        data = response.read(LINUX_METADATA_BYTES + 1)
    require(len(data) <= LINUX_METADATA_BYTES, "cache metadata response exceeded bound")
    return json.loads(data)


def linux_cache_entry(document, key, context, environment):
    require(isinstance(document, dict), "cache metadata is unavailable")
    entries = document.get("actions_caches")
    require(isinstance(entries, list) and type(document.get("total_count")) is int
            and document["total_count"] == len(entries) <= 100
            and all(isinstance(entry, dict) for entry in entries), "cache metadata is truncated or unavailable")
    matches = [entry for entry in entries if entry.get("key") == key]
    require(len(matches) == 1, "exact cache metadata is absent or ambiguous")
    entry = matches[0]
    allowed_refs = {context["ref"]}
    for variable in ("GITHUB_BASE_REF", "LINUX_DEFAULT_BRANCH"):
        if environment.get(variable):
            allowed_refs.add("refs/heads/" + environment[variable])
    require(isinstance(entry.get("ref"), str) and len(entry["ref"]) <= 1024 and entry["ref"] in allowed_refs
            and isinstance(entry.get("version"), str) and 0 < len(entry["version"]) <= 256
            and type(entry.get("id")) is int and entry["id"] > 0, "cache ref/version/id is unavailable")
    require(type(entry.get("size_in_bytes")) is int and 0 < entry["size_in_bytes"] <= LINUX_CACHE_BYTES,
            "cache compressed size is unavailable or exceeds limit")
    require(key.startswith(context["restore_prefix"])
            and re.fullmatch("[0-9a-f]{40}", key[len(context["restore_prefix"]):]),
            "cache key leaves compatible family")
    return {name: entry.get(name) for name in ("id", "key", "ref", "version", "size_in_bytes", "created_at")}


def linux_approve_restore(context, environment, metadata_reader=None):
    context["restore"] = False
    try:
        require(context["enabled"] and environment.get("LINUX_LOOKUP_OUTCOME") == "success", "cache lookup unavailable")
        matched = environment.get("LINUX_MATCHED_KEY", "")
        context["lookup_matched_key"] = matched
        require(matched, "cache miss")
        require(context["linux_cache_mode"] != "warm" or matched == context["requested_key"],
                "warm requires the exact source cache")
        require(matched.startswith(context["restore_prefix"])
                and re.fullmatch("[0-9a-f]{40}", matched[len(context["restore_prefix"]):]),
                "cache lookup left the compatible family")
        metadata_reader = metadata_reader or linux_cache_metadata
        entry = linux_cache_entry(metadata_reader(environment, matched), matched, context, environment)
        workspace, staging = linux_directories(environment)
        context.update(approved_entry=entry, producer_source=matched[-40:],
                       storage_before_restore=linux_storage(workspace, staging),
                       scan_before_restore=linux_build_scan(workspace))
        require(context["storage_before_restore"]["eligible"] and context["scan_before_restore"]["complete"]
                and not context["scan_before_restore"]["exists"], "restore admission changed")
        context["restore"] = True
    except (OSError, ValueError, KeyError, TypeError) as error:
        context["refusal"] = str(error)
        context["fatal"] = context["linux_cache_mode"] == "warm"
    return context


def linux_after_restore(context, environment, metadata_reader=None):
    context["restore_outcome"] = environment.get("LINUX_RESTORE_OUTCOME", "unknown")
    context["restored_key"] = environment.get("LINUX_RESTORED_KEY", "")
    try:
        require(context["restore"] and context["restore_outcome"] == "success"
                and context["restored_key"] == context["approved_entry"]["key"],
                "restore failed or matched key changed")
        workspace, staging = linux_directories(environment)
        context["scan_after_restore"] = linux_build_scan(workspace)
        require(context["scan_after_restore"]["complete"] and context["scan_after_restore"]["exists"],
                "restored build tree is absent, invalid or incompletely scanned")
        metadata_reader = metadata_reader or linux_cache_metadata
        observed = linux_cache_entry(metadata_reader(environment, context["restored_key"]),
                                     context["restored_key"], context, environment)
        require(observed == context["approved_entry"], "restored cache metadata changed after approval")
        context["restored"] = True
        context["restored_exact"] = context["restored_key"] == context["requested_key"]
        context["storage_after_restore"] = linux_storage(workspace, staging)
    except (OSError, ValueError, KeyError, TypeError) as error:
        # A download may already have changed .build. Never delete or relabel it cold.
        context.update(fatal=True, refusal=str(error), restored=False)
    return context


def linux_input_deadline(deadline):
    require(time.monotonic() <= deadline, "input metadata processing exceeded time bound")


def linux_input_git(workspace, arguments, deadline):
    """Bound Git's metadata pipe; no hooks, text conversion, or external diff is requested."""
    command = ["git", "-c", "core.fsmonitor=false", "-C", str(workspace), *arguments]
    output = bytearray()
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while True:
                    linux_input_deadline(deadline)
                    require(selector.select(max(0, deadline - time.monotonic())), "input Git read timed out")
                    block = os.read(process.stdout.fileno(), 65536)
                    if not block:
                        break
                    output.extend(block)
                    require(len(output) <= LINUX_INPUT_METADATA_BYTES, "input Git inventory exceeded byte bound")
            require(process.wait(timeout=max(0.001, deadline - time.monotonic())) == 0, "input Git read failed")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    return bytes(output)


def linux_input_inventory(workspace, source, deadline):
    require(linux_input_git(workspace, ["rev-parse", "HEAD"], deadline).decode().strip() == source,
            "input checkout source changed")
    committed = linux_input_git(workspace, ["ls-tree", "-r", "-z", "--full-tree", source,
                                           "--", *LINUX_INPUT_ROOTS], deadline)
    indexed = linux_input_git(workspace, ["ls-files", "--stage", "--cached", "--others",
                                         "-z", "--", *LINUX_INPUT_ROOTS], deadline)

    def parse(raw, tree):
        require(raw.endswith(b"\0"), "missing or unterminated input inventory")
        records = []
        for line in raw[:-1].split(b"\0"):
            header, path = line.split(b"\t", 1)
            fields = header.decode("ascii").split(" ")
            require(len(fields) == 3 and fields[0] in ("100644", "100755", "120000"),
                    "untracked, conflicted or unsupported input")
            require(fields[1 if tree else 2] == ("blob" if tree else "0"), "non-file or conflicted input")
            oid = fields[2 if tree else 1]
            require(re.fullmatch("[0-9a-f]{40}", oid), "unsupported input object identity")
            records.append({"path": path.decode("utf-8"), "git_mode": fields[0], "git_oid": oid})
        records.sort(key=lambda item: item["path"])
        require(0 < len(records) <= LINUX_INPUT_PATHS
                and len({item["path"] for item in records}) == len(records), "input count or uniqueness failed")
        return records

    records = parse(committed, True)
    require(records == parse(indexed, False), "complete input set/index differs from committed source")
    return records


def linux_input_parts(path):
    require(isinstance(path, str) and 0 < len(path.encode()) <= 4096, "invalid input path length")
    parts = path.split("/")
    require(all(part and part not in (".", "..", ".git", ".build") and "\0" not in part
                and not part.startswith(FIXTURE_PREFIXES) for part in parts), "input path leaves containment")
    return parts


def linux_input_fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


@contextlib.contextmanager
def linux_input_parent(root_fd, path):
    parts = linux_input_parts(path)
    with contextlib.ExitStack() as stack:
        current = root_fd
        chain = []
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=current)
            stack.callback(os.close, child)
            chain.append((current, part, child))
            current = child

        def check():
            for parent, name, child in chain:
                observed = os.stat(name, dir_fd=parent, follow_symlinks=False)
                opened = os.fstat(child)
                require(stat.S_ISDIR(observed.st_mode)
                        and (observed.st_dev, observed.st_ino) == (opened.st_dev, opened.st_ino),
                        "input ancestor changed during processing")

        check()
        yield current, parts[-1], check
        check()


def linux_input_link(root_fd, path, text):
    require(text and not text.startswith("/") and len(text.encode()) <= 4096, "unsupported input symlink target")
    target = path.split("/")[:-1]
    for part in text.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            require(target, "input symlink escapes checkout")
            target.pop()
        else:
            target.append(part)
    resolved = "/".join(target)
    linux_input_parts(resolved)
    with linux_input_parent(root_fd, resolved) as (parent, name, check):
        info = os.stat(name, dir_fd=parent, follow_symlinks=False)
        require(stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode),
                "input symlink target is missing, chained or unsupported")
        check()
    return resolved


def linux_input_content(entry):
    return {key: value for key, value in entry.items() if key != "mtime_ns"}


def linux_input_update(descriptor, parent, name, current, mtime_ns):
    # Descriptor/no-follow updates never traverse the leaf symlink. A race is a failed treatment.
    if descriptor is not None:
        os.utime(descriptor, ns=(current.st_atime_ns, mtime_ns))
    else:
        os.utime(name, ns=(current.st_atime_ns, mtime_ns), dir_fd=parent, follow_symlinks=False)


def linux_input_visit(root_fd, item, deadline, remaining, expected=None, fingerprint=None, progress=None):
    linux_input_deadline(deadline)
    with linux_input_parent(root_fd, item["path"]) as (parent, name, check), contextlib.ExitStack() as stack:
        before = os.stat(name, dir_fd=parent, follow_symlinks=False)
        before_id = linux_input_fingerprint(before)
        require(fingerprint is None or before_id == fingerprint, "input changed after complete verification")
        require(0 <= before.st_size <= remaining, "input content exceeded byte bound")
        entry = {**item, "mode": stat.S_IMODE(before.st_mode), "size": before.st_size,
                 "mtime_ns": before.st_mtime_ns}
        blob = hashlib.sha1(f"blob {before.st_size}\0".encode())
        digest = hashlib.sha256()
        descriptor = None
        if stat.S_ISREG(before.st_mode) and item["git_mode"] in ("100644", "100755"):
            require(bool(before.st_mode & 0o111) == (item["git_mode"] == "100755"),
                    "input executable mode differs from committed source")
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
            stack.callback(os.close, descriptor)
            require(linux_input_fingerprint(os.fstat(descriptor)) == before_id, "input replaced while opening")
            total = 0
            while True:
                linux_input_deadline(deadline)
                block = os.read(descriptor, 65536)
                if not block:
                    break
                total += len(block)
                require(total <= before.st_size, "input grew while hashing")
                blob.update(block)
                digest.update(block)
            require(total == before.st_size and linux_input_fingerprint(os.fstat(descriptor)) == before_id,
                    "input changed while hashing")
            entry["type"] = "file"
        elif stat.S_ISLNK(before.st_mode) and item["git_mode"] == "120000":
            text = os.readlink(name, dir_fd=parent)
            data = os.fsencode(text)
            require(len(data) == before.st_size, "input symlink changed while reading")
            blob.update(data)
            digest.update(data)
            entry.update(type="symlink", target=text, contained_target=linux_input_link(root_fd, item["path"], text))
        else:
            raise ValueError("input type differs from committed file/symlink")
        entry["sha256"] = digest.hexdigest()
        require(blob.hexdigest() == item["git_oid"], "input content differs from committed source")
        require(linux_input_fingerprint(os.stat(name, dir_fd=parent, follow_symlinks=False)) == before_id,
                "input replaced while verifying")
        check()
        if expected is not None:
            require(linux_input_content(entry) == linux_input_content(expected), "input content/type/mode changed")
            if entry["mtime_ns"] != expected["mtime_ns"]:
                linux_input_deadline(deadline)
                progress.update(attempted=progress["attempted"] + 1, last_path=item["path"])
                current = os.fstat(descriptor) if descriptor is not None else before
                linux_input_update(descriptor, parent, name, current, expected["mtime_ns"])
                after = os.stat(name, dir_fd=parent, follow_symlinks=False)
                require((after.st_dev, after.st_ino, after.st_mode, after.st_size) == before_id[:4]
                        and after.st_mtime_ns == expected["mtime_ns"], "input timestamp update was not exact")
                check()
                progress["applied"] += 1
        return entry, before_id


def linux_input_snapshot(workspace, context, deadline, inventory_reader=None):
    reader = inventory_reader or linux_input_inventory
    inventory = reader(workspace, context["actual_sha"], deadline)
    require(0 < len(inventory) <= LINUX_INPUT_PATHS, "input count exceeds bound")
    entries, fingerprints, total = [], {}, 0
    root_fd = os.open(workspace, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for item in inventory:
            entry, fingerprint = linux_input_visit(root_fd, item, deadline, LINUX_INPUT_BYTES - total)
            total += entry["size"]
            entries.append(entry)
            fingerprints[item["path"]] = fingerprint
        require(inventory == reader(workspace, context["actual_sha"], deadline), "input inventory changed during scan")
        linux_input_deadline(deadline)
        return entries, fingerprints
    finally:
        os.close(root_fd)


@contextlib.contextmanager
def linux_input_build_fd(workspace, create=False):
    root = os.open(workspace, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        if create:
            try:
                os.mkdir(".build", dir_fd=root)
            except FileExistsError:
                pass
        build = os.open(".build", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root)
        try:
            yield build
        finally:
            os.close(build)
    finally:
        os.close(root)


def linux_input_manifest(workspace, value=None):
    with linux_input_build_fd(workspace, create=value is not None) as build:
        if value is None:
            descriptor = os.open(LINUX_INPUT_MANIFEST, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=build)
            with os.fdopen(descriptor, "rb") as stream:
                before = os.fstat(stream.fileno())
                require(stat.S_ISREG(before.st_mode) and before.st_size <= LINUX_INPUT_METADATA_BYTES,
                        "input manifest is not a bounded regular file")
                data = stream.read(LINUX_INPUT_METADATA_BYTES + 1)
                require(linux_input_fingerprint(before) == linux_input_fingerprint(os.fstat(stream.fileno())),
                        "input manifest changed while reading")
            require(len(data) <= LINUX_INPUT_METADATA_BYTES, "input manifest exceeded byte bound")
            value = json.loads(data)
        else:
            data = (encode(value) + "\n").encode()
            require(len(data) <= LINUX_INPUT_METADATA_BYTES, "input manifest exceeded byte bound")
            temporary = ".codexbar-input-timestamps-" + uuid.uuid4().hex
            try:
                descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                     0o600, dir_fd=build)
                with os.fdopen(descriptor, "wb") as stream:
                    stream.write(data)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(temporary, LINUX_INPUT_MANIFEST, src_dir_fd=build, dst_dir_fd=build)
            finally:
                try:
                    os.unlink(temporary, dir_fd=build)
                except FileNotFoundError:
                    pass
    return value, hashlib.sha256(data).hexdigest(), len(data)


def linux_input_binding(context):
    return {key: context[key] for key in ("actual_sha", "requested_key", "identity_hashes")}


def linux_input_validate_manifest(manifest, context, state):
    require(isinstance(manifest, dict) and manifest.get("schema") == "codexbar.linux-input-timestamps/v1"
            and manifest.get("state") == state and manifest.get("roots") == list(LINUX_INPUT_ROOTS)
            and manifest.get("binding") == linux_input_binding(context), "input manifest source/state/binding differs")
    entries = manifest.get("entries")
    require(isinstance(entries, list) and 0 < len(entries) <= LINUX_INPUT_PATHS
            and all(isinstance(entry, dict) and type(entry.get("mtime_ns")) is int
                    and 0 <= entry["mtime_ns"] < 2 ** 63 for entry in entries), "invalid input timestamp entries")
    producer = manifest.get("producer", {})
    require(all(isinstance(producer.get(key), str) and producer[key] for key in ("run_id", "run_attempt", "ref")),
            "input producer identity unavailable")
    return entries


def linux_input_timestamps(context, environment, inventory_reader=None):
    mode = context.get("linux_timestamp_mode", "off")
    if mode == "off":
        return context
    started = time.monotonic()
    deadline = started + LINUX_INPUT_SECONDS
    receipt = context["input_timestamps"] = {"mode": mode, "status": "unavailable", "attempted": 0, "applied": 0,
        "input_byte_limit": LINUX_INPUT_BYTES, "path_limit": LINUX_INPUT_PATHS,
        "metadata_byte_limit": LINUX_INPUT_METADATA_BYTES, "time_limit_seconds": LINUX_INPUT_SECONDS}
    try:
        require(context["event"] == "workflow_dispatch" and environment.get("RUNNER_OS") == "Linux"
                and context["enabled"] and not context.get("fatal"), "timestamp treatment was not admitted")
        workspace, _ = linux_directories(environment)
        if mode == "record":
            require(context["linux_cache_mode"] == "seed" and not context.get("restored_exact"),
                    "timestamp seed must be able to publish a new exact cache entry")
            entries, _ = linux_input_snapshot(workspace, context, deadline, inventory_reader)
            manifest = {"schema": "codexbar.linux-input-timestamps/v1", "state": "before-build",
                "roots": list(LINUX_INPUT_ROOTS), "binding": linux_input_binding(context), "entries": entries,
                "producer": {key: context[key] for key in ("run_id", "run_attempt", "ref")}}
            _, digest, size = linux_input_manifest(workspace, manifest)
            receipt.update(status="recorded-before-build", manifest_sha256=digest, manifest_bytes=size,
                           before_matching=len(entries), verification_passes=1)
        else:
            require(mode == "replay" and context["linux_cache_mode"] == "warm" and context.get("restored_exact")
                    and context.get("restored") and context.get("producer_source") == context["actual_sha"],
                    "timestamp replay requires a verified exact-source warm restore")
            require(os.utime in os.supports_fd and os.utime in os.supports_follow_symlinks,
                    "native nanosecond/no-follow timestamp capability is unavailable")
            manifest, digest, size = linux_input_manifest(workspace)
            expected = linux_input_validate_manifest(manifest, context, "qualified")
            entries, fingerprints = linux_input_snapshot(workspace, context, deadline, inventory_reader)
            require([linux_input_content(item) for item in entries] == [linux_input_content(item) for item in expected],
                    "complete input manifest differs before replay")
            # A second content read detects persistent writes hidden by metadata observation precision.
            confirmed, confirmed_fingerprints = linux_input_snapshot(workspace, context, deadline, inventory_reader)
            require(confirmed == entries and confirmed_fingerprints == fingerprints,
                    "input changed between complete pre-replay scans")
            receipt.update(manifest_sha256=digest, manifest_bytes=size, producer=manifest["producer"],
                           before_matching=sum(a["mtime_ns"] == b["mtime_ns"] for a, b in zip(entries, expected)))
            root = os.open(workspace, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                for current, saved in zip(entries, expected):
                    item = {key: current[key] for key in ("path", "git_mode", "git_oid")}
                    linux_input_visit(root, item, deadline, LINUX_INPUT_BYTES, saved,
                                      fingerprints[item["path"]], receipt)
            finally:
                os.close(root)
            verified, _ = linux_input_snapshot(workspace, context, deadline, inventory_reader)
            require(verified == expected, "input contents/timestamps changed during replay")
            receipt.update(status="replayed-and-verified", after_matching=len(verified), verification_passes=4)
        receipt.update(input_count=len(entries), input_bytes=sum(item["size"] for item in entries))
        linux_input_deadline(deadline)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        receipt.update(status="failed", reason=str(error), partial_replay_possible=receipt["attempted"] > 0)
        context.update(fatal=True, refusal="input timestamp treatment failed")
    receipt["elapsed_seconds"] = round(time.monotonic() - started, 6)
    return context


def linux_input_after_build(context, environment, inventory_reader=None):
    mode = context.get("linux_timestamp_mode", "off")
    if mode == "off":
        return
    started = time.monotonic()
    workspace, _ = linux_directories(environment)
    manifest, digest, _ = linux_input_manifest(workspace)
    expected = linux_input_validate_manifest(manifest, context, "before-build" if mode == "record" else "qualified")
    require(digest == context["input_timestamps"]["manifest_sha256"], "input manifest changed during native commands")
    entries, _ = linux_input_snapshot(workspace, context, started + LINUX_INPUT_SECONDS, inventory_reader)
    require(entries == expected, "producer/native build changed input contents, modes, set or timestamps")
    if mode == "record":
        manifest["state"] = "qualified"
        _, digest, size = linux_input_manifest(workspace, manifest)
        context["input_timestamps"].update(manifest_sha256=digest, manifest_bytes=size, status="qualified-after-build")
    context["input_timestamps"].update(after_build_matching=len(entries),
                                      after_build_seconds=round(time.monotonic() - started, 6))


def linux_before_save(context, environment):
    context["save"] = False
    context["command_outcomes"] = {name: environment.get("LINUX_" + name.upper() + "_OUTCOME", "unknown")
                                   for name in ("release", "tests", "smoke")}
    windows = {}
    for name, start, end in (("release", "BEFORE_RELEASE_END", "AFTER_RELEASE_START"),
                             ("tests", "AFTER_RELEASE_END", "AFTER_TESTS_START"),
                             ("smoke", "AFTER_TESTS_END", None)):
        try:
            started = float(environment["LINUX_" + start])
            ended = float(environment["LINUX_" + end]) if end else time.time()
            require(ended >= started > 0, "invalid command window")
            windows[name] = {"seconds": round(ended - started, 6), "kind": "step-window-upper-bound"}
        except (KeyError, ValueError):
            windows[name] = {"kind": "unavailable"}
    context["command_windows"] = windows
    try:
        require(context["enabled"] and not context.get("fatal"), "cache disabled or prior restore failed")
        require(all(value == "success" for value in context["command_outcomes"].values()),
                "qualification command did not pass")
        workspace, staging = linux_directories(environment)
        require(linux_dependencies(workspace) == context["dependencies"], "dependency manifests changed during build")
        linux_input_after_build(context, environment)
        context.update(scan_before_save=linux_build_scan(workspace),
                       storage_before_save=linux_storage(workspace, staging))
        require(context["scan_before_save"]["complete"] and context["scan_before_save"]["exists"]
                and context["storage_before_save"]["eligible"], "save scan/storage admission refused")
        context["save"] = not context.get("restored_exact", False)
        context["save_disposition"] = "eligible" if context["save"] else "exact-key-already-restored"
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        context["save_disposition"] = str(error)
        if context.get("linux_timestamp_mode", "off") != "off":
            context.update(fatal=True, refusal="timestamp treatment did not qualify after native commands")
    return context


def linux_after_save(context, environment, metadata_reader=None):
    context["save_outcome"] = environment.get("LINUX_SAVE_OUTCOME", "unknown")
    context["publication"] = "not-attempted"
    if context["save"]:
        try:
            require(context["save_outcome"] == "success", "save action did not succeed")
            metadata_reader = metadata_reader or linux_cache_metadata
            context["published_entry"] = linux_cache_entry(metadata_reader(environment, context["requested_key"]),
                                                           context["requested_key"], context, environment)
            require(context["published_entry"]["ref"] == context["ref"], "save readback belongs to another ref")
            context["publication"] = "exact-entry-observed; producer-run-unproved"
        except (OSError, ValueError, KeyError, TypeError) as error:
            context.update(publication="unavailable", publication_reason=str(error))
    return context


def linux_cache_command(args, environment):
    started = time.time()
    if args.phase == "source":
        context = linux_cache_source(environment, args.checkout_sha)
    else:
        raw = environment.get("LINUX_CACHE_CONTEXT", "")
        require(len(raw.encode()) <= 128 * 1024, "cache receipt exceeded bound")
        context = json.loads(raw)
        require(context["schema"] == "codexbar.linux-build-cache/v1"
                and context["event_sha"] == environment["GITHUB_SHA"]
                and context["run_id"] == environment["GITHUB_RUN_ID"]
                and context["run_attempt"] == environment["GITHUB_RUN_ATTEMPT"]
                and context["ref"] == environment["GITHUB_REF"], "cache receipt owner changed")
        handlers = {"plan": linux_cache_plan, "approve-restore": linux_approve_restore,
                    "after-restore": linux_after_restore, "input-timestamps": linux_input_timestamps,
                    "before-save": linux_before_save,
                    "after-save": linux_after_save}
        context = handlers[args.phase](context, environment)
    context["phase"] = args.phase
    context["phase_timings"][args.phase] = {"started_at": started, "finished_at": time.time()}
    for phase, previous, name in (("after-restore", "approve-restore", "restore"),
                                  ("after-save", "before-save", "save")):
        if args.phase == phase and previous in context["phase_timings"]:
            context[name + "_window"] = {"kind": "step-window-upper-bound",
                "seconds": round(started - context["phase_timings"][previous]["finished_at"], 6)}
    encoded = encode(context)
    require(len(encoded.encode()) <= 128 * 1024, "cache receipt exceeded bound")
    with open(environment["GITHUB_OUTPUT"], "a") as output:
        output.write("context=" + encoded + "\n")
        for name in ("enabled", "restore", "save"):
            output.write(f"{name}={str(context[name]).lower()}\n")
        output.write("key=" + context.get("requested_key", "") + "\n")
        output.write("restore-prefix=" + (context.get("restore_prefix", "")
                     if context["linux_cache_mode"] != "warm" else "") + "\n")
        output.write("approved-key=" + context.get("approved_entry", {}).get("key", "") + "\n")
    print(encoded)
    return int(context.get("fatal", False))


def measure_linux(environment, phase):
    """Observe existing build output without changing command status."""
    receipt = {"schema": "codexbar.linux-build-storage/v1", "phase": phase,
               "source_revision": environment.get("GITHUB_SHA"), "runner_arch": environment.get("RUNNER_ARCH"),
               "image_version": environment.get("ImageVersion"), "declared_swift_version": environment.get("SWIFT_VERSION"),
               "cache_enabled": environment.get("LINUX_CACHE_ACTIVE") == "true",
               "linux_cache_mode": environment.get("LINUX_CACHE_MODE", "off"),
               "cache_path_manifest": [".build"], "status": "unavailable",
               "entry_limit": 200000, "time_limit_seconds": 10}
    started = time.monotonic()
    entries = 0
    def scan_error(error):
        raise error
    try:
        require(phase in ("before-release", "after-release", "after-tests"), "unknown measurement phase")
        workspace = Path(environment["GITHUB_WORKSPACE"]).resolve(strict=True)
        require(environment.get("RUNNER_OS") == "Linux", "storage observation requires Linux")
        require(re.fullmatch("[0-9a-f]{40}", environment.get("GITHUB_SHA", "")), "missing source identity")
        build = workspace / ".build"
        require(not build.is_symlink(), "build root is a symlink")
        receipt.update(available_bytes=shutil.disk_usage(workspace).free, build_exists=build.exists(),
                       regular_files=0, logical_bytes=0, symlinks=0, fixture_paths_in_build=0)
        prefixes = (".test-fixtures-", ".swift-test-evidence-")
        fixture_roots = [path for path in workspace.iterdir() if path.name.startswith(".test-fixtures-")]
        receipt["fixture_parent_count"] = len(fixture_roots)
        receipt["fixture_parents_absent"] = not fixture_roots
        receipt["evidence_root_count"] = sum(path.name.startswith(".swift-test-evidence-") for path in workspace.iterdir())
        tree = os.walk(build, followlinks=False, onerror=scan_error) if build.exists() else ()
        for directory, dirs, files in tree:
            for name in dirs + files:
                entries += 1
                require(entries <= receipt["entry_limit"] and time.monotonic() - started <= receipt["time_limit_seconds"],
                        "storage observation exceeded its entry/time bound")
                path = Path(directory) / name
                info = path.lstat()
                receipt["fixture_paths_in_build"] += int(name.startswith(prefixes))
                if stat.S_ISLNK(info.st_mode):
                    receipt["symlinks"] += 1
                    receipt["fixture_paths_in_build"] += int(any(
                        part.startswith(prefixes) for part in Path(os.readlink(path)).parts))
                elif stat.S_ISREG(info.st_mode):
                    receipt["regular_files"] += 1
                    receipt["logical_bytes"] += info.st_size
        receipt["status"] = "observed"
    except (OSError, ValueError, KeyError, TypeError) as error:
        receipt["error_type"] = type(error).__name__
        receipt["error_errno"] = getattr(error, "errno", None)
        if isinstance(error, ValueError):
            receipt["reason"] = str(error)
    receipt["elapsed_seconds"] = round(time.monotonic() - started, 6)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("plan")
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("--checkout-sha", required=True)
    verify_parser = commands.add_parser("verify")
    verify_parser.add_argument("root", type=Path)
    cleanup_parser = commands.add_parser("cleanup")
    cleanup_parser.add_argument("root", type=Path)
    measure_parser = commands.add_parser("measure-linux")
    measure_parser.add_argument("--phase", required=True)
    measure_parser.add_argument("--step-times", action="store_true")
    linux_parser = commands.add_parser("linux-cache")
    linux_parser.add_argument("phase", choices=("source", "plan", "approve-restore", "after-restore",
                                               "input-timestamps", "before-save", "after-save"))
    linux_parser.add_argument("--checkout-sha")
    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("--baseline", type=Path, nargs="+", required=True)
    compare_parser.add_argument("--candidate", type=Path, nargs="+", required=True)
    args = parser.parse_args()
    try:
        if args.command == "plan":
            env = os.environ
            matrix = resolve_plan(env["GITHUB_EVENT_NAME"], env.get("CAMPAIGN_GROUP_SIZE", ""),
                                  env.get("CAMPAIGN_SHARD_COUNT", ""), env.get("CAMPAIGN_EXPECTED_SHA", ""),
                                  env["GITHUB_SHA"], env.get("CAMPAIGN_CACHE_MODE", ""),
                                  env.get("LINUX_CACHE_MODE", "off"), env.get("LINUX_TIMESTAMP_MODE", "off"))
            with open(env["GITHUB_OUTPUT"], "a") as output:
                output.write("matrix=" + encode(matrix) + "\n")
            print(encode(matrix))
        elif args.command == "prepare":
            root = prepare(os.environ, args.checkout_sha)
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(f"root={root}\n")
            print(f"Campaign evidence: {root}; budget={MAX_BYTES} bytes; cleanup after artifact upload")
        elif args.command == "verify":
            receipt = verify(args.root)
            write_json(args.root / "receipt.json", receipt)
            require(receipt["complete_identity"], "; ".join(receipt["limitations"]))
            print(encode({"complete_identity": True, "functions": len(receipt["functions"]),
                          "cases": len(receipt["cases"])}))
        elif args.command == "cleanup":
            cleanup(args.root, os.environ)
        elif args.command == "measure-linux":
            started = time.time()
            receipt = measure_linux(os.environ, args.phase)
            if args.step_times:
                with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                    output.write(f"started-at={started}\nfinished-at={time.time()}\n")
            print(encode(receipt))
        elif args.command == "linux-cache":
            return linux_cache_command(args, os.environ)
        else:
            print(encode(compare([read_json(path) for path in args.baseline],
                                 [read_json(path) for path in args.candidate])))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Campaign evidence unavailable: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
