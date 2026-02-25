#!/usr/bin/env bash
# model_detect.sh — CLIの実行中モデル名を検出するライブラリ
# cmd_320: @model_nameリアルタイム同期
#
# Usage: source scripts/lib/model_detect.sh
#
# 提供関数:
#   detect_real_model <agent_name> <pane_target>
#     → 成功時: stdout にモデル名を出力、return 0
#     → 失敗時: stdout 空、return 1
#
# 依存: cli_lookup.sh が既にsourceされていること
#
# 検出方式:
#   Claude Code: バナー行 ▝▜█████▛▘  {Model} · {Plan} をcapture-paneで解析
#   Codex CLI:   │ model: {model_name} /model to change │ を解析
#   その他:      未対応 → return 1（フォールバック利用を前提）
#
# キャッシュ:
#   検出成功時に tmux @real_model ペイン変数に保存。
#   次回検出失敗時はキャッシュ値を返す（バナーがスクロールオフした場合の安全網）。

# detect_real_model <agent_name> <pane_target>
# CLI種別に応じた方式でペインから実行中のモデル名を検出
detect_real_model() {
    local agent="$1"
    local pane_target="$2"
    local cli_t

    cli_t=$(cli_type "$agent")

    case "$cli_t" in
        claude)
            # Claude Code: バナー行 ▝▜█████▛▘  {Model} · {Plan}
            local output
            output=$(tmux capture-pane -t "$pane_target" -p -S -1000 2>/dev/null)

            if [ -n "$output" ]; then
                # バナー行を抽出（モデル名パターンで精密マッチ = false positive防止）
                # 形式: ▝▜█████▛▘  {Opus|Sonnet|Haiku} {X.Y} · {Plan}
                local banner
                banner=$(echo "$output" | grep -E '▝▜█████▛▘[[:space:]]+(Opus|Sonnet|Haiku)[[:space:]]+[0-9]+\.[0-9]+[[:space:]]+·' | tail -1)

                if [ -n "$banner" ]; then
                    # モデル名抽出: ▝▜█████▛▘ の後ろ、· の前
                    local model
                    model=$(echo "$banner" | sed -E 's/.*▝▜█████▛▘[[:space:]]*//' | sed -E 's/[[:space:]]*·.*//')
                    if [ -n "$model" ]; then
                        # キャッシュに保存（次回バナースクロールオフ時の安全網）
                        tmux set-option -p -t "$pane_target" @real_model "$model" 2>/dev/null
                        echo "$model"
                        return 0
                    fi
                fi
            fi

            # バナー未検出 → キャッシュ(@real_model)にフォールバック
            local cached
            cached=$(tmux show-options -p -t "$pane_target" -v @real_model 2>/dev/null)
            if [ -n "$cached" ]; then
                echo "$cached"
                return 0
            fi

            return 1
            ;;
        codex)
            # Codex CLI: │ model: {model_name} /model to change │
            local output
            output=$(tmux capture-pane -t "$pane_target" -p -S -1000 2>/dev/null)

            if [ -n "$output" ]; then
                local model_line
                model_line=$(echo "$output" | grep -E '│.*model:' | tail -1)

                if [ -n "$model_line" ]; then
                    # "model:" の後ろ、"/model" or "│" の前
                    local model
                    model=$(echo "$model_line" | sed -E 's/.*model:[[:space:]]*//' | sed -E 's/[[:space:]]*(\/model|│).*//')
                    # "loading" は検出失敗扱い
                    if [ -n "$model" ] && [ "$model" != "loading" ]; then
                        tmux set-option -p -t "$pane_target" @real_model "$model" 2>/dev/null
                        echo "$model"
                        return 0
                    fi
                fi
            fi

            # キャッシュにフォールバック
            local cached
            cached=$(tmux show-options -p -t "$pane_target" -v @real_model 2>/dev/null)
            if [ -n "$cached" ]; then
                echo "$cached"
                return 0
            fi

            return 1
            ;;
        *)
            # copilot, kimi等: 未対応 → fallback
            return 1
            ;;
    esac
}
