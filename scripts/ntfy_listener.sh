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

# lord_conversation.sh読み込み (cmd_546: 重複ロジック集約)
# shellcheck source=../lib/lord_conversation.sh
source "$SCRIPT_DIR/lib/lord_conversation.sh"

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

SCREENSHOT_PATH=$(awk '
    /^screenshot:[[:space:]]*$/ { in_block=1; next }
    in_block && /^[^[:space:]]/ { in_block=0 }
    in_block && /^[[:space:]]+path:[[:space:]]*/ {
        sub(/^[[:space:]]+path:[[:space:]]*/, "", $0)
        gsub(/"/, "", $0)
        print $0
        exit
    }
' "$SETTINGS")
[ -z "$SCREENSHOT_PATH" ] && SCREENSHOT_PATH="queue/screenshots"

if [[ "$SCREENSHOT_PATH" = /* ]]; then
    SCREENSHOT_DIR="$SCREENSHOT_PATH"
else
    SCREENSHOT_DIR="$SCRIPT_DIR/$SCREENSHOT_PATH"
fi

mkdir -p "$SCREENSHOT_DIR" 2>/dev/null || \
    echo "[$(date)] WARNING: Failed to create screenshot dir: $SCREENSHOT_DIR" >&2

# JSON field extractor (python3 — jq not available)
parse_json() {
    python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

parse_tags() {
    python3 -c "import sys,json; print(','.join(json.load(sys.stdin).get('tags',[])))" 2>/dev/null
}

parse_attachment_field() {
    python3 -c "import sys,json; k=sys.argv[1]; a=json.load(sys.stdin).get('attachment') or {}; print(a.get(k,'') if isinstance(a,dict) else '')" "$1" 2>/dev/null
}

to_repo_relative_path() {
    case "$1" in
        "$SCRIPT_DIR"/*) echo "${1#"$SCRIPT_DIR"/}" ;;
        *) echo "$1" ;;
    esac
}

download_attachment_image() {
    local attachment_url="$1"
    local ts outfile latest_file

    [ -z "$attachment_url" ] && return 1

    ts=$(date "+%Y%m%d_%H%M%S")
    outfile="$SCREENSHOT_DIR/ntfy_${ts}.png"
    latest_file="$SCREENSHOT_DIR/latest.png"

    if curl -sS --fail "${AUTH_ARGS[@]}" -o "$outfile" "$attachment_url"; then
        if ! cp "$outfile" "$latest_file" 2>/dev/null; then
            echo "[$(date)] WARNING: saved image but failed to update latest.png" >&2
        fi
        echo "$outfile"
        return 0
    fi

    rm -f "$outfile"
    echo "[$(date)] ERROR: failed to download ntfy attachment from $attachment_url" >&2
    return 1
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

        # Extract payload
        MSG=$(echo "$line" | parse_json message)
        ATTACHMENT_TYPE=$(echo "$line" | parse_attachment_field type)
        ATTACHMENT_URL=$(echo "$line" | parse_attachment_field url)

        HAS_IMAGE_ATTACHMENT=0
        if [[ "$ATTACHMENT_TYPE" == image/* ]] && [ -n "$ATTACHMENT_URL" ]; then
            HAS_IMAGE_ATTACHMENT=1
        fi

        [ -z "$MSG" ] && [ "$HAS_IMAGE_ATTACHMENT" -eq 0 ] && continue

        if [ "$HAS_IMAGE_ATTACHMENT" -eq 1 ]; then
            SAVED_IMAGE=$(download_attachment_image "$ATTACHMENT_URL")
            if [ $? -eq 0 ] && [ -n "$SAVED_IMAGE" ]; then
                SAVED_IMAGE_REL=$(to_repo_relative_path "$SAVED_IMAGE")
                echo "[$(date)] Saved image attachment: $SAVED_IMAGE_REL" >&2
                bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun \
                    "スクショ受信: $SAVED_IMAGE (latest: $SCREENSHOT_DIR/latest.png)" \
                    screenshot_received ntfy_listener
            fi
        fi

        # Attachment-only message: screenshot通知のみで終了
        [ -z "$MSG" ] && continue

        # Skip MCAS monitoring alerts (MCAS project archived 2026-02-26)
        case "$MSG" in
            *'【MCAS】'*) echo "[$(date)] Filtered MCAS alert: ${MSG:0:80}" >&2; continue ;;
        esac

        append_lord_conversation "$MSG" "inbound" || true

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
