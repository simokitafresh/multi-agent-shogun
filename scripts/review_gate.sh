#!/bin/bash
# review_gate.sh — コード変更を含むcmdのレビュー完了ゲート
# Usage: bash scripts/review_gate.sh <cmd_id>
# Exit 0: PASS(レビュー済み) or SKIP(コード変更なし)
# Exit 1: BLOCK(レビュー未完了 or レビュータスクなし)

set -e

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_ID="$1"

if [ -z "$CMD_ID" ]; then
    echo "Usage: review_gate.sh <cmd_id>" >&2
    exit 1
fi

TASKS_DIR="$SCRIPT_DIR/queue/tasks"

if [ ! -d "$TASKS_DIR" ]; then
    echo "SKIP: タスクディレクトリが存在しない ($TASKS_DIR)"
    exit 0
fi

set +e
PY_OUT="$(
    awk -v cmd_id="$CMD_ID" '
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
function unquote(s) {
    s = trim(s)
    if (length(s) >= 2) {
        first = substr(s, 1, 1)
        last = substr(s, length(s), 1)
        if ((first == "\"" && last == "\"") || (first == "'\''" && last == "'\''")) {
            s = substr(s, 2, length(s) - 2)
        }
    }
    return s
}
function lower(s) { return tolower(s) }
function field_value(line) {
    sub(/^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/, "", line)
    return unquote(line)
}
function has_code_keyword(text) {
    text = lower(text)
    return text ~ /(commit|push|コード変更|修正|実装|implement|update|change|refactor|fix|create|add|delete|config|script|hook|wrapper|modify|patch|remove|更新|変更|リファクタ|作成|追加|削除|設定|構築|強化)/
}
function has_review_keyword(text) {
    text = lower(text)
    return text ~ /(review|レビュー)/
}
function finish_task() {
    if (!in_task) return
    if (parent_cmd != cmd_id) return

    all_count++
    search_text = command " " purpose
    is_review = (lower(task_type) == "review" || has_review_keyword(search_text))
    is_code = has_code_keyword(search_text)

    if (is_review) {
        review_count++
        if (status == "done") {
            done_review_count++
            done_reviewers = done_reviewers (done_reviewers != "" ? ", " : "") (assigned_to != "" ? assigned_to : "?")
        } else {
            not_done_count++
            not_done_lines = not_done_lines sprintf("BLOCK: レビュー未完了 (%sが%s) [%s]\n", assigned_to != "" ? assigned_to : "?", status != "" ? status : "?", task_id != "" ? task_id : "?")
        }
    }
    if (is_code && !is_review) {
        code_count++
        code_ids = code_ids (code_ids != "" ? ", " : "") (task_id != "" ? task_id : "?")
    }
}
FNR == 1 {
    finish_task()
    in_task = 0
    task_id = status = parent_cmd = command = purpose = task_type = assigned_to = ""
}
/^task:[[:space:]]*$/ { in_task = 1; next }
in_task && /^[[:space:]]{2}task_id:/ { task_id = field_value($0); next }
in_task && /^[[:space:]]{2}status:/ { status = field_value($0); next }
in_task && /^[[:space:]]{2}parent_cmd:/ { parent_cmd = field_value($0); next }
in_task && /^[[:space:]]{2}command:/ { command = field_value($0); next }
in_task && /^[[:space:]]{2}purpose:/ { purpose = field_value($0); next }
in_task && /^[[:space:]]{2}task_type:/ { task_type = field_value($0); next }
in_task && /^[[:space:]]{2}assigned_to:/ { assigned_to = field_value($0); next }
END {
    finish_task()
    if (all_count == 0) {
        printf "SKIP: %sに該当するタスクなし\n", cmd_id
        exit 0
    }
    if (code_count == 0) {
        printf "SKIP: コード変更タスクなし (%d件中0件)\n", all_count
        exit 0
    }
    if (review_count == 0) {
        printf "BLOCK: コード変更あるがレビュータスクなし (変更タスク: %s)\n", code_ids
        exit 1
    }
    if (done_review_count > 0 && not_done_count == 0) {
        printf "PASS: レビュー済み (%s)\n", done_reviewers
        exit 0
    }
    printf "%s", not_done_lines
    exit 1
}
' "$TASKS_DIR"/*.yaml
)"
PY_RC=$?
set -e

printf '%s\n' "$PY_OUT"

if [ "$PY_RC" -eq 0 ]; then
    if [[ "$PY_OUT" == PASS:* ]]; then
        reviewer="$(printf '%s\n' "$PY_OUT" | sed -n 's/^PASS: レビュー済み (\(.*\))$/\1/p')"
        [ -z "$reviewer" ] && reviewer="unknown"
        write_gate_flag "$CMD_ID" "review_gate" "pass" "レビュー完了(${reviewer})"
    elif [[ "$PY_OUT" == SKIP:* ]]; then
        write_gate_flag "$CMD_ID" "review_gate" "skip" "コード変更なし"
    fi
    # cmd_108: Write .done flag for cmd_complete_gate
    local_gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
    mkdir -p "$local_gates_dir"
    echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$local_gates_dir/review_gate.done"
    echo "result: ${PY_OUT%%:*}" >> "$local_gates_dir/review_gate.done"
fi

exit "$PY_RC"
