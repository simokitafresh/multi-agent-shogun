#!/usr/bin/env bash
# model_resolve.sh — モデル表示名解決の唯一の実装（DRY原則）
# Usage: source scripts/lib/model_resolve.sh
#
# 依存: cli_lookup.sh, model_detect.sh が既にsource済みであること
#
# API:
#   resolve_model_display <agent_id> [pane_target]
#     → stdout にモデル表示名を出力（例: "Opus 4.6 high", "Codex", "Sonnet 4.6"）
#
# 優先順:
#   1. detect_real_model（実行中CLIバナーから検出。最も正確）
#   2. cli_model_display（settings.yaml model_name → 表示名）
#   3. cli_profile_get display_name（cli_profiles.yaml）
#   4. cli_type（CLIタイプ名: "Codex", "Claude" 等）

resolve_model_display() {
    local agent="$1"
    local target="${2:-}"

    # 1st: detect_real_model（capture-paneバナー検出）
    if [[ -n "$target" ]]; then
        local real_model
        real_model=$(detect_real_model "$agent" "$target" 2>/dev/null) || real_model=""
        if [[ -n "$real_model" ]]; then
            echo "$real_model"
            return 0
        fi
    fi

    # 2nd: settings.yaml model_name
    local settings_display
    settings_display=$(cli_model_display "$agent" 2>/dev/null) || settings_display=""
    if [[ -n "$settings_display" ]]; then
        echo "$settings_display"
        return 0
    fi

    # 3rd: cli_profiles.yaml display_name
    local display_name
    display_name=$(cli_profile_get "$agent" "display_name" 2>/dev/null) || display_name=""
    if [[ -n "$display_name" ]]; then
        echo "$display_name"
        return 0
    fi

    # 4th: CLI type fallback
    local ct
    ct=$(cli_type "$agent" 2>/dev/null) || ct="claude"
    case "$ct" in
        codex)   echo "Codex" ;;
        copilot) echo "Copilot" ;;
        kimi)    echo "Kimi" ;;
        *)       echo "Claude" ;;
    esac
}
