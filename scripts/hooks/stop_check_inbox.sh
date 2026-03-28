#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly COMPLETE_PATTERN='任務完了|完了でござる|報告YAML.*更新|task completed|タスク完了'
readonly ERROR_PATTERN='エラー.*中断|失敗.*中断|error.*abort|failed.*stop'
readonly SUMMARY_LIMIT=5
readonly SUMMARY_SNIPPET_LEN=80
readonly INOTIFY_TIMEOUT="${STOP_HOOK_INOTIFY_TIMEOUT:-5}"

payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

agent_id=""
if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
  fi
fi

if [[ -z "$agent_id" || "$agent_id" == "shogun" ]]; then
  exit 0
fi

STATE_DIR="${SHOGUN_STATE_DIR:-/tmp}"
mkdir -p "$STATE_DIR"
idle_flag="${STATE_DIR}/shogun_idle_${agent_id}"
last_assistant_message="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"

stop_hook_active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [[ "$stop_hook_active" == "true" ]]; then
  touch "$idle_flag"
  exit 0
fi

notify_completion() {
  local msg_type="$1"
  local message="$2"
  (
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" karo "$message" "$msg_type" "$agent_id"
  ) >/dev/null 2>&1 &
}

if [[ -n "$last_assistant_message" ]]; then
  if printf '%s\n' "$last_assistant_message" | grep -Eiq "$COMPLETE_PATTERN"; then
    notify_completion "report_completed" "${agent_id}、タスク完了"
  elif printf '%s\n' "$last_assistant_message" | grep -Eiq "$ERROR_PATTERN"; then
    notify_completion "error_report" "${agent_id}、エラー停止"
  fi
fi

inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
if [[ ! -f "$inbox_file" ]]; then
  exit 0
fi

unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
  unread_count=0
fi

if (( unread_count > 0 )); then
  unread_summary="$(
    INBOX_FILE="$inbox_file" SUMMARY_LIMIT_ENV="$SUMMARY_LIMIT" SUMMARY_SNIPPET_LEN_ENV="$SUMMARY_SNIPPET_LEN" python3 - <<'PY'
import os
import yaml

inbox_path = os.environ["INBOX_FILE"]
limit = int(os.environ["SUMMARY_LIMIT_ENV"])
snippet_len = int(os.environ["SUMMARY_SNIPPET_LEN_ENV"])

with open(inbox_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

parts = []
for msg in data.get("messages", []):
    if msg.get("read") is not False:
        continue
    sender = str(msg.get("from", "?"))
    msg_type = str(msg.get("type", "?"))
    content = " ".join(str(msg.get("content", "")).split())
    content = content[:snippet_len]
    parts.append(f"[{sender}/{msg_type}] {content}")
    if len(parts) >= limit:
        break

print(" | ".join(parts))
PY
  )"
  touch "$idle_flag"
  if [[ -n "$unread_summary" ]]; then
    reason_text="inbox未読${unread_count}件あり。内容: ${unread_summary}"
  else
    reason_text="inbox未読${unread_count}件あり"
  fi
  REASON_TEXT="$reason_text" python3 - <<'PY'
import json
import os

print(json.dumps({"decision": "block", "reason": os.environ["REASON_TEXT"]}, ensure_ascii=False))
PY
else
  # inotifywait待機: 未読0件でも新メッセージ到着を短時間待つ（おしお殿知見）
  # WSL2 /mnt/c/ でもinotifyは正常動作（実測1sで検知）。タイムアウトは安全網のみ
  if command -v inotifywait >/dev/null 2>&1; then
    inotifywait -qq -e close_write -e moved_to --timeout "$INOTIFY_TIMEOUT" "$inbox_file" &>/dev/null || true
    # 待機後に再チェック
    recheck_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
    if [[ "$recheck_count" =~ ^[0-9]+$ ]] && (( recheck_count > 0 )); then
      touch "$idle_flag"
      reason_text="inbox未読${recheck_count}件あり(待機中に到着)"
      REASON_TEXT="$reason_text" python3 - <<'PY'
import json
import os
print(json.dumps({"decision": "block", "reason": os.environ["REASON_TEXT"]}, ensure_ascii=False))
PY
      exit 0
    fi
  fi
  touch "$idle_flag"
fi

exit 0
