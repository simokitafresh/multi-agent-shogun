#!/usr/bin/env bash
# @source: cmd_1808 (SessionEnd clear prep check hook)
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

payload="$(cat 2>/dev/null || true)"
if [[ -n "$payload" ]] && ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  exit 0
fi

agent_id="${SESSION_END_AGENT_ID:-}"
if [[ -z "$agent_id" ]] && command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
  fi
fi
if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

# 殿への通知対象は将軍のみ
if [[ "$agent_id" != "shogun" ]]; then
  exit 0
fi

lc_file="${SESSION_END_LORD_CONVERSATION_FILE:-$SCRIPT_DIR/queue/lord_conversation.jsonl}"
prep_check="${SESSION_END_CLEAR_PREP_CMD:-$SCRIPT_DIR/scripts/clear_prep_check.sh}"
ntfy_cmd="${SESSION_END_NTFY_CMD:-$SCRIPT_DIR/scripts/ntfy.sh}"

issues=()
detail_lines=()

if [[ -f "$lc_file" ]]; then
  inbound_count="$(grep -c '"direction":"inbound"\|"direction": "inbound"' "$lc_file" 2>/dev/null || echo 0)"
  detail_lines+=("殿の言葉 inbound=${inbound_count}件")
  if [[ ! "$inbound_count" =~ ^[0-9]+$ ]]; then
    inbound_count=0
  fi
  if [[ "$inbound_count" -eq 0 ]]; then
    issues+=("lord_conversation inbound=0")
  fi
else
  detail_lines+=("lord_conversation.jsonl 不在")
  issues+=("lord_conversation missing")
fi

prep_status="SKIP"
prep_digest=""
if [[ -f "$prep_check" ]]; then
  prep_output="$(bash "$prep_check" 2>&1 || true)"
  if printf '%s\n' "$prep_output" | grep -q '^\[STATUS\] ALERT'; then
    prep_status="ALERT"
    issues+=("clear_prep_check ALERT")
  else
    prep_status="OK"
  fi
  prep_digest="$(printf '%s\n' "$prep_output" | awk 'BEGIN{n=0} /^\[/{print; n++; if (n>=6) exit}')"
else
  prep_status="MISSING"
  issues+=("clear_prep_check missing")
fi

detail_lines+=("clear_prep_check=${prep_status}")
if [[ -n "$prep_digest" ]]; then
  detail_lines+=("$prep_digest")
fi

if [[ "${#issues[@]}" -eq 0 ]]; then
  printf 'OK: session_end_clear_check (%s)\n' "$agent_id"
  exit 0
fi

message="【SessionEnd ALERT】/clear前確認で問題検出
agent=${agent_id}
issues=$(IFS=', '; echo "${issues[*]}")
$(printf '%s\n' "${detail_lines[@]}")"

"$ntfy_cmd" "$message"
printf 'ALERT: %s\n' "$(IFS=', '; echo "${issues[*]}")"
exit 0
