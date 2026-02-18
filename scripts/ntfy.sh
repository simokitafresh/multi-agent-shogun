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

# ntfy_auth.sh読み込み
# shellcheck source=../lib/ntfy_auth.sh
source "$SCRIPT_DIR/lib/ntfy_auth.sh"

TOPIC=$(grep 'ntfy_topic:' "$SETTINGS" | awk '{print $2}' | tr -d '"')
if [ -z "$TOPIC" ]; then
  echo "ntfy_topic not configured in settings.yaml" >&2
  exit 1
fi

# 認証引数を取得（設定がなければ空 = 後方互換）
AUTH_ARGS=()
while IFS= read -r line; do
    [ -n "$line" ] && AUTH_ARGS+=("$line")
done < <(ntfy_get_auth_args "$SCRIPT_DIR/config/ntfy_auth.env")

LOGFILE="$SCRIPT_DIR/logs/ntfy.log"
mkdir -p "$SCRIPT_DIR/logs"

MSG="$1"

# Background send with timeout + retry
(
  _ntfy_send() {
    local http_code start end elapsed
    start=$(date +%s)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time 30 --connect-timeout 15 \
      "${AUTH_ARGS[@]}" -H "Tags: outbound" -d "$1" \
      "https://ntfy.sh/$TOPIC" 2>/dev/null)
    end=$(date +%s)
    elapsed=$((end - start))
    echo "$(date '+%Y-%m-%d %H:%M:%S') http=$http_code time=${elapsed}s msg=\"${1:0:80}\"" >> "$LOGFILE"
    [ "$http_code" = "200" ]
  }

  if _ntfy_send "$MSG"; then
    exit 0
  fi

  # Retry once after 3s
  sleep 3
  if _ntfy_send "$MSG"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') RETRY_OK" >> "$LOGFILE"
    exit 0
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') FAILED after retry msg=\"${MSG:0:80}\"" >> "$LOGFILE"
) &

# Return immediately (caller is not blocked)
exit 0
