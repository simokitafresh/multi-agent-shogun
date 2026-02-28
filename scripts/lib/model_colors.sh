#!/usr/bin/env bash
# model_colors.sh — モデル別ペイン色定義（DRY原則: ここが唯一の定義元）
# Usage: source scripts/lib/model_colors.sh

resolve_bg_color() {
  local agent_id="$1"
  local model_display="$2"
  # 生モデル文字列を正規化（例: "gpt-5.3-codex/high" → "Codex"）
  local normalized
  case "$model_display" in
    *[Cc]odex*)  normalized="Codex" ;;
    *[Oo]pus*)   normalized="Opus" ;;
    *[Ss]onnet*) normalized="Sonnet" ;;
    *[Hh]aiku*)  normalized="Haiku" ;;
    *)           normalized="$model_display" ;;
  esac
  case "$agent_id" in
    karo) echo "#121214" ;;
    *)
      case "$normalized" in
        Opus*)   echo "#1a1e28" ;;   # 紺系
        Sonnet*) echo "#1a2420" ;;   # 深緑系
        Codex*)  echo "#201a1e" ;;   # 深紫系
        Haiku*)  echo "#1e2420" ;;   # 薄緑系
        *)       echo "#1a1e28" ;;   # fallback = Opus
      esac
      ;;
  esac
}

resolve_border_fg_color() {
  local model_display="$1"
  # 生モデル文字列を正規化（例: "gpt-5.3-codex/high" → "Codex"）
  local normalized
  case "$model_display" in
    *[Cc]odex*)  normalized="Codex" ;;
    *[Oo]pus*)   normalized="Opus" ;;
    *[Ss]onnet*) normalized="Sonnet" ;;
    *[Hh]aiku*)  normalized="Haiku" ;;
    *)           normalized="$model_display" ;;
  esac
  case "$normalized" in
    Opus*)   echo "#cba6f7" ;;  # 紫
    Sonnet*) echo "#89b4fa" ;;  # 青
    Codex*)  echo "#a6e3a1" ;;  # 緑
    Haiku*)  echo "#f9e2af" ;;  # 黄
    *)       echo "#a6e3a1" ;;  # fallback = 緑
  esac
}
