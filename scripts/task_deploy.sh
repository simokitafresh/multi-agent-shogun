#!/bin/bash
# task_deploy.sh — タスク配備後の偵察2名並行チェック
# Usage: bash scripts/task_deploy.sh <cmd_id> <task_type>
# task_type: recon | implement | review | other
# recon時: 2名以上の偵察タスクがあるか+別々の忍者か検証

set -e

# SCRIPT_DIR: string ops instead of $(cd) subshells (~5ms savings on WSL2)
_td_self="${BASH_SOURCE[0]:-$0}"
[[ "$_td_self" != /* ]] && _td_self="$PWD/$_td_self"
SCRIPT_DIR="${_td_self%/scripts/task_deploy.sh}"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"

CMD_ID="$1"
TASK_TYPE="$2"

write_gate_flag() {
    local cmd_id="$1" gate_name="$2" result="$3" reason="$4"
    local gates_dir="$SCRIPT_DIR/queue/gates"
    # printf -v builtin avoids spawning date; [[ -d ]] skip avoids mkdir when exists
    local _ts
    printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
    [[ -d "$gates_dir" ]] || mkdir -p "$gates_dir"
    local flag_file="$gates_dir/${cmd_id}_${gate_name}.${result}"
    # printf builtin avoids forking cat for heredoc write
    printf 'timestamp: %s\ncmd_id: %s\ngate_name: %s\nresult: %s\nreason: "%s"\n' \
        "$_ts" "$cmd_id" "$gate_name" "$result" "$reason" > "$flag_file"
}

# Validate arguments
if [ -z "$CMD_ID" ] || [ -z "$TASK_TYPE" ]; then
    echo "Usage: task_deploy.sh <cmd_id> <task_type>" >&2
    echo "  task_type: recon | implement | review | other" >&2
    exit 1
fi

# Non-recon: skip check
if [ "$TASK_TYPE" != "recon" ]; then
    echo "OK: task_type=$TASK_TYPE — 偵察チェックスキップ"
    write_gate_flag "$CMD_ID" "task_deploy" "skip" "task_type=$TASK_TYPE"
    exit 0
fi

# Scan queue/tasks/*.yaml for recon tasks matching parent_cmd.
# gawk+ENDFILE replaces python3 heredoc: eliminates ~70ms Python startup cost.
# Each file is parsed for parent_cmd/title/assigned_to without yaml.safe_load.
_recon_list=$(gawk -v cmd_id="$CMD_ID" '
    FNR == 1 { pc = ""; title = ""; at = "" }
    /parent_cmd:/ {
        sub(/^[^:]+:[[:space:]]*/, ""); gsub(/["'\'']/, ""); pc = $0
    }
    /[[:space:]]title:[[:space:]]/ {
        sub(/^[^:]+:[[:space:]]*/, ""); gsub(/["'\'']/, ""); title = $0
    }
    /assigned_to:/ {
        sub(/^[^:]+:[[:space:]]*/, ""); gsub(/["'\'']/, ""); at = $0 == "" ? "unknown" : $0
    }
    ENDFILE {
        if (pc == cmd_id && (title ~ /偵察/ || tolower(title) ~ /recon/)) {
            print at "\t" FILENAME
        }
        pc = ""; title = ""; at = ""
    }
' "$TASKS_DIR"/*.yaml 2>/dev/null)

_recon_count=$(printf '%s\n' "$_recon_list" | grep -c .) 2>/dev/null || _recon_count=0

if [ "$_recon_count" -lt 2 ]; then
    printf 'ERROR: 偵察タスクは2名並行が必須(現在%d件)\n' "$_recon_count" >&2
    if [ -n "$_recon_list" ]; then
        printf '%s\n' "$_recon_list" | while IFS=$'\t' read -r at f; do
            printf '  - %s → %s\n' "${f##*/}" "$at" >&2
        done
    fi
    exit 1
fi

# Duplicate assignee check
_dupes=$(printf '%s\n' "$_recon_list" | awk -F'\t' '{print $1}' | sort | uniq -d)
if [ -n "$_dupes" ]; then
    printf 'ERROR: 並行偵察は別々の忍者に割り当てよ(重複: %s)\n' "$_dupes" >&2
    printf '%s\n' "$_recon_list" | while IFS=$'\t' read -r at f; do
        printf '  - %s → %s\n' "${f##*/}" "$at" >&2
    done
    exit 1
fi

_recon_names=$(printf '%s\n' "$_recon_list" | awk -F'\t' '{print $1}' | paste -sd ', ')
check_output="OK: 偵察${_recon_count}件(${_recon_names})"
echo "$check_output"

write_gate_flag "$CMD_ID" "task_deploy" "pass" "偵察${_recon_count}件(${_recon_names})"
exit 0
