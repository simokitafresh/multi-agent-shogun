#!/usr/bin/env bash
set -eu

# Read追跡 + Write/Edit未Readガード hook
# - PreToolUse Read: file_pathを /tmp/claude_read_log_{agent_id}.txt に追記
# - PreToolUse Write|Edit: tmpにfile_pathがあるか確認 → 未Read+既存ファイル → deny

payload="$(cat 2>/dev/null || true)"
case "$payload" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac

# Fast-path: only process Read/Write/Edit
case "$payload" in
    *'"Read"'*|*'"Write"'*|*'"Edit"'*) ;;
    *) exit 0 ;;
esac

# Extract tool_name and file_path with single jq call
_parsed="$(printf '%s' "$payload" | jq -r '[(.tool_name // .toolName // ""), ((.tool_input // .toolInput // {}) | .file_path // .filePath // .path // "")] | @tsv' 2>/dev/null)" || exit 0
tool_name="${_parsed%%	*}"
file_path="${_parsed#*	}"

[[ -z "$file_path" ]] && exit 0

# Claude's Read path must consume the same three-layer evidence as every
# other action.  Tracking a Read before this check would turn an unevidenced
# read into a false proof for the later Write/Edit guard.
_tracker_self="${BASH_SOURCE[0]}"
[[ "$_tracker_self" == /* ]] || _tracker_self="$PWD/$_tracker_self"
_tracker_root="${SHOGUN_REPO_ROOT:-${_tracker_self%/.claude/hooks/pre-write-read-tracker.sh}}"
_tracker_preflight="$_tracker_root/scripts/hooks/three_layer_preflight.sh"
if [[ ! -x "$_tracker_preflight" ]] || ! bash "$_tracker_preflight" verify "Read" "$file_path" "" >/dev/null 2>&1; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Claude Readは三層preflight証跡が必要です。先にthree_layer_preflight.sh issueを実行してください。"}}\n'
    exit 1
fi

# Get agent_id with env fast-path, fallback to tmux, then unknown
agent_id="${MOCK_AGENT_ID:-${AGENT_ID:-}}"
if [[ -z "$agent_id" ]]; then
    agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo 'unknown')"
fi
[[ -z "$agent_id" ]] && agent_id="unknown"

LOG_FILE="/tmp/claude_read_log_${agent_id}.txt"

case "$tool_name" in
    Read)
        echo "$file_path" >> "$LOG_FILE"
        exit 0
        ;;
    Write|Edit)
        # queue/tasks/*.yaml → 無条件deny（deploy_task.shを使え）
        # queue/reports/*.yaml → 無条件deny（report_field_set.shを使え）(cmd_1284でBLOCK復元)
        case "$file_path" in
            */queue/tasks/*.yaml)
                printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"queue/tasks/*.yamlはWrite/Editで直接書くな。状態更新→bash scripts/lib/yaml_field_set.sh queue/tasks/{name}.yaml task {field} {value}。新規配備→deploy_task.sh。"}}\n'
                exit 1
                ;;
            */queue/reports/*.yaml)
                printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"queue/reports/*.yamlはWrite/Editで直接書くな。report_field_set.shを使え。"}}\n'
                exit 1
                ;;
        esac
        # New file → allow
        if [ ! -f "$file_path" ]; then
            exit 0
        fi
        # Read済み → allow
        if [ -f "$LOG_FILE" ] && grep -qFx "$file_path" "$LOG_FILE" 2>/dev/null; then
            exit 0
        fi
        # 未Read → deny
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"このファイルはまだReadされていません。先にReadツールで読んでからWrite/Editしてください。"}}\n'
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
