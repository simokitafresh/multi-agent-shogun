#!/bin/bash
# semantic-links: [[inbox_watcherプロセスモデル]], [[インフラ運用基盤]], [[デーモン監視と復旧]]
# shellcheck disable=SC1091,SC2034,SC2155
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

_iw_self="${BASH_SOURCE[0]}"; [[ "$_iw_self" != /* ]] && _iw_self="$PWD/$_iw_self"
SCRIPT_DIR="${_iw_self%/scripts/inbox_watcher.sh}"

# stale monitorが保持中に生成したwatcherはdeploy lock FDを継承し得る。
# source/業務childを起動する前に無条件で閉じ、子孫へ伝播させない。
close_inherited_deploy_lock_fds() {
    local fd_path fd_target inherited_fd
    for fd_path in "/proc/$$/fd/"*; do
        [ -e "$fd_path" ] || continue
        fd_target="$(readlink "$fd_path" 2>/dev/null || true)"
        case "$fd_target" in
            */queue/locks/deploy_ninja_*.lock)
                inherited_fd="${fd_path##*/}"
                exec {inherited_fd}>&-
                ;;
        esac
    done
}
close_inherited_deploy_lock_fds

# cli_lookup.sh を source（CLI種別をsettings.yaml+cli_profiles.yamlから動的取得）
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
[ ! -f "$SCRIPT_DIR/scripts/lib/model_family.sh" ] || source "$SCRIPT_DIR/scripts/lib/model_family.sh"
source "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
[ ! -f "$SCRIPT_DIR/scripts/lib/pane_lookup.sh" ] || source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
source "$SCRIPT_DIR/lib/agent_state.sh"
source "$SCRIPT_DIR/scripts/lib/script_update.sh"
source "$SCRIPT_DIR/scripts/lib/lock_path.sh"
source "$SCRIPT_DIR/scripts/lib/respawn_recovery.sh"
if [ -f "$SCRIPT_DIR/scripts/lib/pane_confirmation_guard.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/pane_confirmation_guard.sh"
elif [ "${INBOX_WATCHER_LIB_ONLY:-0}" = "1" ]; then
    # Minimal source-only fixtures may omit optional production dependencies.
    # The daemon path remains fail-closed when the shared safety library is absent.
    _pane_has_confirmation_prompt() { return 1; }
else
    echo "[inbox_watcher] ERROR: missing shared pane confirmation guard" >&2
    exit 1
fi

AGENT_ID="$1"
PANE_TARGET="$2"
# 第3引数は後方互換で受け付けるが無視（shutsujin_departure.shが渡す）
CLI_TYPE_AT_STARTUP=$(cli_type "$AGENT_ID")  # settings.yaml → cli_profiles.yaml の2段参照

STATE_DIR="${SHOGUN_STATE_DIR:-${IDLE_FLAG_DIR:-/tmp}}"
IDLE_FLAG_DIR="$STATE_DIR"
mkdir -p "$STATE_DIR"

resolve_inbox_file_path() {
    local inbox_file="$1"
    local resolved=""

    resolved=$(readlink -f "$inbox_file" 2>/dev/null || true)
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    local inbox_dir inbox_base resolved_dir
    inbox_dir="${inbox_file%/*}"
    inbox_base="${inbox_file##*/}"
    resolved_dir=$(readlink -f "$inbox_dir" 2>/dev/null || true)
    if [ -n "$resolved_dir" ]; then
        printf '%s/%s\n' "$resolved_dir" "$inbox_base"
    else
        printf '%s\n' "$inbox_file"
    fi
}

INBOX_DIR_LINK="$SCRIPT_DIR/queue/inbox"
if [ -L "$INBOX_DIR_LINK" ] && [ ! -e "$INBOX_DIR_LINK" ]; then
    echo "[inbox_watcher] ALERT: queue/inbox symlink is broken: $INBOX_DIR_LINK -> $(readlink "$INBOX_DIR_LINK" 2>/dev/null || echo unknown)" >&2
    exit 1
fi

INBOX_LINK_PATH="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
INBOX="$(resolve_inbox_file_path "$INBOX_LINK_PATH")"
LOCKFILE="$(lock_path "$INBOX")"
SEND_KEYS_TIMEOUT=5  # seconds — prevents hang (PID 274337 incident)
# ASW_PROCESS_TIMEOUT=0: disable timeout on tmux commands to shogun pane
if [ "${ASW_PROCESS_TIMEOUT:-}" = "0" ]; then
    SEND_KEYS_TIMEOUT=0  # timeout 0 = no limit
fi
DEBOUNCE_SEC="${NUDGE_COOLDOWN_SEC:-30}"
NORMAL_BATCH_WINDOW_SEC="${NORMAL_BATCH_WINDOW_SEC:-300}"
DEBOUNCE_FILE="${STATE_DIR}/inbox_watcher_last_nudge_${AGENT_ID}"
FINGERPRINT_FILE="${STATE_DIR}/inbox_watcher_fingerprint_${AGENT_ID}"
source "$SCRIPT_DIR/scripts/lib/inbox_nudge_policy.sh"
BACKOFF_SEC="${BACKOFF_SEC:-$INBOX_RENUDGE_BACKOFF_SEC}"
MAX_RENUDGE="${MAX_RENUDGE:-$INBOX_RENUDGE_MAX_ATTEMPTS}"
STATE_LOCK_FILE="${STATE_DIR}/inbox_watcher_state_${AGENT_ID}.lock"
SINGLETON_LOCK_FILE="${STATE_DIR}/inbox_watcher_singleton_${AGENT_ID}.lock"
DEFERRED_NUDGE_FILE="${STATE_DIR}/inbox_watcher_deferred_nudge_${AGENT_ID}"
BUSY_QUEUE_CLAIM_FILE="${STATE_DIR}/inbox_watcher_busy_queue_claim_${AGENT_ID}"
FIRST_UNREAD_SEEN="${FIRST_UNREAD_SEEN:-${STATE_DIR}/first_unread_seen_${AGENT_ID}}"
idle_flag="${IDLE_FLAG_DIR}/shogun_idle_${AGENT_ID}"
idle_flag_lock="${idle_flag}.lock"
# Shared with stop_check_inbox.sh.  The flag is a lifecycle token, not a
# timeout marker: only an observed idle pane may publish it, and delivery
# consumes it before entering the active turn.
set_idle_flag() {
    (
        flock -w 5 9 || exit 1
        : > "$idle_flag"
    ) 9>"$idle_flag_lock"
}
clear_idle_flag() {
    (
        flock -w 5 9 || exit 1
        rm -f "$idle_flag"
    ) 9>"$idle_flag_lock"
}
claim_idle_delivery() {
    (
        flock -w 5 9 || exit 1
        local state
        state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || true)
        if [ "$state" != "idle" ]; then
            rm -f "$idle_flag"
            exit 2
        fi
        tmux set-option -p -t "$PANE_TARGET" @agent_state active 2>/dev/null || true
        rm -f "$idle_flag"
    ) 9>"$idle_flag_lock"
}
restore_idle_delivery() {
    (
        flock -w 5 9 || exit 1
        tmux set-option -p -t "$PANE_TARGET" @agent_state idle 2>/dev/null || true
        : > "$idle_flag"
    ) 9>"$idle_flag_lock"
}
FORCE_IDLE_AFTER_SEC="${FORCE_IDLE_AFTER_SEC:-60}"
BUSY_TIMEOUT_SEC="${BUSY_TIMEOUT_SEC:-30}"  # @last_active based timeout (AC1: idle_flag force-creation)
HANG_DETECT_SEC="${HANG_DETECT_SEC:-300}"  # seconds before daemon_watchdog.sh considers this watcher hung
LOOP_HEARTBEAT_FILE="${STATE_DIR}/inbox_watcher_loop_hb_${AGENT_ID}"
DELIVERY_LATENCY_WARN_SEC="${DELIVERY_LATENCY_WARN_SEC:-60}"  # cmd_3646: 殿指摘の長い尾(上位1割>60s)を可視化するしきい値
HIGH_PRIORITY_NUDGE_DEADLINE_SEC="${HIGH_PRIORITY_NUDGE_DEADLINE_SEC:-60}"
NORMAL_PRIORITY_NUDGE_DEADLINE_SEC="${NORMAL_PRIORITY_NUDGE_DEADLINE_SEC:-120}"
LOW_PRIORITY_NUDGE_DEADLINE_SEC="${LOW_PRIORITY_NUDGE_DEADLINE_SEC:-600}"

# Self-restart on script change (cmd_100)
SCRIPT_PATH="$_iw_self"  # reuse already-resolved path (avoids realpath subprocess)
unset _iw_self
SCRIPT_HASH="$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null)"
STARTUP_TIME="$(date +%s)"
MIN_UPTIME=10  # minimum seconds before allowing auto-restart
WATCHED_DEPS=(
    "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
    "$SCRIPT_DIR/scripts/lib/respawn_recovery.sh"
    "$SCRIPT_DIR/scripts/lib/tmux_utils.sh"
    "$SCRIPT_DIR/lib/agent_state.sh"
)
DEPS_HASH="$(compute_deps_hash)"

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

# CLI generation tracking for delivery lease scope (generation change → invalidate leases)
CURRENT_CLI_GENERATION=$(respawn_recovery_generation "$PANE_TARGET" 2>/dev/null || echo "")

ensure_current_pane_target() {
    local current_agent resolved

    current_agent=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_id}' 2>/dev/null || true)
    if [ "$current_agent" = "$AGENT_ID" ]; then
        return 0
    fi

    if ! declare -f pane_lookup >/dev/null 2>&1; then
        echo "[$(date)] [PANE-RETARGET-WARN] $AGENT_ID current pane $PANE_TARGET has @agent_id='${current_agent:-empty}', and pane_lookup is unavailable" >&2
        return 1
    fi

    resolved=$(pane_lookup "$AGENT_ID" 2>/dev/null || true)
    if [ -z "$resolved" ]; then
        echo "[$(date)] [PANE-RETARGET-WARN] $AGENT_ID current pane $PANE_TARGET has @agent_id='${current_agent:-empty}', and pane_lookup failed" >&2
        return 1
    fi

    if [ "$resolved" != "$PANE_TARGET" ]; then
        echo "[$(date)] [PANE-RETARGET] $AGENT_ID: $PANE_TARGET(@agent_id=${current_agent:-empty}) -> $resolved" >&2
        PANE_TARGET="$resolved"
    fi
    return 0
}

# Ensure inotifywait is available. Unit tests source this file with
# INBOX_WATCHER_LIB_ONLY=1 to exercise helper functions without daemon deps.
if [ "${INBOX_WATCHER_LIB_ONLY:-0}" != "1" ] && ! command -v inotifywait &>/dev/null; then
    echo "[inbox_watcher] ERROR: inotifywait not found. Install: sudo apt install inotify-tools" >&2
    exit 1
fi

# ─── Extract unread message info (lock-free read) ───
# Returns TAB-separated: count \t has_specials \t fingerprint \t specials_tsv \t has_task_assigned \t priority \t batchable
# specials_tsv: newline-separated "id\ttype\tbase64_content" lines (base64-encoded as whole)
# inbox_write.sh emits a constrained YAML shape, so use a lightweight line parser
# instead of PyYAML full-load on every watch cycle.
# IMPORTANT: Empty fields use placeholder '-' to prevent bash IFS='\t' read
# from merging consecutive tabs (tab is IFS-whitespace → adjacent tabs collapse)
fingerprint_unread_ids() {
    local unread_ids="$1"
    [ -n "$unread_ids" ] && [ "$unread_ids" != "-" ] || {
        printf '%s\n' "-"
        return
    }
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$unread_ids" | sha256sum | awk '{print $1}'
    else
        printf '%s' "$unread_ids" | shasum -a 256 | awk '{print $1}'
    fi
}

# Exact task_assigned retries for one published task generation must not become
# new prompts merely because inbox_write allocated another message id.
task_publication_fingerprint() {
    local unread_fingerprint="${1:-}"
    local task_file="${SCRIPT_DIR}/queue/tasks/${AGENT_ID}.yaml"
    [ -f "$task_file" ] || return 1
    local identity
    identity=$(awk '
        /^[[:space:]]*(task_id|_ac_task_id|deployed_at):/ {
            line=$0; sub(/^[^:]*:[[:space:]]*/, "", line); gsub(/["[:space:]]/, "", line)
            if ($1 ~ /task_id:/ && task_id == "") task_id=line
            else if ($1 ~ /_ac_task_id:/ && task_id == "") task_id=line
            else if ($1 ~ /deployed_at:/) deployed_at=line
        }
        END { if (task_id != "" && deployed_at != "") print task_id "@" deployed_at }
    ' "$task_file")
    [ -n "$identity" ] || return 1
    printf 'task-%s\n' "$(printf '%s\t%s' "$identity" "$unread_fingerprint" | sha256sum | awk '{print $1}')"
}


get_unread_info() {
    # Fast path: skip Python3 startup (~40ms) when no unread messages exist
    if ! grep -qF 'read: false' "$INBOX" 2>/dev/null; then
        printf '0\tfalse\t-\t-\tfalse\n'
        return
    fi
    # Common path: normal unread messages only. Avoid Python startup on each
    # watcher cycle; fall back to the parser below when special CLI commands
    # may need multiline/base64 handling.
    if ! grep -qE 'type:[[:space:]]*['"'"'"]?(clear_command|model_switch)['"'"'"]?' "$INBOX" 2>/dev/null; then
        local fast_info fast_count fast_has_task fast_ids fast_fp fast_priority fast_batchable
        fast_info=$(awk '
function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
function unquote(s) {
    s = trim(s)
    if ((substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") ||
        (substr(s, 1, 1) == "'\''" && substr(s, length(s), 1) == "'\''")) {
        s = substr(s, 2, length(s) - 2)
    }
    return s
}
function assign(line, target,    key,value,pos) {
    pos = index(line, ":")
    if (pos == 0) return
    key = trim(substr(line, 1, pos - 1))
    value = unquote(substr(line, pos + 1))
    target[key] = value
}
function flush_message(    mid) {
    if (msg["read"] != "false") return
    mid = msg["id"]
    if (!mid) return
    count++
    ids[count] = mid
    if (msg["type"] == "task_assigned") has_task = "true"
    if (msg["type"] != "bulletin_notify") all_batchable = "false"
    if (msg["type"] ~ /^(task_assigned|task_supplement|report_received|investigation_result|report_review|verify_request|cmd_new|escalation|recovery|gate_clear)$/) high_count++
    else if (msg["type"] ~ /^(info|heartbeat|status_update)$/) low_count++
    else normal_count++
}
BEGIN { count = 0; high_count = 0; normal_count = 0; low_count = 0; has_task = "false"; all_batchable = "true"; in_msg = 0 }
/^- / {
    if (in_msg) flush_message()
    delete msg
    in_msg = 1
    assign(substr($0, 3), msg)
    next
}
in_msg && /^  [A-Za-z0-9_.-]+:/ {
    assign(substr($0, 3), msg)
}
END {
    if (in_msg) flush_message()
    if (count == 0) {
        print "0\tfalse\t-\tnone"
        exit
    }
    for (i = 1; i <= count; i++) {
        for (j = i + 1; j <= count; j++) {
            if (ids[j] < ids[i]) {
                tmp = ids[i]; ids[i] = ids[j]; ids[j] = tmp
            }
        }
    }
    fp_ids = ids[1]
    for (i = 2; i <= count; i++) fp_ids = fp_ids "," ids[i]
    priority = "normal"
    if (high_count > 0) priority = "high"
    else if (low_count == count) priority = "low"
    print count "\t" has_task "\t" fp_ids "\t" priority "\t" (count > 0 && all_batchable == "true" ? "true" : "false")
}
' "$INBOX")
        IFS=$'\t' read -r fast_count fast_has_task fast_ids fast_priority fast_batchable <<< "$fast_info"
        fast_count="${fast_count:-0}"
        fast_has_task="${fast_has_task:-false}"
        fast_ids="${fast_ids:--}"
        fast_priority="${fast_priority:-normal}"
        if [ "$fast_count" -gt 0 ] 2>/dev/null; then
            fast_fp="$(fingerprint_unread_ids "$fast_ids")"
            printf '%s\tfalse\t%s\t-\t%s\t%s\t%s\n' "$fast_count" "$fast_fp" "$fast_has_task" "$fast_priority" "${fast_batchable:-false}"
        else
            printf '0\tfalse\t-\t-\tfalse\tnone\n'
        fi
        return
    fi
    INBOX_PATH="$INBOX" python3 -c "
import sys, os, base64, ast, hashlib

SPECIAL_TYPES = {'clear_command', 'model_switch'}
TASK_NUDGE_TYPES = {'task_assigned'}

def decode_scalar(value):
    value = value.strip()
    if not value:
        return ''
    if value in ('true', 'false'):
        return value
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('\"', \"'\"):
        try:
            return ast.literal_eval(value)
        except Exception:
            if value[0] == \"'\":
                return value[1:-1].replace(\"''\", \"'\")
            return value[1:-1]
    return value

try:
    inbox_path = os.environ['INBOX_PATH']
    normal_ids = []
    normal_types = []
    specials = []
    task_nudge_ids = []
    current = None
    state = {'block_key': None, 'block_lines': []}

    def flush_block():
        if current is not None and state['block_key'] is not None:
            current[state['block_key']] = '\n'.join(state['block_lines'])
        state['block_key'] = None
        state['block_lines'] = []

    def flush_message():
        flush_block()
        if not current or current.get('read', 'true') != 'false':
            return
        if current.get('type', '') in SPECIAL_TYPES:
            specials.append(current)
        else:
            normal_ids.append(current.get('id', ''))
            msg_type = current.get('type', '')
            normal_types.append(msg_type)
            if msg_type in TASK_NUDGE_TYPES:
                task_nudge_ids.append(current.get('id', ''))

    def assign_field(target, key, raw_value):
        value = raw_value.lstrip()
        if value == '|-' or value == '|':
            state['block_key'] = key
            state['block_lines'] = []
            return
        target[key] = decode_scalar(value)

    with open(inbox_path, encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n')

            if state['block_key'] is not None:
                if line.startswith('    '):
                    state['block_lines'].append(line[4:])
                    continue
                flush_block()

            if line == 'messages: []':
                continue
            if line == 'messages:' or not line:
                continue

            if line.startswith('- '):
                flush_message()
                current = {}
                key, value = line[2:].split(':', 1)
                assign_field(current, key.strip(), value)
                continue

            if current is not None and line.startswith('  '):
                key, value = line[2:].split(':', 1)
                assign_field(current, key.strip(), value)

    flush_message()

    if not normal_ids and not specials:
        print('0\tfalse\t-\t-\tfalse\tnone')
        sys.exit(0)

    normal_count = len(normal_ids)
    normal_id_set = ','.join(sorted(normal_ids))
    normal_fp = hashlib.sha256(normal_id_set.encode('utf-8')).hexdigest() if normal_id_set else '-'
    specials_tsv = '-'
    if specials:
        lines = []
        for s in specials:
            content_b64 = base64.b64encode(str(s.get('content', '')).encode('utf-8')).decode('ascii')
            lines.append(f\"{s.get('id', '')}\t{s.get('type', '')}\t{content_b64}\")
        specials_tsv = base64.b64encode('\n'.join(lines).encode('utf-8')).decode('ascii')
    has_task_assigned = 'true' if task_nudge_ids else 'false'
    # gate_clear is an actionable completion event, not informational noise.
    high_types = {'task_assigned', 'task_supplement', 'report_received', 'investigation_result', 'report_review', 'verify_request', 'cmd_new', 'escalation', 'recovery', 'gate_clear'}
    low_types = {'info', 'heartbeat', 'status_update'}
    priority = 'normal'
    if any(t in high_types for t in normal_types):
        priority = 'high'
    elif normal_types and all(t in low_types for t in normal_types):
        priority = 'low'
    batchable = bool(normal_types) and all(t == 'bulletin_notify' for t in normal_types)
    print(f\"{normal_count}\t{'true' if specials else 'false'}\t{normal_fp}\t{specials_tsv}\t{has_task_assigned}\t{priority}\t{'true' if batchable else 'false'}\")
except Exception:
    print('0\tfalse\t-\t-\tfalse\tnone')
" 2>/dev/null
}

get_single_unread_task_message_id() {
    awk '
        function strip(value) {
            gsub(/^[[:space:]\047"]+|[[:space:]\047"]+$/, "", value)
            return value
        }
        function flush_message() {
            if (in_message && read_state == "false" && type_value == "task_assigned" && id_value != "") {
                task_count++
                task_id_value = id_value
            }
        }
        /^- / {
            flush_message()
            in_message = 1
            id_value = ""
            read_state = ""
            type_value = ""
            line = substr($0, 3)
            key = line
            sub(/:.*/, "", key)
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            if (key == "id") id_value = strip(value)
            next
        }
        in_message && /^  [A-Za-z0-9_.-]+:/ {
            line = substr($0, 3)
            key = line
            sub(/:.*/, "", key)
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            value = strip(value)
            if (key == "id") id_value = value
            else if (key == "read") read_state = value
            else if (key == "type") type_value = value
        }
        END {
            flush_message()
            if (task_count == 1) print task_id_value
        }
    ' "$INBOX"
}

# task_assigned wake-ups must identify the destination generation in the
# visible nudge as well as in the durable inbox row.  Read only the current
# destination task YAML; never infer identity from message prose.
current_task_id_for_nudge() {
    local task_file="${SCRIPT_DIR}/queue/tasks/${AGENT_ID}.yaml"
    [ -f "$task_file" ] || return 1
    awk '
        /^[[:space:]]*task_id:/ && $0 !~ /_ac_task_id:/ {
            value=$0
            sub(/^[^:]*:[[:space:]]*/, "", value)
            gsub(/["'"'"'[:space:]]/, "", value)
            if (value != "") { print value; exit }
        }
        /^[[:space:]]*_ac_task_id:/ && fallback == "" {
            fallback=$0
            sub(/^[^:]*:[[:space:]]*/, "", fallback)
            gsub(/["'"'"'[:space:]]/, "", fallback)
        }
        END { if (fallback != "") print fallback }
    ' "$task_file"
}

# Return a fingerprint of unread task_assigned message IDs bound to the
# destination task's current task_id and parent_cmd.  Unrelated task/empty-task
# rows must not expire a generation lease, while a newly appended ID for the
# current task must create a fresh delivery obligation.
current_task_assignment_fingerprint() {
    local task_file="${SCRIPT_DIR}/queue/tasks/${AGENT_ID}.yaml"
    [ -f "$task_file" ] || { printf '%s\n' '-'; return 0; }

    local task_identity current_task_id current_parent_cmd matching_ids
    task_identity=$(awk '
        function strip(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["'"'"']|["'"'"']$/, "", value)
            return value
        }
        /^[[:space:]]*task_id:/ && $0 !~ /_ac_task_id:/ && task_id == "" {
            value=$0; sub(/^[^:]*:[[:space:]]*/, "", value); task_id=strip(value)
        }
        /^[[:space:]]*parent_cmd:/ && parent_cmd == "" {
            value=$0; sub(/^[^:]*:[[:space:]]*/, "", value); parent_cmd=strip(value)
        }
        END { print task_id "\t" parent_cmd }
    ' "$task_file")
    IFS=$'\t' read -r current_task_id current_parent_cmd <<< "$task_identity"
    if [ -z "$current_task_id" ] || [ -z "$current_parent_cmd" ]; then
        printf '%s\n' '-'
        return 0
    fi

    matching_ids=$(awk -v wanted_task="$current_task_id" -v wanted_parent="$current_parent_cmd" '
        function strip(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            gsub(/^["'"'"']|["'"'"']$/, "", value)
            return value
        }
        function assign(line,    key,value,pos) {
            pos=index(line, ":")
            if (pos == 0) return
            key=strip(substr(line, 1, pos - 1))
            value=strip(substr(line, pos + 1))
            if (key == "id") message_id=value
            else if (key == "read") message_read=value
            else if (key == "type") message_type=value
            else if (key == "task_id") message_task=value
            else if (key == "parent_cmd") message_parent=value
        }
        function flush_message() {
            if (message_read == "false" && message_type == "task_assigned" &&
                message_task == wanted_task && message_parent == wanted_parent &&
                message_id != "") ids[++count]=message_id
        }
        function reset_message() {
            message_id=""; message_read=""; message_type=""
            message_task=""; message_parent=""
        }
        /^- / {
            if (in_message) flush_message()
            reset_message(); in_message=1; assign(substr($0, 3)); next
        }
        in_message && /^  [A-Za-z0-9_.-]+:/ { assign(substr($0, 3)) }
        END {
            if (in_message) flush_message()
            for (i=1; i<=count; i++) for (j=i+1; j<=count; j++)
                if (ids[j] < ids[i]) { tmp=ids[i]; ids[i]=ids[j]; ids[j]=tmp }
            for (i=1; i<=count; i++) printf "%s%s", (i==1 ? "" : ","), ids[i]
        }
    ' "$INBOX")
    [ -n "$matching_ids" ] || { printf '%s\n' '-'; return 0; }
    fingerprint_unread_ids "$matching_ids"
}

priority_deadline_sec() {
    local priority="${1:-normal}"
    local deadline
    case "$priority" in
        high) deadline="$HIGH_PRIORITY_NUDGE_DEADLINE_SEC" ;;
        low) deadline="$LOW_PRIORITY_NUDGE_DEADLINE_SEC" ;;
        *) deadline="$NORMAL_PRIORITY_NUDGE_DEADLINE_SEC" ;;
    esac
    [[ "$deadline" =~ ^[0-9]+$ ]] || deadline="$NORMAL_PRIORITY_NUDGE_DEADLINE_SEC"
    printf '%s\n' "$deadline"
}

priority_deadline_reached() {
    local priority="${1:-normal}"
    local unread_age="${2:-0}"
    local deadline
    deadline=$(priority_deadline_sec "$priority")
    [ "$unread_age" -ge "$deadline" ] 2>/dev/null
}

# ─── Mark one special message as read (flock + atomic write) ───
# Called AFTER send_cli_command succeeds, to prevent message loss on send failure.
mark_special_read() {
    local message_id="$1"
    [ -n "$message_id" ] || return 1
    # 2026-09-01 将軍 D0: receipt contract(cmd_karo_hotfix_inbox_processing_receipt)後、watcher の
    # 特殊 type(clear_command/model_switch)既読化が『no inbox read receipt』で BLOCK され、stderr を
    # 捨てていたため clear_command が未読のまま残り generation 変化ごとに /clear を再送した
    # (軍師 17:35/17:43/18:13 の 3 回、recovery が毎回消えた)。mark 前に watcher 自身が receipt を発行し、
    # BLOCK は log に残す(型5弾-2: 検証コマンドの stderr を捨てるな)。
    bash "$SCRIPT_DIR/scripts/inbox_read.sh" "$AGENT_ID" >/dev/null 2>&1 || true
    if ! bash "$SCRIPT_DIR/scripts/inbox_mark_read.sh" "$AGENT_ID" "$message_id" 2>&1 | grep -E "BLOCK|ERROR" >&2; then :; else
        echo "[$(date)] [WARN] special-type mark_read failed for $AGENT_ID msg=$message_id (see BLOCK above)" >&2
    fi
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
    if ! write_state_file "$DEBOUNCE_FILE" "$EPOCHSECONDS" "debounce"; then
        echo "[$(date)] WARNING: failed to refresh debounce file: $DEBOUNCE_FILE" >&2
        return 1
    fi
}

get_first_unread_age() {
    if [ -f "$FIRST_UNREAD_SEEN" ]; then
        local first_seen
        IFS= read -r first_seen < "$FIRST_UNREAD_SEEN" 2>/dev/null || true
        if [[ "$first_seen" =~ ^[0-9]+$ ]]; then
            echo $(( EPOCHSECONDS - first_seen ))
            return
        fi
    fi
    echo 0
}

mark_first_unread_seen() {
    if [ ! -f "$FIRST_UNREAD_SEEN" ]; then
        write_state_file "$FIRST_UNREAD_SEEN" "$EPOCHSECONDS" "first_unread_seen" || true
    fi
}

clear_first_unread_seen() {
    rm -f "$FIRST_UNREAD_SEEN"
}

record_deferred_nudge() {
    local fingerprint="${1:-}"
    local reason="${2:-unknown}"
    local tmp_file="${DEFERRED_NUDGE_FILE}.$$"
    {
        printf 'ts=%s\n' "$EPOCHSECONDS"
        printf 'fingerprint=%s\n' "$fingerprint"
        printf 'reason=%s\n' "$reason"
    } > "$tmp_file"
    mv -f "$tmp_file" "$DEFERRED_NUDGE_FILE"
}

clear_deferred_nudge() {
    rm -f "$DEFERRED_NUDGE_FILE" 2>/dev/null || true
}

has_deferred_nudge_for_fp() {
    local fingerprint="${1:-}"
    [ -s "$DEFERRED_NUDGE_FILE" ] || return 1
    [ -n "$fingerprint" ] && [ "$fingerprint" != "-" ] || return 0
    grep -q "^fingerprint=${fingerprint}\$" "$DEFERRED_NUDGE_FILE" 2>/dev/null
}

maybe_force_idle_flag() {
    local effective_cli="$1"
    [ "$effective_cli" = "claude" ] || return 1
    ensure_current_pane_target || return 1

    [ -f "$idle_flag" ] && return 1

    # A background shell is genuinely busy even when the pane footer looks
    # idle.  Never turn a stale clock into permission to deliver.
    if _agent_state_has_busy_subprocess "$PANE_TARGET"; then
        return 1
    fi

    local agent_state
    agent_state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || true)
    [ "$agent_state" = "idle" ] || return 1

    # Reconcile a missing flag from the live pane state.  This is a normal
    # lifecycle repair, not a timeout-based recovery/force path.
    if set_idle_flag; then
        echo "[$(date)] [IDLE-RECONCILED] restored idle flag for $AGENT_ID from @agent_state=idle" >&2
        return 0
    fi
    return 1
}

# ─── Fingerprint age helper ───
get_fp_age() {
    if [ -f "$FINGERPRINT_FILE" ]; then
        local fp_mtime
        fp_mtime=$(stat -c %Y "$FINGERPRINT_FILE" 2>/dev/null || echo 0)
        if [[ "$fp_mtime" =~ ^[0-9]+$ ]] && [ "$fp_mtime" -gt 0 ]; then
            echo $(( EPOCHSECONDS - fp_mtime ))
            return
        fi
    fi
    echo 0
}

# ─── CLI generation lease invalidation ───
# After respawn/clear, CLI generation (PID:starttime) changes.
# Delivery leases (sent_tokens) from the old generation must be invalidated
# so that the same task fingerprint can be re-delivered to the new CLI instance.
invalidate_leases_on_generation_change() {
    local new_gen
    new_gen=$(respawn_recovery_generation "$PANE_TARGET" 2>/dev/null || echo "")
    [ -n "$new_gen" ] || return 0
    if [ -n "$CURRENT_CLI_GENERATION" ] && [ "$new_gen" != "$CURRENT_CLI_GENERATION" ]; then
        echo "[$(date)] [GENERATION-CHANGE] $AGENT_ID: $CURRENT_CLI_GENERATION -> $new_gen, invalidating delivery leases" >&2
        rm -f "${STATE_DIR}/inbox_watcher_sent_${AGENT_ID}_"*
        rm -f "$FINGERPRINT_FILE"
        rm -f "$DEBOUNCE_FILE"
    fi
    CURRENT_CLI_GENERATION="$new_gen"
}

# Normal/high inbox nudges have one outstanding delivery obligation per CLI
# generation.  Keep the lease under the existing sent-token namespace so
# inbox_write.sh's verified-delivery rearm can coexist with it without a
# second state protocol.  The unread fingerprint remains diagnostic only; it
# must not create a new lease when an unread message is appended during the
# same CLI turn.
outstanding_lease_file_for_generation() {
    local generation="${1:-}"
    local safe_generation
    [ -n "$generation" ] || return 1
    safe_generation="${generation//[^A-Za-z0-9_.-]/_}"
    printf '%s/inbox_watcher_sent_%s_outstanding_lease_%s\n' \
        "$STATE_DIR" "$AGENT_ID" "$safe_generation"
}

current_outstanding_lease_file() {
    local generation="${1:-${CURRENT_CLI_GENERATION:-}}"
    [ -n "$generation" ] || return 1
    outstanding_lease_file_for_generation "$generation"
}

# Before generation leases were introduced, a delivered unread set left a
# fingerprint-keyed sent token behind.  A watcher self-restart keeps the CLI
# process (and therefore its generation) alive, so that token is still a
# valid delivery lease and must be carried forward instead of sending again.
# Only the currently observed fingerprint is eligible: stale legacy tokens
# from another unread set must not suppress a new nudge.
migrate_legacy_fingerprint_lease() {
    local fingerprint="${1:-}" unread_count="${2:-0}" generation="${3:-${CURRENT_CLI_GENERATION:-}}"
    local task_assignment_fp="${4:--}"
    local safe_fp legacy_file lease_file lease_scope_fp
    [ -n "$fingerprint" ] && [ "$fingerprint" != "-" ] || return 1
    [ -n "$generation" ] || return 1
    [ "$generation" = "${CURRENT_CLI_GENERATION:-}" ] || return 1
    [[ "$unread_count" =~ ^[0-9]+$ ]] || return 1
    local observed_generation
    observed_generation="$(respawn_recovery_generation "$PANE_TARGET" 2>/dev/null || true)"
    [ -n "$observed_generation" ] && [ "$observed_generation" = "$generation" ] || return 1

    safe_fp="${fingerprint//[^A-Za-z0-9_.-]/_}"
    legacy_file="${STATE_DIR}/inbox_watcher_sent_${AGENT_ID}_${safe_fp}"
    [ -e "$legacy_file" ] || return 1
    lease_file="$(outstanding_lease_file_for_generation "$generation")" || return 1

    # This function is called while STATE_LOCK_FILE is held.  Claim the new
    # lease with noclobber so a concurrent/reentrant caller cannot overwrite
    # an already established generation lease.
    if [ ! -e "$lease_file" ]; then
        if ! ( set -C; : > "$lease_file" ) 2>/dev/null; then
            return 1
        fi
        lease_scope_fp="$fingerprint"
        if [ "$task_assignment_fp" != "-" ]; then
            lease_scope_fp="$task_assignment_fp"
        fi
        printf '%s\t%s\t%s\t%s\n' "$generation" "$unread_count" "$lease_scope_fp" "$fingerprint" > "$lease_file"
    fi
    rm -f -- "$legacy_file"
    echo "[$(date)] [LEGACY-LEASE-MIGRATED] $AGENT_ID fingerprint=$fingerprint generation=$generation" >&2
    return 0
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

pane_input_line_has_text() {
    local pane_target="$1"
    local effective_cli="${2:-unknown}"
    local pane_tail styled_tail last_line stripped

    pane_tail=$(tmux capture-pane -t "$pane_target" -p -J -S -3 2>/dev/null || true)
    last_line=$(printf '%s\n' "$pane_tail" | grep -E '^[[:space:]]*[›❯]' | tail -1 || true)
    [ -n "$last_line" ] || return 1

    # Codex and Claude render their idle suggestions inside the prompt using
    # ANSI dim (SGR 2).
    # Plain capture makes that placeholder indistinguishable from unsent user text,
    # which can defer recovery nudges forever. Preserve styles for this one check;
    # genuinely typed text is not dim and remains protected by INPUT-GUARD.
    if [[ "$effective_cli" = "codex" || "$effective_cli" = "claude" ]]; then
        styled_tail=$(tmux capture-pane -t "$pane_target" -p -e -J -S -3 2>/dev/null || true)
        [[ "$styled_tail" == *$'\033[2m'* ]] && return 1
    fi

    stripped="$last_line"
    stripped="${stripped//$'\r'/}"
    stripped="${stripped//$'\302\240'/}"
    stripped="$(printf '%s' "$stripped" | sed -E \
        -e 's/^[[:space:]]*[›❯][[:space:]]*//' \
        -e 's/[[:space:]]*[0-9]+%[[:space:]]+(context[[:space:]]+)?left.*$//' \
        -e 's/[[:space:]]*\\?[[:space:]]+for[[:space:]]+shortcuts.*$//' \
        -e 's/[[:space:]]+$//')"

    [[ "$stripped" =~ ^\[[^]]+\][[:space:]] ]] && return 1
    [ -n "$stripped" ]
}

# Codex can leave a generated idle suggestion visible while background
# terminals are still running.  That prompt is the delivery boundary: the
# visible background marker must not keep a queued claim alive.  Inspect only
# the prompt line's style; footer/status dimming is not evidence that the
# prompt itself is idle.
codex_explicit_idle_prompt() {
    local pane_target="$1"
    local plain_tail styled_tail prompt_line

    plain_tail=$(tmux capture-pane -t "$pane_target" -p -J -S -3 2>/dev/null || true)
    prompt_line=$(printf '%s\n' "$plain_tail" | grep -E '^[[:space:]]*›' | tail -1 || true)
    [ -n "$prompt_line" ] || return 1

    styled_tail=$(tmux capture-pane -t "$pane_target" -p -e -J -S -3 2>/dev/null || true)
    prompt_line=$(printf '%s\n' "$styled_tail" | grep '›' | tail -1 || true)
    [[ "$prompt_line" == *$'\033[2m'* ]]
}

# ─── Send CLI command directly via send-keys ───
# For /clear and /model only. These are CLI commands, not conversation messages.
# CLI種別はcli_profiles.yamlのフィールドで動的に判定（name-based分岐なし）
send_cli_command() {
    local cmd="$1"
    ensure_current_pane_target || return 1
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
        clear_method=$(cli_profile_get_for_type "$effective_cli" "clear_method")
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
        actual_cmd=$(cli_profile_get_for_type "$effective_cli" "clear_cmd")
        actual_cmd="${actual_cmd:-/clear}"
        post_wait=3
    fi

    # /model: supports_model_switchで動的判定
    if [[ "$cmd" == /model* ]]; then
        local supports_model
        supports_model=$(cli_profile_get_for_type "$effective_cli" "supports_model_switch")
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
_pid_is_descendant_of_self() {
    local candidate_pid="$1"
    local self_pid="${ASW_SELF_PID:-$$}"
    local parent_pid=""

    while [[ "$candidate_pid" =~ ^[0-9]+$ ]] && [ "$candidate_pid" -gt 1 ]; do
        if [ "$candidate_pid" = "$self_pid" ]; then
            return 0
        fi

        parent_pid=$(ps -p "$candidate_pid" -o ppid= 2>/dev/null | awk 'NR==1 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')
        if ! [[ "$parent_pid" =~ ^[0-9]+$ ]] || [ "$parent_pid" = "$candidate_pid" ]; then
            break
        fi

        candidate_pid="$parent_pid"
    done

    return 1
}

_pid_has_live_parent() {
    local candidate_pid="$1"
    local parent_pid=""

    [[ "$candidate_pid" =~ ^[0-9]+$ ]] || return 1

    parent_pid=$(ps -p "$candidate_pid" -o ppid= 2>/dev/null | awk 'NR==1 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}')
    [[ "$parent_pid" =~ ^[0-9]+$ ]] || return 1
    [ "$parent_pid" -gt 1 ] || return 1

    ps -p "$parent_pid" >/dev/null 2>&1
}

agent_has_self_watch() {
    local watch_pids pid

    watch_pids=$(pgrep -f "inotifywait.*inbox/${AGENT_ID}.yaml" 2>/dev/null || true)
    [ -n "$watch_pids" ] || return 1

    for pid in $watch_pids; do
        if _pid_has_live_parent "$pid" && ! _pid_is_descendant_of_self "$pid"; then
            return 0
        fi
    done

    return 1
}

# ─── Send wake-up nudge ───
# Layered approach (send-keys撲滅):
#   1. If agent has active inotifywait self-watch → skip (agent wakes itself)
#   2. Fallback: paste-buffer + Enter (avoids send-keys for content)
# timeout prevents the 1.5-hour hang incident from recurring.
send_wakeup() {
    local unread_count="$1"
    local has_task_assigned="${2:-false}"
    local current_fp="${3:-}"
    # Log series identifier. The series is not a separate code path: it is which
    # assignment last wrote current_fp. The caller (process_unread) always passes the
    # unread-set fingerprint from get_unread_info(), so the entry value is the inbox
    # series by construction; the in-lock re-snapshot below may overwrite it with
    # task_publication_fingerprint(), and only that assignment sets fp_kind=task.
    # Never infer the series from the fingerprint text.
    local fp_kind="inbox"
    if [ -z "$current_fp" ] || [ "$current_fp" = "-" ]; then
        fp_kind="none"
    fi
    local priority="${4:-normal}"
    local resnapshot_before_send="${5:-false}"
    local batchable="${6:-false}"
    local delivery_msg_id="${7:-}"
    ensure_current_pane_target || return 1
    if [ "${ASW_DISABLE_ESCALATION:-0}" = "1" ]; then
        echo "[$(date)] [SKIP] Escalation disabled for $AGENT_ID (nudge: inbox${unread_count})" >&2
        return 0
    fi
    local nudge="inbox${unread_count}"
    local task_id=""
    local now
    local last
    local elapsed
    local effective_cli
    local allow_nonempty_input_line=0
    effective_cli=$(get_effective_cli_type)
    if [ "$has_task_assigned" = "true" ] && [ -z "$delivery_msg_id" ]; then
        delivery_msg_id=$(get_single_unread_task_message_id || true)
    fi

    # Codex/non-claude ninja: task_assigned時のみ「前task無効+再読」ナッジを付与してSTALL防止
    # task_info等の補足メッセージでは付与しない（CTX浪費防止）
    # 家老/軍師にはtask YAMLが存在しないため付与しない（2026-04-22 Codex家老バグ修正）
    # 家老/軍師/将軍は忍者 task 規則の対象外(2026-08-28 T122: queue/tasks/karo.yaml が実在するため -f ガードが素通りし、家老が将軍 task_assigned を「現task不一致」で既読化=本日 3 回)
    [[ "$AGENT_ID" != "karo" && "$AGENT_ID" != "gunshi" && "$AGENT_ID" != "shogun" ]] && if [[ "$effective_cli" != "claude" ]] && [[ -f "${SCRIPT_DIR}/queue/tasks/${AGENT_ID}.yaml" ]] && [[ "$has_task_assigned" == "true" ]]; then
        task_id=$(current_task_id_for_nudge || true)
        nudge="${nudge} — task_id=${task_id} 現task YAMLを正本として読み直せ。inboxはread:falseかつ現task_id一致の補足だけを命令として扱い、read:trueまたは別taskのRC/補足は参照しても適用するな"
        [ -n "$delivery_msg_id" ] && nudge+=" delivery_msg=${delivery_msg_id}"
    fi

    # gate_sync手動廃止(2026-05-03): startup gate自動syncに委ねる。nudgeへのgate-sync指示は不要。

    # 家老向け: cmd_new未処理があればnudgeに配備指示を付与（STALL防止）
    if [[ "$AGENT_ID" == "karo" ]]; then
        local _has_cmd_new=0
        _has_cmd_new=$(awk '
            /^- /{block=""; read_state=""}
            /read:[[:space:]]*false/{read_state="unread"}
            /type:.*cmd_new/{if(read_state=="unread"){print 1; exit}}
            END{if(!NR) print 0}
        ' "${SCRIPT_DIR}/queue/inbox/karo.yaml" 2>/dev/null || echo 0)
        if [[ "$_has_cmd_new" == "1" ]]; then
            nudge="${nudge} — CMD受領済み。queue/shogun_to_karo.yaml を読みレビュー+忍者配備を開始せよ"
        fi
    fi

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
        echo "[$(date)] [BUSY] Agent $AGENT_ID is busy or pane state is unknown (no idle flag), Stop hook will deliver" >&2
        return 2
    fi

    if [[ "$effective_cli" != "claude" ]]; then
        local agent_state
        agent_state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || echo "unknown")
        if [[ "$effective_cli" == "codex" ]]; then
            local codex_busy_rc codex_idle_prompt=0
            if codex_explicit_idle_prompt "$PANE_TARGET"; then
                # Explicit Codex idle prompt wins over background-terminal
                # markers.  This releases an old busy claim and permits the
                # queued nudge to cross the delivery boundary exactly once.
                codex_busy_rc=0
                codex_idle_prompt=1
            elif check_agent_busy "$PANE_TARGET" "$AGENT_ID"; then
                codex_busy_rc=0
            else
                codex_busy_rc=$?
            fi
            if [ "$codex_busy_rc" -eq 1 ]; then
                allow_nonempty_input_line=1
                echo "[$(date)] [BUSY-CODEX-QUEUE] Agent $AGENT_ID is actually busy in Codex; sending nudge immediately as queued message" >&2
            else
                # Idle/unknown is a delivery boundary: a previously queued
                # Codex nudge has either become consumable or its CLI
                # generation is no longer trustworthy.
                rm -f "$BUSY_QUEUE_CLAIM_FILE"
            fi
        fi
        if [ "$agent_state" = "active" ] && [ "$allow_nonempty_input_line" != "1" ] && [ "${codex_idle_prompt:-0}" != "1" ]; then
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
                local unread_age
                unread_age=$(get_first_unread_age)
                if [[ "$effective_cli" == "codex" ]]; then
                    allow_nonempty_input_line=1
                    echo "[$(date)] [BUSY-CODEX-QUEUE] Agent $AGENT_ID active+busy in Codex; sending nudge immediately as queued message" >&2
                elif [ "$fp_age" -lt "$busy_max_defer" ] && [ "$unread_age" -lt "$busy_max_defer" ]; then
                    echo "[$(date)] [BUSY] Agent $AGENT_ID is active+busy, deferring nudge (age=${fp_age}s/unread=${unread_age}s < ${busy_max_defer}s)" >&2
                    return 2
                elif [ "$unread_age" -lt "$busy_max_defer" ] || ! priority_deadline_reached "$priority" "$unread_age"; then
                    local priority_deadline
                    priority_deadline=$(priority_deadline_sec "$priority")
                    echo "[$(date)] [BUSY] Agent $AGENT_ID is active+busy, deferring ${priority} nudge (unread=${unread_age}s < deadline=${priority_deadline}s)" >&2
                    return 2
                else
                    echo "[$(date)] [PRIORITY-DEADLINE] Agent $AGENT_ID ${priority} unread ${unread_age}s reached deadline, allowing nudge despite busy state" >&2
                    echo "[$(date)] [BUSY-FORCE] Agent $AGENT_ID active+busy for fp=${fp_age}s unread=${unread_age}s, forcing nudge" >&2
                fi
            elif [ "$busy_rc" -eq 2 ]; then
                local unread_age
                unread_age=$(get_first_unread_age)
                if [ "$fp_age" -lt "$busy_max_defer" ] && [ "$unread_age" -lt "$busy_max_defer" ]; then
                    echo "[$(date)] [BUSY-UNKNOWN] Agent $AGENT_ID active with unknown pane state, deferring nudge (age=${fp_age}s/unread=${unread_age}s < ${busy_max_defer}s)" >&2
                    return 2
                fi
                if [ "$unread_age" -lt "$busy_max_defer" ] || ! priority_deadline_reached "$priority" "$unread_age"; then
                    local priority_deadline
                    priority_deadline=$(priority_deadline_sec "$priority")
                    echo "[$(date)] [BUSY-UNKNOWN] Agent $AGENT_ID active with unknown pane state, deferring ${priority} nudge (unread=${unread_age}s < deadline=${priority_deadline}s)" >&2
                    return 2
                fi
                echo "[$(date)] [PRIORITY-DEADLINE] Agent $AGENT_ID ${priority} unread ${unread_age}s reached deadline, allowing nudge despite unknown busy state" >&2
                echo "[$(date)] [BUSY-UNKNOWN-FORCE] Agent $AGENT_ID active with unknown pane state for fp=${fp_age}s unread=${unread_age}s, forcing nudge" >&2
            fi
        fi
        # @agent_state=idle時にflag補完（flag方式との整合性）
        [ ! -f "$idle_flag" ] && set_idle_flag
    fi

    # Tier 1.5: Debounce repeated nudge storms is enforced by one outstanding
    # lease per CLI generation and current-task assignment-ID set. Unrelated
    # unread rows cannot expire a task lease; a new current-task ID can.
    # The check and claim decision share one flock.
    local current_task_fp="-"
    if [ "$has_task_assigned" = "true" ]; then
        current_task_fp=$(current_task_assignment_fingerprint 2>/dev/null || printf '%s' '-')
    fi

    if [ -n "$current_fp" ] && [ "$current_fp" != "-" ]; then
        local atomic_result decision log_line atomic_result_file
        atomic_result_file="${STATE_DIR}/inbox_watcher_atomic_result_${AGENT_ID}_${BASHPID}"
        if ! (
            flock -w 5 201 || { echo "error	STATE_LOCK_TIMEOUT"; exit 1; }

            _now="$EPOCHSECONDS"

            # A changed unread set is only diagnostic while the same CLI
            # generation owns a lease, except for a new current-task
            # assignment-ID set, which is a new delivery obligation.
            _prev_fp=""
            if [ -f "$FINGERPRINT_FILE" ]; then
                IFS= read -r _prev_fp < "$FINGERPRINT_FILE" 2>/dev/null || true
            fi

            if [ "$current_fp" != "$_prev_fp" ]; then
                printf '%s' "$current_fp" > "$FINGERPRINT_FILE"
                printf '%s' "$_now" > "$DEBOUNCE_FILE"
                echo "[$(date)] [FP-OBSERVED] Unread set changed for $AGENT_ID ($unread_count unread); evaluating generation lease" >&2
            fi

            # Preserve the legacy debounce timestamp for diagnostics. It is no
            # longer a send gate: the generation lease is the sole normal-path
            # duplicate barrier.
            if [ -f "$DEBOUNCE_FILE" ]; then
                _last=""
                IFS= read -r _last < "$DEBOUNCE_FILE" 2>/dev/null || true
            fi

            _lease_file="$(current_outstanding_lease_file 2>/dev/null || true)"
            # A self-restarted watcher inherits the CLI generation.  Migrate
            # only the matching legacy fingerprint token before evaluating the
            # generation lease, so restart does not paste a duplicate nudge.
            migrate_legacy_fingerprint_lease "$current_fp" "$unread_count" "${CURRENT_CLI_GENERATION:-}" "$current_task_fp" >/dev/null || true
            _lease_expired=0
            if [ -n "$_lease_file" ] && [ -e "$_lease_file" ] && [ "$current_task_fp" != "-" ]; then
                _lease_scope_fp=""
                IFS=$'\t' read -r _lease_generation _lease_count _lease_scope_fp _lease_inbox_fp < "$_lease_file" 2>/dev/null || true
                if [ "$_lease_scope_fp" != "$current_task_fp" ]; then
                    rm -f -- "$_lease_file"
                    _lease_expired=1
                    printf 'send\t[TASK-LEASE-EXPIRED] New current-task unread ID set for %s generation=%s\n' "$AGENT_ID" "${CURRENT_CLI_GENERATION:-unknown}" > "$atomic_result_file"
                fi
            fi
            if [ "$_lease_expired" -eq 0 ] && [ -n "$_lease_file" ] && [ -e "$_lease_file" ]; then
                # 2026-09-01 根治(v2 家老RC対応): 4列目inbox_fpで比較。
                # 3列目=lease_scope_fp(task-bound時はtask_fp)、4列目=inbox_fp。
                # task_scope変更はL1191-1198で処理済み。ここではinbox fp変更のみ判定。
                local _lease_stored_inbox_fp=""
                IFS=$'\t' read -r _ _ _ _lease_stored_inbox_fp < "$_lease_file" 2>/dev/null || true
                # 3列leaseの4列目は空。expire+再送で4列へupgrade(家老RC2 2026-09-01)
                if [ -z "$_lease_stored_inbox_fp" ] || [ "$_lease_stored_inbox_fp" = "-" ]; then
                    rm -f -- "$_lease_file"
                    _lease_expired=1
                    printf 'send\t[LEASE-UPGRADE] 3-col lease upgraded to 4-col for %s; resending\n' "$AGENT_ID" > "$atomic_result_file"
                elif [ "$_lease_stored_inbox_fp" != "$current_fp" ]; then
                    rm -f -- "$_lease_file"
                    _lease_expired=1
                    printf 'send\t[LEASE-RENEWED] Fingerprint changed for %s: %s→%s; renewing lease\n' "$AGENT_ID" "${_lease_stored_inbox_fp:0:16}" "${current_fp:0:16}" > "$atomic_result_file"
                else
                    printf 'skip\t[OUTSTANDING-LEASE] Suppressing normal nudge for %s generation=%s until unread=0, generation-change, or current-task-set-change\n' "$AGENT_ID" "${CURRENT_CLI_GENERATION:-unknown}" > "$atomic_result_file"
                fi
            elif [ "$_lease_expired" -eq 0 ]; then
                printf 'send\t[LEASE-AVAILABLE] Claiming normal nudge for %s generation=%s\n' "$AGENT_ID" "${CURRENT_CLI_GENERATION:-unknown}" > "$atomic_result_file"
            fi
        ) 201>"$STATE_LOCK_FILE"; then
            echo "[$(date)] WARNING: atomic wakeup state update failed for $AGENT_ID" >&2
            return 1
        fi
        atomic_result="$(cat "$atomic_result_file" 2>/dev/null || true)"
        rm -f "$atomic_result_file"
        decision="${atomic_result%%$'\t'*}"
        log_line="${atomic_result#*$'\t'}"
        [ -n "$log_line" ] && echo "[$(date)] $log_line" >&2
        [ "$decision" = "send" ] || return 0
    else
        if [ -f "$DEBOUNCE_FILE" ]; then
            last=""
            IFS= read -r last < "$DEBOUNCE_FILE" 2>/dev/null || true
            if [[ "$last" =~ ^[0-9]+$ ]]; then
                now="$EPOCHSECONDS"
                elapsed=$((now - last))
                if [ "$elapsed" -lt "$DEBOUNCE_SEC" ]; then
                    echo "[$(date)] [DEBOUNCE] Skipping nudge (${elapsed}s < ${DEBOUNCE_SEC}s) for $AGENT_ID" >&2
                    return 0
                fi
            fi
        fi
    fi

    # Tier 2: paste-buffer nudge (replaces send-keys for content)
    echo "[$(date)] [NUDGE] Sending paste-buffer nudge to $AGENT_ID" >&2

    # Optimistic lock: update debounce BEFORE send to prevent concurrent nudges.
    # Normal nudges already updated this in the atomic block above.
    if [ -z "$current_fp" ] || [ "$current_fp" = "-" ]; then
        if ! refresh_debounce_file; then
            echo "[$(date)] WARNING: failed to update debounce file: $DEBOUNCE_FILE" >&2
        fi
    fi

    # Send nudge via paste-buffer + Enter (atomic lock). The inbox may have
    # changed while this wake waited behind a busy Codex turn or another sender.
    # Re-snapshot under the send lock so stale generations coalesce on the
    # current unread fingerprint/count instead of pasting old inboxN values.
    # Note: Pre-clear Enter was removed — idle flag guarantees empty prompt,
    # and Enter risked submitting partial input in race conditions.
    local lock
    lock="${STATE_DIR}/tmux_sendkeys_$(echo "$PANE_TARGET" | tr ':.' '_').lock"
    local send_rc=0 send_result_file send_result send_outcome sent_count sent_fp sent_kind
    send_result_file="${STATE_DIR}/inbox_watcher_send_result_${AGENT_ID}_${BASHPID}"
    echo "[$(date)] [SEND-RESULT] attempted agent=$AGENT_ID observed_count=$unread_count fingerprint=$current_fp kind=$fp_kind" >&2
    (
        flock -w 5 200 || { echo "[$(date)] LOCK TIMEOUT: send_wakeup $PANE_TARGET" >&2; exit 1; }
        if [ "$resnapshot_before_send" = "true" ]; then
            local live_info live_count live_has_specials live_fp live_specials_b64 live_has_task live_priority
            live_info=$(get_unread_info)
            IFS=$'\t' read -r live_count live_has_specials live_fp live_specials_b64 live_has_task live_priority <<< "$live_info"
            live_count="${live_count:-0}"
            live_fp="${live_fp:--}"
            live_has_task="${live_has_task:-false}"
            if [ "$live_count" -eq 0 ] 2>/dev/null; then
                printf 'coalesced-empty\t0\t-\tnone\n' > "$send_result_file"
                exit 0
            fi
            unread_count="$live_count"
            current_fp="$live_fp"
            fp_kind="inbox"
            if [ "$live_has_task" = "true" ]; then
                current_task_fp=$(current_task_assignment_fingerprint 2>/dev/null || printf '%s' '-')
                current_fp=$(task_publication_fingerprint "$live_fp" 2>/dev/null || printf '%s' "$live_fp")
                [ "$current_fp" = "$live_fp" ] || fp_kind="task"
            fi
            nudge="inbox${unread_count}"
            # 家老/軍師/将軍は忍者 task 規則の対象外(T122、上と同じ)
            [[ "$AGENT_ID" != "karo" && "$AGENT_ID" != "gunshi" && "$AGENT_ID" != "shogun" ]] && if [[ "$effective_cli" != "claude" ]] && [[ -f "${SCRIPT_DIR}/queue/tasks/${AGENT_ID}.yaml" ]] && [[ "$live_has_task" == "true" ]]; then
                task_id=$(current_task_id_for_nudge || true)
                nudge="${nudge} — task_id=${task_id} 現task YAMLを正本として読み直せ。inboxはread:falseかつ現task_id一致の補足だけを命令として扱い、read:trueまたは別taskのRC/補足は参照しても適用するな"
                delivery_msg_id=$(get_single_unread_task_message_id || true)
                [ -n "$delivery_msg_id" ] && nudge+=" delivery_msg=${delivery_msg_id}"
            fi
        fi

        local sent_token=""
        if [ "$allow_nonempty_input_line" = "1" ]; then
            local claim_generation claim_fp="" claim_epoch="" claim_age=0
            claim_generation=$(respawn_recovery_generation "$PANE_TARGET" 2>/dev/null || true)
            if [ -f "$BUSY_QUEUE_CLAIM_FILE" ]; then
                local stored_generation=""
                IFS=$'\t' read -r stored_generation claim_fp claim_epoch < "$BUSY_QUEUE_CLAIM_FILE" 2>/dev/null || true
                [[ "$claim_epoch" =~ ^[0-9]+$ ]] && claim_age=$((EPOCHSECONDS - claim_epoch))
                if [ -n "$stored_generation" ] && [ "$stored_generation" = "$claim_generation" ] && [ "$claim_age" -lt "$BACKOFF_SEC" ]; then
                    record_deferred_nudge "$current_fp" "busy_queue_singleflight"
                    printf 'busy-coalesced\t%s\t%s\t%s\n' "$unread_count" "$current_fp" "$fp_kind" > "$send_result_file"
                    exit 0
                fi
                echo "[$(date)] [BUSY-QUEUE-STALE] Reclaiming stale queued nudge for $AGENT_ID generation=${stored_generation:-unknown}->${claim_generation:-unknown} age=${claim_age}s" >&2
            fi
            printf '%s\t%s\t%s\n' "$claim_generation" "$current_fp" "$EPOCHSECONDS" > "$BUSY_QUEUE_CLAIM_FILE"
            echo "[$(date)] [BUSY-QUEUE-CLAIM] Claimed single queued nudge for $AGENT_ID fingerprint=$current_fp generation=${claim_generation:-unknown}" >&2
        fi
        if [ -n "$current_fp" ] && [ "$current_fp" != "-" ]; then
            local safe_fp sent_token sent_mtime sent_elapsed lease_generation lease_scope_fp
            # Normal/high nudges are leased by CLI generation. For task-bound
            # messages, the lease scope is the current-task assignment-ID set;
            # inbox_write.sh rearm preserves it so retries cannot duplicate.
            lease_generation=$(respawn_recovery_generation "$PANE_TARGET" 2>/dev/null || true)
            lease_generation="${lease_generation:-${CURRENT_CLI_GENERATION:-}}"
            if [ -n "$lease_generation" ]; then
                sent_token="$(outstanding_lease_file_for_generation "$lease_generation")"
            fi
            if [ -z "$sent_token" ]; then
                # Compatibility fallback for an unavailable generation: retain
                # the old fingerprint lease rather than sending unboundedly.
                safe_fp="${current_fp//[^A-Za-z0-9_.-]/_}"
                sent_token="${STATE_DIR}/inbox_watcher_sent_${AGENT_ID}_${safe_fp}"
            fi
            if ! ( set -C; : > "$sent_token" ) 2>/dev/null; then
                # 2026-09-01 根治: leaseファイル内のfingerprintと現在のfingerprintを比較。
                # fingerprintが変わった=新しい未読が追加された→leaseを解放して再送する。
                # 同一fingerprintならdedup(既に送信済み)。
                local _lease_stored_inbox_fp2=""
                if [ -n "$lease_generation" ] && [ -f "$sent_token" ]; then
                    IFS=$'\t' read -r _ _ _ _lease_stored_inbox_fp2 < "$sent_token" 2>/dev/null || true
                fi
                if [ -n "$_lease_stored_inbox_fp2" ] && [ "$_lease_stored_inbox_fp2" != "$current_fp" ] && [ "$_lease_stored_inbox_fp2" != "-" ]; then
                    rm -f "$sent_token" 2>/dev/null || true
                    if ( set -C; : > "$sent_token" ) 2>/dev/null; then
                        echo "[$(date)] [LEASE-RENEWED] Fingerprint changed for $AGENT_ID: ${_lease_stored_inbox_fp2:0:16}→${current_fp:0:16}; renewing lease and resending" >&2
                    else
                        echo "[$(date)] [LEASE-RENEW-RACE] $AGENT_ID concurrent renewal; deferring" >&2
                        printf 'dedup\t%s\t%s\t%s\n' "$unread_count" "$current_fp" "$fp_kind" > "$send_result_file"
                        exit 0
                    fi
                else
                    if [ -n "$lease_generation" ]; then
                        echo "[$(date)] [OUTSTANDING-LEASE] Skipping ${priority} nudge for $AGENT_ID until unread=0, generation-change, or current-task-set-change: generation=$lease_generation fingerprint=$current_fp" >&2
                    else
                        echo "[$(date)] [SEND-LEASE] Skipping delivered fingerprint for $AGENT_ID until ACK/set change: $current_fp kind=$fp_kind" >&2
                    fi
                    printf 'dedup\t%s\t%s\t%s\n' "$unread_count" "$current_fp" "$fp_kind" > "$send_result_file"
                    exit 0
                fi
            fi
            if [ -n "$lease_generation" ]; then
                # Persist the observed unread count with the lease so a later
                # read transition can be recognized as an ACK even when other
                # unread messages remain.
                lease_scope_fp="$current_fp"
                if [ "$current_task_fp" != "-" ]; then
                    lease_scope_fp="$current_task_fp"
                fi
                printf '%s\t%s\t%s\t%s\n' "$lease_generation" "$unread_count" "$lease_scope_fp" "$current_fp" > "$sent_token"
            fi
        fi
        # Force-exit copy-mode if active (mouse scroll → copy-mode → nudge配信失敗を防止)
        local in_mode
        in_mode=$(tmux display-message -t "$PANE_TARGET" -p '#{pane_in_mode}' 2>/dev/null || echo "0")
        if [ "$in_mode" = "1" ]; then
            tmux send-keys -t "$PANE_TARGET" -X cancel 2>/dev/null || true
            sleep 0.3
            echo "[$(date)] [COPY-MODE] Exited copy-mode for $AGENT_ID before nudge" >&2
        fi
        # Never paste a nudge into an interactive confirmation prompt. The
        # prompt may consume the nudge as its Yes/No choice. Keep the inbox
        # unread and persist one deferred record so the normal retry path can
        # deliver after the prompt is resolved.
        if _pane_has_confirmation_prompt "$PANE_TARGET"; then
            [ -n "$sent_token" ] && rm -f "$sent_token" 2>/dev/null || true
            record_deferred_nudge "$current_fp" "confirmation_prompt"
            rm -f "$FINGERPRINT_FILE" "$DEBOUNCE_FILE" 2>/dev/null || true
            echo "[$(date)] [CONFIRMATION-GUARD] Deferring nudge for $AGENT_ID: confirmation prompt active nudge=0 unread=${unread_count} held=1" >&2
            exit 2
        fi
        if [ "$allow_nonempty_input_line" != "1" ] && pane_input_line_has_text "$PANE_TARGET" "$effective_cli"; then
            [ -n "$sent_token" ] && rm -f "$sent_token" 2>/dev/null || true
            record_deferred_nudge "$current_fp" "input_guard"
            rm -f "$FINGERPRINT_FILE" "$DEBOUNCE_FILE" 2>/dev/null || true
            echo "[$(date)] [INPUT-GUARD] Deferring nudge for $AGENT_ID: pane input line is not empty" >&2
            exit 2
        elif [ "$allow_nonempty_input_line" = "1" ]; then
            echo "[$(date)] [INPUT-GUARD-BYPASS] $AGENT_ID is Codex active+busy; queueing nudge despite non-empty generated UI line" >&2
        fi
        if [ "$effective_cli" = "claude" ]; then
            if ! claim_idle_delivery; then
                echo "[$(date)] [LIFECYCLE-GUARD] Deferring nudge for $AGENT_ID: idle claim was not valid" >&2
                exit 2
            fi
        fi
        tmux set-buffer -b "nudge_${AGENT_ID}" "$nudge"
        if ! timeout "$SEND_KEYS_TIMEOUT" tmux paste-buffer -t "$PANE_TARGET" -b "nudge_${AGENT_ID}" -d 2>/dev/null; then
            [ "$effective_cli" = "claude" ] && restore_idle_delivery || true
            [ -n "$sent_token" ] && rm -f "$sent_token" 2>/dev/null || true
            echo "[$(date)] WARNING: paste-buffer timed out ($SEND_KEYS_TIMEOUT s)" >&2
            exit 1
        fi
        sleep 0.5
        if ! timeout "$SEND_KEYS_TIMEOUT" tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null; then
            [ "$effective_cli" = "claude" ] && restore_idle_delivery || true
            [ -n "$sent_token" ] && rm -f "$sent_token" 2>/dev/null || true
            echo "[$(date)] WARNING: send-keys Enter timed out ($SEND_KEYS_TIMEOUT s)" >&2
            exit 1
        fi
        printf 'pasted\t%s\t%s\t%s\n' "$unread_count" "$current_fp" "$fp_kind" > "$send_result_file"
    ) 200>"$lock" || send_rc=$?
    if [ "$send_rc" -eq 2 ]; then
        return 2
    elif [ "$send_rc" -ne 0 ]; then
        rm -f "$send_result_file"
        return 1
    fi

    send_result=$(cat "$send_result_file" 2>/dev/null || true)
    rm -f "$send_result_file"
    IFS=$'\t' read -r send_outcome sent_count sent_fp sent_kind <<< "$send_result"
    case "$send_outcome" in
        dedup)
            echo "[$(date)] [SEND-RESULT] dedup agent=$AGENT_ID current_count=$sent_count fingerprint=$sent_fp kind=${sent_kind:-none}" >&2
            return 0
            ;;
        busy-coalesced)
            echo "[$(date)] [BUSY-QUEUE-COALESCE] Deferred changed unread set for $AGENT_ID fingerprint=$sent_fp; queued nudge already exists" >&2
            return 2
            ;;
        coalesced-empty)
            echo "[$(date)] [SEND-RESULT] dedup agent=$AGENT_ID current_count=0 fingerprint=- reason=no-unread kind=none" >&2
            return 0
            ;;
        pasted)
            unread_count="$sent_count"
            current_fp="$sent_fp"
            fp_kind="${sent_kind:-none}"
            echo "[$(date)] [SEND-RESULT] pasted agent=$AGENT_ID current_count=$sent_count fingerprint=$sent_fp kind=${sent_kind:-none}" >&2
            ;;
        *)
            echo "[$(date)] WARNING: missing send result for $AGENT_ID" >&2
            return 1
            ;;
    esac

    clear_deferred_nudge

    # AC1(cmd_3646): busy gatingで保留された場合の「保留開始(first-unread)→実配達完了」レイテンシを記録。
    # first_unread_seenはfingerprint再作成に影響されない一次時刻(L841)なので、複数回deferしても保留開始時刻を維持する。
    local _delivery_latency_sec
    _delivery_latency_sec=$(get_first_unread_age)
    echo "[$(date)] [DELIVERY-LATENCY] $AGENT_ID: ${_delivery_latency_sec}s from first-unread to delivery (${unread_count} unread)" >&2
    if [ "$_delivery_latency_sec" -ge "$DELIVERY_LATENCY_WARN_SEC" ]; then
        echo "[$(date)] [DELIVERY-LATENCY-WARN] $AGENT_ID: held ${_delivery_latency_sec}s >= ${DELIVERY_LATENCY_WARN_SEC}s threshold (busy gating tail latency)" >&2
    fi

    echo "[$(date)] Wake-up sent to $AGENT_ID (${unread_count} unread via paste-buffer)" >&2
    return 0
}



# ─── Process cycle ───
record_info_autoack_gate() {
    local result="$1" detail="$2" gate_log="${INBOX_INFO_GATE_LOG:-$SCRIPT_DIR/logs/gate_fire_log.yaml}"
    detail="${detail//\"/_}"
    mkdir -p "${gate_log%/*}"
    { flock 9; printf '%s\n' "- ts: \"$(date -Iseconds)\", gate: inbox_info_digest_autoack, result: ${result}, detail: \"${detail}\"" >&9; } 9>>"$gate_log"
}

# A verified CLI generation is the commit point for clear_command delivery.
# Recovery notification is a follow-up signal: failure must be visible, but it
# must not roll back the already successful clear or leave the command unread.
finalize_clear_command() {
    local ready="$1" recovery_content="${2:-}" generation=""
    if [ "$ready" -ne 1 ]; then
        echo "[$(date)] [WARN] clear_command verification failed: $AGENT_ID ready=0; leaving unread for retry" >&2
        return 1
    fi

    generation=$(respawn_recovery_generation "$PANE_TARGET" 2>/dev/null || true)
    echo "[$(date)] [OK] clear_command verified: $AGENT_ID generation=$generation ready=1" >&2
    if [ -z "$generation" ] || ! respawn_recovery_notify "$SCRIPT_DIR" "$AGENT_ID" "$generation" clear-command "$recovery_content"; then
        echo "[$(date)] [WARN] clear_command recovery notification failed: $AGENT_ID generation=${generation:-unknown}; clear remains acknowledged" >&2
    fi
    return 0
}

process_unread() {
    # Invalidate delivery leases on CLI generation change (respawn/clear)
    invalidate_leases_on_generation_change

    # Persist judgment-free informational messages before acknowledging them.
    # Failure is fail-closed: messages remain unread and enter the normal nudge path.
    local auto_info_output="" auto_info_rc=0
    auto_info_output=$(bash "$SCRIPT_DIR/scripts/inbox_mark_read.sh" "$AGENT_ID" --auto-info 2>&1) || auto_info_rc=$?
    if [ "$auto_info_rc" -ne 0 ]; then
        record_info_autoack_gate BLOCK "agent=${AGENT_ID} rc=${auto_info_rc} digest_failed=1 auto_ack=0"
        echo "[$(date)] [BLOCK] info digest auto-ack failed for $AGENT_ID; leaving unread" >&2
    elif [[ "$auto_info_output" != *"eligible=0"* ]]; then
        local auto_ack_count=0
        auto_ack_count=$(printf '%s\n' "$auto_info_output" | sed -n 's/.*Marked \([0-9][0-9]*\) message.*/\1/p' | tail -1)
        auto_ack_count="${auto_ack_count:-0}"
        record_info_autoack_gate PASS "agent=${AGENT_ID} digest_success=${auto_ack_count} auto_ack=${auto_ack_count} false_positive=0"
    fi
    # Single parser call: TAB-separated "count \t has_specials \t fingerprint \t specials_b64 \t has_task_assigned \t priority \t batchable"
    local raw_info
    raw_info=$(get_unread_info)
    local normal_count has_specials _current_fp specials_b64 has_task_assigned priority batchable
    IFS=$'\t' read -r normal_count has_specials _current_fp specials_b64 has_task_assigned priority batchable <<< "$raw_info"
    normal_count="${normal_count:-0}"
    has_specials="${has_specials:-false}"
    has_task_assigned="${has_task_assigned:-false}"
    priority="${priority:-normal}"
    batchable="${batchable:-false}"

    if [ "$normal_count" -gt 0 ] 2>/dev/null || [ "$has_specials" = "true" ]; then
        mark_first_unread_seen
    fi
    # NOTE: clear_first_unread_seen() for the normal_count==0 case is handled
    # below in the "No unread" branch (same condition), avoiding a duplicate call.

    # Handle special CLI commands first (/clear, /model)
    local specials=""
    if [ "$has_specials" = "true" ] && [ -n "$specials_b64" ] && [ "$specials_b64" != "-" ]; then
        specials=$(printf '%s' "$specials_b64" | base64 -d 2>/dev/null || true)
    fi

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
                    # clear_commandはbusy gatingをバイパスする。
                    # 停止命令がbusy判定でブロックされるのは論理矛盾。
                    # バックグラウンドshellが残っている場合でも/clearを強制送信する。
                    echo "[$(date)] [CLEAR-FORCE] clear_command received for $AGENT_ID — bypassing busy gating" >&2

                    recovery_content="$special_content"
                    if [ -n "$recovery_content" ] && [[ "$recovery_content" =~ [\`\$\|\;\&\<\>] ]]; then
                        echo "[$(date)] [SECURITY] clear_command content rejected (shell metacharacters): ${recovery_content:0:80}" >&2
                        recovery_content=""
                    fi

                    # Tests and isolated recovery probes may provide the exact
                    # executable boundary explicitly. Production leaves this
                    # unset and continues to resolve the CLI from its SSOT.
                    launch="${RESPAWN_RECOVERY_LAUNCH_OVERRIDE:-}"
                    [ -n "$launch" ] || launch=$(cli_launch_cmd "$AGENT_ID" 2>/dev/null || true)
                    launch_command=$(respawn_recovery_launch_command "$SCRIPT_DIR" "$launch" 2>/dev/null || true)
                    if [ -z "$launch_command" ] || ! tmux respawn-pane -k -t "$PANE_TARGET" "$launch_command" 2>/dev/null; then
                        special_ok=false
                    else
                        ready=0
                        for _ in {1..30}; do
                            if respawn_recovery_ready "$PANE_TARGET"; then ready=1; break; fi
                            sleep 1
                        done
                        if ! finalize_clear_command "$ready" "$recovery_content"; then
                            special_ok=false
                        fi
                    fi
                    ;;
                model_switch)
                    # Whitelist: only /model <known-provider-prefix> allowed
                    _model_input_re="^/model[[:space:]]+(claude-|${MODEL_FAMILY_TOKEN_GPT}-|o[0-9]|${MODEL_FAMILY_OPUS}|${MODEL_FAMILY_TOKEN_SONNET}|${MODEL_FAMILY_HAIKU})"
                    if [[ "$special_content" =~ $_model_input_re ]]; then
                        if ! send_cli_command "$special_content"; then
                            special_ok=false
                        fi
                    else
                        echo "[$(date)] [SECURITY] model_switch content rejected (not whitelisted): ${special_content:0:80}" >&2
                        special_ok=true  # mark read to prevent retry loop
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
        local wake_rc=0
        send_wakeup "$normal_count" "$has_task_assigned" "$_current_fp" "$priority" true "$batchable" || wake_rc=$?
        if [ "$wake_rc" -eq 2 ]; then
            echo "[$(date)] [WAKE-DEFER] Deferred nudge for $AGENT_ID (busy gating)" >&2
        fi
    else
        # No unread → clear fingerprint
        if [ -f "$FINGERPRINT_FILE" ]; then
            rm -f "$FINGERPRINT_FILE"
            echo "[$(date)] [FP-RESET] No unread, cleared fingerprint for $AGENT_ID" >&2
        fi
        # An empty inbox is the only normal-path acknowledgement boundary.
        # Clear every lease variant (including a lease created without a
        # fingerprint file) so the next unread set can claim one delivery.
        rm -f "${STATE_DIR}/inbox_watcher_sent_fingerprint_${AGENT_ID}"
        rm -f "${STATE_DIR}/inbox_watcher_sent_${AGENT_ID}_"*
        clear_deferred_nudge
        rm -f "$BUSY_QUEUE_CLAIM_FILE"
        clear_first_unread_seen
    fi
}

if [ "${INBOX_WATCHER_LIB_ONLY:-0}" = "1" ]; then
    # shellcheck disable=SC2317
    return 0 2>/dev/null || exit 0
fi

# Agent-level singleton: two watchers for the same agent race on fingerprint and
# debounce state, so the second process exits before observing inbox events.
exec 209>"$SINGLETON_LOCK_FILE"
if ! flock -n 209; then
    echo "[$(date)] inbox_watcher already running for $AGENT_ID; exiting duplicate" >&2
    exit 0
fi
SCRIPT_UPDATE_SINGLETON_FD=209

# ─── Startup: ensure @agent_state is initialized (deadlock prevention) ───
# If @agent_state is not set (fresh pane, after reset), initialize to idle.
# Without this, a missing state would be treated as "unknown" and nudges
# would still be sent, but explicit initialization prevents ambiguity.
_startup_state=$(tmux display-message -t "$PANE_TARGET" -p '#{@agent_state}' 2>/dev/null || echo "")
if [ -z "$_startup_state" ]; then
    tmux set-option -p -t "$PANE_TARGET" @agent_state idle 2>/dev/null || true
    echo "[$(date)] Initialized @agent_state=idle for $AGENT_ID" >&2
fi

# ─── Cleanup trap: safely kill child processes on exit ───
cleanup_inbox_watcher() {
    # Kill any remaining child processes (e.g., inotifywait)
    local child_pids
    child_pids=$(jobs -p 2>/dev/null || true)
    for pid in $child_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    echo "[$(date)] inbox_watcher exiting for $AGENT_ID" >&2
}
trap cleanup_inbox_watcher EXIT

# ─── Startup: process any existing unread messages ───
process_unread

# ─── Main loop: event-driven via inotifywait ───
# Timeout 60s: WSL2 /mnt/c/ can miss inotify events.
# On timeout (exit 2), check for unread messages as a safety net.
INOTIFY_TIMEOUT="${INOTIFY_TIMEOUT:-60}"
MTIME_POLL_INTERVAL="${MTIME_POLL_INTERVAL:-3}"  # MTIME_POLL: seconds between stat mtime checks (10→3: 殿指摘 inbox遅延改善)

# Initialize mtime baseline for MTIME_POLL fallback
LAST_MTIME=$(stat -c %Y "$INBOX" 2>/dev/null || echo 0)

while true; do
    # Start inotifywait in background to allow parallel MTIME_POLL
    # set +e: inotifywait returns 2 on timeout, which would kill script under set -e
    # outer timeout: WSL2 DrvFs bug — when inbox_write.sh atomically replaces the file
    #   (os.replace = rename), inotifywait loses the inode and its -t timeout can hang
    #   indefinitely (3-hour blank confirmed). The outer `timeout` provides an OS-level safety net.
    set +e
    timeout "$((INOTIFY_TIMEOUT + 2))" inotifywait -q -t "$INOTIFY_TIMEOUT" -e modify -e close_write "$INBOX" 2>/dev/null 209>&- &
    INOTIFY_PID=$!

    # MTIME_POLL: parallel stat mtime poller — WSL2 inotifywait hang fallback
    # If mtime changes but inotifywait is hung, kill it to unblock within MTIME_POLL_INTERVAL seconds.
    # rc=0: event, rc=1: watch invalidated (atomic write), rc=2: timeout
    # rc=124: outer timeout killed inotifywait (WSL2 DrvFs inode-replace hang)
    # MTIME_POLL kill: mtime changed while inotifywait hung — force unblock
    (
        while kill -0 "$INOTIFY_PID" 2>/dev/null; do
            sleep "$MTIME_POLL_INTERVAL"
            CURRENT_MTIME=$(stat -c %Y "$INBOX" 2>/dev/null || echo 0)
            if [[ "$CURRENT_MTIME" != "$LAST_MTIME" ]]; then
                kill "$INOTIFY_PID" 2>/dev/null || true
                break
            fi
        done
    ) 209>&- &
    POLLER_PID=$!

    wait "$INOTIFY_PID" 2>/dev/null || true
    kill "$POLLER_PID" 2>/dev/null || true
    wait "$POLLER_PID" 2>/dev/null || true
    set -e

    # rc=0: event fired (instant delivery)
    # rc=1: watch invalidated — Claude Code uses atomic write (tmp+rename),
    #        which replaces the inode. inotifywait sees DELETE_SELF → rc=1.
    #        File still exists with new inode. Treat as event, re-watch next loop.
    # rc=2: timeout (60s safety net for WSL2 inotify gaps)
    # All cases: check for unread, then loop back to inotifywait (re-watches new inode)

    # Update mtime baseline for next MTIME_POLL iteration
    LAST_MTIME=$(stat -c %Y "$INBOX" 2>/dev/null || echo 0)

    sleep 2  # coalesce rapid-fire events (e.g. screenshot+ntfy 1sec apart → single nudge)

    process_unread
    check_script_update "$AGENT_ID" "$PANE_TARGET"

    # Heartbeat: daemon_watchdog.sh がhang検知に使う
    # $EPOCHSECONDS: bash 5+組込み変数。date +%sと同一形式でsubprocess forkを回避
    printf '%s\n' "$EPOCHSECONDS" > "$LOOP_HEARTBEAT_FILE"
done
