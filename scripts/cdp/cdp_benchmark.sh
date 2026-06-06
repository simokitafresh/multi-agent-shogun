#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="${BASH_SOURCE[0]}"
case "$SOURCE_PATH" in
    */*) SCRIPT_DIR="${SOURCE_PATH%/*}" ;;
    *) SCRIPT_DIR="." ;;
esac
exec python3 "${SCRIPT_DIR}/cdp_benchmark.py" "$@"
