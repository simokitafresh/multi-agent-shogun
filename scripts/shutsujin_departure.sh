#!/bin/bash
# shutsujin_departure.sh — セッション起動時の初期設定スクリプト
# Usage: bash scripts/shutsujin_departure.sh
#
# tmuxセッション作成後、エージェント起動前に実行する。
# セッション固有の設定を適用する。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─── remain-on-exit (cmd_183) ───
# CLIプロセスが死んでもペインを残す（OOM Kill等の原因調査用）
# agents window(shogun:2)のみ。将軍window(shogun:1)は不要。
tmux set-option -w -t shogun:2 remain-on-exit on 2>/dev/null

echo "[shutsujin] remain-on-exit: on (shogun:2)"

# ─── pane-border-format with inbox count (cmd_188) ───
# Color scheme: karo=#f9e2af(黄) Opus=#cba6f7(紫) Sonnet=#89b4fa(青) else=#a6e3a1(緑)
# #{m:pattern,string} = fnmatch前方一致。"Opus 4.6"等バージョン付きにも対応
# Window 2 (agents): agent_id + model_name + context_pct + inbox_count + current_task
tmux set-option -w -t shogun:2 pane-border-format \
  '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:Sonnet*,#{@model_name}},#[fg=#89b4fa],#[fg=#a6e3a1]}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}' \
  2>/dev/null

# Window 1 (shogun): Opus紫(#cba6f7) + model_name + context_pct
tmux set-option -w -t shogun:1 pane-border-status top 2>/dev/null
tmux set-option -w -t shogun:1 pane-border-format \
  '#[fg=#cba6f7]#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]' \
  2>/dev/null

echo "[shutsujin] pane-border-format: inbox count enabled (shogun:1, shogun:2)"

# ─── status bar style: Catppuccin Mocha base ───
tmux set-option -g status-style "bg=#1e1e2e,fg=#cdd6f4" 2>/dev/null
echo "[shutsujin] status-style: Catppuccin Mocha base (#1e1e2e)"

# ─── session status-right: datetime ───
tmux set-option -t shogun status-right-length 200
tmux set-option -t shogun status-right "#[fg=#cdd6f4]%Y-%m-%d %H:%M"

echo "[shutsujin] status-right: datetime only"

# ─── gunshi pane variables (cmd_389) ───
# 軍師ペイン(saizo転用pane 7)にエージェント識別変数を設定
# ninja_monitor.shはNINJA_NAMESから軍師を除外し、auto-/clear対象外とする
tmux set-option -p -t shogun:2.7 @agent_id gunshi 2>/dev/null
tmux set-option -p -t shogun:2.7 @agent_cli claude 2>/dev/null
tmux set-option -p -t shogun:2.7 @model_name Opus 2>/dev/null
echo "[shutsujin] gunshi pane variables set (shogun:2.7, model=Opus)"

# ─── gunshi model switch (cmd_399) ───
# 現行セッションが起動中ならOpusに即時切替
# shutsujin_departure.shはCLI起動しない(tmux変数設定のみ)
# CLIが既に起動している場合のみ /model コマンドを送信
tmux send-keys -t shogun:2.7 "/model claude-opus-4-6" Enter 2>/dev/null
echo "[shutsujin] gunshi model switch sent (claude-opus-4-6)"
