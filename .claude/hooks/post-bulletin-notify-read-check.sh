#!/usr/bin/env bash
# PostToolUse hook: warn when a bulletin_notify inbox item is marked read before reading bulletin_board.yaml.
set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
[[ "$payload" != *'"Bash"'* || "$payload" != *'inbox_mark_read.sh'* ]] && exit 0

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${_self%/.claude/hooks/post-bulletin-notify-read-check.sh}"
unset _self

command="$(printf '%s' "$payload" | jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null || true)"
[[ "$command" == *'inbox_mark_read.sh'* ]] || exit 0

extract_mark_args() {
    COMMAND="$command" python3 - <<'PY'
import os
import shlex

command = os.environ.get("COMMAND", "")
try:
    tokens = shlex.split(command, posix=True)
except ValueError:
    raise SystemExit(0)

for i, token in enumerate(tokens):
    if token.endswith("inbox_mark_read.sh"):
        agent = tokens[i + 1] if i + 1 < len(tokens) else ""
        msg_id = tokens[i + 2] if i + 2 < len(tokens) else ""
        print(agent)
        print(msg_id)
        break
PY
}

args="$(extract_mark_args 2>/dev/null || true)"
agent="$(printf '%s\n' "$args" | sed -n '1p')"
msg_id="$(printf '%s\n' "$args" | sed -n '2p')"
[[ "$agent" =~ ^[a-z_]+$ ]] || exit 0

inbox="$ROOT/queue/inbox/${agent}.yaml"
bulletin="$ROOT/queue/bulletin_board.yaml"
[[ -f "$inbox" && -f "$bulletin" ]] || exit 0

read_log="${READ_LOG_DIR:-/tmp}/claude_read_log_${agent}.txt"
if [[ -f "$read_log" ]]; then
    recent_reads="$(tail -20 "$read_log" 2>/dev/null || true)"
    if [[ "$recent_reads" == *"queue/bulletin_board.yaml"* || "$recent_reads" == *"$bulletin"* ]]; then
        exit 0
    fi
fi

result="$(python3 - "$inbox" "$bulletin" "$agent" "$msg_id" <<'PY' 2>/dev/null || true
import sys
import yaml

inbox_path, bulletin_path, agent, msg_id = sys.argv[1:5]

with open(inbox_path, encoding="utf-8") as fh:
    inbox_data = yaml.safe_load(fh) or {}

marked_bulletin = False
for msg in inbox_data.get("messages") or []:
    if not isinstance(msg, dict):
        continue
    if msg_id and str(msg.get("id", "")) != msg_id:
        continue
    if msg.get("type") == "bulletin_notify":
        marked_bulletin = True
        break

if not marked_bulletin:
    raise SystemExit(0)

with open(bulletin_path, encoding="utf-8") as fh:
    bulletin_data = yaml.safe_load(fh) or {}

pending = []
for entry in bulletin_data.get("entries") or []:
    if not isinstance(entry, dict):
        continue
    rc = entry.get("requires_confirmation", False)
    if not rc:
        continue
    if isinstance(rc, list) and agent not in rc:
        continue
    if str(entry.get("status", "")).lower() == "closed":
        continue
    confirmed = entry.get("confirmed_by") or []
    if agent in confirmed:
        continue
    text = str(entry.get("content", "")).splitlines()
    head = text[0] if text else ""
    pending.append(f"{entry.get('id', '?')} by {entry.get('posted_by', '?')} - {head[:80]}")

if pending:
    print(len(pending))
    for item in pending[:3]:
        print(item)
PY
)"

count="$(printf '%s\n' "$result" | sed -n '1p')"
[[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || exit 0
items="$(printf '%s\n' "$result" | tail -n +2 | sed 's/^/  - /')"

msg="WARNING: bulletin_notifyを既読化したが、掲示板未確認エントリが${count}件残っている。
WHY: inbox通知は索引であり、結論本文は queue/bulletin_board.yaml の掲示板エントリにある。
FIX: Read toolで queue/bulletin_board.yaml を読み、必要なら bash scripts/bulletin_confirm.sh ${agent} <entry_id> を実行せよ。
${items}"

printf '%s' "$msg" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:.}}' 2>/dev/null || true
