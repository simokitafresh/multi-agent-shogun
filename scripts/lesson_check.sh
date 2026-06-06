#!/bin/bash
# lesson_check.sh — 教訓レビュー「該当なし」判定時のフラグ出力
# Usage: bash scripts/lesson_check.sh <cmd_id> "<reason>"
# Example: bash scripts/lesson_check.sh cmd_108 "コード変更のみ、教訓なし"

set -e

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
_scripts_dir="${_self%/*}"
SCRIPT_DIR="${_scripts_dir%/*}"
unset _self _scripts_dir
CMD_ID="$1"
REASON="$2"

# Validate arguments
if [ -z "$CMD_ID" ]; then
    echo "Usage: lesson_check.sh <cmd_id> <reason>" >&2
    exit 1
fi

if [ -z "$REASON" ]; then
    echo "Usage: lesson_check.sh <cmd_id> <reason>" >&2
    echo "ERROR: reason is required" >&2
    exit 1
fi

# Write .done flag
gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
mkdir -p "$gates_dir"
printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
cat > "$gates_dir/lesson.done" <<EOF
timestamp: $_ts
source: lesson_check
reason: "$REASON"
EOF
unset _ts

echo "LESSON CHECK: ${CMD_ID} — ${REASON}"
exit 0
