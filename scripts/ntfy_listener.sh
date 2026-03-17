#!/bin/bash
# shellcheck disable=SC1091,SC2317
# ═══════════════════════════════════════════════════════════════
# ntfy Input Listener
# Streams messages from ntfy topic, writes to inbox YAML, wakes shogun.
# NOT polling — uses ntfy's streaming endpoint (long-lived HTTP connection).
# FR-066: ntfy認証対応 (Bearer token / Basic auth)
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NTFY_LISTENER_LIB_ONLY="${NTFY_LISTENER_LIB_ONLY:-0}"

# Single-instance guard (flock) — 多重起動による二重記録を防止
if [ "$NTFY_LISTENER_LIB_ONLY" != "1" ]; then
    exec 200>/tmp/ntfy_listener.lock
    flock -n 200 || { echo "[$(date)] ntfy_listener already running, exiting" >&2; exit 0; }
fi

SETTINGS="$SCRIPT_DIR/config/settings.yaml"

# tmux排他制御ライブラリ（将軍pane直接注入用）
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
TOPIC=$(grep 'ntfy_topic:' "$SETTINGS" | awk '{print $2}' | tr -d '"')
INBOX="$SCRIPT_DIR/queue/ntfy_inbox.yaml"

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

STREAM_WATCHDOG_SECS=1800
STREAM_READ_WATCHDOG_SECS=120
CURL_MAX_TIME_SECS=3600
CURL_KEEPALIVE_SECS=30
READ_POLL_SECS=5
ATTACHMENT_DOWNLOAD_MAX_TIME_SECS=30

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

sanitize_attachment_name() {
    python3 -c '
import os
import re
import sys

name = sys.argv[1] if len(sys.argv) > 1 else ""
name = os.path.basename(name)
name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._")
print(name or "attachment.png")
' "$1" 2>/dev/null
}

append_ntfy_inbox() {
    local msg_id="$1"
    local timestamp="$2"
    local message="$3"
    local status="${4:-pending}"
    local lockfile="${INBOX}.lock"
    local py_exit

    py_exit=$(
        (
            flock -w 5 200 || exit 1

            INBOX_PATH="$INBOX" NTFY_MSG_ID="$msg_id" NTFY_TIMESTAMP="$timestamp" \
            NTFY_MESSAGE="$message" NTFY_STATUS="$status" python3 <<'PYEOF'
import os
import sys
import tempfile

import yaml

inbox_path = os.environ["INBOX_PATH"]
msg_id = os.environ.get("NTFY_MSG_ID", "")
timestamp = os.environ["NTFY_TIMESTAMP"]
message = os.environ["NTFY_MESSAGE"]
status = os.environ["NTFY_STATUS"]

try:
    with open(inbox_path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    inbox_entries = data.get("inbox")
    if not isinstance(inbox_entries, list):
        inbox_entries = []
        data["inbox"] = inbox_entries

    if msg_id and any(isinstance(entry, dict) and entry.get("id") == msg_id for entry in inbox_entries):
        print("duplicate")
        raise SystemExit(0)

    inbox_entries.append({
        "id": msg_id,
        "timestamp": timestamp,
        "message": message,
        "status": status,
    })

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
        os.replace(tmp_path, inbox_path)
    except Exception:
        os.unlink(tmp_path)
        raise

    print("written")
except Exception as exc:
    print(f"error:{exc}", file=sys.stderr)
    sys.exit(1)
PYEOF
        ) 200>"$lockfile"
    )

    case "$py_exit" in
        written) return 0 ;;
        duplicate) return 2 ;;
        *)
            [ -n "$py_exit" ] && echo "[$(date)] ERROR: append_ntfy_inbox failed: $py_exit" >&2
            return 1
            ;;
    esac
}

to_repo_relative_path() {
    case "$1" in
        "$SCRIPT_DIR"/*) echo "${1#"$SCRIPT_DIR"/}" ;;
        *) echo "$1" ;;
    esac
}

download_attachment_image() {
    local attachment_url="$1"
    local attachment_name="${2:-}"
    local ts safe_name outfile latest_file

    [ -z "$attachment_url" ] && return 1

    ts=$(date "+%Y%m%d_%H%M%S")
    safe_name=$(sanitize_attachment_name "$attachment_name")
    outfile="$SCREENSHOT_DIR/${ts}_${safe_name}"
    latest_file="$SCREENSHOT_DIR/latest.png"

    if curl -sS --fail --max-time "$ATTACHMENT_DOWNLOAD_MAX_TIME_SECS" \
        "${AUTH_ARGS[@]}" -o "$outfile" "$attachment_url"; then
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

mark_message_activity() {
    LAST_MESSAGE_ACTIVITY=$(date +%s)
}

should_restart_stream() {
    local now_epoch="$1"
    local last_stream_activity="$2"
    local last_message_activity="$3"

    if [ $((now_epoch - last_stream_activity)) -ge "$STREAM_READ_WATCHDOG_SECS" ]; then
        RECONNECT_REASON="Stream read timeout"
        WATCHDOG_LOG_MSG="[$(date)] Watchdog triggered: no stream bytes for ${STREAM_READ_WATCHDOG_SECS}s, restarting curl"
        return 0
    fi

    if [ $((now_epoch - last_message_activity)) -ge "$STREAM_WATCHDOG_SECS" ]; then
        RECONNECT_REASON="Message activity timeout"
        WATCHDOG_LOG_MSG="[$(date)] Watchdog triggered: no inbound messages for ${STREAM_WATCHDOG_SECS}s, restarting curl"
        return 0
    fi

    return 1
}

process_stream_line() {
    local line="$1"

    # Skip keepalive pings and non-message events
    EVENT=$(echo "$line" | parse_json event)
    [ "$EVENT" != "message" ] && return 0

    # Skip outbound messages (sent by our own scripts/ntfy.sh)
    TAGS=$(echo "$line" | parse_tags)
    echo "$TAGS" | grep -q "outbound" && return 0

    # Extract payload (sanitize control characters from external input, preserve Japanese)
    MSG=$(echo "$line" | parse_json message | tr -d '\000-\010\013-\037\177')
    ATTACHMENT_TYPE=$(echo "$line" | parse_attachment_field type)
    ATTACHMENT_URL=$(echo "$line" | parse_attachment_field url)
    ATTACHMENT_NAME=$(echo "$line" | parse_attachment_field name)

    HAS_IMAGE_ATTACHMENT=0
    if [[ "$ATTACHMENT_TYPE" == image/* ]] && [ -n "$ATTACHMENT_URL" ]; then
        HAS_IMAGE_ATTACHMENT=1
    fi

    [ -z "$MSG" ] && [ "$HAS_IMAGE_ATTACHMENT" -eq 0 ] && return 0

    # MSG_ID dedup check — 同一IDが既に記録済みならスキップ（二重起動・再接続対策）
    MSG_ID=$(echo "$line" | parse_json id)
    if [ -n "$MSG_ID" ] && grep -q "id: \"$MSG_ID\"" "$INBOX" 2>/dev/null; then
        echo "[$(date)] Duplicate MSG_ID: $MSG_ID, skipping" >&2
        return 0
    fi

    if [ "$HAS_IMAGE_ATTACHMENT" -eq 1 ]; then
        SAVED_IMAGE=$(download_attachment_image "$ATTACHMENT_URL" "$ATTACHMENT_NAME")
        if [ $? -eq 0 ] && [ -n "$SAVED_IMAGE" ]; then
            SAVED_IMAGE_REL=$(to_repo_relative_path "$SAVED_IMAGE")
            echo "[$(date)] Saved image attachment: $SAVED_IMAGE_REL" >&2
            mark_message_activity
            bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun \
                "スクショ受信: $SAVED_IMAGE (latest: $SCREENSHOT_DIR/latest.png)" \
                screenshot_received ntfy_listener
        fi
    fi

    # Attachment-only message: screenshot通知のみで終了
    [ -z "$MSG" ] && return 0

    # Skip MCAS monitoring alerts (MCAS project archived 2026-02-26)
    case "$MSG" in
        *'【MCAS】'*) echo "[$(date)] Filtered MCAS alert: ${MSG:0:80}" >&2; return 0 ;;
    esac

    TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S%:z")

    echo "[$(date)] Received: $MSG" >&2

    append_ntfy_inbox "$MSG_ID" "$TIMESTAMP" "$MSG" pending
    append_rc=$?
    if [ "$append_rc" -eq 2 ]; then
        echo "[$(date)] Duplicate MSG_ID during atomic append: $MSG_ID, skipping" >&2
        return 0
    fi
    if [ "$append_rc" -ne 0 ]; then
        echo "[$(date)] ERROR: failed to persist ntfy message to $INBOX" >&2
        return 0
    fi
    mark_message_activity

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
}

if [ "$NTFY_LISTENER_LIB_ONLY" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

echo "[$(date)] ntfy listener started — topic: $TOPIC (auth: ${NTFY_TOKEN:+token}${NTFY_USER:+basic}${NTFY_TOKEN:-${NTFY_USER:-none}})" >&2

while true; do
    coproc NTFY_STREAM {
        exec curl -s --no-buffer \
            --keepalive-time "$CURL_KEEPALIVE_SECS" \
            --max-time "$CURL_MAX_TIME_SECS" \
            "${AUTH_ARGS[@]}" \
            "https://ntfy.sh/$TOPIC/json" 2>/dev/null
    }

    STREAM_PID=$NTFY_STREAM_PID
    LAST_STREAM_ACTIVITY=$(date +%s)
    LAST_MESSAGE_ACTIVITY=$LAST_STREAM_ACTIVITY
    RECONNECT_REASON="Connection lost"
    WATCHDOG_LOG_MSG=""

    while true; do
        if IFS= read -r -t "$READ_POLL_SECS" -u "${NTFY_STREAM[0]}" line; then
            LAST_STREAM_ACTIVITY=$(date +%s)
            process_stream_line "$line"
            continue
        fi

        NOW_EPOCH=$(date +%s)
        if should_restart_stream "$NOW_EPOCH" "$LAST_STREAM_ACTIVITY" "$LAST_MESSAGE_ACTIVITY"; then
            echo "$WATCHDOG_LOG_MSG" >&2
            kill "$STREAM_PID" 2>/dev/null || true
            wait "$STREAM_PID" 2>/dev/null || true
            break
        fi

        if ! kill -0 "$STREAM_PID" 2>/dev/null; then
            wait "$STREAM_PID" 2>/dev/null || true
            break
        fi
    done

    echo "[$(date)] $RECONNECT_REASON, reconnecting in 5s..." >&2
    sleep 5
done
