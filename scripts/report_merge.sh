#!/bin/bash
# report_merge.sh — 並行偵察報告の統合判定スクリプト
# Usage: bash scripts/report_merge.sh <cmd_id>
#
# 指定cmd_idに紐づく偵察タスクの完了状態を判定し、
# 家老が統合分析(Step 1.5)を開始すべきか判断する。
#
# Exit codes:
#   0 — 偵察タスクなし or 全件完了(READY)
#   2 — 一部/全件未完了(WAITING/PENDING)
#   1 — 引数エラー

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/field_get.sh"
CMD_ID="$1"

write_gate_flag() {
    local cmd_id="$1" gate_name="$2" result="$3" reason="$4"
    local gates_dir="$SCRIPT_DIR/queue/gates"
    mkdir -p "$gates_dir"
    local flag_file="$gates_dir/${cmd_id}_${gate_name}.${result}"
    cat > "$flag_file" <<EOF2
timestamp: $(date +%Y-%m-%dT%H:%M:%S)
cmd_id: $cmd_id
gate_name: $gate_name
result: $result
reason: "$reason"
EOF2
}

# ─── 引数バリデーション ───
if [ -z "$CMD_ID" ]; then
    echo "Usage: report_merge.sh <cmd_id>" >&2
    echo "Example: bash scripts/report_merge.sh cmd_092" >&2
    exit 1
fi

TASKS_DIR="$SCRIPT_DIR/queue/tasks"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"

# ─── 偵察タスク収集 ───
# queue/tasks/*.yaml から parent_cmd=<cmd_id> かつ titleに偵察/recon/並行偵察を含むものを列挙
declare -a RECON_FILES=()
declare -a RECON_NINJAS=()
declare -a RECON_STATUSES=()
declare -a RECON_TASK_IDS=()

for task_file in "$TASKS_DIR"/*.yaml; do
    [ -f "$task_file" ] || continue

    # parent_cmdが一致するか確認
    local_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "parent_cmd" "" 2>/dev/null)
    if [ "$local_parent" != "$CMD_ID" ]; then
        continue
    fi

    # titleに偵察関連キーワードを含むか確認
    local_title=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "title" "" 2>/dev/null)
    if ! echo "$local_title" | grep -qiE '偵察|recon|並行偵察'; then
        continue
    fi

    # 偵察タスクとして登録
    local_ninja=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "assigned_to" "" 2>/dev/null)
    local_task_id=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "task_id" "" 2>/dev/null)

    # L070: field_get経由でインデント変動に対応 + 空結果チェック
    task_status=""
    task_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "status" "" 2>/dev/null)
    if [ -z "$task_status" ]; then
        echo "[WARN] Empty status in $task_file" >&2
        continue
    fi
    local_status="$task_status"

    RECON_FILES+=("$task_file")
    RECON_NINJAS+=("$local_ninja")
    RECON_STATUSES+=("$local_status")
    RECON_TASK_IDS+=("$local_task_id")
done

TOTAL=${#RECON_FILES[@]}

# ─── 偵察タスクなし ───
if [ "$TOTAL" -eq 0 ]; then
    echo "INFO: ${CMD_ID}に偵察タスクなし"
    write_gate_flag "$CMD_ID" "report_merge" "skip" "偵察タスクなし"
    # cmd_108: Write .done flag for cmd_complete_gate
    local_gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
    mkdir -p "$local_gates_dir"
    echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$local_gates_dir/report_merge.done"
    echo "result: SKIP" >> "$local_gates_dir/report_merge.done"
    exit 0
fi

# ─── 完了状態の集計 ───
DONE_COUNT=0
PENDING_NINJAS=()

for i in "${!RECON_NINJAS[@]}"; do
    ninja="${RECON_NINJAS[$i]}"
    status="${RECON_STATUSES[$i]}"
    task_id="${RECON_TASK_IDS[$i]}"
    report_path="${REPORTS_DIR}/${ninja}_report_${CMD_ID}.yaml"
    if [ ! -f "$report_path" ]; then
        # 後方互換: 旧形式を許容
        report_path="${REPORTS_DIR}/${ninja}_report.yaml"
    fi

    if [ "$status" = "done" ]; then
        DONE_COUNT=$((DONE_COUNT + 1))
        echo "${ninja}: done (${report_path})"
    else
        PENDING_NINJAS+=("$ninja")
        echo "${ninja}: ${status} (${report_path})"
    fi
done

# ─── 判定結果出力 ───
if [ "$DONE_COUNT" -eq "$TOTAL" ]; then
    echo ""
    echo "READY: 並行偵察${TOTAL}件完了。統合分析(Step 1.5)を実施せよ"
    write_gate_flag "$CMD_ID" "report_merge" "pass" "偵察${DONE_COUNT}件完了"
    # cmd_108: Write .done flag for cmd_complete_gate
    local_gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
    mkdir -p "$local_gates_dir"
    echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$local_gates_dir/report_merge.done"
    echo "result: READY" >> "$local_gates_dir/report_merge.done"
    exit 0
elif [ "$DONE_COUNT" -gt 0 ]; then
    pending_names=$(IFS=,; echo "${PENDING_NINJAS[*]}")
    echo ""
    echo "WAITING: 偵察${DONE_COUNT}/${TOTAL}件完了。${pending_names}の報告待ち"
    exit 2
else
    echo ""
    echo "PENDING: 偵察${TOTAL}件すべて進行中"
    exit 2
fi
