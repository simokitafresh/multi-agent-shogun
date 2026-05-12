#!/usr/bin/env bash
# @source: cmd_452 (SessionStart context注入hook)
set -euo pipefail

_session_start_self="${BASH_SOURCE[0]}"
[[ "$_session_start_self" != /* ]] && _session_start_self="$PWD/$_session_start_self"
SCRIPT_DIR="${_session_start_self%/scripts/hooks/session_start_inject.sh}"
unset _session_start_self

_session_start_json_get() {
  local _session_start_field="$1"
  local _session_start_default="$2"
  local _session_start_value

  if [[ "$_session_start_field" == ".type" ]]; then
    if _session_start_value="$(jq -r 'try (.type // "unknown") catch "unknown"' 2>/dev/null <<<"$payload")"; then
      printf '%s' "$_session_start_value"
      return 0
    fi
  fi

  JSON_PAYLOAD="$payload" JSON_FIELD="$_session_start_field" JSON_DEFAULT="$_session_start_default" python3 - <<'PY'
import json
import os
import sys

payload = os.environ.get("JSON_PAYLOAD", "")
field = os.environ.get("JSON_FIELD", "")
default = os.environ.get("JSON_DEFAULT", "")

try:
    obj = json.loads(payload)
except Exception:
    raise SystemExit(1)

field_map = {
    ".type": "type",
}
key = field_map.get(field)
if key is None:
    raise SystemExit(1)

value = obj.get(key, default)
if value is None:
    value = default
if not isinstance(value, str):
    value = str(value)
sys.stdout.write(value)
PY
}

_session_start_emit_output() {
  local _session_start_event="$1"
  local _session_start_context="$2"
  local _session_start_json

  if _session_start_json="$(jq -Rs --arg event_name "$_session_start_event" '{hookSpecificOutput:{hookEventName:$event_name,additionalContext:.}}' 2>/dev/null <<<"$_session_start_context")"; then
    printf '%s\n' "$_session_start_json"
    return 0
  fi

  printf '%s' "$_session_start_context" | HOOK_EVENT_NAME="$_session_start_event" python3 -c '
import json
import os
import sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": os.environ["HOOK_EVENT_NAME"],
        "additionalContext": sys.stdin.read(),
    }
}, ensure_ascii=False))
'
}

# --- Read stdin JSON (type: startup|resume|clear|compact) ---
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

source_type="$(_session_start_json_get ".type" "unknown")" || {
  exit 0
}

# --- Get agent_id from tmux ---
agent_id="unknown"
if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  fi
fi
if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

# --- Timestamp (ISO 8601) ---
printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
if [[ "$timestamp" =~ ^(.+)([+-][0-9]{2})([0-9]{2})$ ]]; then
  timestamp="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
fi

# --- Inbox unread count ---
inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
unread_count=0
if [[ -f "$inbox_file" ]]; then
  unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
  if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
    unread_count=0
  fi
fi

# --- karo_snapshot ---
snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
karo_snapshot="unavailable"
if [[ -f "$snapshot_file" ]]; then
  karo_snapshot="$(< "$snapshot_file")"
  if [[ -z "$karo_snapshot" ]]; then
    karo_snapshot="unavailable"
  fi
fi

# --- compact_state ---
# /clear は PreCompact を発火しないため、compact_state は /clear 時に古い情報のまま。
# さらに軍師/将軍/一部忍者は auto-compact 頻度が低く、startup/resume でも構造的に
# 古い情報になる。古い情報を「現在の状態」として注入するとノイズ=誤読リスク。
# 2段階防御: (1) source_type == clear → 全面スキップ注記
#            (2) それ以外でも timestamp が 24h 超なら stale 注記を冒頭に付与
# 殿原則「想像するな確認せよ」(2026-03-21) に準拠。
compact_file="$SCRIPT_DIR/queue/compact_state/${agent_id}.yaml"
compact_state="none"
compact_stale_threshold=86400  # 24h in seconds
if [[ "$source_type" == "clear" ]]; then
  compact_state="(skipped: /clear type does not update compact_state; last value may be stale)"
elif [[ -f "$compact_file" ]]; then
  raw_state="$(< "$compact_file")"
  if [[ -z "$raw_state" ]]; then
    compact_state="none"
  else
    # timestamp行を抽出してepoch比較。quote除去にawkを使用
    ts_line="$(awk '
      /^timestamp:/ {
        sub(/^timestamp:[[:space:]]*/, "")
        gsub(/^'\''|'\''$/, "")
        print
        exit
      }
    ' "$compact_file" 2>/dev/null || true)"
    if [[ -n "$ts_line" ]]; then
      ts_epoch="$(date -d "$ts_line" +%s 2>/dev/null || echo 0)"
      printf -v now_epoch '%(%s)T' -1
      age_sec=$((now_epoch - ts_epoch))
      if (( ts_epoch > 0 && age_sec > compact_stale_threshold )); then
        age_days=$((age_sec / 86400))
        compact_state="(stale: ${age_days}d old; last update=${ts_line}; auto-compact未踏=構造的古さ)
${raw_state}"
      else
        compact_state="$raw_state"
      fi
    else
      compact_state="$raw_state"
    fi
  fi
fi

# --- Role startup gate ---
# cmd_2683: 起動手順スキップを防ぐため、SessionStart時に役職別startup gateを
# 自動実行し、その結果をadditionalContextへ注入する。
startup_gate_output="none"
startup_gate_name="none"
case "$agent_id" in
  shogun)
    startup_gate_name="gate_shogun_startup.sh"
    ;;
  karo)
    startup_gate_name="gate_karo_startup.sh"
    ;;
  gunshi)
    startup_gate_name="gate_gunshi_startup.sh"
    ;;
esac

if [[ "$startup_gate_name" != "none" ]]; then
  startup_gate_path="$SCRIPT_DIR/scripts/gates/$startup_gate_name"
  if [[ -x "$startup_gate_path" || -f "$startup_gate_path" ]]; then
    if command -v timeout >/dev/null 2>&1; then
      startup_gate_output="$(timeout 50s bash "$startup_gate_path" 2>&1 || printf 'startup_gate_exit=%s\n' "$?")"
    else
      startup_gate_output="$(bash "$startup_gate_path" 2>&1 || printf 'startup_gate_exit=%s\n' "$?")"
    fi
  else
    startup_gate_output="missing: $startup_gate_path"
  fi
fi

# --- Build additionalContext ---
header="=== Session Context (auto-injected) ==="
fixed_part="${header}
source: ${source_type}
timestamp: ${timestamp}
agent: ${agent_id}
inbox_unread: ${unread_count}
startup_gate: ${startup_gate_name}
--- karo_snapshot ---
"
compact_section="
--- compact_state ---
${compact_state}"
startup_gate_section="
--- startup_gate_output ---
${startup_gate_output}"

# 大きいセクションは役割ごとに上限を設ける。startup gateは手順強制の正本なので
# snapshot/compactより優先して広めに残す。
snapshot_budget=500
compact_budget=1000
startup_gate_budget=20000

if (( ${#karo_snapshot} > snapshot_budget )); then
  karo_snapshot="${karo_snapshot:0:$snapshot_budget}
(truncated)"
fi
if (( ${#compact_section} > compact_budget )); then
  compact_section="${compact_section:0:$compact_budget}
(truncated)"
fi
if (( ${#startup_gate_section} > startup_gate_budget )); then
  startup_gate_section="${startup_gate_section:0:$startup_gate_budget}
(truncated)"
fi

additional_context="${fixed_part}${karo_snapshot}${compact_section}${startup_gate_section}"

# --- Output JSON ---
_session_start_emit_output "SessionStart" "$additional_context"

exit 0
