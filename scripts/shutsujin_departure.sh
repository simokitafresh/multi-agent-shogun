#!/bin/bash
# shutsujin_departure.sh — セッション起動時の初期設定スクリプト
# Usage: bash scripts/shutsujin_departure.sh
#
# tmuxセッション作成後、エージェント起動前に実行する。
# セッション固有の設定を適用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# モデル検出ライブラリ（将軍@model_name同期用）
if [ -f "$SCRIPT_DIR/scripts/lib/cli_lookup.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"
fi
if [ -f "$SCRIPT_DIR/scripts/lib/model_detect.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/scripts/lib/model_detect.sh"
fi

# 互換ターゲット解決（window名優先、なければ従来index）
resolve_window_target() {
    local named_target="$1"
    local indexed_target="$2"
    if tmux list-panes -t "$named_target" >/dev/null 2>&1; then
        echo "$named_target"
    else
        echo "$indexed_target"
    fi
}

resolve_first_pane_target() {
    local window_target="$1"
    local pane_index
    pane_index=$(tmux list-panes -t "$window_target" -F '#{pane_index}' 2>/dev/null | head -1)
    if [ -n "$pane_index" ]; then
        echo "${window_target}.${pane_index}"
    else
        # pane-base-index=1前提の最終フォールバック
        echo "${window_target}.1"
    fi
}

SHOGUN_WINDOW_TARGET=$(resolve_window_target "shogun:main" "shogun:1")
AGENTS_WINDOW_TARGET=$(resolve_window_target "shogun:agents" "shogun:2")
SHOGUN_PANE_TARGET=$(resolve_first_pane_target "$SHOGUN_WINDOW_TARGET")

# ─── remain-on-exit (cmd_183) ───
# CLIプロセスが死んでもペインを残す（OOM Kill等の原因調査用）
# agents windowのみ。将軍windowは不要。
tmux set-option -w -t "$AGENTS_WINDOW_TARGET" remain-on-exit on 2>/dev/null

echo "[shutsujin] remain-on-exit: on (${AGENTS_WINDOW_TARGET})"

# ─── pane-border-format with inbox count (cmd_188) ───
# Color scheme: karo=#f9e2af(黄) Opus=#cba6f7(紫) Sonnet=#89b4fa(青) else=#a6e3a1(緑)
# #{m:pattern,string} = fnmatch前方一致。"Opus 4.6"等バージョン付きにも対応
# agents: agent_id + model_name + context_pct + inbox_count + current_task
tmux set-option -w -t "$AGENTS_WINDOW_TARGET" pane-border-format \
  '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:Sonnet*,#{@model_name}},#[fg=#89b4fa],#[fg=#a6e3a1]}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}' \
  2>/dev/null

# shogun: Opus紫(#cba6f7) + model_name + context_pct
tmux set-option -w -t "$SHOGUN_WINDOW_TARGET" pane-border-status top 2>/dev/null
tmux set-option -w -t "$SHOGUN_WINDOW_TARGET" pane-border-format \
  '#[fg=#cba6f7]#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]' \
  2>/dev/null

# 将軍ペイン変数を補正（@model_nameは実モデル優先）
tmux set-option -p -t "$SHOGUN_PANE_TARGET" @agent_id shogun 2>/dev/null
shogun_model=$(tmux show-options -p -t "$SHOGUN_PANE_TARGET" -v @model_name 2>/dev/null || echo "")
if declare -F detect_real_model >/dev/null 2>&1; then
    detected_model=$(detect_real_model shogun "$SHOGUN_PANE_TARGET" 2>/dev/null || echo "")
    if [ -n "$detected_model" ]; then
        shogun_model="$detected_model"
    fi
fi
if [ -z "$shogun_model" ] && declare -F cli_profile_get >/dev/null 2>&1; then
    shogun_model=$(cli_profile_get shogun "display_name" 2>/dev/null || echo "")
fi
shogun_model="${shogun_model:-claude-opus-4-6}"
tmux set-option -p -t "$SHOGUN_PANE_TARGET" @model_name "$shogun_model" 2>/dev/null

echo "[shutsujin] pane-border-format: applied (${SHOGUN_WINDOW_TARGET}, ${AGENTS_WINDOW_TARGET})"
echo "[shutsujin] shogun pane vars: @agent_id=shogun @model_name=${shogun_model} (${SHOGUN_PANE_TARGET})"

# ─── status bar style: Catppuccin Mocha base ───
tmux set-option -g status-style "bg=#1e1e2e,fg=#cdd6f4" 2>/dev/null
echo "[shutsujin] status-style: Catppuccin Mocha base (#1e1e2e)"

# ─── session status-right: datetime ───
tmux set-option -t shogun status-right-length 200
tmux set-option -t shogun status-right "#[fg=#cdd6f4]%Y-%m-%d %H:%M"

echo "[shutsujin] status-right: datetime only"

# ─── saizo pane variables (cmd_403: gunshi凍結→saizo復帰) ───
AGENTS_PANE_BASE=$(tmux show-options -gv pane-base-index 2>/dev/null || echo "1")
SAIZO_PANE_INDEX=$((AGENTS_PANE_BASE + 6))
SAIZO_PANE_TARGET="${AGENTS_WINDOW_TARGET}.${SAIZO_PANE_INDEX}"
tmux set-option -p -t "$SAIZO_PANE_TARGET" @agent_id saizo 2>/dev/null
tmux set-option -p -t "$SAIZO_PANE_TARGET" @agent_cli codex 2>/dev/null
tmux set-option -p -t "$SAIZO_PANE_TARGET" @model_name "gpt-5.3-codex high" 2>/dev/null
echo "[shutsujin] saizo pane variables set (${SAIZO_PANE_TARGET}, model=gpt-5.3-codex high, cli=codex)"

# ─── idle flag initialization (cmd_455) ───
for agent in karo sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru; do
    touch "/tmp/shogun_idle_${agent}"
done
echo "[shutsujin] idle flags: created for all agents"
