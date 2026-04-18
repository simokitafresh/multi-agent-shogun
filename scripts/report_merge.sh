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

# GP-XXX3: SCRIPT_DIR をサブシェル不要のbash文字列操作で取得 (cd+pwd+dirname排除)
_s="${BASH_SOURCE[0]%/*}"
SCRIPT_DIR="${_s%/*}"
unset _s
CMD_ID="$1"

write_gate_flag() {
    local cmd_id="$1" gate_name="$2" result="$3" reason="$4"
    local gates_dir="$SCRIPT_DIR/queue/gates"
    mkdir -p "$gates_dir"
    local flag_file="$gates_dir/${cmd_id}_${gate_name}.${result}"
    # GP-XXX3: cat+dateサブシェル2個 → printf -v timestamp + printf (subshell排除)
    local _ts; printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
    printf 'timestamp: %s\ncmd_id: %s\ngate_name: %s\nresult: %s\nreason: "%s"\n' \
        "$_ts" "$cmd_id" "$gate_name" "$result" "$reason" > "$flag_file"
}

write_done_flag() {
    local cmd_id="$1" result="$2"
    local done_dir="$SCRIPT_DIR/queue/gates/${cmd_id}"
    mkdir -p "$done_dir"
    # GP-XXX3: cat+dateサブシェル2個 → printf -v timestamp + printf (subshell排除)
    local _ts; printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
    printf 'timestamp: %s\nresult: %s\n' "$_ts" "$result" > "$done_dir/report_merge.done"
}

# ─── 引数バリデーション ───
if [ -z "$CMD_ID" ]; then
    echo "Usage: report_merge.sh <cmd_id>" >&2
    echo "Example: bash scripts/report_merge.sh cmd_092" >&2
    exit 1
fi

TASKS_DIR="$SCRIPT_DIR/queue/tasks"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"
AWK_BIN="awk"
if command -v mawk >/dev/null 2>&1; then
    AWK_BIN="mawk"
fi

# ─── 偵察タスク収集（全ファイルを単一awkパスで処理）───
# 旧実装: field_get を1ファイルあたり4-5回呼び出し(subshell多数) → 遅い
# 現在: awk系実装を優先。WSL2では mawk が gawk より軽いため、あれば優先使用する
declare -a RECON_FILES=()
declare -a RECON_NINJAS=()
declare -a RECON_STATUSES=()
declare -a RECON_TASK_IDS=()

# awkで全タスクファイルを1パス処理: TAB区切りで file|ninja|status|task_id を出力
while IFS=$'\t' read -r r_file r_ninja r_status r_task_id; do
    if [ -z "$r_status" ]; then
        echo "[WARN] Empty status in $r_file" >&2
        continue
    fi
    RECON_FILES+=("$r_file")
    RECON_NINJAS+=("$r_ninja")
    RECON_STATUSES+=("$r_status")
    RECON_TASK_IDS+=("$r_task_id")
done < <(
    shopt -s nullglob
    files=("$TASKS_DIR"/*.yaml)
    [ "${#files[@]}" -eq 0 ] && exit 0
    "$AWK_BIN" -v cmd_id="$CMD_ID" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function unquote(s,   c1, cl) {
        if (length(s) >= 2) {
            c1 = substr(s,1,1); cl = substr(s,length(s),1)
            if ((c1 == "\"" && cl == "\"") || (c1 == "\047" && cl == "\047"))
                return substr(s, 2, length(s)-2)
        }
        return s
    }
    FNR == 1 {
        if (NR > 1) process()
        cur_file = FILENAME
        parent_cmd = task_type = assigned_to = task_id = ac_task_id = status = ""
    }
    /^[[:space:]]*(parent_cmd|task_type|assigned_to|task_id|_ac_task_id|status):/ {
        colon = index($0, ":")
        key   = substr($0, 1, colon - 1); gsub(/^[ \t]+/, "", key)
        val   = substr($0, colon + 1);    val = trim(unquote(val))
        if      (key == "parent_cmd")  parent_cmd  = val
        else if (key == "task_type")   task_type   = val
        else if (key == "assigned_to") assigned_to = val
        else if (key == "task_id")     task_id     = val
        else if (key == "_ac_task_id") ac_task_id  = val
        else if (key == "status")      status      = val
    }
    END { process() }
    function process(   tid) {
        if (parent_cmd == cmd_id && (task_type == "recon" || task_type == "scout")) {
            tid = (task_id != "") ? task_id : ac_task_id
            print cur_file "\t" assigned_to "\t" status "\t" tid
        }
    }
    ' "${files[@]}"
)

# ─── 偵察タスク数 ───
TOTAL=${#RECON_FILES[@]}

# ─── 偵察タスクなし ───
if [ "$TOTAL" -eq 0 ]; then
    echo "INFO: ${CMD_ID}に偵察タスクなし"
    write_gate_flag "$CMD_ID" "report_merge" "skip" "偵察タスクなし"
    # cmd_108: Write .done flag for cmd_complete_gate
    write_done_flag "$CMD_ID" "SKIP"
    exit 0
fi

# ─── 完了状態の集計 ───
DONE_COUNT=0
PENDING_NINJAS=()

for i in "${!RECON_NINJAS[@]}"; do
    ninja="${RECON_NINJAS[$i]}"
    status="${RECON_STATUSES[$i]}"
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
    write_done_flag "$CMD_ID" "READY"
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
