#!/bin/bash
# gate_yaml_status.sh — cmd完了時にshogun_to_karo.yamlのstatusをcompletedに更新
# Usage: bash scripts/gates/gate_yaml_status.sh <cmd_id> [--dry-run]
# Output: UPDATED / ALREADY_OK / ERROR
# Exit 0: 正常完了
# Exit 1: エラー

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
# source は書き込み直前に遅延（early-exitパスでのコスト削減）

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

# (a) 現在のstatusを確認（awkで安全に抽出。list形式とmap key形式の両方に対応）
current_status=$(awk -v cmd_id="${CMD_ID}" '
    # list形式: "- id: cmd_xxx"
    /- id:/ && index($0, cmd_id) > 0 { found=1; list_mode=1; next }
    found && list_mode && /- id:/ { exit }
    # map key形式: "  cmd_xxx:"
    !found && $0 ~ ("^[[:space:]]+" cmd_id ":") { found=1; list_mode=0; next }
    found && !list_mode && /^[[:space:]]+[a-z]/ && !/^[[:space:]][[:space:]][[:space:]]/ { exit }
    found && /[[:space:]]status:/ { sub(/.*status: */, ""); gsub(/[[:space:]]/, ""); print; exit }
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

# (d) yaml_field_setでstatusをcompletedに書き換え（flock+readback検証内包）
# ここで初めてライブラリをsource（early-exitパスでは不要）
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh"
if ! yaml_field_set "$YAML_FILE" "$CMD_ID" "status" "completed"; then
    echo "ERROR: yaml_field_set failed for ${CMD_ID}" >&2
    exit 1
fi

echo "UPDATED: ${CMD_ID} status: ${current_status} → completed"
