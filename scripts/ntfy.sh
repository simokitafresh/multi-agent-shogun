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
  echo "WARNING: ntfy called by non-authorized agent: ${AGENT_ID}" >&2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"
LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.jsonl"
# shellcheck disable=SC2034  # Used by lord_conversation.sh
LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

# ntfy_auth.sh読み込み
# shellcheck source=../lib/ntfy_auth.sh
source "$SCRIPT_DIR/lib/ntfy_auth.sh"

# lord_conversation.sh読み込み (cmd_546: 重複ロジック集約)
# shellcheck source=../lib/lord_conversation.sh
source "$SCRIPT_DIR/lib/lord_conversation.sh"

TOPIC=$(grep 'ntfy_topic:' "$SETTINGS" | awk '{print $2}' | tr -d '"')
if [ -z "$TOPIC" ]; then
  echo "ntfy_topic not configured in settings.yaml" >&2
  exit 1
fi

# Validate topic name security (warn-only; do not block send)
ntfy_validate_topic "$TOPIC" || true

# 認証引数を取得（設定がなければ空 = 後方互換）
AUTH_ARGS=()
while IFS= read -r line; do
    [ -n "$line" ] && AUTH_ARGS+=("$line")
done < <(ntfy_get_auth_args "$SCRIPT_DIR/config/ntfy_auth.env")

LOGFILE="$SCRIPT_DIR/logs/ntfy.log"
mkdir -p "$SCRIPT_DIR/logs"

MSG="$1"

NTFY_ENDPOINT="${NTFY_ENDPOINT:-https://ntfy.sh/$TOPIC}"

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

send_with_retry() {
  local payload="$1"
  local http_code

  http_code=$(_ntfy_send "$payload")
  if [ "$http_code" = "200" ]; then
    append_lord_conversation "$payload" "outbound" "${AGENT_ID:-unknown}" "ntfy" || true
    return 0
  fi

  # Retry only on connection failure (000 = no response from server).
  # HTTP 500 etc. means the server received the request — message likely
  # already delivered. Retrying would cause duplicate notifications.
  if [ "$http_code" != "000" ]; then
    printf '%(%Y-%m-%d %H:%M:%S)T NO_RETRY http=%s (server responded)\n' -1 "$http_code" >> "$LOGFILE"
    return 1
  fi

  sleep 3
  http_code=$(_ntfy_send "$payload")
  if [ "$http_code" = "200" ]; then
    append_lord_conversation "$payload" "outbound" "${AGENT_ID:-unknown}" "ntfy" || true
    printf '%(%Y-%m-%d %H:%M:%S)T RETRY_OK\n' -1 >> "$LOGFILE"
    return 0
  fi

  printf '%(%Y-%m-%d %H:%M:%S)T FAILED after retry msg="%s"\n' -1 "${payload:0:80}" >> "$LOGFILE"
  return 1
}

if [ "${NTFY_SYNC:-0}" = "1" ]; then
  # Optional sync mode for callers that need delivery observability.
  send_with_retry "$MSG"
  exit $?
fi

# Default mode: fire-and-forget
( send_with_retry "$MSG" ) &
exit 0
