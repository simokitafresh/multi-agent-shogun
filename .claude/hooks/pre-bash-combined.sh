#!/usr/bin/env bash
# Combined Bash PreToolUse guard: block_destructive + no-verify + report-deny + yaml-dump
# cmd_1661: 4 hooks → 1 script. Eliminates 3 bash startup costs (~60ms each).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/pre_bash_combined_guard.sh"

payload="$(cat)"
pre_bash_combined_eval_payload "$payload" "$SCRIPT_DIR"
exit $?
