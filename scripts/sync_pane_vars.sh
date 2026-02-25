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

# エージェント → ペインのマッピング
declare -A AGENT_PANES=(
    [karo]=1
    [sasuke]=2
    [kirimaru]=3
    [hayate]=4
    [kagemaru]=5
    [hanzo]=6
    [saizo]=7
    [kotaro]=8
    [tobisaru]=9
)

changed=0

# ── 将軍ペイン（shogun:main）の @model_name 同期 ──
shogun_target="shogun:main"
shogun_model=$(detect_real_model "shogun" "$shogun_target" 2>/dev/null) || shogun_model="Opus"
shogun_current=$(tmux show-options -p -t "$shogun_target" -v @model_name 2>/dev/null || echo "")
if [[ "$shogun_current" != "$shogun_model" ]]; then
    tmux set-option -p -t "$shogun_target" @model_name "$shogun_model"
    echo "  [sync] shogun (main): @model_name = ${shogun_model}"
    ((changed++)) || true
fi

for agent in "${!AGENT_PANES[@]}"; do
    pane="${AGENT_PANES[$agent]}"
    target="shogun:agents.${pane}"

    # cli_lookup.sh 経由で display_name を取得（フォールバック値）
    display_name=$(cli_profile_get "$agent" "display_name")

    if [[ -z "$display_name" ]]; then
        display_name=$(cli_type "$agent")
    fi

    # 実モデル検出を試行（AC1: /model切替後のリアルタイム同期）
    real_model=$(detect_real_model "$agent" "$target" 2>/dev/null) || real_model=""

    # 優先順位: 実モデル値 > settings.yaml/cli_profiles.yaml定義値（AC3: フォールバック）
    effective_model="${real_model:-$display_name}"

    # 現在の値と比較
    current=$(tmux show-options -p -t "$target" -v @model_name 2>/dev/null || echo "")

    if [[ "$current" != "$effective_model" ]]; then
        tmux set-option -p -t "$target" @model_name "$effective_model"
        source_label="${real_model:+detected}"; source_label="${source_label:-fallback}"
        echo "  [sync] ${agent} (agents.${pane}): @model_name = ${effective_model} (${source_label})"
        ((changed++)) || true
    fi
done

if [[ $changed -eq 0 ]]; then
    echo "  [sync] 変更なし（全ペイン同期済み）"
else
    echo "  [sync] ${changed} ペイン更新完了"
fi
