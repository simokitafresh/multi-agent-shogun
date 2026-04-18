#!/usr/bin/env bash
# mark_no_learning.sh — 学習ループ「記録なし」明示フラグ生成
# Usage: bash scripts/gates/mark_no_learning.sh <cmd_id>
# 目的: workaround/frictionが本当になかった場合に家老が明示宣言する
# 生成先: queue/gates/{cmd_id}/learning_loop.done

set -euo pipefail

_mark_no_learning_self="${BASH_SOURCE[0]}"
[[ "$_mark_no_learning_self" != /* ]] && _mark_no_learning_self="$PWD/$_mark_no_learning_self"
SCRIPT_DIR="${_mark_no_learning_self%/scripts/gates/mark_no_learning.sh}"
unset _mark_no_learning_self
CMD_ID="${1:-}"

if [[ -z "$CMD_ID" ]]; then
    echo "Usage: bash scripts/gates/mark_no_learning.sh <cmd_id>" >&2
    exit 1
fi

if [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: cmd_id must be cmd_XXX format. Got: $CMD_ID" >&2
    exit 1
fi

GATES_DIR="$SCRIPT_DIR/queue/gates/${CMD_ID}"
DONE_FILE="$GATES_DIR/learning_loop.done"

mkdir -p "$GATES_DIR"

printf -v _mark_no_learning_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
printf 'no_friction_no_workaround\ntimestamp: %s\n' "$_mark_no_learning_ts" > "$DONE_FILE"

echo "[mark_no_learning] Created: $DONE_FILE"
