#!/bin/bash
# SayTask通知 — ntfy.sh経由でスマホにプッシュ通知
# FR-066: ntfy認証対応 (Bearer token / Basic auth)
#
# Usage: bash scripts/ntfy.sh "メッセージ"
#
# ⚠️ WARNING: Do NOT add --send flag guard or any argument gate.
#   2026-02-11 incident: --send guard silently dropped ALL notifications.
#   All callers (shogun/karo/ninja instructions) call without flags.
#   Changing the interface breaks the entire notification pipeline.

# Validate: message argument required
if [ -z "$1" ]; then
    echo "Usage: ntfy.sh <message>" >&2
    exit 1
fi

# Validate caller agent_id (warn-only; do not block send)
AGENT_ID=""
if [ -n "${TMUX_PANE:-}" ]; then
  AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
if [ -z "$AGENT_ID" ]; then
  AGENT_ID="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
fi
if [ -z "$AGENT_ID" ]; then
  echo "WARNING: ntfy called with unavailable agent_id (outside tmux?)" >&2
elif [ "$AGENT_ID" != "shogun" ] && [ "$AGENT_ID" != "karo" ]; then
  # ninja_monitor daemon inherits TMUX_PANE from launch context — suppress warning
  CALLER="${BASH_SOURCE[1]:-}"; CALLER="${CALLER##*/}"  # pure bash basename
  if [ "$CALLER" != "ninja_monitor.sh" ]; then
    echo "WARNING: ntfy called by non-authorized agent: ${AGENT_ID}" >&2
  fi
fi

# Pure bash: avoid cd+pwd subshell (saves ~5ms)
_ntfy_script="${BASH_SOURCE[0]}"
[[ "$_ntfy_script" != /* ]] && _ntfy_script="$PWD/$_ntfy_script"
_ntfy_dir="${_ntfy_script%/*}"
SCRIPT_DIR="${_ntfy_dir%/*}"
unset _ntfy_script _ntfy_dir
SETTINGS="$SCRIPT_DIR/config/settings.yaml"
LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
# shellcheck disable=SC2034  # Used by lord_conversation.sh
LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

# ntfy_auth.sh読み込み
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ntfy_auth.sh"

read_ntfy_topic() {
  local settings_file="$1"
  local line value

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ntfy_topic:*)
        value="${line#*:}"
        value="${value//[[:space:]\"]/}"
        [ -n "$value" ] || return 1
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  done < "$settings_file"

  return 1
}

TOPIC="$(read_ntfy_topic "$SETTINGS" || true)"
if [ -z "$TOPIC" ]; then
  echo "ntfy_topic not configured in settings.yaml" >&2
  exit 1
fi

# Validate topic name security (warn-only; do not block send)
ntfy_validate_topic "$TOPIC" || true

# 認証引数を取得（設定がなければ空 = 後方互換）
AUTH_ARGS=()
ntfy_get_auth_args_into_array "$SCRIPT_DIR/config/ntfy_auth.env" AUTH_ARGS

LOGFILE="$SCRIPT_DIR/logs/ntfy.log"
[ -d "$SCRIPT_DIR/logs" ] || mkdir -p "$SCRIPT_DIR/logs"

MSG="$1"

NTFY_ENDPOINT="${NTFY_ENDPOINT:-https://ntfy.sh/$TOPIC}"
NTFY_MIN_INTERVAL_SECONDS="${NTFY_MIN_INTERVAL_SECONDS:-10}"
NTFY_429_COOLDOWN_SECONDS="${NTFY_429_COOLDOWN_SECONDS:-60}"
NTFY_STATE_DIR="${NTFY_STATE_DIR:-/tmp/multi_agent_shogun_ntfy}"
[[ "$NTFY_429_COOLDOWN_SECONDS" =~ ^[0-9]+$ ]] || NTFY_429_COOLDOWN_SECONDS=60

mkdir -p "$NTFY_STATE_DIR" 2>/dev/null || true
_ntfy_state_key="$(printf '%s' "$NTFY_ENDPOINT" | sha256sum | awk '{print $1}')"
NTFY_STATE_FILE="$NTFY_STATE_DIR/${_ntfy_state_key}.state"
NTFY_LOCK_FILE="$NTFY_STATE_DIR/${_ntfy_state_key}.lock"
unset _ntfy_state_key

append_lord_conversation_safe() {
  local payload="$1"

  if [ -z "${_NTFY_LORD_CONVERSATION_LOADED:-}" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/lord_conversation.sh"
    _NTFY_LORD_CONVERSATION_LOADED=1
  fi

  append_lord_conversation "$payload" "outbound" "${AGENT_ID:-unknown}" "ntfy" || true
}

_ntfy_send() {
  local payload="$1"
  local http_code start end elapsed
  start=$EPOCHSECONDS
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 30 --connect-timeout 15 \
    "${AUTH_ARGS[@]}" -H "Tags: outbound" -d "$payload" \
    "$NTFY_ENDPOINT" 2>/dev/null)
  end=$EPOCHSECONDS
  elapsed=$((end - start))
  printf '%(%Y-%m-%d %H:%M:%S)T http=%s time=%ss msg="%s"\n' -1 "$http_code" "$elapsed" "${payload:0:80}" >> "$LOGFILE"
  echo "$http_code"
}

_ntfy_read_state_value() {
  local key="$1"
  local value=""

  if [ -f "$NTFY_STATE_FILE" ]; then
    while IFS='=' read -r state_key state_value || [ -n "$state_key" ]; do
      if [ "$state_key" = "$key" ]; then
        value="$state_value"
        break
      fi
    done < "$NTFY_STATE_FILE"
  fi

  printf '%s\n' "$value"
}

_ntfy_write_state() {
  local last_send_epoch="$1"
  local cooldown_until="$2"
  local tmp="${NTFY_STATE_FILE}.$$"

  {
    printf 'last_send_epoch=%s\n' "$last_send_epoch"
    printf 'cooldown_until=%s\n' "$cooldown_until"
  } > "$tmp"
  mv "$tmp" "$NTFY_STATE_FILE"
}

send_with_retry() {
  local payload="$1"
  local http_code now last_send_epoch cooldown_until elapsed

  now=$EPOCHSECONDS
  last_send_epoch="$(_ntfy_read_state_value last_send_epoch)"
  cooldown_until="$(_ntfy_read_state_value cooldown_until)"
  [[ "$last_send_epoch" =~ ^[0-9]+$ ]] || last_send_epoch=0
  [[ "$cooldown_until" =~ ^[0-9]+$ ]] || cooldown_until=0

  if (( cooldown_until > now )); then
    printf '%(%Y-%m-%d %H:%M:%S)T SKIP cooldown_until=%s remaining=%ss msg="%s"\n' -1 "$cooldown_until" "$((cooldown_until - now))" "${payload:0:80}" >> "$LOGFILE"
    return 0
  fi

  if [[ "$NTFY_MIN_INTERVAL_SECONDS" =~ ^[0-9]+$ ]] && (( NTFY_MIN_INTERVAL_SECONDS > 0 && last_send_epoch > 0 )); then
    elapsed=$((now - last_send_epoch))
    if (( elapsed >= 0 && elapsed < NTFY_MIN_INTERVAL_SECONDS )); then
      printf '%(%Y-%m-%d %H:%M:%S)T SKIP throttle elapsed=%ss min=%ss msg="%s"\n' -1 "$elapsed" "$NTFY_MIN_INTERVAL_SECONDS" "${payload:0:80}" >> "$LOGFILE"
      return 0
    fi
  fi

  http_code=$(_ntfy_send "$payload")
  if [ "$http_code" = "200" ]; then
    _ntfy_write_state "$EPOCHSECONDS" 0
    append_lord_conversation_safe "$payload"
    return 0
  fi

  if [ "$http_code" = "429" ]; then
    cooldown_until=$((EPOCHSECONDS + NTFY_429_COOLDOWN_SECONDS))
    _ntfy_write_state "$EPOCHSECONDS" "$cooldown_until"
    printf '%(%Y-%m-%d %H:%M:%S)T COOLDOWN http=429 until=%s msg="%s"\n' -1 "$cooldown_until" "${payload:0:80}" >> "$LOGFILE"
    return 0
  fi

  # Retry only on connection failure (000 = no response from server).
  # HTTP 500 etc. means the server received the request — message likely
  # already delivered. Retrying would cause duplicate notifications.
  if [ "$http_code" != "000" ]; then
    printf '%(%Y-%m-%d %H:%M:%S)T NO_RETRY http=%s (server responded)\n' -1 "$http_code" >> "$LOGFILE"
    echo "ERROR: ntfy send failed (HTTP $http_code)" >&2
    return 1
  fi

  sleep 3
  http_code=$(_ntfy_send "$payload")
  if [ "$http_code" = "200" ]; then
    _ntfy_write_state "$EPOCHSECONDS" 0
    append_lord_conversation_safe "$payload"
    printf '%(%Y-%m-%d %H:%M:%S)T RETRY_OK\n' -1 >> "$LOGFILE"
    return 0
  fi

  if [ "$http_code" = "429" ]; then
    cooldown_until=$((EPOCHSECONDS + NTFY_429_COOLDOWN_SECONDS))
    _ntfy_write_state "$EPOCHSECONDS" "$cooldown_until"
    printf '%(%Y-%m-%d %H:%M:%S)T COOLDOWN http=429 until=%s msg="%s"\n' -1 "$cooldown_until" "${payload:0:80}" >> "$LOGFILE"
    return 0
  fi

  printf '%(%Y-%m-%d %H:%M:%S)T FAILED after retry msg="%s"\n' -1 "${payload:0:80}" >> "$LOGFILE"
  echo "ERROR: ntfy send failed after retry (HTTP $http_code)" >&2
  return 1
}

if [ "${NTFY_SYNC:-0}" = "1" ]; then
  (
    flock -w 30 200 || { echo "ERROR: ntfy throttle lock timeout" >&2; exit 1; }
    send_with_retry "$MSG"
  ) 200>"$NTFY_LOCK_FILE"
  exit $?
fi

# Default mode: fire-and-forget
(
  flock -w 30 200 || { echo "ERROR: ntfy throttle lock timeout" >&2; exit 1; }
  send_with_retry "$MSG"
) 200>"$NTFY_LOCK_FILE" &
exit 0
