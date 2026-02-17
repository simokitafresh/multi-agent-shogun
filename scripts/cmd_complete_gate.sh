#!/bin/bash
# cmd_complete_gate.sh — cmd完了時の全ゲートフラグ確認スクリプト（ディレクトリ方式）
# Usage: bash scripts/cmd_complete_gate.sh <cmd_id>
# Exit 0: GATE CLEAR (全ゲートdone、または緊急override)
# Exit 1: GATE BLOCK (未完了フラグあり)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_ID="$1"

if [ -z "$CMD_ID" ]; then
    echo "Usage: cmd_complete_gate.sh <cmd_id>" >&2
    exit 1
fi

GATES_DIR="$SCRIPT_DIR/queue/gates/${CMD_ID}"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"
mkdir -p "$GATES_DIR"

# ─── status自動更新関数 ───
update_status() {
    local cmd_id="$1"
    local lock_file="${YAML_FILE}.lock"

    (
        flock -w 10 200 || { echo "ERROR: flock取得失敗 (${cmd_id})" >&2; return 1; }

        if sed -n "/^  - id: ${cmd_id}$/,/^  - id: /p" "$YAML_FILE" | grep -q "^    status: completed"; then
            echo "STATUS ALREADY COMPLETED: ${cmd_id} (skip)"
            return 0
        fi

        sed -i "/^  - id: ${cmd_id}$/,/^  - id: /{s/    status: pending/    status: completed/}" "$YAML_FILE"

        echo "STATUS UPDATED: ${cmd_id} → completed"
    ) 200>"$lock_file"
}

# ─── task_type検出: タスクYAMLからparent_cmd一致のtask_typeを収集 ───
detect_task_types() {
    local cmd_id="$1"
    local has_recon=false
    local has_implement=false

    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        # parent_cmdが一致するか確認
        if grep -q "parent_cmd: ${cmd_id}" "$task_file" 2>/dev/null; then
            local ttype
            ttype=$(grep 'task_type:' "$task_file" 2>/dev/null | head -1 | sed 's/.*task_type: *//' | tr -d '[:space:]')
            case "$ttype" in
                recon) has_recon=true ;;
                implement) has_implement=true ;;
            esac
        fi
    done

    # 結果を標準出力に返す（スペース区切り）
    echo "${has_recon} ${has_implement}"
}

# ─── 必須フラグ構築 ───
ALWAYS_REQUIRED=("archive" "lesson")

# task_type検出
read -r HAS_RECON HAS_IMPLEMENT <<< "$(detect_task_types "$CMD_ID")"

CONDITIONAL=()
if [ "$HAS_RECON" = "true" ]; then
    CONDITIONAL+=("report_merge")
fi
if [ "$HAS_IMPLEMENT" = "true" ]; then
    CONDITIONAL+=("review_gate")
fi

ALL_GATES=("${ALWAYS_REQUIRED[@]}" "${CONDITIONAL[@]}")

# ─── 緊急override確認 ───
if [ -f "$GATES_DIR/emergency.override" ]; then
    echo "GATE CLEAR (緊急override): ${CMD_ID}の全ゲートをバイパス"
    for gate in "${ALL_GATES[@]}"; do
        echo "  ${gate}: OVERRIDE"
    done
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "🚨 緊急override: ${CMD_ID}のゲートをバイパス"
    update_status "$CMD_ID"
    exit 0
fi

# ─── 各フラグの状態確認 ───
MISSING_GATES=()
ALL_CLEAR=true

echo "Gate check: ${CMD_ID}"
echo "  Required: ${ALL_GATES[*]}"
if [ ${#CONDITIONAL[@]} -gt 0 ]; then
    echo "  Conditional: ${CONDITIONAL[*]} (task_type: recon=${HAS_RECON}, implement=${HAS_IMPLEMENT})"
fi
echo ""

for gate in "${ALL_GATES[@]}"; do
    done_file="$GATES_DIR/${gate}.done"

    if [ -f "$done_file" ]; then
        detail=$(head -1 "$done_file" 2>/dev/null)
        if [ -n "$detail" ]; then
            echo "  ${gate}: DONE (${detail})"
        else
            echo "  ${gate}: DONE"
        fi
    else
        echo "  ${gate}: MISSING ← 未完了"
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
    echo "GATE BLOCK: 不足フラグ=[${missing_list}]"
    exit 1
fi
