#!/usr/bin/env bash
# semantic-links: [[デーモン監視と復旧]]
# =============================================================================
# daemon_watchdog.sh — デーモン死活監視+自動再起動
# cronから毎分実行。PIDベースの生存確認でデーモンを再起動する。
#
# 監視対象:
#   - ninja_monitor.sh   (単一インスタンス)
#   - ntfy_listener.sh   (単一インスタンス、自身もflock持ち)
#   - inbox_watcher.sh   (エージェント毎に1プロセス、計10)
#
# Usage:
#   bash scripts/daemon_watchdog.sh          # 手動実行
#   * * * * * bash /path/to/scripts/daemon_watchdog.sh
# =============================================================================
set -uo pipefail
# NOTE: set -e を外した(2026-04-16 GP-204)。個別チェック関数の失敗で全体が死ぬと
# 後続デーモンの監視がスキップされる。各関数内で個別にエラーハンドリングする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/daemon_watchdog.log"
HEARTBEAT_FILE="${DAEMON_WATCHDOG_HEARTBEAT_FILE:-/tmp/daemon_watchdog_heartbeat}"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/daemon_maintenance_lock.sh"

close_inherited_restart_watchers_lock() {
    local lock_path="${RESTART_WATCHERS_LOCK_FILE:-/tmp/restart_watchers.lock}"
    local fd_path fd target
    for fd_path in /proc/$$/fd/*; do
        fd="${fd_path##*/}"
        [[ "$fd" =~ ^[0-9]+$ && "$fd" != 0 && "$fd" != 1 && "$fd" != 2 ]] || continue
        target="$(readlink "$fd_path" 2>/dev/null || true)"
        [[ "$target" == "$lock_path" ]] || continue
        eval "exec ${fd}>&-"
    done
}
close_inherited_restart_watchers_lock

restart_watchers_lock_is_active() {
    local lock_path="$1"
    local pid cmd
    flock -n "$lock_path" -c ':' 2>/dev/null && return 1
    for pid in $(fuser "$lock_path" 2>/dev/null || true); do
        cmd="$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
        [[ "$cmd" == *"/scripts/restart_watchers.sh"* ]] && return 0
    done
    return 2
}

# 多重起動防止: 手動実行時も短時間で完了するため内部lockは持たない。
# 各デーモンの重複防止はPIDファイル/プロセス生存確認に寄せる。

LOG_DIR_READY=0
RESTART_STATE_DIR_READY=0

ensure_log_dir() {
    if (( LOG_DIR_READY == 0 )); then
        mkdir -p "$(dirname "$LOG")"
        LOG_DIR_READY=1
    fi
}

ensure_restart_state_dir() {
    if (( RESTART_STATE_DIR_READY == 0 )); then
        mkdir -p "$RESTART_STATE_DIR"
        RESTART_STATE_DIR_READY=1
    fi
}

# ログローテーション: 1MB超過時に末尾500行を残して切り詰め
rotate_log() {
    ensure_log_dir
    local max_bytes=1048576  # 1MB
    if [[ -f "$LOG" ]]; then
        local size
        size=$(stat -c%s "$LOG" 2>/dev/null) || return 0
        if (( size > max_bytes )); then
            local tmp="${LOG}.tmp"
            tail -n 500 "$LOG" > "$tmp" && mv "$tmp" "$LOG"
        fi
    fi
}

log() {
    ensure_log_dir
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

notify() {
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "$1" >/dev/null 2>&1 || true
}

check_tmux_health() {
    if tmux list-sessions >/dev/null 2>&1; then
        return 0
    fi
    local message="TMUX-HEALTH-ALERT: tmux list-sessions failed; all agent watchers may be unavailable"
    log "$message"
    notify "【watchdog/CRITICAL】tmux server異常。全watcher/monitor停止の可能性あり"
    printf '%s\n' "$message"
    return 1
}

# Return the live Unix-socket inventory reported by the kernel.  The file
# override keeps the parser independently testable without creating or
# stopping a tmux server.
daemon_watchdog_tmux_socket_snapshot() {
    if [[ -n "${DAEMON_WATCHDOG_TMUX_SS_OUTPUT_FILE:-}" ]]; then
        cat "$DAEMON_WATCHDOG_TMUX_SS_OUTPUT_FILE" 2>/dev/null || true
        return 0
    fi
    command -v ss >/dev/null 2>&1 || return 0
    ss -xlp 2>/dev/null || true
}

# Print one `socket|pid` record per tmux server.  Only rows with the kernel's
# tmux server owner annotation are accepted; a generic process listing is not
# evidence of a listening server.
daemon_watchdog_tmux_server_records() {
    daemon_watchdog_tmux_socket_snapshot | awk '
        /users:\(\("tmux: server",pid=[0-9]+/ {
            prefix = substr($0, 1, index($0, "users:") - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", prefix)
            n = split(prefix, fields, /[[:space:]]+/)
            socket = ""
            for (i = n; i >= 1; i--) {
                if (fields[i] ~ /^\//) {
                    socket = fields[i]
                    break
                }
            }
            if (match($0, /pid=[0-9]+/)) {
                pid = substr($0, RSTART + 4, RLENGTH - 4)
            } else {
                pid = ""
            }
            if (socket != "" && pid != "") print socket "|" pid
        }
    ' | sort -t'|' -k1,1 -k2,2n
}

# Print `socket|pid` for every socket with more than one listening tmux
# server.  A single server is intentionally silent.
daemon_watchdog_tmux_duplicate_records() {
    daemon_watchdog_tmux_server_records | awk -F'|' '
        function flush_group() {
            if (current != "" && count > 1) print current "|" pids
        }
        {
            if ($1 != current) {
                flush_group()
                current = $1
                count = 0
                pids = ""
            }
            count++
            pids = (pids == "" ? $2 : pids "," $2)
        }
        END { flush_group() }
    '
}

# Return the owner of the currently reachable tmux server as `socket pid`.
# Empty/malformed output is deliberately retained as unknown so a duplicate
# cannot be silently classified as safe after a socket race.
daemon_watchdog_tmux_current_owner() {
    if [[ -n "${DAEMON_WATCHDOG_TMUX_OWNER_OUTPUT_FILE:-}" ]]; then
        cat "$DAEMON_WATCHDOG_TMUX_OWNER_OUTPUT_FILE" 2>/dev/null || true
        return 0
    fi
    tmux display-message -p '#{socket_path} #{pid}' 2>/dev/null || true
}

check_tmux_duplicate_servers() {
    local duplicate_records owner_output owner_socket owner_pid
    duplicate_records="$(daemon_watchdog_tmux_duplicate_records)"
    local dedupe_file="${DAEMON_WATCHDOG_TMUX_DEDUPE_FILE:-${RESTART_STATE_DIR}/tmux_duplicate_servers.fingerprint}"

    # A resolved event is allowed to notify again if it reappears later.
    if [[ -z "$duplicate_records" ]]; then
        unlink "$dedupe_file" 2>/dev/null || true
        return 0
    fi

    owner_output="$(daemon_watchdog_tmux_current_owner)"
    owner_socket="${owner_output%% *}"
    owner_pid="${owner_output#* }"
    owner_pid="${owner_pid#pid=}"
    if [[ "$owner_socket" == "$owner_output" || ! "$owner_socket" =~ ^/ || ! "$owner_pid" =~ ^[0-9]+$ ]]; then
        owner_socket=""
        owner_pid=""
    fi

    local alert_parts="" record socket pids owner_for_socket old_pids pid
    while IFS='|' read -r socket pids; do
        [[ -n "$socket" && -n "$pids" ]] || continue
        owner_for_socket="unknown"
        old_pids="$pids"
        if [[ -n "$owner_socket" && "$owner_socket" == "$socket" ]]; then
            owner_for_socket="$owner_pid"
            old_pids=""
            IFS=',' read -ra _tmux_pids <<< "$pids"
            for pid in "${_tmux_pids[@]}"; do
                [[ "$pid" == "$owner_pid" ]] && continue
                old_pids="${old_pids:+${old_pids},}${pid}"
            done
            [[ -n "$old_pids" ]] || old_pids="none"
        fi
        record="socket=${socket} owner=${owner_for_socket} old=${old_pids}"
        alert_parts="${alert_parts:+${alert_parts}; }${record}"
    done <<< "$duplicate_records"

    [[ -n "$alert_parts" ]] || return 0
    local fingerprint
    fingerprint="$(printf '%s|owner_socket=%s|owner_pid=%s\n' "$duplicate_records" "$owner_socket" "$owner_pid" | sha256sum | awk '{print $1}')"
    ensure_restart_state_dir
    local lock_fd=""
    exec {lock_fd}>"${dedupe_file}.lock"
    flock "$lock_fd"
    if [[ -f "$dedupe_file" ]] && [[ "$(cat "$dedupe_file" 2>/dev/null || true)" == "$fingerprint" ]]; then
        log "TMUX-DUPLICATE-DEDUPE: ${alert_parts}"
        flock -u "$lock_fd"
        eval "exec ${lock_fd}>&-"
        return 0
    fi
    local tmp_file="${dedupe_file}.tmp.$$"
    printf '%s\n' "$fingerprint" > "$tmp_file" && mv "$tmp_file" "$dedupe_file"
    flock -u "$lock_fd"
    eval "exec ${lock_fd}>&-"

    local message="TMUX-DUPLICATE-ALERT: ${alert_parts}"
    log "$message"
    notify "【watchdog/CRITICAL】${message}"
    printf '%s\n' "$message"
    return 0
}

RESTARTED=0
RESTART_STATE_DIR="${RESTART_STATE_DIR:-/tmp/daemon_watchdog_state}"
RESTART_THROTTLE_WINDOW=600  # 10 minutes
RESTART_THROTTLE_MAX=3       # max restarts within window

pid_is_live() {
    local pid="${1:-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

pid_cmdline_matches() {
    local pid="${1:-}"
    local needle="$2"
    pid_is_live "$pid" || return 1

    local cmdline=""
    # The process can disappear between kill -0 and reading cmdline.  Keep the
    # pathname open inside cat so that a failed open is silenced as well.
    cmdline=$(cat "/proc/${pid}/cmdline" 2>/dev/null | tr '\0' ' ' || true)
    [[ "$cmdline" == *"$needle"* ]]
}

find_live_daemon_pid() {
    local pgrep_pattern="$1"
    local cmdline_needle="$2"
    local pid

    while IFS= read -r pid; do
        if pid_cmdline_matches "$pid" "$cmdline_needle"; then
            printf '%s\n' "$pid"
            return 0
        fi
    done < <(pgrep -f "$pgrep_pattern" 2>/dev/null || true)
    return 1
}

pid_file_has_live_daemon() {
    local pid_file="$1"
    local cmdline_needle="$2"
    local pid=""

    [[ -f "$pid_file" ]] || return 1
    pid=$(cat "$pid_file" 2>/dev/null || true)
    pid_cmdline_matches "$pid" "$cmdline_needle"
}

# 再起動ストーム防止: 直近N分間でM回以上再起動された場合はスロットル
# Returns 0 if restart is allowed, 1 if throttled
check_restart_throttle() {
    local daemon_name="$1"
    ensure_restart_state_dir
    local state_file="$RESTART_STATE_DIR/${daemon_name}.restarts"
    local now
    now=$(date +%s)
    local cutoff=$((now - RESTART_THROTTLE_WINDOW))

    # Prune old entries and count recent restarts
    local recent_count=0
    if [[ -f "$state_file" ]]; then
        local tmp="${state_file}.tmp"
        while IFS= read -r ts; do
            if (( ts > cutoff )); then
                echo "$ts"
                recent_count=$((recent_count + 1))
            fi
        done < "$state_file" > "$tmp"
        mv "$tmp" "$state_file"
    fi

    if (( recent_count >= RESTART_THROTTLE_MAX )); then
        return 1  # throttled
    fi
    return 0
}

# Record a restart event
record_restart() {
    local daemon_name="$1"
    ensure_restart_state_dir
    local state_file="$RESTART_STATE_DIR/${daemon_name}.restarts"
    date +%s >> "$state_file"
}

# =============================================================================
# ninja_monitor.sh — 忍者idle検知デーモン
# =============================================================================
watchdog_ninja_monitor_owner_healthy() {
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-${STATE_DIR:-/tmp}/ninja_monitor.owner}"
    local identity_file="${owner_file}.identity"
    local owner_pid="" generation="" heartbeat="" _legacy_mtime="" _legacy_fingerprint=""
    local script_mtime="" fingerprint="" current_fingerprint=""
    [ -f "$owner_file" ] || return 1
    read -r owner_pid generation heartbeat _legacy_mtime _legacy_fingerprint < "$owner_file" 2>/dev/null || return 1
    [[ "$owner_pid" =~ ^[0-9]+$ && -n "$generation" && "$heartbeat" =~ ^[0-9]+$ ]] || return 1
    pid_cmdline_matches "$owner_pid" "ninja_monitor.sh" || return 1
    read -r script_mtime fingerprint < "$identity_file" 2>/dev/null || return 1
    current_fingerprint="$(sha256sum "$SCRIPT_DIR/scripts/ninja_monitor.sh" 2>/dev/null | awk '{print $1}')"
    [ -n "$fingerprint" ] && [ "$fingerprint" = "$current_fingerprint" ]
}

watchdog_ninja_monitor_owner_generation() {
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-${STATE_DIR:-/tmp}/ninja_monitor.owner}"
    awk 'NR==1 {print $2; exit}' "$owner_file" 2>/dev/null || true
}

check_ninja_monitor() {
    local pid_file="${STATE_DIR:-/tmp}/ninja_monitor.pid"
    local owner_file="${NINJA_MONITOR_OWNER_FILE:-${STATE_DIR:-/tmp}/ninja_monitor.owner}"
    local start_lock="${STATE_DIR:-/tmp}/ninja_monitor.watchdog.start.lock"
    local starting_file="${STATE_DIR:-/tmp}/ninja_monitor.watchdog.starting"
    local observed_generation="" new_pid="" lock_fd="" starting_pid="" starting_epoch="" starting_age=0

    if watchdog_ninja_monitor_owner_healthy; then
        return 0
    fi

    if is_maintenance_active; then
        log "SKIP: daemon maintenance active; ninja_monitor restart deferred"
        return 0
    elif [[ $? -eq 2 ]]; then
        log "BLOCK: corrupt daemon maintenance marker; ninja_monitor restart refused"
        return 1
    fi
    if ! check_restart_throttle "ninja_monitor"; then
        log "THROTTLED: ninja_monitor.sh — ${RESTART_THROTTLE_MAX} restarts in ${RESTART_THROTTLE_WINDOW}s, skipping"
        notify "【watchdog/CRITICAL】ninja_monitor.shが再起動ストーム。手動確認必要"
        return
    fi

    mkdir -p "${STATE_DIR:-/tmp}"
    exec {lock_fd}>"$start_lock"
    flock "$lock_fd"
    if watchdog_ninja_monitor_owner_healthy; then
        flock -u "$lock_fd"; eval "exec ${lock_fd}>&-"
        return 0
    fi
    if [ -f "$starting_file" ]; then
        read -r starting_pid starting_epoch < "$starting_file" 2>/dev/null || true
        if [[ "$starting_epoch" =~ ^[0-9]+$ ]]; then
            starting_age=$((EPOCHSECONDS - starting_epoch))
        else
            starting_age=999999
        fi
        if [[ "$starting_pid" =~ ^[0-9]+$ ]] && pid_is_live "$starting_pid" && (( starting_age < 60 )); then
            flock -u "$lock_fd"; eval "exec ${lock_fd}>&-"
            return 0
        fi
    fi
    observed_generation="$(watchdog_ninja_monitor_owner_generation)"
    log "RESTART: ninja_monitor owner/identity invalid; legacy process presence is not serving evidence"
    if [ -n "$observed_generation" ]; then
        nohup env NINJA_MONITOR_REPLACE_GENERATION="$observed_generation" \
            bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
    else
        nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
    fi
    new_pid=$!
    disown
    printf '%s\n' "$new_pid" > "$pid_file"
    printf '%s %s\n' "$new_pid" "$EPOCHSECONDS" > "$starting_file"
    # Verify the new process survived startup without treating legacy PIDs as success.
    sleep 2
    if ! pid_cmdline_matches "$new_pid" "ninja_monitor.sh"; then
        unlink "$pid_file" 2>/dev/null || true
        log "RESTART-FAILED: ninja_monitor.sh PID $new_pid died immediately"
        notify "【watchdog/WARN】ninja_monitor.sh再起動失敗(即死)。次サイクルで再試行"
    else
        record_restart "ninja_monitor"
        notify "【watchdog】ninja_monitor.shを自動再起動しました"
        RESTARTED=$((RESTARTED + 1))
    fi
    flock -u "$lock_fd"
    eval "exec ${lock_fd}>&-"
    return 0
}

# =============================================================================
# ntfy_listener.sh — ntfy入力リスナー
# =============================================================================
check_ntfy_listener() {
    if ! find_live_daemon_pid "[n]tfy_listener\.sh" "ntfy_listener.sh" >/dev/null; then
        if is_maintenance_active; then
            log "SKIP: daemon maintenance active; ntfy_listener restart deferred"
            return 0
        elif [[ $? -eq 2 ]]; then
            log "BLOCK: corrupt daemon maintenance marker; ntfy_listener restart refused"
            return 1
        fi
        if ! check_restart_throttle "ntfy_listener"; then
            log "THROTTLED: ntfy_listener.sh — ${RESTART_THROTTLE_MAX} restarts in ${RESTART_THROTTLE_WINDOW}s, skipping"
            notify "【watchdog/CRITICAL】ntfy_listener.shが再起動ストーム。手動確認必要"
            return
        fi
        log "RESTART: ntfy_listener.sh not found, restarting..."
        nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" &>> "$SCRIPT_DIR/logs/ntfy_listener_watchdog.log" &
        disown
        record_restart "ntfy_listener"
        notify "【watchdog】ntfy_listener.shを自動再起動しました"
        RESTARTED=$((RESTARTED + 1))
    fi
    return 0
}

# =============================================================================
# inbox_watcher.sh — エージェント毎のメールボックス監視
# =============================================================================
# inbox_watcher ループhangチェック
# heartbeatファイルの更新が INBOX_WATCHER_HANG_SEC 秒以上止まっていて
# かつ未読メッセージがある場合、hangとみなしてwatcherプロセスをkillする
INBOX_WATCHER_HANG_SEC="${INBOX_WATCHER_HANG_SEC:-300}"
STATE_DIR="${SHOGUN_STATE_DIR:-${IDLE_FLAG_DIR:-/tmp}}"

inbox_unread_count_file() {
    local inbox_file="$1"
    [[ -f "$inbox_file" ]] || {
        echo 0
        return 0
    }

    local count=""
    count=$(awk '
        BEGIN { c = 0 }
        /^- / { in_msg = 1; read_state = "false"; next }
        in_msg && /^  read:[[:space:]]*/ {
            line = $0
            sub(/^  read:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (tolower(line) != "true") c++
            in_msg = 0
        }
        END {
            if (in_msg) c++
            print c
        }
    ' "$inbox_file" 2>/dev/null || true)
    # awk still executes END after an input error. Select exactly one numeric
    # line so arithmetic callers can never receive a multi-line value.
    count=$(printf '%s\n' "$count" | awk '/^[0-9]+$/ { value=$0 } END { print value == "" ? 0 : value }')
    printf '%s\n' "$count"
}

daemon_inventory_snapshot() {
    ps ax -o args= 2>/dev/null || true
}

check_daemon_inventory() {
    local snapshot
    snapshot=$(daemon_inventory_snapshot)
    local -a expected=(
        "inbox_watcher.sh:9"
        "ninja_monitor.sh:1"
        "ntfy_listener.sh:1"
        "usage_statusbar_loop.sh:1"
        "gist_sync.sh:1"
    )
    local spec daemon expected_count actual_count
    for spec in "${expected[@]}"; do
        daemon=${spec%%:*}
        expected_count=${spec##*:}
        actual_count=$(printf '%s\n' "$snapshot" | awk -v daemon="$daemon" 'index($0, daemon) { count++ } END { print count + 0 }')
        if (( actual_count < expected_count )); then
            log "DAEMON-INVENTORY-WARN: ${daemon} expected>=${expected_count} actual=${actual_count}"
        fi
    done
}

_check_inbox_watcher_hang() {
    local agent="$1"
    local hb_file="${STATE_DIR}/inbox_watcher_loop_hb_${agent}"
    local inbox_file="$SCRIPT_DIR/queue/inbox/${agent}.yaml"

    # heartbeatファイルがなければhang検知不能（まだ1ループ目 or 機能未サポート）
    [[ -f "$hb_file" ]] || return 0

    local now
    now=$(date +%s)
    local hb_time
    hb_time=$(cat "$hb_file" 2>/dev/null || echo 0)
    [[ "$hb_time" =~ ^[0-9]+$ ]] || return 0

    local age=$(( now - hb_time ))
    if (( age < INBOX_WATCHER_HANG_SEC )); then
        return 0  # 正常
    fi

    # heartbeatが古い — 未読があるか確認
    local has_unread=0
    has_unread=$(inbox_unread_count_file "$inbox_file")

    if (( has_unread == 0 )); then
        return 0  # 未読なし — hangではなくidle(変更なし)の可能性
    fi

    log "HANG-DETECT: inbox_watcher(${agent}) heartbeat ${age}s old (>= ${INBOX_WATCHER_HANG_SEC}s) with ${has_unread} unread message(s)"
    notify "【watchdog/WARN】inbox_watcher(${agent})がhang検知。未読${has_unread}件。強制再起動"

    # hangプロセスをkillして再起動させる（watchdogの次サイクルで再起動）
    local watcher_pids
    watcher_pids=$(pgrep -f "[i]nbox_watcher\.sh.*${agent}" 2>/dev/null || true)
    for pid in $watcher_pids; do
        kill -TERM "$pid" 2>/dev/null || true
        log "HANG-KILL: inbox_watcher(${agent}) PID $pid killed (SIGTERM)"
    done
    # heartbeatをリセット（killが届かなかった場合の誤再通知防止）
    rm -f "$hb_file"
    return 0
}

check_inbox_watchers() {
    if is_maintenance_active; then
        log "SKIP: daemon maintenance active; inbox_watcher supervision deferred"
        return 0
    elif [[ $? -eq 2 ]]; then
        log "BLOCK: corrupt daemon maintenance marker; inbox_watcher restart refused"
        return 1
    fi
    local restart_lock="${RESTART_WATCHERS_LOCK_FILE:-/tmp/restart_watchers.lock}"
    restart_watchers_lock_is_active "$restart_lock"
    local lock_state=$?
    if (( lock_state == 0 )); then
        log "SKIP: restart_watchers.sh is running; inbox_watcher supervision deferred"
        return 0
    elif (( lock_state == 2 )); then
        log "WARN: restart lock held by non-restart process; continuing watcher supervision"
    fi

    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
    local agents_str
    agents_str="shogun $(get_all_agents)"
    local agents
    read -ra agents <<< "$agents_str"

    # 最適化: 9回のpgrep呼び出し(~150ms)を1回のps+awkで置換(~27ms)
    # /inbox_watcher.sh の直後引数(argv[2])がエージェント名。shogun:agents.N との誤マッチを防ぐ。
    declare -A _iw_pid_map
    while IFS=' ' read -r _iw_pid _iw_agent; do
        [[ -n "$_iw_pid" && -n "$_iw_agent" ]] || continue
        [[ -d "/proc/${_iw_pid}" ]] || continue
        _iw_pid_map["$_iw_agent"]="${_iw_pid_map[$_iw_agent]:-$_iw_pid}"
    done < <(ps ax -o pid=,args= 2>/dev/null | awk '
        /\/inbox_watcher\.sh [a-z]/{
            for(i=1;i<=NF;i++){
                if($i ~ /\/inbox_watcher\.sh$/){ if(i+1<=NF) print $1, $(i+1); break }
            }
        }
    ' 2>/dev/null || true)

    for agent in "${agents[@]}"; do
        # マップ参照でpgrep不要(O(1))
        if [[ -n "${_iw_pid_map[$agent]:-}" ]]; then
            # プロセス生存中でもhangしていないか確認
            _check_inbox_watcher_hang "$agent" || true
            continue
        fi

        # pane target を tmux から取得
        local pane_target=""
        if [[ "$agent" == "shogun" ]]; then
            pane_target="shogun:main"
        else
            if [[ -f "$SCRIPT_DIR/scripts/lib/pane_lookup.sh" ]]; then
                # shellcheck source=/dev/null
                source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"
            fi
            pane_target="$(pane_lookup "$agent" 2>/dev/null || true)"
            if [[ -z "$pane_target" ]]; then
                log "WARN: Cannot find pane for ${agent}, skipping inbox_watcher restart"
                continue
            fi
        fi

        # CLI type を tmux 変数から取得
        local cli_type
        cli_type=$(tmux show-options -p -t "$pane_target" -v @agent_cli 2>/dev/null) || cli_type="claude"

        if ! check_restart_throttle "inbox_watcher_${agent}"; then
            log "THROTTLED: inbox_watcher(${agent}) — ${RESTART_THROTTLE_MAX} restarts in ${RESTART_THROTTLE_WINDOW}s, skipping"
            notify "【watchdog/CRITICAL】inbox_watcher(${agent})が再起動ストーム。手動確認必要"
            continue
        fi

        log "RESTART: inbox_watcher(${agent}) not found, restarting (pane=${pane_target}, cli=${cli_type})..."

        nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$pane_target" "$cli_type" \
            &>> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" &
        disown

        record_restart "inbox_watcher_${agent}"
        notify "【watchdog】inbox_watcher(${agent})を自動再起動しました"
        RESTARTED=$((RESTARTED + 1))
    done
}

check_crontab_registration() {
    local cron_text=""
    local marker="daemon_watchdog.sh"
    local state_file="$RESTART_STATE_DIR/crontab_registration.last_warn"
    local now
    now=$(date +%s)

    cron_text=$(crontab -l 2>/dev/null || true)
    if ! grep -q "$marker" <<< "$cron_text"; then
        if [[ ! -f "$state_file" ]] || (( now - $(cat "$state_file" 2>/dev/null || echo 0) > 3600 )); then
            log "CRONTAB-MISSING: daemon_watchdog.sh is not registered in crontab"
            notify "【watchdog/WARN】daemon_watchdog.shのcrontab登録が見つかりません"
            printf '%s\n' "$now" > "$state_file"
        fi
        return 1
    fi

    if grep "$marker" <<< "$cron_text" | grep -q "flock"; then
        if [[ ! -f "$state_file" ]] || (( now - $(cat "$state_file" 2>/dev/null || echo 0) > 3600 )); then
            log "CRONTAB-FLOCK-WARN: daemon_watchdog.sh crontab still uses flock"
            notify "【watchdog/WARN】daemon_watchdog.shのcrontabが旧flock形式です"
            printf '%s\n' "$now" > "$state_file"
        fi
        return 1
    fi

    return 0
}

# =============================================================================
# Main
# =============================================================================
if [[ "${DAEMON_WATCHDOG_LIB_ONLY:-0}" != "1" ]]; then
rotate_log
check_crontab_registration || true
check_ninja_monitor
check_ntfy_listener
check_inbox_watchers
check_daemon_inventory
check_tmux_health || true
check_tmux_duplicate_servers

# heartbeat更新: 外部から「watchdog自体が動いているか」を検証可能にする
date +%s > "$HEARTBEAT_FILE"

if [[ "$RESTARTED" -gt 0 ]]; then
    log "Total restarted: ${RESTARTED} daemon(s)"
else
    # 10分毎にOKログ（ログ肥大化防止）
    minute=$(date +%-M)
    if (( minute % 10 == 0 )); then
        log "OK: All daemons running"
    fi
fi
fi
