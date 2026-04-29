#!/usr/bin/env bash
# =============================================================================
# daemon_watchdog.sh — デーモン死活監視+自動再起動
# cronから毎分実行。flockで多重起動防止。
#
# 監視対象:
#   - ninja_monitor.sh   (単一インスタンス)
#   - ntfy_listener.sh   (単一インスタンス、自身もflock持ち)
#   - inbox_watcher.sh   (エージェント毎に1プロセス、計10)
#
# Usage:
#   bash scripts/daemon_watchdog.sh          # 手動実行
#   * * * * * flock -n /tmp/daemon_watchdog.lock bash /path/to/scripts/daemon_watchdog.sh
# =============================================================================
set -uo pipefail
# NOTE: set -e を外した(2026-04-16 GP-204)。個別チェック関数の失敗で全体が死ぬと
# 後続デーモンの監視がスキップされる。各関数内で個別にエラーハンドリングする。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/daemon_watchdog.log"
HEARTBEAT_FILE="/tmp/daemon_watchdog_heartbeat"

# 多重起動防止: crontabのflock -n で制御済み。
# スクリプト内部での二重flockは同一ファイルで競合するため削除(GP-204)。
# 手動実行時はflock不要（短時間で完了するため）。

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
RESTART_STATE_DIR="/tmp/daemon_watchdog_state"
RESTART_THROTTLE_WINDOW=600  # 10 minutes
RESTART_THROTTLE_MAX=3       # max restarts within window
mkdir -p "$RESTART_STATE_DIR"

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
    if ! pgrep -f "[n]inja_monitor\.sh" > /dev/null 2>&1; then
        if ! check_restart_throttle "ninja_monitor"; then
            log "THROTTLED: ninja_monitor.sh — ${RESTART_THROTTLE_MAX} restarts in ${RESTART_THROTTLE_WINDOW}s, skipping"
            notify "【watchdog/CRITICAL】ninja_monitor.shが再起動ストーム。手動確認必要"
            return
        fi
        # Release stale singleton lock before restart (SINGLETON-EXIT prevention)
        local lock_file="/tmp/ninja_monitor.singleton.lock"
        if [[ -f "$lock_file" ]] && flock -n "$lock_file" true 2>/dev/null; then
            rm -f "$lock_file"
            log "STALE-LOCK-REMOVED: $lock_file (no holder)"
        fi
        log "RESTART: ninja_monitor.sh not found, restarting..."
        nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
        local new_pid=$!
        disown
        # Verify the new process survived (SINGLETON-EXIT kills within 1-2s)
        sleep 2
        if ! kill -0 "$new_pid" 2>/dev/null; then
            log "RESTART-FAILED: ninja_monitor.sh PID $new_pid died immediately (check SINGLETON-EXIT)"
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
    if ! pgrep -f "[n]tfy_listener\.sh" > /dev/null 2>&1; then
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
        if pgrep -f "[i]nbox_watcher\.sh.*${agent}" > /dev/null 2>&1; then
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

# =============================================================================
# Main
# =============================================================================
rotate_log
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
