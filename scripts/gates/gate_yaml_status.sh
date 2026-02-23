#!/bin/bash
# gate_yaml_status.sh — cmd完了時にshogun_to_karo.yamlのstatusをcompletedに更新
# Usage: bash scripts/gates/gate_yaml_status.sh <cmd_id> [--dry-run]
# Output: UPDATED / ALREADY_OK / ERROR
# Exit 0: 正常完了
# Exit 1: エラー

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"

# 引数解析
CMD_ID=""
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        cmd_*) CMD_ID="$arg" ;;
    esac
done

if [ -z "$CMD_ID" ]; then
    echo "Usage: gate_yaml_status.sh <cmd_id> [--dry-run]" >&2
    exit 1
fi

if [ ! -f "$YAML_FILE" ]; then
    echo "ERROR: $YAML_FILE not found" >&2
    exit 1
fi

# (a) 現在のstatusを確認（awkで安全に抽出。インデントに非依存）
current_status=$(awk -v cmd_id="${CMD_ID}" '
    /- id:/ && index($0, cmd_id) > 0 { found=1; next }
    found && /- id:/ { exit }
    found && /status:/ { sub(/.*status: */, ""); gsub(/[[:space:]]/, ""); print; exit }
' "$YAML_FILE")

if [ -z "$current_status" ]; then
    echo "ERROR: ${CMD_ID} not found in shogun_to_karo.yaml" >&2
    exit 1
fi

# (b) completed/doneならスキップ
case "$current_status" in
    completed|done)
        echo "ALREADY_OK (status=${current_status})"
        exit 0
        ;;
esac

# (c) dry-runモード
if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: ${CMD_ID} status: ${current_status} → completed (変更なし)"
    exit 0
fi

# (d) flock付きでstatusをcompletedに書き換え
LOCK_FILE="${YAML_FILE}.lock"
(
    flock -w 10 200 || { echo "ERROR: flock取得失敗 (${CMD_ID})" >&2; exit 1; }

    # 該当cmdブロック内のstatus行をcompletedに置換（インデント非依存）
    sed -i "/- id: ${CMD_ID}$/,/- id: /{s/status: ${current_status}/status: completed/}" "$YAML_FILE"

    echo "UPDATED: ${CMD_ID} status: ${current_status} → completed"
) 200>"$LOCK_FILE"
