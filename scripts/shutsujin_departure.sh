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

# Window 1 (shogun): agent_id + model_name + context_pct + inbox_count + current_task
tmux set-option -w -t shogun:1 pane-border-format \
  '#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:Sonnet*,#{@model_name}},#[fg=#89b4fa],#[fg=#a6e3a1]}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}' \
  2>/dev/null

echo "[shutsujin] pane-border-format: inbox count enabled (shogun:1, shogun:2)"

# ─── session status-right: MCAS usage display (cmd_331/cmd_341) ───
# BGループ方式: usage_statusbar_loop.shが60秒ごとにstatus-rightを値+色込みで直接更新。
# #()方式は色が効かないため不採用（検証済み）。
# 色: active=白(#ffffff), inactive=薄グレー(#585b70), PJ名=#89b4fa(青), 区切り=#585b70(灰)
# 注意: session-level（-gなし）に設定すること。globalだとsession設定に負ける。
MCAS_LOOP_SCRIPT="/mnt/c/Python_app/multi-claude-account-switcher/usage_statusbar_loop.sh"
MCAS_LOOP_PID_FILE="/tmp/mcas_statusbar_loop.pid"

# まずsession-levelのstatus-rightを暫定値で設定（ループ起動前でも表示される）
tmux set-option status-right-length 200
tmux set-option status-right "#[fg=#89b4fa][mcas] #[fg=#585b70]| #[fg=#585b70]Main D:—  W:—  #[fg=#585b70]| #[fg=#ffffff]Sub D:—  W:—  #[fg=#585b70]| #[fg=#cdd6f4]%Y-%m-%d %H:%M"

if [[ -f "$MCAS_LOOP_SCRIPT" ]]; then
    # Check if already running
    already_running=false
    if [[ -f "$MCAS_LOOP_PID_FILE" ]]; then
        old_pid=$(cat "$MCAS_LOOP_PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            already_running=true
        fi
    fi

    if [[ "$already_running" == true ]]; then
        echo "[shutsujin] status-right: MCAS usage loop already running (PID: ${old_pid}), skip"
    else
        nohup bash "$MCAS_LOOP_SCRIPT" >> /tmp/mcas_statusbar_loop.log 2>&1 &
        sleep 1
        echo "[shutsujin] status-right: MCAS usage loop started (PID: $(cat "$MCAS_LOOP_PID_FILE" 2>/dev/null))"
    fi
else
    echo "[shutsujin] status-right: MCAS loop script not found, static fallback set"
fi
