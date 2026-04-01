#!/usr/bin/env bash
# agent_status.sh — 全エージェント状態一覧表示
# Usage: bash scripts/agent_status.sh
#
# tmux変数を一括読み取りし、全エージェントの状態を表示する。
# 状態定義:
#   active  : @agent_state == "active"
#   idle    : @agent_state == "idle"
#   unknown : @agent_state未設定
#   ⚠ stale : STATE=active かつ AGE>600秒（10分）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/pane_lookup.sh"

# 表示順序はpane_lookup.shから取得
AGENT_ORDER=("${PANE_LOOKUP_AGENT_ORDER[@]}")

STALE_THRESHOLD=600  # 10分（秒）

# AGEを人間可読な形式に変換
format_age() {
    local seconds="$1"
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        local min=$((seconds / 60))
        local sec=$((seconds % 60))
        echo "${min}m${sec}s"
    else
        local hr=$((seconds / 3600))
        local min=$(( (seconds % 3600) / 60 ))
        echo "${hr}h${min}m"
    fi
}

# ヘッダー出力
printf "%-10s %-9s %-5s %-12s %s\n" "AGENT" "STATE" "CTX" "LAST_ACTIVE" "AGE"

NOW=$(date +%s)

for name in "${AGENT_ORDER[@]}"; do
    pane=$(pane_lookup "$name")

    if [ -z "$pane" ]; then
        printf "%-10s %-9s %-5s %-12s %s\n" "$name" "missing" "—" "—" "—"
        continue
    fi

    # pane存在確認+tmux変数を一括読取り（4回→1回のtmux呼出し）
    _tmux_raw=$(tmux display-message -t "$pane" -p '#{pane_id}|#{@agent_id}|#{@agent_state}|#{@last_active}|#{@context_pct}' 2>/dev/null) || _tmux_raw=""
    if [ -z "$_tmux_raw" ]; then
        printf "%-10s %-9s %-5s %-12s %s\n" "$name" "missing" "—" "—" "—"
        continue
    fi

    # shellcheck disable=SC2034  # pane_id/agent_idはフォーマット分解で必要（将来の拡張用に保持）
    IFS='|' read -r pane_id agent_id agent_state last_active context_pct <<< "$_tmux_raw"

    # STATE判定
    if [ -z "$agent_state" ]; then
        state="unknown"
    else
        state="$agent_state"
    fi

    # CTX表示（未設定時は "—"）
    if [ -z "$context_pct" ] || [ "$context_pct" = "--" ]; then
        ctx_display="—"
    else
        ctx_display="$context_pct"
    fi

    # LAST_ACTIVE / AGE計算
    if [ -z "$last_active" ] || ! [[ "$last_active" =~ ^[0-9]+$ ]]; then
        time_display="—"
        age_display="—"
        age_seconds=""
    else
        time_display=$(date -d "@$last_active" '+%H:%M:%S' 2>/dev/null) || time_display="$last_active"
        age_seconds=$((NOW - last_active))
        if [ "$age_seconds" -lt 0 ]; then
            age_seconds=0
        fi
        age_display=$(format_age "$age_seconds")
    fi

    # stale検知: active + AGE > 600秒
    if [ "$state" = "active" ] && [ -n "$age_seconds" ] && [ "$age_seconds" -gt "$STALE_THRESHOLD" ]; then
        state="⚠ stale"
    fi

    printf "%-10s %-9s %-5s %-12s %s\n" "$name" "$state" "$ctx_display" "$time_display" "$age_display"
done
