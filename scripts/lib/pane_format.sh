#!/usr/bin/env bash
# pane_format.sh — tmux pane-border-format 文字列の唯一の定義元（DRY原則）
# Usage: source scripts/lib/pane_format.sh
#
# Color: karo=#f9e2af(黄) gunshi=#94e2d5(ティール) Opus=#cba6f7(紫) Sonnet=#89dceb(水色)
#        Codex/gpt=#a6e3a1(緑) Haiku=#f9e2af(黄) else=#89b4fa(青)
# #{m:pattern,string} = fnmatch前方一致。"Opus 4.6 high"等にも対応

# shellcheck disable=SC2034  # sourced by shutsujin_departure.sh / reset_layout.sh
AGENTS_PANE_BORDER_FORMAT='#{?#{==:#{@agent_id},karo},#[fg=#f9e2af],#{?#{==:#{@agent_id},gunshi},#[fg=#94e2d5],#{?#{m:Opus*,#{@model_name}},#[fg=#cba6f7],#{?#{m:Sonnet*,#{@model_name}},#[fg=#89dceb],#{?#{m:Codex*,#{@model_name}},#[fg=#a6e3a1],#{?#{m:gpt-*,#{@model_name}},#[fg=#a6e3a1],#{?#{m:Haiku*,#{@model_name}},#[fg=#f9e2af],#[fg=#89b4fa]}}}}}}}#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[nobold] (#{@model_name}) #{@context_pct}#[default]#{?#{!=:#{@inbox_count},},#[fg=#fab387]#{@inbox_count}#[default],} #{@current_task}'
