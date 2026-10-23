#!/bin/bash
set -euo pipefail

# JONES(app-updates): Python is an explicit prerequisite, never installed here.
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Jones installer requires Python 3.9+. Supply it through your approved tool setup, then retry.' >&2
  exit 2
fi
PYTHON_BIN="$(command -v python3)"
if [[ "$PYTHON_BIN" == /usr/bin/python3 && "$(uname -s)" == Darwin ]]; then
  if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    echo 'The macOS python3 shim has no selected developer tools. Supply an approved Python 3.9+ runtime.' >&2
    echo 'This helper will not request a tools installation.' >&2
    exit 2
  fi
fi
if ! "$PYTHON_BIN" -I -S -B -c 'import sys; sys.exit(0 if (3, 9) <= sys.version_info[:2] < (4, 0) else 1)'; then
  echo 'Jones installer requires Python 3.9+ (Python 3). Check python3 --version.' >&2
  echo 'An Xcode command-line-tools shim alone is not proof of availability.' >&2
  exit 2
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$PYTHON_BIN" -I -S -B "$SCRIPT_DIR/jones_install_app.py" "$@"
