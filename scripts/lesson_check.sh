#!/bin/bash
# lesson_check.sh — 教訓レビュー「該当なし」判定時のフラグ出力
# Usage: bash scripts/lesson_check.sh <cmd_id> "<reason>"
# Example: bash scripts/lesson_check.sh cmd_108 "コード変更のみ、教訓なし"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
cat > "$gates_dir/lesson.done" <<EOF
timestamp: $(date +%Y-%m-%dT%H:%M:%S)
source: lesson_check
reason: "$REASON"
EOF

echo "LESSON CHECK: ${CMD_ID} — ${REASON}"
exit 0
