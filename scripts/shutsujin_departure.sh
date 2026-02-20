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
# Window 2 (agents): agent_id + model_name + context_pct + inbox_count + current_task
tmux set-option -w -t shogun:2 pane-border-format \
  '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{==:#{@model_name},Opus},#[fg=#cba6f7],#[fg=#a6e3a1]}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}' \
  2>/dev/null

# Window 1 (shogun): agent_id + model_name + inbox_count
tmux set-option -w -t shogun:1 pane-border-format \
  '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{==:#{@model_name},Opus},#[fg=#cba6f7],#[fg=#a6e3a1]}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name})#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],}' \
  2>/dev/null

echo "[shutsujin] pane-border-format: inbox count enabled (shogun:1, shogun:2)"
