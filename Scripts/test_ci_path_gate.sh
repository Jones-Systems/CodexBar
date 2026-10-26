#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d "${ROOT_DIR}/.test-ci-gate.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

assert_gate() {
  local expected="$1"
  local name="$2"
  local paths_file="${tmp_dir}/${name}.paths"
  local output_file="${tmp_dir}/${name}.output"
  shift 2

  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$paths_file" >/dev/null
  local actual
  actual="$(sed -n 's/^macos-tests=//p' "$output_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s: expected macos-tests=%s, got %s\n' "$name" "$expected" "${actual:-<empty>}" >&2
    exit 1
  fi

  local reason
  reason="$(sed -n 's/^macos-tests-reason=//p' "$output_file")"
  if [[ -z "$reason" ]]; then
    printf '%s: expected macos-tests-reason output\n' "$name" >&2
    exit 1
  fi

  local deferred
  deferred="$(sed -n 's/^macos-tests-deferred=//p' "$output_file")"
  if [[ "$deferred" != false ]]; then
    printf '%s: expected macos-tests-deferred=false, got %s\n' "$name" "${deferred:-<empty>}" >&2
    exit 1
  fi

  local path_count
  path_count="$(sed -n 's/^changed-path-count=//p' "$output_file")"
  if ! [[ "$path_count" =~ ^[0-9]+$ ]]; then
    printf '%s: expected numeric changed-path-count output, got %s\n' \
      "$name" "${path_count:-<empty>}" >&2
    exit 1
  fi

  if [[ "$expected" == false && "$reason" != "changes covered by portable checks or another platform" ]]; then
    printf '%s: expected platform skip reason, got %s\n' "$name" "$reason" >&2
    exit 1
  fi
}

assert_gate false docs-only $'M\tdocs/providers.md' $'M\tREADME.md'
assert_gate true configuration-doc $'M\tdocs/configuration.md'
assert_gate true rename-to-configuration-doc $'R100\tdocs/old.md\tdocs/configuration.md'
assert_gate true rename-from-configuration-doc $'R100\tdocs/configuration.md\tdocs/new.md'
assert_gate true agents-contract $'M\tAGENTS.md'
assert_gate true rename-to-agents-contract $'R100\tdocs/old.md\tAGENTS.md'
assert_gate true rename-from-agents-contract $'R100\tAGENTS.md\tdocs/new.md'
assert_gate true claude-contract $'M\tCLAUDE.md'
assert_gate true rename-to-claude-contract $'R100\tdocs/old.md\tCLAUDE.md'
assert_gate true rename-from-claude-contract $'R100\tCLAUDE.md\tdocs/new.md'
assert_gate true source $'M\tSources/CodexBar/App.swift'
assert_gate false docs-site $'M\tdocs/index.html' $'M\tdocs/site.css' $'M\tdocs/site.js' \
  $'M\tdocs/site-locales.mjs' $'M\tdocs/social.html' $'M\tdocs/social.png' \
  $'M\tdocs/CNAME' $'M\tdocs/.nojekyll' $'M\tdocs/llms.txt'
assert_gate false docs-site-assets $'M\tdocs/icon.png' $'M\tdocs/logos/provider-logo.svg'
assert_gate true docs-unknown-code $'M\tdocs/custom-tool.js'
assert_gate true docs-site-with-config $'M\tdocs/site.css' $'M\tdocs/configuration.md'
assert_gate true empty
assert_gate true source-to-docs $'R100\tSources/CodexBar/App.swift\tdocs/App.md'
assert_gate true docs-to-source $'R100\tdocs/App.md\tSources/CodexBar/App.swift'
assert_gate false docs-to-site $'R100\tdocs/old.md\tdocs/site.css'

assert_linux_musl_gate() {
  local expected="$1"
  local name="$2"
  local paths_file="${tmp_dir}/linux-musl-${name}.paths"
  local output_file="${tmp_dir}/linux-musl-${name}.output"
  shift 2

  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_linux_musl_build_gate.sh" "$paths_file" >/dev/null
  local actual
  actual="$(sed -n 's/^linux-musl-build=//p' "$output_file")"
  if [[ "$actual" != "$expected" ]]; then
    printf '%s: expected linux-musl-build=%s, got %s\n' "$name" "$expected" "${actual:-<empty>}" >&2
    exit 1
  fi

  local reason
  reason="$(sed -n 's/^linux-musl-build-reason=//p' "$output_file")"
  if [[ -z "$reason" ]]; then
    printf '%s: expected linux-musl-build-reason output\n' "$name" >&2
    exit 1
  fi
}

assert_linux_musl_gate true package-manifest $'M\tPackage.swift'
assert_linux_musl_gate true swift-source $'M\tSources/CodexBarCore/Process.swift'
assert_linux_musl_gate true nested-swift-source $'M\tSources/CodexBarCore/Host/Process/Process.swift'
assert_linux_musl_gate true rename-from-swift $'R100\tSources/CodexBarCore/Old.swift\tdocs/Old.md'
assert_linux_musl_gate true rename-to-swift $'R100\tdocs/New.md\tSources/CodexBarCore/New.swift'
assert_linux_musl_gate false tests-only $'M\tTests/CodexBarTests/ProcessTests.swift'
assert_linux_musl_gate true workflow-only $'M\t.github/workflows/ci.yml'
assert_linux_musl_gate true script-only $'M\tScripts/ci_verify_test_jobs.sh'
assert_linux_musl_gate true package-resolved $'M\tPackage.resolved'
assert_linux_musl_gate true empty-diff

# Native-only paths must not compile either Linux matrix, including deleted and renamed paths.
assert_gate false portable-site-script $'M\tScripts/check-site-locales.mjs'
assert_gate false candidate-workflow $'M\t.github/workflows/jones-app-candidate.yml'
assert_gate true global-ci $'M\t.github/workflows/ci.yml'
assert_gate true global-harness $'M\tScripts/test.sh'
assert_gate true development-policy $'M\tdocs/DEVELOPMENT.md'
assert_gate true agent-policy $'M\t.agents/skills/example/SKILL.md'
assert_gate true shared-c $'M\tSources/CQuickJS/quickjs.c'
assert_gate true dependencies $'M\tPackage.resolved'
assert_gate true portable-tests $'M\tTestsLinux/UsageTests.swift'
assert_gate true plugin-tests $'M\tTestsPlugin/PluginTests.swift'
assert_gate true adaptive-tests $'M\tTests/AdaptiveReplayKitTests/ReplayTests.swift'
assert_gate true native-source-markdown $'M\tSources/CodexBar/Resources/runtime.md'
assert_linux_musl_gate false native-only $'M\tSources/CodexBar/App.swift'
assert_linux_musl_gate false native-deletion $'D\tWidgetExtension/Widget.swift'
assert_linux_musl_gate false native-rename $'R100\tSources/CodexBar/Old.swift\tSources/CodexBar/New.swift'
assert_linux_musl_gate true shared-c $'M\tSources/CQuickJS/quickjs.c'
assert_linux_musl_gate true module-map $'M\tSources/CSQLite3/module.modulemap'
assert_linux_musl_gate true shared-to-native $'R100\tSources/CodexBarCore/A.swift\tSources/CodexBar/A.swift'
assert_linux_musl_gate true deleted-shared $'D\tSources/CodexBarCore/A.swift'
assert_linux_musl_gate false portable-tests $'M\tTestsLinux/UsageTests.swift'
assert_linux_musl_gate true unknown $'M\tnew-build-input'

assert_linux_gate() {
  local expected="$1"
  local name="$2"
  local paths_file="${tmp_dir}/linux-${name}.paths"
  local output_file="${tmp_dir}/linux-${name}.output"
  shift 2
  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_linux_test_gate.sh" "$paths_file" >/dev/null
  if [[ "$(sed -n 's/^linux-tests=//p' "$output_file")" != "$expected" ]] \
    || [[ -z "$(sed -n 's/^linux-tests-reason=//p' "$output_file")" ]]; then
    printf '%s: unexpected Linux glibc gate output\n' "$name" >&2
    exit 1
  fi
}

assert_linux_gate false docs $'M\tREADME.md'
assert_linux_gate false native-source $'M\tSources/CodexBar/App.swift'
assert_linux_gate false native-tests $'M\tTests/CodexBarTests/AppTests.swift'
assert_linux_gate false native-deleted $'D\tWidgetExtension/Widget.swift'
assert_linux_gate false portable-script $'M\tScripts/check-site-locales.mjs'
assert_linux_gate false candidate-workflow $'M\t.github/workflows/jones-menu-candidate.yml'
assert_linux_gate true shared-source $'M\tSources/CodexBarCore/Core.swift'
assert_linux_gate true c-source $'M\tSources/CQuickJS/quickjs.c'
assert_linux_gate true dependencies $'M\tPackage.resolved'
assert_linux_gate true linux-tests $'M\tTestsLinux/Tests.swift'
assert_linux_gate true plugin-tests $'M\tTestsPlugin/Tests.swift'
assert_linux_gate true adaptive-tests $'M\tTests/AdaptiveReplayCLITests/Tests.swift'
assert_linux_gate true global-ci $'M\t.github/workflows/ci.yml'
assert_linux_gate true global-harness $'M\tScripts/test.sh'
assert_linux_gate true unknown $'M\tnew-build-input'
assert_linux_gate true empty
assert_linux_gate true rename-from-shared $'R100\tSources/CodexBarCore/Core.swift\tdocs/Old.md'
assert_linux_gate true rename-to-shared $'R100\tdocs/Old.md\tSources/CodexBarCore/Core.swift'
assert_linux_gate true copy-from-shared $'C100\tSources/CodexBarCore/Core.swift\tdocs/Old.md'
for name in ProviderPluginDetailsParityTests ProviderPluginExtensionParityTests ProviderPluginParityTests \
  ProviderPluginRuntimeTests Sub2APIPluginGoldenTests; do
  shared_path="Tests/CodexBarTests/${name}.swift"
  assert_linux_gate true "${name}-modified" "$(printf 'M\t%s' "$shared_path")"
  assert_linux_gate true "${name}-deleted" "$(printf 'D\t%s' "$shared_path")"
  assert_linux_gate true "${name}-renamed" "$(printf 'R100\t%s\tdocs/old.md' "$shared_path")"
  assert_gate true "${name}-native" "$(printf 'M\t%s' "$shared_path")"
done

draft_paths="${tmp_dir}/draft-source.paths"
draft_output="${tmp_dir}/draft-source.output"
printf '%s\n' $'M\tSources/CodexBar/App.swift' > "$draft_paths"
CI_PULL_REQUEST_DRAFT=true GITHUB_OUTPUT="$draft_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$draft_paths" >/dev/null
if [[ "$(sed -n 's/^macos-tests=//p' "$draft_output")" != true ]]; then
  printf 'draft source: expected macOS tests to remain required while deferred\n' >&2
  exit 1
fi
if [[ "$(sed -n 's/^macos-tests-reason=//p' "$draft_output")" != \
  "draft pull request: macOS Swift tests deferred until ready for review" ]]
then
  printf 'draft source: expected draft deferral reason\n' >&2
  exit 1
fi
if [[ "$(sed -n 's/^macos-tests-deferred=//p' "$draft_output")" != true ]]; then
  printf 'draft source: expected macOS tests to be marked deferred\n' >&2
  exit 1
fi

draft_docs_output="${tmp_dir}/draft-docs.output"
CI_PULL_REQUEST_DRAFT=true GITHUB_OUTPUT="$draft_docs_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "${tmp_dir}/docs-only.paths" >/dev/null
if [[ "$(sed -n 's/^macos-tests=//p' "$draft_docs_output")" != false ]] \
  || [[ "$(sed -n 's/^macos-tests-deferred=//p' "$draft_docs_output")" != false ]]
then
  printf 'draft docs: expected required=false and deferred=false\n' >&2
  exit 1
fi

assert_gate_fails() {
  local name="$1"
  local paths_file="${tmp_dir}/${name}.paths"
  local output_file="${tmp_dir}/${name}.output"
  shift

  printf '%s\n' "$@" > "$paths_file"
  if GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$paths_file" >/dev/null 2>&1; then
    printf '%s: malformed gate input unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$output_file" ]]; then
    printf '%s: malformed gate input emitted an output\n' "$name" >&2
    exit 1
  fi
}

assert_gate_fails missing-rename-target $'R100\tREADME.md'
assert_gate_fails extra-modified-path $'M\tREADME.md\tdocs/configuration.md'
assert_gate_fails missing-rename-score $'R\tREADME.md\tdocs/README.md'
assert_gate_fails invalid-rename-score $'Rfoo\tREADME.md\tdocs/README.md'
assert_gate_fails out-of-range-rename-score $'R101\tREADME.md\tdocs/README.md'
assert_gate_fails empty-column $'M\t\tREADME.md'
assert_gate_fails trailing-column $'M\tREADME.md\t'

for malformed_case in missing-rename-target extra-modified-path missing-rename-score \
  invalid-rename-score out-of-range-rename-score empty-column trailing-column
do
  paths_file="${tmp_dir}/${malformed_case}.paths"
  for platform_script in ci_linux_musl_build_gate.sh ci_linux_test_gate.sh; do
    output_file="${tmp_dir}/${platform_script}-${malformed_case}.output"
    if GITHUB_OUTPUT="$output_file" \
      "${ROOT_DIR}/Scripts/$platform_script" "$paths_file" >/dev/null 2>&1
    then
      printf '%s: malformed %s input unexpectedly succeeded\n' "$malformed_case" "$platform_script" >&2
      exit 1
    fi
    if [[ -s "$output_file" ]]; then
      printf '%s: malformed gate input emitted an output\n' "$malformed_case" >&2
      exit 1
    fi
  done
done

if CI_PULL_REQUEST_DRAFT=maybe GITHUB_OUTPUT="${tmp_dir}/invalid-draft.output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "${tmp_dir}/docs-only.paths" >/dev/null 2>&1
then
  printf 'invalid draft flag unexpectedly succeeded\n' >&2
  exit 1
fi

unterminated_paths="${tmp_dir}/unterminated.paths"
unterminated_output="${tmp_dir}/unterminated.output"
printf '%s' $'M\tREADME.md\tdocs/configuration.md' > "$unterminated_paths"
if GITHUB_OUTPUT="$unterminated_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$unterminated_paths" >/dev/null 2>&1
then
  printf 'unterminated malformed gate input unexpectedly succeeded\n' >&2
  exit 1
fi
if [[ -s "$unterminated_output" ]]; then
  printf 'unterminated malformed gate input emitted an output\n' >&2
  exit 1
fi

verify="${ROOT_DIR}/Scripts/ci_verify_test_jobs.sh"
assert_verify_fails() {
  if "$verify" "$@" >/dev/null 2>&1; then
    printf 'unexpected aggregate success: %s\n' "$*" >&2
    exit 1
  fi
}

# Every selected scope requires success; only a known false gate permits skipped.
for macos_required in true false; do
  macos_result=success
  [[ "$macos_required" == true ]] || macos_result=skipped
  for musl_required in true false; do
    musl_result=success
    [[ "$musl_required" == true ]] || musl_result=skipped
    for linux_required in true false; do
      linux_result=success
      [[ "$linux_required" == true ]] || linux_result=skipped
      valid_args=(success success "$macos_required" "$macos_result" false \
        "$musl_required" "$musl_result" "$linux_result" "$linux_required" "$macos_result")
      "$verify" "${valid_args[@]}" >/dev/null
      for result_index in 0 1 3 6 7 9; do
        for result in success failure cancelled skipped '' unknown; do
          [[ "$result" == "${valid_args[$result_index]}" ]] && continue
          invalid_args=("${valid_args[@]}")
          invalid_args[$result_index]="$result"
          assert_verify_fails "${invalid_args[@]}"
        done
      done
      for gate_index in 2 5 8; do
        for value in '' unknown; do
          invalid_args=("${valid_args[@]}")
          invalid_args[$gate_index]="$value"
          assert_verify_fails "${invalid_args[@]}"
        done
      done
      for deferred in true '' unknown; do
        invalid_args=("${valid_args[@]}")
        invalid_args[4]="$deferred"
        assert_verify_fails "${invalid_args[@]}"
      done
      assert_verify_fails "${valid_args[@]:0:8}"
      assert_verify_fails "${valid_args[@]:0:7}"
      assert_verify_fails "${valid_args[@]:0:9}"
    done
  done
done
assert_verify_fails success success true skipped true false skipped skipped false skipped

# Check the actual aggregate dependency and shell argument, not summary text elsewhere in the workflow.
python3 - "${ROOT_DIR}/.github/workflows/ci.yml" <<'PY'
import ast
import os
import pathlib
import re
import shlex
import sys

workflow = pathlib.Path(sys.argv[1]).read_text()
aggregate = re.search(r"(?ms)^  lint-build-test:\n(.*?)(?=^  [\w-]+:|\Z)", workflow)
if aggregate is None:
    sys.exit("missing lint-build-test aggregate")
body = aggregate.group(1)
needs = re.search(r"(?m)^    needs:\n((?:      - [^\n]+\n)+)", body)
if needs is None or "      - build-linux-cli" not in needs.group(1).splitlines():
    sys.exit("lint-build-test must need build-linux-cli")
if "      - swift-build-macos" not in needs.group(1).splitlines():
    sys.exit("lint-build-test must need the macOS build producer")
command = re.search(r"(?m)^          \./Scripts/ci_verify_test_jobs\.sh(?:[^\n]*\\\n)+[^\n]*", body)
if command is None:
    sys.exit("missing aggregate verifier command")
arguments = shlex.split(command.group(0).replace("\\\n", ""))
if len(arguments) != 11 or arguments[8] != "${{ needs.build-linux-cli.result }}":
    sys.exit("aggregate verifier argument eight must be needs.build-linux-cli.result")
if arguments[9] != "${{ needs.changes.outputs.linux-tests }}":
    sys.exit("aggregate verifier argument nine must explicitly supply the Linux gate")
if arguments[10] != "${{ needs.swift-build-macos.result }}":
    sys.exit("aggregate verifier argument ten must explicitly supply the macOS producer result")
linux = re.search(r"(?ms)^  build-linux-cli:\n(.*?)(?=^  [\w-]+:|\Z)", workflow).group(1)
if "needs: changes" not in linux or "needs.changes.outputs.linux-tests == 'true'" not in linux:
    sys.exit("Linux matrix must use the explicit path gate")
if "LINUX_BUILD_CONFIGURATION: ${{ github.event_name == 'pull_request' && 'debug' || 'release' }}" not in linux:
    sys.exit("Linux PR build must share debug compilation with tests")
if 'build_args+=(--static-swift-stdlib)' not in linux or 'grep -q "macOS" <<< "$smoke_error"' not in linux:
    sys.exit("Linux release/static and offline platform rejection checks must remain")

for filename, label in (("jones-app-candidate.yml", "codexbar-package"),
                        ("jones-menu-candidate.yml", "codexbar-menu-candidate")):
    candidate = pathlib.Path(sys.argv[1]).with_name(filename).read_text()
    if re.search(r"(?m)^  push:", candidate) or "  workflow_dispatch:" not in candidate:
        sys.exit(f"{filename}: candidates must be opt-in, without automatic main pushes")
    if not re.search(r"types: \[[^\]]*synchronize[^\]]*labeled", candidate):
        sys.exit(f"{filename}: label and subsequent source changes must be supported")
    for condition in ("github.event_name == 'workflow_dispatch'", "github.event_name == 'pull_request'",
                      "github.event.pull_request.draft == false",
                      "github.event.pull_request.head.repo.full_name == github.repository",
                      f"contains(github.event.pull_request.labels.*.name, '{label}')",
                      f"github.event.label.name == '{label}'"):
        if condition not in candidate:
            sys.exit(f"{filename}: missing opt-in condition: {condition}")
    if "    paths:" not in candidate or "ref: ${{ github.event.pull_request.head.sha || github.sha }}" not in candidate:
        sys.exit(f"{filename}: retain path filters and exact-head checkout")
    if "    concurrency:" not in candidate or "  cancel-in-progress: true" not in candidate:
        sys.exit(f"{filename}: selected PR updates must cancel superseded packaging")
    if "format('pr-{0}', github.event.pull_request.number) || format('event-{0}', github.run_id)" not in candidate:
        sys.exit(f"{filename}: skipped events need a separate cancellation group")
    if "group: codexbar-candidate-packaging" not in candidate or "cancel-in-progress: false" not in candidate:
        sys.exit(f"{filename}: serialize packaging without cancelling active candidates")

root = pathlib.Path(sys.argv[1]).resolve().parents[2]
classifier = (root / "Scripts/ci_path_gate.sh").read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
shared_sources = next(ast.literal_eval(node.value) for node in ast.parse(classifier).body
                      if isinstance(node, ast.Assign)
                      and any(isinstance(target, ast.Name) and target.id == "portable_source_paths"
                              for target in node.targets))
symlink_sources = {str((path.parent / os.readlink(path)).resolve().relative_to(root))
                   for path in (root / "TestsPlugin").iterdir() if path.is_symlink()}
if shared_sources != symlink_sources:
    sys.exit("shared plugin source path gate must match TestsPlugin symlink targets")

PY

printf 'CI path gate tests passed.\n'
