#!/usr/bin/env bash
# @source: cmd_1808 (SessionEnd clear prep check hook)
set -eu

_session_end_self="${BASH_SOURCE[0]}"
[[ "$_session_end_self" != /* ]] && _session_end_self="$PWD/$_session_end_self"
SCRIPT_DIR="${_session_end_self%/scripts/hooks/session_end_clear_check.sh}"
unset _session_end_self
_session_end_overhead_source="session_end_clear_check"
_session_end_overhead_start_epoch="${EPOCHREALTIME/./}"
_session_end_overhead_start_ms="${_session_end_overhead_start_epoch:0:13}"
_session_end_overhead_event_id="${_session_end_overhead_source}-$$-${RANDOM}-${EPOCHREALTIME//./}"
if [[ -f "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh" ]]; then
  # shellcheck source=/dev/null
  _session_end_overhead_path="${PATH:-}"
  PATH="${PATH:-}:/usr/bin:/bin" source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
  PATH="$_session_end_overhead_path"
  unset _session_end_overhead_path
else
  defense_overhead_write_async() { :; }
fi
_session_end_overhead_emit() {
  local _session_end_overhead_rc="$1"
  local _session_end_overhead_end_epoch="${EPOCHREALTIME/./}"
  local _session_end_overhead_end_ms="${_session_end_overhead_end_epoch:0:13}"
  local _session_end_overhead_wall_ms=$((_session_end_overhead_end_ms - _session_end_overhead_start_ms))
  local _session_end_overhead_verdict=PASS
  [[ "$_session_end_overhead_rc" -eq 0 ]] || _session_end_overhead_verdict=FAIL
  PATH="${PATH:-}:/usr/bin:/bin" defense_overhead_write_async "$_session_end_overhead_source" "${_session_end_overhead_source}_total" \
    "$_session_end_overhead_wall_ms" "$_session_end_overhead_verdict" "$_session_end_overhead_event_id" '{}' || true
  return "$_session_end_overhead_rc"
}
trap '_session_end_overhead_emit "$?"' EXIT

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
  inbound_count="$(awk '
    /"direction":"inbound"/ || /"direction": "inbound"/ { c++ }
    END { print c + 0 }
  ' "$lc_file" 2>/dev/null || echo 0)"
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
  prep_output="$("$prep_check" 2>&1 || true)"
  if [[ "$prep_output" == *"[STATUS] ALERT"* ]]; then
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
  if [[ "${#detail_lines[@]}" -gt 0 ]]; then
    info_message="【SessionEnd 報告】/clear前確認
agent=${agent_id}
$(printf '%s\n' "${detail_lines[@]}")"
    "$ntfy_cmd" "$info_message"
  fi
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
