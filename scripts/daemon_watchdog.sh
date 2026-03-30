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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/daemon_watchdog.log"
LOCK_FILE="/tmp/daemon_watchdog.lock"

# flock for single-instance (cron多重起動防止)
exec 201>"$LOCK_FILE"
flock -n 201 || exit 0

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

# =============================================================================
# ninja_monitor.sh — 忍者idle検知デーモン
# =============================================================================
check_ninja_monitor() {
    if ! pgrep -f "[n]inja_monitor\.sh" > /dev/null 2>&1; then
        log "RESTART: ninja_monitor.sh not found, restarting..."
        nohup bash "$SCRIPT_DIR/scripts/ninja_monitor.sh" >> "$SCRIPT_DIR/logs/ninja_monitor.log" 2>&1 &
        disown
        notify "【watchdog】ninja_monitor.shを自動再起動しました"
        RESTARTED=$((RESTARTED + 1))
    fi
}

# =============================================================================
# ntfy_listener.sh — ntfy入力リスナー
# =============================================================================
check_ntfy_listener() {
    if ! pgrep -f "[n]tfy_listener\.sh" > /dev/null 2>&1; then
        log "RESTART: ntfy_listener.sh not found, restarting..."
        nohup bash "$SCRIPT_DIR/scripts/ntfy_listener.sh" &>> "$SCRIPT_DIR/logs/ntfy_listener_watchdog.log" &
        disown
        notify "【watchdog】ntfy_listener.shを自動再起動しました"
        RESTARTED=$((RESTARTED + 1))
    fi
}

# =============================================================================
# inbox_watcher.sh — エージェント毎のメールボックス監視
# =============================================================================
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

        log "RESTART: inbox_watcher(${agent}) not found, restarting (pane=${pane_target}, cli=${cli_type})..."

        if [[ "$agent" == "shogun" ]]; then
            nohup env ASW_DISABLE_ESCALATION=1 ASW_PROCESS_TIMEOUT=0 \
                bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$pane_target" "$cli_type" \
                &>> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" &
        else
            nohup bash "$SCRIPT_DIR/scripts/inbox_watcher.sh" "$agent" "$pane_target" "$cli_type" \
                &>> "$SCRIPT_DIR/logs/inbox_watcher_${agent}.log" &
        fi
        disown

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

if [[ "$RESTARTED" -gt 0 ]]; then
    log "Total restarted: ${RESTARTED} daemon(s)"
else
    # 10分毎にOKログ（ログ肥大化防止）
    minute=$(date +%-M)
    if (( minute % 10 == 0 )); then
        log "OK: All daemons running"
    fi
fi
