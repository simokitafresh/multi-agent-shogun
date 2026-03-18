#!/usr/bin/env bash
# ctx_utils.sh — CTX%取得共通ライブラリ
# Usage: source scripts/lib/ctx_utils.sh
#
# API:
#   get_ctx_pct <pane_target> [agent_name]  → CTX使用率(0-100)を標準出力
#
# 取得優先順位:
#   1. tmux @context_pct変数
#   2. capture-pane + cli_profiles.yamlパターン
#   3. capture-paneフォールバック(CTX:XX% / XX% context left)
#   4. デフォルト値(50)
#
# deploy_task.sh / ninja_monitor.sh 共通のCTX%取得ロジックを統合

_CTX_UTILS_DEFAULT=50

get_ctx_pct() {
    local pane_target="$1"
    local agent_name="${2:-}"
    local ctx_num

    # Source 1: tmux pane variable (@context_pct)
    local ctx_val
    ctx_val=$(tmux show-options -p -t "$pane_target" -v @context_pct 2>/dev/null || true)
    ctx_num=$(echo "$ctx_val" | grep -oE '[0-9]+' | tail -1)
    if [ -n "$ctx_num" ] && [ "$ctx_num" -gt 0 ] 2>/dev/null; then
        echo "$ctx_num"
        return 0
    fi

    # Source 2: capture-pane + cli_profiles.yamlのパターン
    local output
    output=$(tmux capture-pane -t "$pane_target" -p -J -S -5 2>/dev/null || true)

    if [ -n "$agent_name" ] && command -v cli_profile_get >/dev/null 2>&1; then
        local ctx_pattern ctx_mode
        ctx_pattern=$(cli_profile_get "$agent_name" "ctx_pattern")
        ctx_mode=$(cli_profile_get "$agent_name" "ctx_mode")

        if [ -n "$ctx_pattern" ]; then
            if [ "$ctx_mode" = "usage" ]; then
                ctx_num=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
                if [ -n "$ctx_num" ]; then
                    echo "$ctx_num"
                    return 0
                fi
            elif [ "$ctx_mode" = "remaining" ]; then
                local remaining
                remaining=$(echo "$output" | grep -oE "$ctx_pattern" | tail -1 | grep -oE '[0-9]+')
                if [ -n "$remaining" ]; then
                    echo $((100 - remaining))
                    return 0
                fi
            fi
        fi
    fi

    # Source 3: フォールバック — 両パターン試行
    ctx_num=$(echo "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | grep -oE '[0-9]+')
    if [ -n "$ctx_num" ]; then
        echo "$ctx_num"
        return 0
    fi

    local remaining
    remaining=$(echo "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+')
    if [ -n "$remaining" ]; then
        echo $((100 - remaining))
        return 0
    fi

    # デフォルト: 50（不明時は中間値で安全側）
    echo "$_CTX_UTILS_DEFAULT"
    return 1
}
