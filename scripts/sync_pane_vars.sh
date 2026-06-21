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

case "${1:-}" in
    -h|--help)
        cat <<'USAGE'
Usage: bash scripts/sync_pane_vars.sh

Synchronize tmux @model_name and @agent_cli pane variables from settings and live panes.
USAGE
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# cli_lookup.sh を使って SSOT から値を取得
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
# model_detect.sh を使って実行中モデル名を検出
source "$SCRIPT_DIR/scripts/lib/model_detect.sh"
# model_resolve.sh — モデル表示名解決の統一実装
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/model_resolve.sh"

# エージェント → ペインのマッピング（settings.yamlから動的生成 — cmd_1136）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
declare -A AGENT_PANES=()
_sp_idx=1
# get_all_agents() は監視用に shogun を含む (agent_config.sh L160) が、shogun は
# shogun:main で別途同期する(下記 L92)。agents window に shogun ペインは無いため除外し、
# karo=agents.1, gunshi=agents.2, ... の正準マッピング(pane_lookup.sh準拠)に揃える。
for _sp_agent in $(get_all_agents); do
    [ "$_sp_agent" = "shogun" ] && continue
    AGENT_PANES[$_sp_agent]=$_sp_idx
    ((_sp_idx++)) || true
done
unset _sp_idx _sp_agent

changed=0
_spv_tmp=""

# ── sync_one_pane: 1ペインの @model_name / @agent_cli を同期 ──
# Usage: sync_one_pane <agent_name> <tmux_target> <pane_label>
sync_one_pane() {
    local agent="$1"
    local target="$2"
    local pane_label="$3"

    # モデル表示名解決（model_resolve.shに統一委譲）
    local effective_model
    effective_model=$(resolve_model_display "$agent" "$target")

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

# ── 全ペインを並列同期（各ペインは独立のため安全）──
_spv_tmp=$(mktemp -d /tmp/spv_XXXXXX)
_spv_pids=()

sync_one_pane "shogun" "shogun:main" "main" > "$_spv_tmp/0_shogun" 2>&1 &
_spv_pids+=($!)

for agent in "${!AGENT_PANES[@]}"; do
    pane="${AGENT_PANES[$agent]}"
    sync_one_pane "$agent" "${TMUX_WINDOW:-shogun:agents}.${pane}" "agents.${pane}" > "$_spv_tmp/${pane}_${agent}" 2>&1 &
    _spv_pids+=($!)
done

wait "${_spv_pids[@]}"

# 出力収集 + changed カウント（出力1行 = 変更1件）
for _spv_f in "$_spv_tmp"/*; do
    [[ -s "$_spv_f" ]] || continue
    while IFS= read -r _spv_line; do
        echo "$_spv_line"
        ((changed++)) || true
    done < "$_spv_f"
done
rm -rf "$_spv_tmp"

if [[ $changed -eq 0 ]]; then
    echo "  [sync] 変更なし（全ペイン同期済み）"
else
    echo "  [sync] ${changed} ペイン更新完了"
fi
# hanzo_test
