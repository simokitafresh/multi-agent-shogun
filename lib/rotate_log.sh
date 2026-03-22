#!/bin/bash
# rotate_log.sh — 共通ログローテーション関数
# Usage: source lib/rotate_log.sh; rotate_log <logfile> [max_lines]
#
# max_lines超 or 1MB超でローテーション(copytruncate方式):
#   現ファイルをコピー→.1、.1→.2、.2→.3、.3→削除
#   copytruncate: 長時間プロセス(&>>リダイレクト)のfd互換性を保持
#
# cmd_802: ログ肥大化対策（ninja_monitor 16万行他）

rotate_log() {
    local logfile="$1"
    local max_lines="${2:-10000}"

    [ -f "$logfile" ] || return 0

    local need_rotate=false

    # Check line count
    local lines
    lines=$(wc -l < "$logfile" 2>/dev/null) || return 0
    [ "$lines" -gt "$max_lines" ] && need_rotate=true

    # Check file size (1MB = 1048576 bytes)
    if [ "$need_rotate" = false ]; then
        local size
        size=$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null) || return 0
        [ "$size" -gt 1048576 ] && need_rotate=true
    fi

    if [ "$need_rotate" = true ]; then
        [ -f "${logfile}.3" ] && rm -f "${logfile}.3"
        [ -f "${logfile}.2" ] && mv -f "${logfile}.2" "${logfile}.3"
        [ -f "${logfile}.1" ] && mv -f "${logfile}.1" "${logfile}.2"
        # copytruncate: fdを保持したまま回転（inbox_watcher等の&>>互換）
        cp -f "$logfile" "${logfile}.1"
        truncate -s 0 "$logfile"
    fi
}

# rotate_all_logs — logs/配下の全主要ログを一括ローテーション
rotate_all_logs() {
    local log_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs}"
    local max="${2:-10000}"

    for f in \
        "$log_dir/ninja_monitor.log" \
        "$log_dir/deploy_task.log" \
        "$log_dir/ntfy.log" \
        "$log_dir/ntfy_listener.log" \
        "$log_dir/auto_deploy.log" \
        "$log_dir/ci_status_check.log" \
        "$log_dir/gist_sync.log" \
        "$log_dir/inbox_prune.log" \
        "$log_dir/mcp_sync.log" \
        "$log_dir/normalize_report.log" \
        "$log_dir/gate_metrics.log" \
        "$log_dir/usage_statusbar_loop.log" \
    ; do
        rotate_log "$f" "$max"
    done

    # inbox_watcher_*.log — 全エージェント分
    for f in "$log_dir"/inbox_watcher_*.log; do
        [ -f "$f" ] && rotate_log "$f" "$max"
    done
}
