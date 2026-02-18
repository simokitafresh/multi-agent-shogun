#!/bin/bash
# sync_pane_vars.sh — settings.yaml + cli_profiles.yaml → tmux @model_name 自動同期
# cmd_155 Phase1: ペイン変数の一元管理
#
# Usage: bash scripts/sync_pane_vars.sh
#
# 動作:
#   1. settings.yaml からエージェント一覧を取得
#   2. 各エージェントのtype → cli_profiles.yaml の display_name を解決
#   3. tmux set-option -p で @model_name を設定（変更時のみログ出力）

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# cli_lookup.sh を使って SSOT から値を取得
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"

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

for agent in "${!AGENT_PANES[@]}"; do
    pane="${AGENT_PANES[$agent]}"
    target="shogun:agents.${pane}"

    # cli_lookup.sh 経由で display_name を取得
    display_name=$(cli_profile_get "$agent" "display_name")

    if [[ -z "$display_name" ]]; then
        # display_name未設定の場合、type名をそのまま使う
        display_name=$(cli_type "$agent")
    fi

    # 現在の値と比較
    current=$(tmux show-options -p -t "$target" -v @model_name 2>/dev/null || echo "")

    if [[ "$current" != "$display_name" ]]; then
        tmux set-option -p -t "$target" @model_name "$display_name"
        echo "  [sync] ${agent} (agents.${pane}): @model_name = ${display_name}"
        ((changed++)) || true
    fi
done

if [[ $changed -eq 0 ]]; then
    echo "  [sync] 変更なし（全ペイン同期済み）"
else
    echo "  [sync] ${changed} ペイン更新完了"
fi
