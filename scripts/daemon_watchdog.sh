#!/usr/bin/env bash
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
HEARTBEAT_FILE="/tmp/daemon_watchdog_heartbeat"

# 多重起動防止: 手動実行時も短時間で完了するため内部lockは持たない。
# 各デーモンの重複防止はPIDファイル/プロセス生存確認に寄せる。

mkdir -p "$SCRIPT_DIR/logs"

# ログローテーション: 1MB超過時に末尾500行を残して切り詰め
rotate_log() {
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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

notify() {
    bash "$SCRIPT_DIR/scripts/ntfy.sh" "$1" >/dev/null 2>&1 || true
}

RESTARTED=0
RESTART_STATE_DIR="${RESTART_STATE_DIR:-/tmp/daemon_watchdog_state}"
RESTART_THROTTLE_WINDOW=600  # 10 minutes
RESTART_THROTTLE_MAX=3       # max restarts within window
mkdir -p "$RESTART_STATE_DIR"

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
    cmdline=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)
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
    local state_file="$RESTART_STATE_DIR/${daemon_name}.restarts"
    date +%s >> "$state_file"
}

# =============================================================================
# ninja_monitor.sh — 忍者idle検知デーモン
# =============================================================================
check_ninja_monitor() {
    local pid_file="${STATE_DIR:-/tmp}/ninja_monitor.pid"
    local live_pid=""

    if pid_file_has_live_daemon "$pid_file" "ninja_monitor.sh"; then
        return 0
    fi

    if [[ -f "$pid_file" ]]; then
        log "STALE-PID-REMOVED: ${pid_file} contained $(cat "$pid_file" 2>/dev/null || true)"
        rm -f "$pid_file"
    fi

    live_pid=$(find_live_daemon_pid "[n]inja_monitor\.sh" "ninja_monitor.sh" || true)
    if [[ -n "$live_pid" ]]; then
        printf '%s\n' "$live_pid" > "$pid_file"
        return 0
    fi

    if [[ -z "$live_pid" ]]; then
        if ! check_restart_throttle "ninja_monitor"; then
            log "THROTTLED: ninja_monitor.sh — ${RESTART_THROTTLE_MAX} restarts in ${RESTART_THROTTLE_WINDOW}s, skipping"
            notify "【watchdog/CRITICAL】ninja_monitor.shが再起動ストーム。手動確認必要"
            return
        fi
        log "RESTART: ninja_monitor.sh not found, restarting..."
        nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
        local new_pid=$!
        disown
        printf '%s\n' "$new_pid" > "$pid_file"
        # Verify the new process survived startup.
        sleep 2
        if ! pid_cmdline_matches "$new_pid" "ninja_monitor.sh"; then
            rm -f "$pid_file"
            log "RESTART-FAILED: ninja_monitor.sh PID $new_pid died immediately"
            notify "【watchdog/WARN】ninja_monitor.sh再起動失敗(即死)。次サイクルで再試行"
        else
            record_restart "ninja_monitor"
            notify "【watchdog】ninja_monitor.shを自動再起動しました"
            RESTARTED=$((RESTARTED + 1))
        fi
    fi
    return 0
}

# =============================================================================
# ntfy_listener.sh — ntfy入力リスナー
# =============================================================================
check_ntfy_listener() {
    if ! find_live_daemon_pid "[n]tfy_listener\.sh" "ntfy_listener.sh" >/dev/null; then
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
    if [[ -f "$inbox_file" ]]; then
        has_unread=$(grep -c 'read:[[:space:]]*false' "$inbox_file" 2>/dev/null || echo 0)
    fi

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
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
    local agents_str
    agents_str="shogun $(get_all_agents)"
    local agents
    read -ra agents <<< "$agents_str"

    for agent in "${agents[@]}"; do
        # pgrep -f でエージェント名を含むinbox_watcherプロセスを検索
        if find_live_daemon_pid "[i]nbox_watcher\.sh.*${agent}" "inbox_watcher.sh" >/dev/null; then
            # プロセス生存中でもhangしていないか確認
            _check_inbox_watcher_hang "$agent" || true
            continue
        fi

        # pane target を tmux から取得
        local pane_target=""
        if [[ "$agent" == "shogun" ]]; then
            pane_target="shogun:main"
        else
            local pane_index
            pane_index=$(tmux list-panes -t "shogun:agents" -F '#{pane_index} #{@agent_id}' 2>/dev/null | \
                awk -v a="$agent" '$2 == a {print $1; exit}') || true
            if [[ -z "$pane_index" ]]; then
                log "WARN: Cannot find pane for ${agent}, skipping inbox_watcher restart"
                continue
            fi
            pane_target="shogun:agents.${pane_index}"
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
