#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${ROOT_DIR}/.test-sharding.XXXXXX")"
cleanup() {
  local status=$?
  if ! rm -rf -- "${TEMP_DIR}"; then
    printf 'Failed to remove sharding-test scratch: %s\n' "${TEMP_DIR}" >&2
    [[ "${status}" -ne 0 ]] || status=1
  fi
  exit "${status}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
export TMPDIR="${TEMP_DIR}"

IFS= read -r -d '' FAKE_SWIFT_SCRIPT <<'EOF' || true
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_SWIFT_LOG}"
if [[ "$*" == "build --build-tests" ]]; then
  if [[ "${FAKE_SWIFT_MODE:-success}" == "build_fail" ]]; then
    echo "build failure marker" >&2
    exit 43
  fi
  exit 0
fi
if [[ "$*" == "build --show-bin-path" ]]; then
  printf '%s\n' "${FAKE_SWIFT_BIN_PATH:?}"
  exit 0
fi
if [[ "$*" == "test list" || "$*" == "test list --skip-build" ]]; then
  if [[ "${FAKE_SWIFT_MODE:-success}" == "list_fail" ]]; then
    sleep 0.25
    printf 'test-list stdout marker\n'
    printf 'test-list stderr marker\n' >&2
    exit 42
  fi
  if [[ "${FAKE_SWIFT_MODE:-success}" == "list_sparkle_fail_once" && ! -f "${FAKE_SWIFT_STATE}" ]]; then
    printf 'failed\n' > "${FAKE_SWIFT_STATE}"
    printf 'Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle\n' >&2
    printf 'tried: %s/PackageFrameworks/Sparkle.framework/Versions/B/Sparkle\n' \
      "${FAKE_SWIFT_BIN_PATH:?}" >&2
    exit 1
  fi
  printf '%s\n' \
    "CodexBarTests.Alpha/test_one()" \
    "CodexBarTests.Alpha/test_two(argument:)" \
    "CodexBarTests.Beta/test_two" \
    "CodexBarTests.Gamma/test_three" \
    "CodexBarTests.Delta/test_four" \
    "CodexBarTests.Epsilon/test_five" \
    "CodexBarTests.Zeta/test_six" \
    "CodexBarTests.Eta/test_seven" \
    "CodexBarTests.Theta/test_eight" \
    'CodexBarTests.`top level works`()' \
    'CodexBarTests.`top/level slash works`()'
  exit 0
fi

is_group=0
if [[ "$*" == *"|"* ]]; then
  is_group=1
fi

next_group_attempt() {
  local attempt=0
  if [[ -f "${FAKE_SWIFT_STATE}" ]]; then
    read -r attempt < "${FAKE_SWIFT_STATE}"
  fi
  attempt=$((attempt + 1))
  printf '%s\n' "${attempt}" > "${FAKE_SWIFT_STATE}"
  printf '%s\n' "${attempt}"
}

case "${FAKE_SWIFT_MODE:-success}" in
  group_fail_once)
    if [[ "${is_group}" == "1" && "$(next_group_attempt)" == "1" ]]; then
      exit 1
    fi
    ;;
  group_always_fail)
    if [[ "${is_group}" == "1" ]]; then
      exit 1
    fi
    ;;
  group_timeout)
    if [[ "${is_group}" == "1" ]]; then
      sleep 2
    fi
    ;;
  singleton_timeout)
    if [[ "${is_group}" == "0" ]]; then
      sleep 2
    fi
    ;;
  group_fail_then_timeout)
    if [[ "${is_group}" == "1" ]]; then
      attempt="$(next_group_attempt)"
      if [[ "${attempt}" == "1" ]]; then
        exit 1
      fi
      sleep 2
    fi
    ;;
esac
EOF

reset_case() {
  local name="$1"
  export FAKE_SWIFT_LOG="${TEMP_DIR}/${name}-swift.log"
  export FAKE_SWIFT_STATE="${TEMP_DIR}/${name}-state"
  export GITHUB_STEP_SUMMARY="${TEMP_DIR}/${name}-summary.md"
  rm -f "${FAKE_SWIFT_LOG}" "${FAKE_SWIFT_STATE}" "${GITHUB_STEP_SUMMARY}"
}

run_harness() {
  python3 "${ROOT_DIR}/Scripts/ci_swift_test_by_suite.py" \
    "$@" \
    --swift-command /bin/bash \
    --swift-command-arg=-c \
    --swift-command-arg="${FAKE_SWIFT_SCRIPT}" \
    --swift-command-arg=fake-swift
}

python3 - "${ROOT_DIR}/.github/workflows/ci.yml" <<'PY'
import pathlib
import re
import sys

workflow = pathlib.Path(sys.argv[1]).read_text()
if "types: [opened, synchronize, reopened, ready_for_review, converted_to_draft]" not in workflow:
    raise SystemExit("CI must rerun when a pull request becomes ready or draft")
if "CI_PULL_REQUEST_DRAFT: ${{ github.event.pull_request.draft || false }}" not in workflow:
    raise SystemExit("CI must pass draft state to the macOS test gate")
if "macos-tests-deferred: ${{ steps.macos-tests.outputs.macos-tests-deferred }}" not in workflow:
    raise SystemExit("CI must expose whether macOS tests were deferred")
job_match = re.search(r"(?ms)^  swift-test-macos:\n(?P<body>.*?)(?=^  [a-zA-Z0-9_-]+:|\Z)", workflow)
if not job_match:
    raise SystemExit("swift-test-macos job not found in CI workflow")

job = job_match.group("body")
required_not_deferred = (
    "if: ${{ needs.changes.outputs.macos-tests == 'true' && "
    "needs.changes.outputs.macos-tests-deferred != 'true' }}"
)
if required_not_deferred not in job:
    raise SystemExit("swift-test-macos must skip only required tests explicitly deferred for drafts")
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / "Scripts"))
from ci_swift_test_campaign import resolve_plan
expected = [{"shard-index": index, "shard-count": 2, "group-size": 4,
             "cache-mode": "ordinary", "campaign": False} for index in (0, 1)]
for event in ("pull_request", "push"):
    if resolve_plan(event)["include"] != expected:
        raise SystemExit("ordinary CI must retain group four and exactly two shards")
if "matrix: ${{ fromJSON(needs.changes.outputs.macos-matrix) }}" not in job:
    raise SystemExit("macOS must consume the validated campaign matrix")
if "name: swift-test-macos (${{ matrix.shard-index }}, ${{ matrix.shard-count }})" not in job:
    raise SystemExit("ordinary macOS check names must remain stable")
if "CODEXBAR_TEST_SHARD_INDEX=${{ matrix.shard-index }}" not in job:
    raise SystemExit("swift-test-macos must pass matrix.shard-index to Scripts/test.sh")
if "CODEXBAR_TEST_SHARD_COUNT=${{ matrix.shard-count }}" not in job:
    raise SystemExit("swift-test-macos must pass matrix.shard-count to Scripts/test.sh")
PY

reset_case retry
export FAKE_SWIFT_MODE=group_fail_once
run_harness --group-size 4 --timeout 10 > "${TEMP_DIR}/retry.log"
grep -Fq "failed with exit code 1; retrying group once" "${TEMP_DIR}/retry.log"
grep -Fq "Swift test timing summary:" "${TEMP_DIR}/retry.log"
grep -Fq '| Discovered selections | `10` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `10` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `3` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| First-pass successful groups | `2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| First-pass failed groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Full-group retries | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `1` |' "${GITHUB_STEP_SUMMARY}"
[[ "$(grep -c '^test --skip-build --no-parallel' "${FAKE_SWIFT_LOG}")" -eq 4 ]]
grep -Fq "CodexBarTests\\.Alpha" "${FAKE_SWIFT_LOG}"
grep -Fq "CodexBarTests\\.Beta" "${FAKE_SWIFT_LOG}"
grep -Fq "CodexBarTests\\..*top\\ level\\ works" "${FAKE_SWIFT_LOG}"
grep -Fq "CodexBarTests\\..*top/level\\ slash\\ works" "${FAKE_SWIFT_LOG}"
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 6 ]]

reset_case strict
export FAKE_SWIFT_MODE=group_fail_once
set +e
CODEXBAR_TEST_GROUP_SIZE=4 \
  CODEXBAR_TEST_SUITE_TIMEOUT=10 \
  CODEXBAR_TEST_RETRY_NON_TIMEOUT_FAILURES=0 \
  "${ROOT_DIR}/Scripts/test.sh" \
    --limit-groups 1 \
    --swift-command /bin/bash \
    --swift-command-arg=-c \
    --swift-command-arg="${FAKE_SWIFT_SCRIPT}" \
    --swift-command-arg=fake-swift \
    > "${TEMP_DIR}/strict.log" 2>&1
strict_status=$?
set -e
[[ "${strict_status}" -eq 1 ]]
grep -Fq '| First-pass failed groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Full-group retries | `0` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `0` |' "${GITHUB_STEP_SUMMARY}"
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 3 ]]

reset_case shard-0
export FAKE_SWIFT_MODE=success
run_harness --group-size 4 --timeout 10 --shard-index 0 --shard-count 2 > "${TEMP_DIR}/shard-0.log"
grep -Fq '| Shard | `1/2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `6` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `2` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-1
run_harness --group-size 4 --timeout 10 --shard-index 1 --shard-count 2 > "${TEMP_DIR}/shard-1.log"
grep -Fq '| Shard | `2/2` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected selections | `4` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Selected groups | `1` |' "${GITHUB_STEP_SUMMARY}"

reset_case shard-list-0
run_harness --group-size 4 --timeout 10 --shard-index 0 --shard-count 2 --list-only \
  > "${TEMP_DIR}/shard-list-0.log" 2> "${TEMP_DIR}/shard-list-0.stderr"
reset_case shard-list-1
run_harness --group-size 4 --timeout 10 --shard-index 1 --shard-count 2 --list-only \
  > "${TEMP_DIR}/shard-list-1.log" 2> "${TEMP_DIR}/shard-list-1.stderr"
cat "${TEMP_DIR}/shard-list-0.log" "${TEMP_DIR}/shard-list-1.log" \
  | sort > "${TEMP_DIR}/shards-combined.log"
reset_case shard-list-all
run_harness --group-size 4 --timeout 10 --list-only 2> "${TEMP_DIR}/shard-list-all.stderr" \
  | sort > "${TEMP_DIR}/shards-expected.log"
diff -u "${TEMP_DIR}/shards-expected.log" "${TEMP_DIR}/shards-combined.log"
[[ "$(wc -l < "${TEMP_DIR}/shard-list-0.log")" -eq 6 ]]
[[ "$(wc -l < "${TEMP_DIR}/shard-list-1.log")" -eq 4 ]]
cat <<'EOF' | sort > "${TEMP_DIR}/selection-names.log"
CodexBarTests.Alpha
CodexBarTests.Beta
CodexBarTests.Gamma
CodexBarTests.Delta
CodexBarTests.Epsilon
CodexBarTests.Zeta
CodexBarTests.Eta
CodexBarTests.Theta
CodexBarTests.`top level works`()
CodexBarTests.`top/level slash works`()
EOF
diff -u "${TEMP_DIR}/selection-names.log" "${TEMP_DIR}/shards-expected.log"
for name in shard-list-0 shard-list-1 shard-list-all; do
  grep -Fq 'Discovered 10 test selections;' "${TEMP_DIR}/${name}.stderr"
  grep -Fq 'Fixture scratch parent (' "${TEMP_DIR}/${name}.stderr"
  grep -Fq '+ /bin/bash -c' "${TEMP_DIR}/${name}.stderr"
done

reset_case group-timeout
export FAKE_SWIFT_MODE=group_timeout
run_harness --group-size 4 --limit-groups 1 --timeout 1 > "${TEMP_DIR}/group-timeout.log"
grep -Fq "timed out; retrying selections one at a time" "${TEMP_DIR}/group-timeout.log"
grep -Fq '| Timed out groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `4` |' "${GITHUB_STEP_SUMMARY}"

reset_case singleton-timeout
export FAKE_SWIFT_MODE=singleton_timeout
set +e
run_harness --group-size 1 --limit-groups 1 --timeout 1 > "${TEMP_DIR}/singleton-timeout.log" 2>&1
singleton_timeout_status=$?
set -e
[[ "${singleton_timeout_status}" -eq 124 ]]
grep -Fq '| Timed out groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `0` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `0` |' "${GITHUB_STEP_SUMMARY}"

reset_case retry-timeout
export FAKE_SWIFT_MODE=group_fail_then_timeout
run_harness --group-size 4 --limit-groups 1 --timeout 1 > "${TEMP_DIR}/retry-timeout.log"
grep -Fq '| Full-group retries | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Timed out groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Isolated selection retries | `4` |' "${GITHUB_STEP_SUMMARY}"

reset_case repeated-failure
export FAKE_SWIFT_MODE=group_always_fail
set +e
run_harness --group-size 4 --limit-groups 1 --timeout 10 > "${TEMP_DIR}/failure.log" 2>&1
failure_status=$?
set -e
[[ "${failure_status}" -eq 1 ]]
grep -Fq '| Full-group retries | `1` |' "${GITHUB_STEP_SUMMARY}"
grep -Fq '| Recovered groups | `0` |' "${GITHUB_STEP_SUMMARY}"

reset_case list-failure
export FAKE_SWIFT_MODE=list_fail
set +e
run_harness --group-size 1 --timeout 10 > "${TEMP_DIR}/list-failure.log" 2>&1
list_failure_status=$?
set -e
[[ "${list_failure_status}" -ne 0 ]]
grep -Fq "test-list stdout marker" "${TEMP_DIR}/list-failure.log"
grep -Fq "test-list stderr marker" "${TEMP_DIR}/list-failure.log"
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 2 ]]
grep -Eq -- '- Discovery seconds: 0\.[1-9]' "${TEMP_DIR}/list-failure.log"
grep -Fq '| Discovered selections | `0` |' "${GITHUB_STEP_SUMMARY}"

reset_case sparkle-recovery
export FAKE_SWIFT_MODE=list_sparkle_fail_once
export FAKE_SWIFT_BIN_PATH="${TEMP_DIR}/sparkle-bin"
mkdir -p \
  "${FAKE_SWIFT_BIN_PATH}/Sparkle.framework/Versions/B" \
  "${FAKE_SWIFT_BIN_PATH}/Wrong.framework" \
  "${FAKE_SWIFT_BIN_PATH}/PackageFrameworks"
touch "${FAKE_SWIFT_BIN_PATH}/Sparkle.framework/Versions/B/Sparkle"
ln -s ../Wrong.framework "${FAKE_SWIFT_BIN_PATH}/PackageFrameworks/Sparkle.framework"
run_harness --group-size 1 --limit-groups 1 --timeout 10 > "${TEMP_DIR}/sparkle-recovery.log" 2> "${TEMP_DIR}/sparkle-recovery.stderr"
[[ "$(readlink "${FAKE_SWIFT_BIN_PATH}/PackageFrameworks/Sparkle.framework")" == "../Sparkle.framework" ]]
[[ "$(grep -c '^build --build-tests$' "${FAKE_SWIFT_LOG}")" -eq 1 ]]
[[ "$(grep -c '^test list --skip-build$' "${FAKE_SWIFT_LOG}")" -eq 2 ]]
[[ "$(grep -c '^build --show-bin-path$' "${FAKE_SWIFT_LOG}")" -eq 1 ]]
grep -Fq "Recovered SwiftPM Sparkle test runtime; retrying discovery once." \
  "${TEMP_DIR}/sparkle-recovery.stderr"
unset FAKE_SWIFT_BIN_PATH

python3 -B "${ROOT_DIR}/Scripts/test_swift_test_evidence.py"
python3 "${ROOT_DIR}/Scripts/test_swift_test_process_cleanup.py"

python3 - "${BASH_SOURCE[0]}" "${TEMP_DIR}" <<'PY'
from pathlib import Path
import subprocess
import sys

source = Path(sys.argv[1]).read_text().split("IFS= read -r -d '' FAKE_SWIFT_SCRIPT", 1)[0]
fixture = Path(sys.argv[2]) / "scratch-lifecycle"
(fixture / "Scripts").mkdir(parents=True)
probe = fixture / "Scripts" / "probe.sh"
sentinel = fixture / "unrelated"
sentinel.write_text("keep")
for command, expected in [("exit 0", 0), ("exit 23", 23), ("kill -HUP $$", 129),
                          ("kill -INT $$", 130), ("kill -TERM $$", 143)]:
    probe.write_text(source + '\nprintf "%s\\n" "$TEMP_DIR" > "$ROOT_DIR/allocated"\n' + command + "\n")
    result = subprocess.run(["/bin/bash", str(probe)], timeout=5)
    assert result.returncode == expected, (command, result.returncode)
    allocated = Path((fixture / "allocated").read_text().strip())
    assert allocated.parent == fixture and not allocated.exists(), allocated
    assert sentinel.read_text() == "keep"
print("Sharding scratch success, failure, and cancellation cleanup passed.")
PY

echo "Swift test sharding tests passed."

reset_case build_failure
export FAKE_SWIFT_MODE=build_fail
set +e
run_harness --group-size 4 --timeout 10 > "${TEMP_DIR}/build-failure.log" 2>&1
build_status=$?
set -e
[[ "$build_status" -eq 43 ]]
grep -Fq 'build failure marker' "${TEMP_DIR}/build-failure.log"
[[ "$(wc -l < "${FAKE_SWIFT_LOG}")" -eq 1 ]]
grep -Fxq 'build --build-tests' "${FAKE_SWIFT_LOG}"
