#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

FILTER='ProviderPluginRuntimeTests|ProviderPluginParityTests|ProviderPluginDetailsParityTests|ProviderPluginExtensionParityTests|Sub2APIPluginGoldenTests|UserProviderPluginPortableTests'

exec ./Scripts/test.sh --command /bin/sh -eu -c '
  echo "plugin engine A/B: QuickJS default"
  env -u CODEXBAR_PLUGIN_ENGINE python3 Scripts/build_jobs.py -- swift test --filter "$1"

  echo "plugin engine A/B: JavaScriptCore rollback"
  CODEXBAR_PLUGIN_ENGINE=jsc python3 Scripts/build_jobs.py -- swift test --skip-build --filter "$1"
' plugin-engine-tests "$FILTER"
