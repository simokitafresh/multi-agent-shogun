#!/usr/bin/env bash
# semantic-links: [[Hook自動化フレームワーク]]
# @source: cmd_452 (SessionStart context注入hook)
set -euo pipefail

_session_start_self="${BASH_SOURCE[0]}"
[[ "$_session_start_self" != /* ]] && _session_start_self="$PWD/$_session_start_self"
SCRIPT_DIR="${_session_start_self%/scripts/hooks/session_start_inject.sh}"
unset _session_start_self

_session_start_overhead_source="session_start_inject"
_session_start_overhead_start_epoch="${EPOCHREALTIME/./}"
_session_start_overhead_start_ms="${_session_start_overhead_start_epoch:0:13}"
_session_start_overhead_event_id="${_session_start_overhead_source}-$$-${RANDOM}-${EPOCHREALTIME//./}"
if [[ -f "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh" ]]; then
  # shellcheck source=/dev/null
  _session_start_overhead_path="${PATH:-}"
  PATH="${PATH:-}:/usr/bin:/bin" source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
  PATH="$_session_start_overhead_path"
  unset _session_start_overhead_path
else
  defense_overhead_write_async() { :; }
fi
_session_start_overhead_emit() {
  local _session_start_overhead_rc="$1"
  # Codex's adapter owns the SessionStart boundary.  Suppress only this
  # helper's row for that nested call; source-specific writers in the child
  # process remain enabled and the wrapped command's rc is preserved.
  if [[ "${SESSION_START_OVERHEAD_SUPPRESS:-0}" == "1" ]]; then
    return "$_session_start_overhead_rc"
  fi
  local _session_start_overhead_end_epoch="${EPOCHREALTIME/./}"
  local _session_start_overhead_end_ms="${_session_start_overhead_end_epoch:0:13}"
  local _session_start_overhead_wall_ms=$((_session_start_overhead_end_ms - _session_start_overhead_start_ms))
  local _session_start_overhead_verdict=PASS
  [[ "$_session_start_overhead_rc" -eq 0 ]] || _session_start_overhead_verdict=FAIL
  PATH="${PATH:-}:/usr/bin:/bin" defense_overhead_write_async "$_session_start_overhead_source" "${_session_start_overhead_source}_total" \
    "$_session_start_overhead_wall_ms" "$_session_start_overhead_verdict" "$_session_start_overhead_event_id" '{}' || true
  return "$_session_start_overhead_rc"
}
trap '_session_start_overhead_emit "$?"' EXIT

if [[ -f "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
fi
if [[ -f "$SCRIPT_DIR/scripts/lib/model_injection_profile.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/scripts/lib/model_injection_profile.sh"
fi

_session_start_json_get() {
  local _session_start_field="$1"
  local _session_start_default="$2"
  local _session_start_value

  if [[ "$_session_start_field" == ".type" ]]; then
    if [[ "$payload" =~ \"type\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      printf '%s' "${BASH_REMATCH[1]:-$_session_start_default}"
      return 0
    fi
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
  local _session_start_event_json
  local _session_start_context_json

  # Keep escaping in the current shell. Command substitutions fork two bash
  # processes on every SessionStart, despite this helper only returning text.
  _session_start_json_escape "$_session_start_event"
  _session_start_event_json="$REPLY"
  _session_start_json_escape "$_session_start_context"
  _session_start_context_json="$REPLY"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$_session_start_event_json" "$_session_start_context_json"
}

_session_start_json_escape() {
  local _session_start_value="$1"
  _session_start_value="${_session_start_value//\\/\\\\}"
  _session_start_value="${_session_start_value//\"/\\\"}"
  _session_start_value="${_session_start_value//$'\n'/\\n}"
  _session_start_value="${_session_start_value//$'\r'/\\r}"
  _session_start_value="${_session_start_value//$'\t'/\\t}"
  REPLY="$_session_start_value"
}

_session_start_epoch_result=0
_session_start_iso_epoch() {
  local _session_start_ts="$1"
  local _session_start_y
  local _session_start_m
  local _session_start_d
  local _session_start_h
  local _session_start_min
  local _session_start_s
  local _session_start_tz
  local _session_start_days_y
  local _session_start_days_m
  local _session_start_era
  local _session_start_yoe
  local _session_start_doy
  local _session_start_doe
  local _session_start_offset

  if [[ ! "$_session_start_ts" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(Z|[+-][0-9]{2}:?[0-9]{2})$ ]]; then
    return 1
  fi

  _session_start_y=$((10#${BASH_REMATCH[1]}))
  _session_start_m=$((10#${BASH_REMATCH[2]}))
  _session_start_d=$((10#${BASH_REMATCH[3]}))
  _session_start_h=$((10#${BASH_REMATCH[4]}))
  _session_start_min=$((10#${BASH_REMATCH[5]}))
  _session_start_s=$((10#${BASH_REMATCH[6]}))
  _session_start_tz="${BASH_REMATCH[7]}"

  _session_start_days_y=$_session_start_y
  if (( _session_start_m <= 2 )); then
    ((_session_start_days_y--))
  fi
  if (( _session_start_days_y >= 0 )); then
    _session_start_era=$((_session_start_days_y / 400))
  else
    _session_start_era=$(((_session_start_days_y - 399) / 400))
  fi
  _session_start_yoe=$((_session_start_days_y - _session_start_era * 400))
  if (( _session_start_m > 2 )); then
    _session_start_days_m=$((_session_start_m - 3))
  else
    _session_start_days_m=$((_session_start_m + 9))
  fi
  _session_start_doy=$(((153 * _session_start_days_m + 2) / 5 + _session_start_d - 1))
  _session_start_doe=$((_session_start_yoe * 365 + _session_start_yoe / 4 - _session_start_yoe / 100 + _session_start_doy))
  _session_start_epoch_result=$(((_session_start_era * 146097 + _session_start_doe - 719468) * 86400 + _session_start_h * 3600 + _session_start_min * 60 + _session_start_s))

  if [[ "$_session_start_tz" != "Z" ]]; then
    _session_start_offset=$((10#${_session_start_tz:1:2} * 3600 + 10#${_session_start_tz: -2} * 60))
    if [[ "${_session_start_tz:0:1}" == "+" ]]; then
      _session_start_epoch_result=$((_session_start_epoch_result - _session_start_offset))
    else
      _session_start_epoch_result=$((_session_start_epoch_result + _session_start_offset))
    fi
  fi
}

# --- Read stdin JSON (type: startup|resume|clear|compact) ---
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

# Claude CodeのSessionStartペイロードは"source"キー、旧形式は"type"キー。
# "type"のみだと常にunknownになり、/clear時のdeepdive markerが更新されず
# 前セッションの受領証が「今セッション」PASSと誤判定される(2026-07-29実測)。
if [[ "$payload" =~ \"source\"[[:space:]]*:[[:space:]]*\"(startup|resume|clear|compact)\" ]]; then
  source_type="${BASH_REMATCH[1]}"
elif [[ "$payload" =~ \"type\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  source_type="${BASH_REMATCH[1]:-unknown}"
else
  source_type="$(_session_start_json_get ".type" "unknown")" || {
    exit 0
  }
fi

# --- Get agent_id from environment or tmux ---
agent_id="${AGENT_ID:-}"
if [[ -z "$agent_id" ]] && command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  fi
  # 2026-09-01 15:19 実測: TMUX_PANE 無しの子プロセス(claude -p 等)がここで
  # `tmux display-message -p`(= 殿が見ている active pane)を引き、shogun と誤解決して
  # logs/deepdive_replay/shogun.session を書き換えた→将軍の追体験 receipt 16/16 が
  # 失効し stop hook が偽 BLOCK。active pane は「誰が見ているか」であり「誰が
  # 走っているか」ではない。TMUX_PANE が無ければ unknown のまま(marker は触らない)。
fi
if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi

# --- deepdive追体験セッションマーカー(殿裁定2026-07-26 23:28: /new後毎回追体験を強制) ---
# startup/clearだけが新しい論理セッションである。resume/compactは同一セッションを
# 継続するため、ここでmarkerを更新すると完了済みreceiptを誤失効させる。
if [[ "$source_type" == "startup" || "$source_type" == "clear" ]]; then
  case "$agent_id" in
    shogun|karo|gunshi)
      mkdir -p "$SCRIPT_DIR/logs/deepdive_replay" 2>/dev/null || true
      printf '%(%Y-%m-%dT%H:%M:%S%z)T' -1 > "$SCRIPT_DIR/logs/deepdive_replay/${agent_id}.session" 2>/dev/null || true
      ;;
  esac
fi

# --- Timestamp (ISO 8601) ---
printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
if [[ "$timestamp" =~ ^(.+)([+-][0-9]{2})([0-9]{2})$ ]]; then
  timestamp="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
fi

snapshot_budget=500
compact_budget=1000
auto_idle_budget=3000
startup_gate_budget=20000

# --- Inbox unread count ---
inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
unread_count=0
if [[ -f "$inbox_file" ]]; then
  while IFS= read -r _session_start_line; do
    [[ "$_session_start_line" =~ ^[[:space:]]*read:[[:space:]]*false[[:space:]]*$ ]] && ((++unread_count))
  done < "$inbox_file"
fi

# --- karo_snapshot ---
snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
karo_snapshot="unavailable"
if [[ -f "$snapshot_file" ]]; then
  IFS= read -r -N $((snapshot_budget + 1)) karo_snapshot < "$snapshot_file" || true
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
  IFS= read -r -N $((compact_budget + 1)) raw_state < "$compact_file" || true
  if [[ -z "$raw_state" ]]; then
    compact_state="none"
  else
    # timestamp行を抽出してepoch比較。短命hookなのでawk/date起動は避ける。
    ts_line=""
    while IFS= read -r _session_start_line; do
      case "$_session_start_line" in
        timestamp:*)
          ts_line="${_session_start_line#timestamp:}"
          ts_line="${ts_line#"${ts_line%%[![:space:]]*}"}"
          ts_line="${ts_line%"${ts_line##*[![:space:]]}"}"
          ts_line="${ts_line#\'}"
          ts_line="${ts_line%\'}"
          break
          ;;
      esac
    done < "$compact_file"
    if [[ -n "$ts_line" ]]; then
      if _session_start_iso_epoch "$ts_line"; then
        ts_epoch="$_session_start_epoch_result"
      else
        ts_epoch=0
      fi
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

# --- CLI switch pending check (殿指示2026-06-21: respawn後は待機状態) ---
# switch_cli_mode.shがrespawnした場合、@cli_switch_pending=trueが設定される。
# startup gateや重い注入を全てスキップし、軽量な待機状態で起動する。
cli_switch_pending=""
if [[ -n "${TMUX_PANE:-}" ]]; then
  cli_switch_pending=$(tmux display-message -t "$TMUX_PANE" -p '#{@cli_switch_pending}' 2>/dev/null || true)
fi
if [[ "$cli_switch_pending" == "true" ]]; then
  # フラグをクリア（次回の通常起動ではrecoveryが走るように）
  tmux set-option -p -t "$TMUX_PANE" @cli_switch_pending "" >/dev/null 2>&1 || true
  # 最小限の注入で終了: agentとsnaphotのみ、startup gate/session_alerts/auto_idle_actionsスキップ
  cat <<HOOK_JSON
{"additionalContext": "=== CLI Switch Respawn (待機状態) ===\nsource: cli_switch\ntimestamp: $(date '+%Y-%m-%dT%H:%M:%S%z')\nagent: ${agent_id}\n★ CLI切替によるrespawn。recovery手順は不要。待機せよ。\n--- karo_snapshot ---\n${karo_snapshot}\n"}
HOOK_JSON
  exit 0
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

# --- Auto idle actions ---
# gate_gunshi_startup.sh writes this file when WARN/ALERT maps to a concrete
# idle self-run step. Inject it separately so the action is visible even when
# startup_gate_output is truncated.
auto_idle_actions="none"
auto_idle_actions_file="$SCRIPT_DIR/queue/auto_idle_actions.txt"
if [[ "$agent_id" == "gunshi" && -s "$auto_idle_actions_file" ]]; then
  auto_idle_actions="$(< "$auto_idle_actions_file")"
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
auto_idle_section="
--- auto_idle_actions ---
${auto_idle_actions}"
model_profile_section=""
if declare -F cli_model_display >/dev/null 2>&1 && declare -F model_injection_profile_text >/dev/null 2>&1; then
  model_label="$(cli_model_display "$agent_id" 2>/dev/null || true)"
  [ -n "$model_label" ] || model_label="$(_cli_lookup_settings_get "$agent_id" model_name unknown 2>/dev/null || true)"
  [ -n "$model_label" ] || model_label="unknown"
  model_profile_section="
--- model_injection_profile ---
$(model_injection_profile_text "$model_label")"
fi
startup_gate_section="
--- startup_gate_output ---
${startup_gate_output}"

# 大きいセクションは役割ごとに上限を設ける。startup gateは手順強制の正本なので
# snapshot/compactより優先して広めに残す。
if (( ${#karo_snapshot} > snapshot_budget )); then
  karo_snapshot="${karo_snapshot:0:$snapshot_budget}
(truncated)"
fi
if (( ${#compact_section} > compact_budget )); then
  compact_section="${compact_section:0:$compact_budget}
(truncated)"
fi
if (( ${#auto_idle_section} > auto_idle_budget )); then
  auto_idle_section="${auto_idle_section:0:$auto_idle_budget}
(truncated)"
fi
if (( ${#startup_gate_section} > startup_gate_budget )); then
  startup_gate_section="${startup_gate_section:0:$startup_gate_budget}
(truncated)"
fi

additional_context="${fixed_part}${karo_snapshot}${compact_section}${auto_idle_section}${model_profile_section}${startup_gate_section}"

# --- Output JSON ---
_session_start_emit_output "SessionStart" "$additional_context"

exit 0
