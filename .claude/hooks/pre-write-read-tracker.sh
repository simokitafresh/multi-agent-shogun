#!/usr/bin/env bash
set -eu

# Read追跡 + Write/Edit未Readガード hook
# - PreToolUse Read: file_pathを /tmp/claude_read_log_{agent_id}.txt に追記
# - PreToolUse Write|Edit: tmpにfile_pathがあるか確認 → 未Read+既存ファイル → deny

payload="$(cat 2>/dev/null || true)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

# Get agent_id from tmux (fallback to 'unknown' on failure)
agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo 'unknown')"
if [ -z "$agent_id" ]; then
    agent_id="unknown"
fi

LOG_FILE="/tmp/claude_read_log_${agent_id}.txt"

# Extract tool_name and file_path from JSON payload
tool_name="$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_name', d.get('toolName', '')))" 2>/dev/null || true)"

file_path="$(printf '%s' "$payload" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', d.get('toolInput', {}))
if isinstance(ti, dict):
    print(ti.get('file_path', ti.get('filePath', ti.get('path', ''))))
else:
    print('')" 2>/dev/null || true)"

if [ -z "$file_path" ]; then
    exit 0
fi

case "$tool_name" in
    Read)
        echo "$file_path" >> "$LOG_FILE"
        exit 0
        ;;
    Write|Edit)
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
