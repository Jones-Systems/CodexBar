#!/usr/bin/env python3
"""Validate manual campaign inputs and native receipts without dispatching work."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import time


ENV_KEY = "CODEXBAR_TEST_EVIDENCE_DIR"
SCHEMA = "codexbar.swift-test-campaign/v1"
MAX_BYTES = 128 * 1024 * 1024
RESERVE_BYTES = 512 * 1024 * 1024
ISOLATION = {"CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1", "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
             "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(values):
    return hashlib.sha256(("\n".join(sorted(values)) + "\n").encode()).hexdigest()


def resolve_plan(event, group_size="", shard_count="", expected_sha="", source_sha="", cache_mode=""):
    if event != "workflow_dispatch":
        group_size, shard_count, cache_mode = "4", "2", "ordinary"
    else:
        require(group_size in ("4", "12"), "group_size must be 4 or 12")
        require(shard_count in ("1", "2", "3"), "shard_count must be 1, 2 or 3")
        require(cache_mode in ("seed", "warm", "cold"), "cache_mode must be seed, warm or cold")
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


def measure_linux(environment, phase):
    """Observe existing build output; never change build status or enable caching."""
    receipt = {"schema": "codexbar.linux-build-storage/v1", "phase": phase,
               "source_revision": environment.get("GITHUB_SHA"), "runner_arch": environment.get("RUNNER_ARCH"),
               "image_version": environment.get("ImageVersion"), "declared_swift_version": environment.get("SWIFT_VERSION"),
               "cache_enabled": False, "cache_path_manifest": [".build"], "status": "unavailable",
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
    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("--baseline", type=Path, nargs="+", required=True)
    compare_parser.add_argument("--candidate", type=Path, nargs="+", required=True)
    args = parser.parse_args()
    try:
        if args.command == "plan":
            env = os.environ
            matrix = resolve_plan(env["GITHUB_EVENT_NAME"], env.get("CAMPAIGN_GROUP_SIZE", ""),
                                  env.get("CAMPAIGN_SHARD_COUNT", ""), env.get("CAMPAIGN_EXPECTED_SHA", ""),
                                  env["GITHUB_SHA"], env.get("CAMPAIGN_CACHE_MODE", ""))
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
            print(encode(measure_linux(os.environ, args.phase)))
        else:
            print(encode(compare([read_json(path) for path in args.baseline],
                                 [read_json(path) for path in args.candidate])))
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Campaign evidence unavailable: {type(error).__name__}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
