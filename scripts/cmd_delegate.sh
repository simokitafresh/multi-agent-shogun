#!/usr/bin/env bash
# cmd_delegate.sh — cmd委任の原子的実行（将軍ワークフロー Step 3）
#
# Usage:
#   bash scripts/cmd_delegate.sh <cmd_id> "<message>"
#
# Example:
#   bash scripts/cmd_delegate.sh cmd_539 "cmd_539を書いた。配備せよ。"
#
# Behavior:
#   1. shogun_to_karo.yaml に cmd_id が存在し status=pending か検証
#   2. delegated_at が既にあれば ALREADY_DELEGATED で終了（冪等性）
#   3. inbox_write.sh karo "<msg>" cmd_new shogun を実行
#   4. 成功後、delegated_at: <ISO8601> を cmd エントリに追加
#   5. 出力: DELEGATED: cmd_XXX at 2026-03-04T18:17:05
#
# Exit codes:
#   0 — 委任成功 or 既に委任済み
#   1 — エラー（cmd未発見/status不正/inbox_write失敗）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SHOGUN_TO_KARO="$PROJECT_DIR/queue/shogun_to_karo.yaml"

CMD_ID="${1:-}"
MESSAGE="${2:-}"

if [ -z "$CMD_ID" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: cmd_delegate.sh <cmd_id> \"<message>\"" >&2
    exit 1
fi

if [ ! -f "$SHOGUN_TO_KARO" ]; then
    echo "ERROR: shogun_to_karo.yaml not found: $SHOGUN_TO_KARO" >&2
    exit 1
fi

# Source yaml_field_set for field get/set
source "$SCRIPT_DIR/lib/yaml_field_set.sh"

# Step 1: cmd_id が存在し status=pending か検証
status=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "status" 2>/dev/null) || {
    echo "ERROR: cmd_id '$CMD_ID' not found in shogun_to_karo.yaml" >&2
    exit 1
}

if [ "$status" != "pending" ]; then
    echo "ERROR: cmd_id '$CMD_ID' status is '$status', expected 'pending'" >&2
    exit 1
fi

# Step 2: delegated_at が既にあれば冪等に終了
existing_delegated=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "delegated_at" 2>/dev/null) || true
if [ -n "$existing_delegated" ]; then
    echo "ALREADY_DELEGATED: $CMD_ID at $existing_delegated"
    exit 0
fi

# Step 3: inbox_write.sh で家老に通知
bash "$SCRIPT_DIR/inbox_write.sh" karo "$MESSAGE" cmd_new shogun || {
    echo "ERROR: inbox_write.sh failed for $CMD_ID" >&2
    exit 1
}

# Step 4: delegated_at を設定
TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")
yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "delegated_at" "\"$TIMESTAMP\"" || {
    echo "ERROR: Failed to set delegated_at for $CMD_ID" >&2
    exit 1
}

# Step 5: 成功出力
echo "DELEGATED: $CMD_ID at $TIMESTAMP"
