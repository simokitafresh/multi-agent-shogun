#!/bin/bash
# sync_pane_vars.sh — 実モデル検出 + settings.yaml → tmux @model_name 自動同期
# cmd_155 Phase1: ペイン変数の一元管理
# cmd_320: 実モデル値優先のフォールバック構造
#
# Usage: bash scripts/sync_pane_vars.sh
#
# 動作:
#   1. settings.yaml からエージェント一覧を取得
#   2. 各エージェントのtype → cli_profiles.yaml の display_name を解決
#   3. 実モデル検出を試行（capture-paneバナー解析）
#   4. 優先順位: 実モデル値 > settings.yaml/cli_profiles.yaml定義値
#   5. tmux set-option -p で @model_name を設定（変更時のみログ出力）

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# cli_lookup.sh を使って SSOT から値を取得
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
# model_detect.sh を使って実行中モデル名を検出
source "$SCRIPT_DIR/scripts/lib/model_detect.sh"

# エージェント → ペインのマッピング（settings.yamlから動的生成 — cmd_1136）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
declare -A AGENT_PANES=()
_sp_idx=1
for _sp_agent in $(get_all_agents); do
    AGENT_PANES[$_sp_agent]=$_sp_idx
    ((_sp_idx++)) || true
done
unset _sp_idx _sp_agent

changed=0

# ── sync_one_pane: 1ペインの @model_name / @agent_cli を同期 ──
# Usage: sync_one_pane <agent_name> <tmux_target> <pane_label>
sync_one_pane() {
    local agent="$1"
    local target="$2"
    local pane_label="$3"

    # 実モデル検出 → settings.yaml model_name → display_name → "Unknown" のフォールバックチェーン
    local real_model settings_display display_name effective_model
    real_model=$(detect_real_model "$agent" "$target" 2>/dev/null) || real_model=""
    settings_display=$(cli_model_display "$agent" 2>/dev/null) || settings_display=""
    display_name=$(cli_profile_get "$agent" "display_name")
    if [[ -z "$display_name" ]]; then
        display_name=$(cli_type "$agent")
    fi
    effective_model="${real_model:-${settings_display:-${display_name:-Unknown}}}"

    # CLI種別
    local effective_cli
    effective_cli=$(cli_type "$agent")
    effective_cli="${effective_cli:-claude}"

    # @model_name 同期
    local current
    current=$(tmux show-options -p -t "$target" -v @model_name 2>/dev/null || echo "")
    if [[ "$current" != "$effective_model" ]]; then
        tmux set-option -p -t "$target" @model_name "$effective_model"
        local source_label="${real_model:+detected}"; source_label="${source_label:-fallback}"
        echo "  [sync] ${agent} (${pane_label}): @model_name = ${effective_model} (${source_label})"
        ((changed++)) || true
    fi

    # @agent_cli 同期
    local current_cli
    current_cli=$(tmux show-options -p -t "$target" -v @agent_cli 2>/dev/null || echo "")
    if [[ "$current_cli" != "$effective_cli" ]]; then
        tmux set-option -p -t "$target" @agent_cli "$effective_cli"
        echo "  [sync] ${agent} (${pane_label}): @agent_cli = ${effective_cli}"
        ((changed++)) || true
    fi
}

# ── 将軍ペイン（shogun:main）──
sync_one_pane "shogun" "shogun:main" "main"

# ── エージェントペイン（shogun:agents.*）──
for agent in "${!AGENT_PANES[@]}"; do
    pane="${AGENT_PANES[$agent]}"
    sync_one_pane "$agent" "shogun:agents.${pane}" "agents.${pane}"
done

if [[ $changed -eq 0 ]]; then
    echo "  [sync] 変更なし（全ペイン同期済み）"
else
    echo "  [sync] ${changed} ペイン更新完了"
fi
