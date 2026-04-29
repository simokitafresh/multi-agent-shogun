#!/usr/bin/env bash
# cmd_publish.sh — 起票サイクルの機械的ステップを一括実行
#
# Usage:
#   bash scripts/cmd_publish.sh <cmd_id> "<message>"
#
# Example:
#   bash scripts/cmd_publish.sh cmd_2405 "cmd_2405を書いた。GSL2 bunshin。配備せよ。"
#
# 実行内容:
#   1. cmd_save.sh でgate検証 → BLOCK/FAILなら停止
#   2. status: draft → status: pending に昇格 (yaml_field_set)
#   3. cmd_delegate.sh で委任 (status=pending検証 + inbox_write + delegated_at)
#
# 設計思想:
#   将軍の「書く」(創造的) と「通す」(機械的) を分離。
#   このスクリプトは「通す」側を自動化し、品質ステップの抜け漏れを構造的に排除する。
#   cmd_save.sh BLOCKで全体が止まるため、gateを迂回することは不可能。

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
PROJECT_DIR="${_self%/scripts/cmd_publish.sh}"

if [ $# -lt 2 ]; then
    echo "Usage: bash scripts/cmd_publish.sh <cmd_id> \"<message>\"" >&2
    exit 1
fi

CMD_ID="$1"
MESSAGE="$2"
SHOGUN_TO_KARO="$PROJECT_DIR/queue/shogun_to_karo.yaml"

source "$PROJECT_DIR/scripts/lib/yaml_field_set.sh"

# --- Step 1: cmd_save.sh gate検証 ---
echo "=== [1/3] cmd_save.sh gate検証: $CMD_ID ==="
if ! bash "$PROJECT_DIR/scripts/cmd_save.sh" "$CMD_ID"; then
    echo "BLOCK: cmd_save.sh failed for $CMD_ID. 修正してから再実行せよ。" >&2
    exit 1
fi

# --- Step 2: draft → pending 昇格 ---
echo "=== [2/3] pending昇格: $CMD_ID ==="
# 現在のstatusを確認
current_status=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "status" 2>/dev/null) || {
    echo "ERROR: $CMD_ID not found in shogun_to_karo.yaml" >&2
    exit 1
}

if [ "$current_status" = "pending" ] || [ "$current_status" = "delegated" ]; then
    echo "SKIP: $CMD_ID is already $current_status"
elif [ "$current_status" = "draft" ]; then
    yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "pending" || {
        echo "ERROR: failed to set status=pending for $CMD_ID" >&2
        exit 1
    }
    echo "OK: $CMD_ID draft → pending"
else
    echo "ERROR: $CMD_ID status is '$current_status', expected 'draft'" >&2
    exit 1
fi

# --- Step 3: cmd_delegate.sh 委任 ---
echo "=== [3/3] cmd_delegate.sh 委任: $CMD_ID ==="
bash "$PROJECT_DIR/scripts/cmd_delegate.sh" "$CMD_ID" "$MESSAGE"
