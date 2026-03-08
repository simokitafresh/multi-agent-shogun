#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# inbox_watcher.sh — メールボックス監視＆起動シグナル配信
# Usage: bash scripts/inbox_watcher.sh <agent_id> <pane_target>
# Example: bash scripts/inbox_watcher.sh karo shogun:2.1
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
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"

AGENT_ID="$1"
PANE_TARGET="$2"
# 第3引数は後方互換で受け付けるが無視（shutsujin_departure.shが渡す）
CLI_TYPE_AT_STARTUP=$(cli_type "$AGENT_ID")  # settings.yaml → cli_profiles.yaml の2段参照

STATE_DIR="${SHOGUN_STATE_DIR:-${IDLE_FLAG_DIR:-/tmp}}"
IDLE_FLAG_DIR="$STATE_DIR"
mkdir -p "$STATE_DIR"

INBOX="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
LOCKFILE="${INBOX}.lock"
SEND_KEYS_TIMEOUT=5  # seconds — prevents hang (PID 274337 incident)
# ASW_PROCESS_TIMEOUT=0: disable timeout on tmux commands to shogun pane
if [ "${ASW_PROCESS_TIMEOUT:-}" = "0" ]; then
    SEND_KEYS_TIMEOUT=0  # timeout 0 = no limit
fi
DEBOUNCE_SEC=10
DEBOUNCE_FILE="${STATE_DIR}/inbox_watcher_last_nudge_${AGENT_ID}"
FINGERPRINT_FILE="${STATE_DIR}/inbox_watcher_fingerprint_${AGENT_ID}"
RETRY_MAX=3      # immediate retries before falling back to BACKOFF interval
RETRY_COUNT_FILE="${STATE_DIR}/inbox_watcher_retry_${AGENT_ID}"
BACKOFF_SEC="${BACKOFF_SEC:-120}"  # 2 minutes — safety net re-notification for stale unread (was 600)
STATE_LOCK_FILE="${STATE_DIR}/inbox_watcher_state_${AGENT_ID}.lock"
FIRST_UNREAD_SEEN="${FIRST_UNREAD_SEEN:-${STATE_DIR}/first_unread_seen_${AGENT_ID}}"
FORCE_IDLE_AFTER_SEC="${FORCE_IDLE_AFTER_SEC:-15}"

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

echo "[$(date)] inbox_watcher started — agent: $AGENT_ID, pane: $PANE_TARGET, cli: $CLI_TYPE_AT_STARTUP, script_hash: $SCRIPT_HASH" >&2

# Ensure inotifywait is available
if ! command -v inotifywait &>/dev/null; then
    echo "[inbox_watcher] ERROR: inotifywait not found. Install: sudo apt install inotify-tools" >&2
    exit 1
fi

# ─── Extract unread message info (lock-free read) ───
# Returns JSON lines: {"count": N, "has_special": true/false, "specials": [...]}
get_unread_info() {
    # Phase 1: Lock-free read to check for unread messages
    local info
    info=$(python3 -c "
import yaml, sys, json
try:
    with open('$INBOX') as f:
        data = yaml.safe_load(f)
    if not data or 'messages' not in data or not data['messages']:
        print(json.dumps({'count': 0, 'specials': [], 'has_specials': False}))
        sys.exit(0)
    unread = [m for m in data['messages'] if not m.get('read', False)]
    special_types = ('clear_command', 'model_switch')
    specials = [m for m in unread if m.get('type') in special_types]
    normal = [m for m in unread if m.get('type') not in special_types]
    normal_ids = sorted([m.get('id', '') for m in normal])
    print(json.dumps({
        'count': len(normal),
        'normal_ids': normal_ids,
        'specials': [{'id': m.get('id',''), 'type': m.get('type',''), 'content': m.get('content','')} for m in specials],
        'has_specials': len(specials) > 0
    }))
except Exception as e:
    print(json.dumps({'count': 0, 'specials': [], 'has_specials': False}))
" 2>/dev/null)

    echo "$info"
}

# ─── Mark one special message as read (flock + atomic write) ───
# Called AFTER send_cli_command succeeds, to prevent message loss on send failure.
mark_special_read() {
    local message_id="$1"
    [ -n "$message_id" ] || return 1

    (
        flock -w 5 200 || { echo "[mark_special_read] WARN: flock timeout" >&2; exit 1; }

        MESSAGE_ID="$message_id" python3 -c "
import yaml, sys, os, tempfile
try:
    with open('$INBOX') as f:
        data = yaml.safe_load(f)
    if not data or 'messages' not in data:
        sys.exit(0)
    target_id = os.environ['MESSAGE_ID']
    changed = False
    for m in data['messages']:
        if not m.get('read', False) and str(m.get('id', '')) == target_id:
            m['read'] = True
            changed = True
            break
    if changed:
        tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname('$INBOX'), suffix='.tmp')
        try:
            with os.fdopen(tmp_fd, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
            os.replace(tmp_path, '$INBOX')
        except:
            os.unlink(tmp_path)
            raise
except Exception as e:
    print(f'[mark_specials_read] error: {e}', file=sys.stderr)
" 2>/dev/null

    ) 200>"$LOCKFILE"
}

write_state_file() {
    local file_path="$1"
    local value="$2"
    local label="${3:-state}"
    (
        flock -w 5 200 || { echo "[$(date)] WARN: ${label} flock timeout: $file_path" >&2; exit 1; }
        printf '%s' "$value" > "$file_path"
    ) 200>"$STATE_LOCK_FILE"
}

touch_state_file() {
    local file_path="$1"
    local label="${2:-state}"
    (
        flock -w 5 200 || { echo "[$(date)] WARN: ${label} flock timeout: $file_path" >&2; exit 1; }
        touch "$file_path"
    ) 200>"$STATE_LOCK_FILE"
}

refresh_debounce_file() {
    if ! date +%s > "$DEBOUNCE_FILE"; then
        echo "[$(date)] WARNING: failed to refresh debounce file: $DEBOUNCE_FILE" >&2
        return 1
    fi
}

get_first_unread_age() {
    if [ -f "$FIRST_UNREAD_SEEN" ]; then
        local first_seen
        first_seen=$(cat "$FIRST_UNREAD_SEEN" 2>/dev/null || echo "")
        if [[ "$first_seen" =~ ^[0-9]+$ ]]; then
            echo $(( $(date +%s) - first_seen ))
            return
        fi
    fi
    echo 0
}

mark_first_unread_seen() {
    if [ ! -f "$FIRST_UNREAD_SEEN" ]; then
        write_state_file "$FIRST_UNREAD_SEEN" "$(date +%s)" "first_unread_seen" || true
    fi
}

clear_first_unread_seen() {
    rm -f "$FIRST_UNREAD_SEEN"
}

maybe_force_idle_flag() {
    local effective_cli="$1"
    [ "$effective_cli" = "claude" ] || return 1

    local idle_flag="${IDLE_FLAG_DIR}/shogun_idle_${AGENT_ID}"
    [ -f "$idle_flag" ] && return 1

    local unread_age
    unread_age=$(get_first_unread_age)
    if [ "$unread_age" -lt "$FORCE_IDLE_AFTER_SEC" ]; then
        return 1
    fi

    echo "[$(date)] [RECOVERY] forcing idle flag for $AGENT_ID after ${unread_age}s unread" >&2
    touch "$idle_flag"
    return 0
}

# ─── Fingerprint age helper ───
get_fp_age() {
    if [ -f "$FINGERPRINT_FILE" ]; then
        local fp_mtime
        fp_mtime=$(stat -c %Y "$FINGERPRINT_FILE" 2>/dev/null || echo 0)
        if [[ "$fp_mtime" =~ ^[0-9]+$ ]] && [ "$fp_mtime" -gt 0 ]; then
            echo $(( $(date +%s) - fp_mtime ))
            return
        fi
    fi
    echo 0
}

# ─── Resolve effective CLI type ───
# Prefer pane @agent_cli (runtime truth) and fall back to settings.yaml.
# If unresolved, choose codex-safe path.
get_effective_cli_type() {
    local pane_cli
    pane_cli=$(tmux show-options -p -t "$PANE_TARGET" -v @agent_cli 2>/dev/null | tr -d '\r' | head -n1 | tr -d '[:space:]')
    case "$pane_cli" in
        claude|codex|copilot|kimi) echo "$pane_cli"; return 0 ;;
    esac

    local cfg_cli
    cfg_cli=$(cli_type "$AGENT_ID")
    case "$cfg_cli" in
        claude|codex|copilot|kimi) echo "$cfg_cli"; return 0 ;;
    esac

    echo "codex"
}

# ─── Send CLI command directly via send-keys ───
# For /clear and /model only. These are CLI commands, not conversation messages.
# CLI種別はcli_profiles.yamlのフィールドで動的に判定（name-based分岐なし）
send_cli_command() {
    local cmd="$1"
    if [ "${ASW_DISABLE_ESCALATION:-0}" = "1" ]; then
        echo "[$(date)] [SKIP] Escalation disabled for $AGENT_ID (cli_command: $cmd)" >&2
        return 0
    fi
    local actual_cmd="$cmd"
    local post_wait=1
    local effective_cli
    effective_cli=$(get_effective_cli_type)

    # /clear: cli_profiles.yamlのclear_method/clear_cmdで動的解決
    if [[ "$cmd" == "/clear" ]]; then
        local clear_method
        clear_method=$(cli_profile_get "$AGENT_ID" "clear_method")
        clear_method="${clear_method:-command}"

        if [[ "$clear_method" == "restart" ]]; then
            # Ctrl-C + launch_cmdで再起動（例: copilot）
            local launch
            launch=$(cli_launch_cmd "$AGENT_ID")
            echo "[$(date)] CLI restart for $AGENT_ID ($effective_cli): Ctrl-C + $launch" >&2
            safe_send_keys "$PANE_TARGET" C-c 2>/dev/null || true
            sleep 2
            safe_send_keys_atomic "$PANE_TARGET" "$launch" 0.3
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
            echo "[$(date)] Skipping $cmd (not supported on $effective_cli)" >&2
            return 0
        fi
    fi

    echo "[$(date)] Sending CLI command to $AGENT_ID ($effective_cli): $actual_cmd" >&2

    if ! safe_send_keys_atomic "$PANE_TARGET" "$actual_cmd" 0.3; then
        echo "[$(date)] WARNING: safe_send_keys_atomic failed for CLI command" >&2
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
    if [ "${ASW_DISABLE_ESCALATION:-0}" = "1" ]; then
        echo "[$(date)] [SKIP] Escalation disabled for $AGENT_ID (nudge: inbox${unread_count})" >&2
        return 0
    fi
    local nudge="inbox${unread_count}"
    local now
    local last
    local elapsed
    local effective_cli
    effective_cli=$(get_effective_cli_type)

    # Tier 1: Agent self-watch — skip nudge entirely
    if agent_has_self_watch; then
        echo "[$(date)] [SKIP] Agent $AGENT_ID has active self-watch, no nudge needed" >&2
        return 0
    fi

    # Tier 1.3: Agent busy check
    # Claude: idle flag managed by Stop hook (exists=idle, absent=busy)
    # Codex/other: fallback to @agent_state for compatibility
    local idle_flag="${IDLE_FLAG_DIR}/shogun_idle_${AGENT_ID}"
    if [[ "$effective_cli" == "claude" ]] && [ ! -f "$idle_flag" ] && ! maybe_force_idle_flag "$effective_cli"; then
        echo "[$(date)] [BUSY] Agent $AGENT_ID is busy (no idle flag), Stop hook will deliver" >&2
        return 2
    fi

    if [[ "$effective_cli" != "claude" ]]; then
        local agent_state
        agent_state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || echo "unknown")
        if [ "$agent_state" = "active" ]; then
            local fp_age
            fp_age=$(get_fp_age)
            local busy_max_defer
            busy_max_defer=$(cli_profile_get "$AGENT_ID" "inbox_busy_max_defer_sec")
            [[ "$busy_max_defer" =~ ^[0-9]+$ ]] || busy_max_defer=30
            local busy_rc
            if check_agent_busy "$PANE_TARGET" "$AGENT_ID"; then
                busy_rc=0
            else
                busy_rc=$?
            fi
            if [ "$busy_rc" -eq 1 ]; then
                if [ "$fp_age" -lt "$busy_max_defer" ]; then
                    echo "[$(date)] [BUSY] Agent $AGENT_ID is active+busy, deferring nudge (age=${fp_age}s < ${busy_max_defer}s)" >&2
                    return 2
                fi
                echo "[$(date)] [BUSY-FORCE] Agent $AGENT_ID active+busy for ${fp_age}s, forcing nudge" >&2
            elif [ "$busy_rc" -eq 2 ]; then
                if [ "$fp_age" -lt "$busy_max_defer" ]; then
                    echo "[$(date)] [BUSY-UNKNOWN] Agent $AGENT_ID active with unknown pane state, deferring nudge (age=${fp_age}s < ${busy_max_defer}s)" >&2
                    return 2
                fi
                echo "[$(date)] [BUSY-UNKNOWN-FORCE] Agent $AGENT_ID active with unknown pane state for ${fp_age}s, forcing nudge" >&2
            fi
        fi
        # @agent_state=idle時にflag補完（flag方式との整合性）
        [ ! -f "$idle_flag" ] && touch "$idle_flag"
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
    if ! refresh_debounce_file; then
        echo "[$(date)] WARNING: failed to update debounce file: $DEBOUNCE_FILE" >&2
    fi

    # Pre-clear: Enter to flush any partial input in the pane
    safe_send_keys "$PANE_TARGET" Enter 2>/dev/null || true
    sleep 0.3

    # Send nudge via paste-buffer + Enter (atomic lock)
    local lock="${STATE_DIR}/tmux_sendkeys_$(echo "$PANE_TARGET" | tr ':.' '_').lock"
    (
        flock -w 5 200 || { echo "[$(date)] LOCK TIMEOUT: send_wakeup $PANE_TARGET" >&2; exit 1; }
        tmux set-buffer -b "nudge_${AGENT_ID}" "$nudge"
        if ! timeout "$SEND_KEYS_TIMEOUT" tmux paste-buffer -t "$PANE_TARGET" -b "nudge_${AGENT_ID}" -d 2>/dev/null; then
            echo "[$(date)] WARNING: paste-buffer timed out ($SEND_KEYS_TIMEOUT s)" >&2
            exit 1
        fi
        sleep 0.5
        if ! timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null; then
            echo "[$(date)] WARNING: send-keys Enter timed out ($SEND_KEYS_TIMEOUT s)" >&2
            exit 1
        fi
    ) 200>"$lock"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # After successful nudge: consume idle flag (Stop hook recreates on idle)
    rm -f "${IDLE_FLAG_DIR}/shogun_idle_${AGENT_ID}"

    # After successful nudge: mark agent as active to prevent duplicate nudges
    # before the agent's own PreToolUse/UserPromptSubmit hook fires.
    tmux set-option -p -t "$PANE_TARGET" @agent_state active 2>/dev/null || true
    echo "[$(date)] Set $AGENT_ID @agent_state to active after nudge" >&2

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
    local normal_count
    normal_count=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null)
    local has_specials
    has_specials=$(echo "$info" | python3 -c "import sys,json; print('true' if json.load(sys.stdin).get('has_specials') else 'false')" 2>/dev/null)

    if [ "$normal_count" -gt 0 ] 2>/dev/null || [ "$has_specials" = "true" ]; then
        mark_first_unread_seen
    else
        clear_first_unread_seen
    fi

    # Handle special CLI commands first (/clear, /model)
    local specials
    specials=$(echo "$info" | python3 -c "
import base64, sys, json
data = json.load(sys.stdin)
for s in data.get('specials', []):
    content = base64.b64encode(str(s.get('content', '')).encode('utf-8')).decode('ascii')
    print(f\"{s.get('id', '')}\\t{s.get('type', '')}\\t{content}\")
" 2>/dev/null)

    if [ -n "$specials" ]; then
        while IFS= read -r special_line; do
            [ -n "$special_line" ] || continue

            local special_id=""
            local special_type=""
            local special_content_b64=""
            local special_content=""
            IFS=$'\t' read -r special_id special_type special_content_b64 <<< "$special_line"
            if [ -n "$special_content_b64" ]; then
                special_content=$(printf '%s' "$special_content_b64" | base64 -d 2>/dev/null || true)
            fi

            local special_ok=true
            case "$special_type" in
                clear_command)
                    local effective_cli
                    effective_cli=$(get_effective_cli_type)
                    local defer_clear=false
                    if [[ "$effective_cli" == "claude" ]]; then
                        local idle_flag="${IDLE_FLAG_DIR}/shogun_idle_${AGENT_ID}"
                        if [ ! -f "$idle_flag" ] && ! maybe_force_idle_flag "$effective_cli"; then
                            defer_clear=true
                        fi
                    else
                        local agent_state
                        agent_state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || echo "unknown")
                        if [ "$agent_state" = "active" ]; then
                            defer_clear=true
                        else
                            local busy_rc
                            if check_agent_busy "$PANE_TARGET" "$AGENT_ID"; then
                                busy_rc=0
                            else
                                busy_rc=$?
                            fi
                            [ "$busy_rc" -eq 1 ] && defer_clear=true
                        fi
                    fi

                    if [ "$defer_clear" = true ]; then
                        echo "[$(date)] [BUSY] Agent $AGENT_ID is busy — /clear (clear_command) deferred to next cycle" >&2
                        break
                    fi

                    if ! send_cli_command "/clear"; then
                        special_ok=false
                    elif [ -n "$special_content" ] && ! send_cli_command "$special_content"; then
                        special_ok=false
                    fi
                    ;;
                model_switch)
                    if ! send_cli_command "$special_content"; then
                        special_ok=false
                    fi
                    ;;
                *)
                    special_ok=false
                    echo "[$(date)] WARNING: unknown special type '$special_type' for $AGENT_ID" >&2
                    ;;
            esac

            if [ "$special_ok" = true ]; then
                mark_special_read "$special_id" || true
            else
                echo "[$(date)] WARNING: send_cli_command failed, special '$special_type' NOT marked read" >&2
                break
            fi
        done <<< "$specials"
    fi

    # Send wake-up nudge for normal messages (fingerprint dedup)
    if [ "$normal_count" -gt 0 ] 2>/dev/null; then
        # Build fingerprint from sorted unread normal message IDs
        local current_fp
        current_fp=$(echo "$info" | python3 -c "import sys,json; ids=json.load(sys.stdin).get('normal_ids',[]); print(','.join(ids))" 2>/dev/null)

        local prev_fp=""
        if [ -f "$FINGERPRINT_FILE" ]; then
            prev_fp=$(cat "$FINGERPRINT_FILE" 2>/dev/null || true)
        fi

        if [ "$current_fp" != "$prev_fp" ]; then
            # Fingerprint changed → new unread messages arrived
            echo "[$(date)] [FP-CHANGE] Unread set changed for $AGENT_ID ($normal_count unread), sending nudge" >&2
            write_state_file "$FINGERPRINT_FILE" "$current_fp" "fingerprint" || true
            write_state_file "$RETRY_COUNT_FILE" "0" "retry_count" || true
            local wake_rc=0
            send_wakeup "$normal_count" || wake_rc=$?
            if [ "$wake_rc" -eq 2 ]; then
                refresh_debounce_file || true
                echo "[$(date)] [WAKE-DEFER] Deferred initial nudge for $AGENT_ID (busy gating)" >&2
            fi
        else
            # FP-SAME: nudge was sent but agent hasn't read messages yet
            # Improvement A: immediate retries before BACKOFF fallback
            local retry_count=0
            if [ -f "$RETRY_COUNT_FILE" ]; then
                retry_count=$(cat "$RETRY_COUNT_FILE" 2>/dev/null || echo 0)
                retry_count=${retry_count:-0}
            fi

            if [ "$retry_count" -lt "$RETRY_MAX" ] 2>/dev/null; then
                # Unacknowledged nudge → retry immediately (next cycle)
                local wake_rc=0
                send_wakeup "$normal_count" || wake_rc=$?
                if [ "$wake_rc" -eq 2 ]; then
                    refresh_debounce_file || true
                    echo "[$(date)] [RETRY-DEFER] Busy gating deferred retry (${retry_count}/${RETRY_MAX}) for $AGENT_ID" >&2
                else
                    retry_count=$((retry_count + 1))
                    write_state_file "$RETRY_COUNT_FILE" "$retry_count" "retry_count" || true
                    echo "[$(date)] [RETRY] Nudge unacknowledged, retry ${retry_count}/${RETRY_MAX} for $AGENT_ID" >&2
                fi
            else
                # Retries exhausted → fall back to BACKOFF_SEC interval
                local fp_age
                fp_age=$(get_fp_age)

                if [ "$fp_age" -ge "$BACKOFF_SEC" ]; then
                    echo "[$(date)] [BACKOFF] Stale unread for ${fp_age}s >= ${BACKOFF_SEC}s, re-notifying $AGENT_ID" >&2
                    touch_state_file "$FINGERPRINT_FILE" "fingerprint" || true  # reset mtime for next backoff cycle
                    send_wakeup "$normal_count"
                else
                    echo "[$(date)] [FP-SAME] Same unread set (age ${fp_age}s, retries exhausted), waiting for backoff for $AGENT_ID" >&2
                fi
            fi
        fi
    else
        # No unread → clear fingerprint + retry counter
        if [ -f "$FINGERPRINT_FILE" ]; then
            rm -f "$FINGERPRINT_FILE"
            rm -f "$RETRY_COUNT_FILE"
            echo "[$(date)] [FP-RESET] No unread, cleared fingerprint for $AGENT_ID" >&2
        fi
        clear_first_unread_seen
    fi
}

# ─── Startup: ensure @agent_state is initialized (deadlock prevention) ───
# If @agent_state is not set (fresh pane, after reset), initialize to idle.
# Without this, a missing state would be treated as "unknown" and nudges
# would still be sent, but explicit initialization prevents ambiguity.
_startup_state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || echo "")
if [ -z "$_startup_state" ]; then
    tmux set-option -p -t "$PANE_TARGET" @agent_state idle 2>/dev/null || true
    echo "[$(date)] Initialized @agent_state=idle for $AGENT_ID" >&2
fi

# ─── Startup: process any existing unread messages ───
process_unread

# ─── Main loop: event-driven via inotifywait ───
# Timeout 60s: WSL2 /mnt/c/ can miss inotify events.
# On timeout (exit 2), check for unread messages as a safety net.
INOTIFY_TIMEOUT="${INOTIFY_TIMEOUT:-60}"

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
