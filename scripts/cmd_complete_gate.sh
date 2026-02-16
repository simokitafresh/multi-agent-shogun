#!/bin/bash
# cmd_complete_gate.sh — cmd完了時の全ゲートフラグ確認スクリプト
# Usage: bash scripts/cmd_complete_gate.sh <cmd_id>
# Exit 0: GATE CLEAR (全ゲートPASS/SKIP、または緊急override)
# Exit 1: GATE BLOCK (未実行ゲートあり)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_ID="$1"

if [ -z "$CMD_ID" ]; then
    echo "Usage: cmd_complete_gate.sh <cmd_id>" >&2
    exit 1
fi

GATES_DIR="$SCRIPT_DIR/queue/gates"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
mkdir -p "$GATES_DIR"

# 必須3ゲート
REQUIRED_GATES=("task_deploy" "report_merge" "review_gate")

# ─── status自動更新関数 ───
update_status() {
    local cmd_id="$1"
    local lock_file="${YAML_FILE}.lock"

    (
        flock -w 10 200 || { echo "ERROR: flock取得失敗 (${cmd_id})" >&2; return 1; }

        # 既にcompletedなら何もしない（冪等性）
        # cmd_idの行から次の"- id:"行までの範囲で、YAMLフィールドレベル(4スペース)のstatus確認
        if sed -n "/^  - id: ${cmd_id}$/,/^  - id: /p" "$YAML_FILE" | grep -q "^    status: completed"; then
            echo "STATUS ALREADY COMPLETED: ${cmd_id} (skip)"
            return 0
        fi

        # pending → completed に更新
        # cmd_idの行を見つけ、その後最初の"status: pending"を"status: completed"に変更
        sed -i "/^  - id: ${cmd_id}$/,/^  - id: /{s/    status: pending/    status: completed/}" "$YAML_FILE"

        echo "STATUS UPDATED: ${cmd_id} → completed"
    ) 200>"$lock_file"
}

# ─── 緊急override確認 ───
if [ -f "$GATES_DIR/${CMD_ID}_emergency.override" ]; then
    echo "GATE CLEAR (緊急override): ${CMD_ID}の全ゲートをバイパス"
    for gate in "${REQUIRED_GATES[@]}"; do
        echo "  ${gate}: OVERRIDE"
    done
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "🚨 緊急override: ${CMD_ID}のゲートをバイパス"
    update_status "$CMD_ID"
    exit 0
fi

# ─── 各ゲートの状態確認 ───
MISSING_GATES=()
ALL_CLEAR=true

for gate in "${REQUIRED_GATES[@]}"; do
    pass_file="$GATES_DIR/${CMD_ID}_${gate}.pass"
    skip_file="$GATES_DIR/${CMD_ID}_${gate}.skip"

    if [ -f "$pass_file" ]; then
        # .passファイルの中身があれば詳細として表示
        detail=$(cat "$pass_file" 2>/dev/null | head -1)
        if [ -n "$detail" ]; then
            echo "  ${gate}: PASS (${detail})"
        else
            echo "  ${gate}: PASS"
        fi
    elif [ -f "$skip_file" ]; then
        detail=$(cat "$skip_file" 2>/dev/null | head -1)
        if [ -n "$detail" ]; then
            echo "  ${gate}: SKIP (${detail})"
        else
            echo "  ${gate}: SKIP"
        fi
    else
        echo "  ${gate}: MISSING ← 未実行"
        MISSING_GATES+=("$gate")
        ALL_CLEAR=false
    fi
done

# ─── 判定結果 ───
echo ""
if [ "$ALL_CLEAR" = true ]; then
    echo "GATE CLEAR: cmd完了許可"
    update_status "$CMD_ID"
    exit 0
else
    missing_list=$(IFS=,; echo "${MISSING_GATES[*]}")
    echo "GATE BLOCK: ${missing_list}が未実行"
    exit 1
fi
