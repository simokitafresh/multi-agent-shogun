#!/usr/bin/env bash
# tmux pane-border-formatの唯一の定義元（DRY原則）。

# shellcheck disable=SC2034  # sourced by shutsujin_departure.sh / reset_layout.sh
AGENTS_PANE_BORDER_FORMAT='#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{==:#{@agent_id},gunshi},#[fg=#94e2d5],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:Sonnet*,#{@model_name}},#[fg=#89dceb],#{?#{m:Codex*,#{@model_name}},#[fg=#a6e3a1],#{?#{m:gpt-*,#{@model_name}},#[fg=#a6e3a1],#{?#{m:Haiku*,#{@model_name}},#[fg=#f9e2af],#[fg=#89b4fa]}}}}}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}'
