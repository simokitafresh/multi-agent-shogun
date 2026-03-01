#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# ntfy Input Listener
# Streams messages from ntfy topic, writes to inbox YAML, wakes shogun.
# NOT polling — uses ntfy's streaming endpoint (long-lived HTTP connection).
# FR-066: ntfy認証対応 (Bearer token / Basic auth)
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="$SCRIPT_DIR/config/settings.yaml"

# tmux排他制御ライブラリ（将軍pane直接注入用）
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
TOPIC=$(grep 'ntfy_topic:' "$SETTINGS" | awk '{print $2}' | tr -d '"')
INBOX="$SCRIPT_DIR/queue/ntfy_inbox.yaml"
LORD_CONVERSATION="$SCRIPT_DIR/queue/lord_conversation.yaml"
LORD_CONVERSATION_LOCK="${LORD_CONVERSATION}.lock"

# ntfy_auth.sh読み込み
# shellcheck source=../lib/ntfy_auth.sh
source "$SCRIPT_DIR/lib/ntfy_auth.sh"

if [ -z "$TOPIC" ]; then
    echo "[ntfy_listener] ntfy_topic not configured in settings.yaml" >&2
    exit 1
fi

# トピック名セキュリティ検証
ntfy_validate_topic "$TOPIC" || true

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    echo "inbox:" > "$INBOX"
fi

# 認証引数を取得（設定がなければ空 = 後方互換）
AUTH_ARGS=()
while IFS= read -r line; do
    [ -n "$line" ] && AUTH_ARGS+=("$line")
done < <(ntfy_get_auth_args "$SCRIPT_DIR/config/ntfy_auth.env")

# JSON field extractor (python3 — jq not available)
parse_json() {
    python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

parse_tags() {
    python3 -c "import sys,json; print(','.join(json.load(sys.stdin).get('tags',[])))" 2>/dev/null
}

append_lord_conversation_inbound() {
    local message="$1"
    local timestamp
    timestamp="$(date "+%Y-%m-%dT%H:%M:%S%:z")"

    if [ ! -f "$LORD_CONVERSATION" ]; then
        mkdir -p "$(dirname "$LORD_CONVERSATION")"
        echo "entries: []" > "$LORD_CONVERSATION"
    fi

    if ! (
        flock -w 5 200 || exit 1
        CONV_PATH="$LORD_CONVERSATION" CONV_TIMESTAMP="$timestamp" \
        CONV_MESSAGE="$message" \
        python3 - <<'PY'
import os
import tempfile

import yaml

path = os.environ["CONV_PATH"]
timestamp = os.environ["CONV_TIMESTAMP"]
message = os.environ["CONV_MESSAGE"]

try:
    with open(path) as f:
        data = yaml.safe_load(f)
except FileNotFoundError:
    data = {}

if not isinstance(data, dict):
    data = {}

entries = data.get("entries")
if not isinstance(entries, list):
    entries = []

entries.append({
    "timestamp": timestamp,
    "direction": "inbound",
    "channel": "ntfy",
    "message": message,
})
data["entries"] = entries

tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
    os.replace(tmp_path, path)
except Exception:
    os.unlink(tmp_path)
    raise
PY
    ) 200>"$LORD_CONVERSATION_LOCK"; then
        echo "[$(date)] WARNING: Failed to append inbound log to lord_conversation.yaml" >&2
        return 1
    fi
}

echo "[$(date)] ntfy listener started — topic: $TOPIC (auth: ${NTFY_TOKEN:+token}${NTFY_USER:+basic}${NTFY_TOKEN:-${NTFY_USER:-none}})" >&2

while true; do
    # Stream new messages (long-lived connection, blocks until message arrives)
    curl -s --no-buffer "${AUTH_ARGS[@]}" "https://ntfy.sh/$TOPIC/json" 2>/dev/null | while IFS= read -r line; do
        # Skip keepalive pings and non-message events
        EVENT=$(echo "$line" | parse_json event)
        [ "$EVENT" != "message" ] && continue

        # Skip outbound messages (sent by our own scripts/ntfy.sh)
        TAGS=$(echo "$line" | parse_tags)
        echo "$TAGS" | grep -q "outbound" && continue

        # Extract message content
        MSG=$(echo "$line" | parse_json message)
        [ -z "$MSG" ] && continue

        # Skip MCAS monitoring alerts (MCAS project archived 2026-02-26)
        case "$MSG" in
            *'【MCAS】'*) echo "[$(date)] Filtered MCAS alert: ${MSG:0:80}" >&2; continue ;;
        esac

        append_lord_conversation_inbound "$MSG" || true

        MSG_ID=$(echo "$line" | parse_json id)
        TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S%:z")

        echo "[$(date)] Received: $MSG" >&2

        # Append to inbox YAML (0-space indent for list items, 2-space for properties)
        cat >> "$INBOX" << ENTRY
- id: "$MSG_ID"
  timestamp: "$TIMESTAMP"
  message: "$MSG"
  status: pending
ENTRY

        # === Primary path: Direct injection to shogun pane ===
        SHOGUN_PANE=$(tmux display-message -t shogun:main -p '#{pane_id}' 2>/dev/null || echo "")
        # Safety: verify the resolved pane is actually the shogun
        if [ -n "$SHOGUN_PANE" ]; then
            RESOLVED_AGENT=$(tmux display-message -t "$SHOGUN_PANE" -p '#{@agent_id}' 2>/dev/null || echo "")
            if [ "$RESOLVED_AGENT" != "shogun" ]; then
                echo "[$(date)] CRITICAL: SHOGUN_PANE resolved to non-shogun agent ($RESOLVED_AGENT), aborting injection" >&2
                SHOGUN_PANE=""
            fi
        fi
        if [ -n "$SHOGUN_PANE" ]; then
            # Truncate at 200 chars
            if [ ${#MSG} -gt 200 ]; then
                INJECT_MSG="【殿ntfy】${MSG:0:200}...（全文: ntfy_inbox.yaml）"
            else
                INJECT_MSG="【殿ntfy】${MSG}"
            fi

            # paste-buffer + Enter (flock排他, timeout付き)
            LOCK="/tmp/tmux_sendkeys_$(echo "$SHOGUN_PANE" | tr ':.' '_').lock"
            (
                flock -w 5 200 || { echo "[$(date)] LOCK TIMEOUT: ntfy inject to shogun" >&2; exit 1; }
                tmux set-buffer -b "ntfy_inject" "$INJECT_MSG" 2>/dev/null || exit 1
                if ! timeout 5 tmux paste-buffer -t "$SHOGUN_PANE" -b "ntfy_inject" -d 2>/dev/null; then
                    echo "[$(date)] WARNING: paste-buffer to shogun timed out" >&2
                    tmux delete-buffer -b "ntfy_inject" 2>/dev/null || true
                    exit 1
                fi
                sleep 0.5
                if ! timeout 5 tmux send-keys -t "$SHOGUN_PANE" Enter 2>/dev/null; then
                    echo "[$(date)] WARNING: send-keys Enter to shogun timed out" >&2
                    exit 1
                fi
            ) 200>"$LOCK"

            if [ $? -eq 0 ]; then
                echo "[$(date)] Injected to shogun pane: ${INJECT_MSG:0:80}..." >&2
            else
                echo "[$(date)] WARNING: Failed to inject to shogun pane, falling back to inbox only" >&2
            fi
        else
            echo "[$(date)] WARNING: Shogun pane not found (shogun:main), inbox only" >&2
        fi

        # === Backup path: Wake shogun via inbox ===
        bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun \
            "ntfyから新しいメッセージ受信。queue/ntfy_inbox.yaml を確認し処理せよ。" \
            ntfy_received ntfy_listener
    done

    # Connection dropped — reconnect after brief pause
    echo "[$(date)] Connection lost, reconnecting in 5s..." >&2
    sleep 5
done
