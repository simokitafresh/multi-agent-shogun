#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# inbox_watcher.sh — メールボックス監視＆起動シグナル配信
# Usage: bash scripts/inbox_watcher.sh <agent_id> <pane_target>
# Example: bash scripts/inbox_watcher.sh karo shogun:0.0
# Note: 第3引数(cli_type)は後方互換で受け付けるが無視。cli_lookup.shで動的取得。
#
# 設計思想:
#   メッセージ本体はファイル（inbox YAML）に書く = 確実
#   send-keys は短い起動シグナルのみ = ハング防止
#   エージェントが自分でinboxをReadして処理する
#   冪等: 2回届いてもunreadがなければ何もしない
#
# inotifywait でファイル変更を検知（イベント駆動、ポーリングではない）
# Fallback 1: 60秒タイムアウト（WSL2 inotify不発時の安全網）
# Fallback 2: rc=1処理（Claude Code atomic write = tmp+rename でinode変更時）
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# cli_lookup.sh を source（CLI種別をsettings.yaml+cli_profiles.yamlから動的取得）
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"

AGENT_ID="$1"
PANE_TARGET="$2"
# 第3引数は後方互換で受け付けるが無視（shutsujin_departure.shが渡す）
CLI_TYPE=$(cli_type "$AGENT_ID")  # settings.yaml → cli_profiles.yaml の2段参照

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
LOCKFILE="${INBOX}.lock"
SEND_KEYS_TIMEOUT=5  # seconds — prevents hang (PID 274337 incident)
DEBOUNCE_SEC=10
DEBOUNCE_FILE="/tmp/inbox_watcher_last_nudge_${AGENT_ID}"

# Self-restart on script change (cmd_100)
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_HASH="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
STARTUP_TIME="$(date +%s)"
MIN_UPTIME=10  # minimum seconds before allowing auto-restart

if [ -z "$AGENT_ID" ] || [ -z "$PANE_TARGET" ]; then
    echo "Usage: inbox_watcher.sh <agent_id> <pane_target>" >&2
    exit 1
fi

# Initialize inbox if not exists
if [ ! -f "$INBOX" ]; then
    mkdir -p "$(dirname "$INBOX")"
    echo "messages: []" > "$INBOX"
fi

echo "[$(date)] inbox_watcher started — agent: $AGENT_ID, pane: $PANE_TARGET, cli: $CLI_TYPE, script_hash: $SCRIPT_HASH" >&2

# Ensure inotifywait is available
if ! command -v inotifywait &>/dev/null; then
    echo "[inbox_watcher] ERROR: inotifywait not found. Install: sudo apt install inotify-tools" >&2
    exit 1
fi

# ─── Extract unread message info (lock-free read) ───
# Returns JSON lines: {"count": N, "has_special": true/false, "specials": [...]}
get_unread_info() {
    python3 -c "
import yaml, sys, json
try:
    with open('$INBOX') as f:
        data = yaml.safe_load(f)
    if not data or 'messages' not in data or not data['messages']:
        print(json.dumps({'count': 0, 'specials': []}))
        sys.exit(0)
    unread = [m for m in data['messages'] if not m.get('read', False)]
    # Special types that need direct send-keys (CLI commands, not conversation)
    special_types = ('clear_command', 'model_switch')
    specials = [m for m in unread if m.get('type') in special_types]
    # Mark specials as read immediately (they'll be delivered directly)
    if specials:
        for m in data['messages']:
            if not m.get('read', False) and m.get('type') in special_types:
                m['read'] = True
        with open('$INBOX', 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
    normal_count = len(unread) - len(specials)
    print(json.dumps({
        'count': normal_count,
        'specials': [{'type': m.get('type',''), 'content': m.get('content','')} for m in specials]
    }))
except Exception as e:
    print(json.dumps({'count': 0, 'specials': []}), file=sys.stderr)
    print(json.dumps({'count': 0, 'specials': []}))
" 2>/dev/null
}

# ─── Send CLI command directly via send-keys ───
# For /clear and /model only. These are CLI commands, not conversation messages.
# CLI種別はcli_profiles.yamlのフィールドで動的に判定（name-based分岐なし）
send_cli_command() {
    local cmd="$1"
    local actual_cmd="$cmd"
    local post_wait=1

    # /clear: cli_profiles.yamlのclear_method/clear_cmdで動的解決
    if [[ "$cmd" == "/clear" ]]; then
        local clear_method
        clear_method=$(cli_profile_get "$AGENT_ID" "clear_method")
        clear_method="${clear_method:-command}"

        if [[ "$clear_method" == "restart" ]]; then
            # Ctrl-C + launch_cmdで再起動（例: copilot）
            local launch
            launch=$(cli_launch_cmd "$AGENT_ID")
            echo "[$(date)] CLI restart for $AGENT_ID ($CLI_TYPE): Ctrl-C + $launch" >&2
            timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" C-c 2>/dev/null || true
            sleep 2
            timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" "$launch" 2>/dev/null || true
            sleep 0.3
            timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null || true
            sleep 3
            return 0
        fi

        # clear_method == "command": clear_cmdを送信（claude=/clear, codex=/new）
        actual_cmd=$(cli_profile_get "$AGENT_ID" "clear_cmd")
        actual_cmd="${actual_cmd:-/clear}"
        post_wait=3
    fi

    # /model: supports_model_switchで動的判定
    if [[ "$cmd" == /model* ]]; then
        local supports_model
        supports_model=$(cli_profile_get "$AGENT_ID" "supports_model_switch")
        if [[ "$supports_model" != "true" ]]; then
            echo "[$(date)] Skipping $cmd (not supported on $CLI_TYPE)" >&2
            return 0
        fi
    fi

    echo "[$(date)] Sending CLI command to $AGENT_ID ($CLI_TYPE): $actual_cmd" >&2

    if ! timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" "$actual_cmd" 2>/dev/null; then
        echo "[$(date)] WARNING: send-keys timed out for CLI command" >&2
        return 1
    fi
    sleep 0.3
    if ! timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null; then
        echo "[$(date)] WARNING: send-keys Enter timed out for CLI command" >&2
        return 1
    fi

    sleep "$post_wait"
}

# ─── Agent self-watch detection ───
# Check if the agent has an active inotifywait on its inbox.
# If yes, the agent will self-wake — no nudge needed.
agent_has_self_watch() {
    pgrep -f "inotifywait.*inbox/${AGENT_ID}.yaml" >/dev/null 2>&1
}

# ─── Send wake-up nudge ───
# Layered approach (send-keys撲滅):
#   1. If agent has active inotifywait self-watch → skip (agent wakes itself)
#   2. Fallback: paste-buffer + Enter (avoids send-keys for content)
# timeout prevents the 1.5-hour hang incident from recurring.
send_wakeup() {
    local unread_count="$1"
    local nudge="inbox${unread_count}"
    local now
    local last
    local elapsed

    # Tier 1: Agent self-watch — skip nudge entirely
    if agent_has_self_watch; then
        echo "[$(date)] [SKIP] Agent $AGENT_ID has active self-watch, no nudge needed" >&2
        return 0
    fi

    # Tier 1.5: Debounce repeated nudge storms (normal messages only)
    if [ -f "$DEBOUNCE_FILE" ]; then
        last="$(cat "$DEBOUNCE_FILE" 2>/dev/null || true)"
        if [[ "$last" =~ ^[0-9]+$ ]]; then
            now="$(date +%s)"
            elapsed=$((now - last))
            if [ "$elapsed" -lt "$DEBOUNCE_SEC" ]; then
                echo "[$(date)] [DEBOUNCE] Skipping nudge (${elapsed}s < ${DEBOUNCE_SEC}s) for $AGENT_ID" >&2
                return 0
            fi
        fi
    fi

    # Tier 2: paste-buffer nudge (replaces send-keys for content)
    echo "[$(date)] [NUDGE] Sending paste-buffer nudge to $AGENT_ID" >&2

    # Optimistic lock: update debounce BEFORE send to prevent concurrent nudges
    if ! date +%s > "$DEBOUNCE_FILE"; then
        echo "[$(date)] WARNING: failed to update debounce file: $DEBOUNCE_FILE" >&2
    fi

    # Pre-clear: Enter to flush any partial input in the pane
    timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null || true
    sleep 0.3

    # Send nudge via paste-buffer
    tmux set-buffer -b "nudge_${AGENT_ID}" "$nudge"
    if ! timeout "$SEND_KEYS_TIMEOUT" tmux paste-buffer -t "$PANE_TARGET" -b "nudge_${AGENT_ID}" -d 2>/dev/null; then
        echo "[$(date)] WARNING: paste-buffer timed out ($SEND_KEYS_TIMEOUT s)" >&2
        rm -f "$DEBOUNCE_FILE"  # Rollback optimistic lock on failure
        return 1
    fi
    sleep 0.5
    if ! timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null; then
        echo "[$(date)] WARNING: send-keys Enter timed out ($SEND_KEYS_TIMEOUT s)" >&2
        rm -f "$DEBOUNCE_FILE"  # Rollback optimistic lock on failure
        return 1
    fi

    echo "[$(date)] Wake-up sent to $AGENT_ID (${unread_count} unread via paste-buffer)" >&2
    return 0
}

# ─── Self-restart on script change (cmd_100) ───
check_script_update() {
    local current_hash
    current_hash="$(md5sum "$SCRIPT_PATH" | cut -d' ' -f1)"
    if [ "$current_hash" != "$SCRIPT_HASH" ]; then
        local uptime=$(($(date +%s) - STARTUP_TIME))
        if [ "$uptime" -lt "$MIN_UPTIME" ]; then
            echo "[$(date)] [RESTART-GUARD] Script changed but uptime too short (${uptime}s < ${MIN_UPTIME}s), skipping" >&2
            return 0
        fi
        echo "[$(date)] [AUTO-RESTART] Script file changed (hash: $SCRIPT_HASH → $current_hash), restarting..." >&2
        exec "$SCRIPT_PATH" "$AGENT_ID" "$PANE_TARGET"
    fi
}

# ─── Process cycle ───
process_unread() {
    local info
    info=$(get_unread_info)

    # Handle special CLI commands first (/clear, /model)
    local specials
    specials=$(echo "$info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('specials', []):
    if s['type'] == 'clear_command':
        print('/clear')
        print(s['content'])  # post-clear instruction
    elif s['type'] == 'model_switch':
        print(s['content'])  # /model command
" 2>/dev/null)

    if [ -n "$specials" ]; then
        echo "$specials" | while IFS= read -r cmd; do
            [ -n "$cmd" ] && send_cli_command "$cmd"
        done
    fi

    # Send wake-up nudge for normal messages
    local normal_count
    normal_count=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null)

    if [ "$normal_count" -gt 0 ] 2>/dev/null; then
        echo "[$(date)] $normal_count normal unread message(s) for $AGENT_ID" >&2
        send_wakeup "$normal_count"
    fi
}

# ─── Startup: process any existing unread messages ───
process_unread

# ─── Main loop: event-driven via inotifywait ───
# Timeout 60s: WSL2 /mnt/c/ can miss inotify events.
# On timeout (exit 2), check for unread messages as a safety net.
INOTIFY_TIMEOUT=60

while true; do
    # Block until file is modified OR timeout (safety net for WSL2)
    # set +e: inotifywait returns 2 on timeout, which would kill script under set -e
    set +e
    inotifywait -q -t "$INOTIFY_TIMEOUT" -e modify -e close_write "$INBOX" 2>/dev/null
    rc=$?
    set -e

    # rc=0: event fired (instant delivery)
    # rc=1: watch invalidated — Claude Code uses atomic write (tmp+rename),
    #        which replaces the inode. inotifywait sees DELETE_SELF → rc=1.
    #        File still exists with new inode. Treat as event, re-watch next loop.
    # rc=2: timeout (60s safety net for WSL2 inotify gaps)
    # All cases: check for unread, then loop back to inotifywait (re-watches new inode)
    sleep 0.3

    process_unread
    check_script_update
done
