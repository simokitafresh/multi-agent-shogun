#!/usr/bin/env bash
# model_colors.sh — モデル別ペイン色定義（DRY原則: ここが唯一の定義元）
# Usage: source scripts/lib/model_colors.sh

# モデル表示名を正規化（"gpt-5.5 high" / "gpt-5.4 high" → "Codex", "Sonnet 4.6 high" → "Sonnet" 等）
_normalize_model_name() {
  local model_display="$1"
  case "$model_display" in
    *[Cc]odex*)  echo "Codex" ;;
    [Gg][Pp][Tt]-*) echo "Codex" ;;
    *[Oo]pus*)   echo "Opus" ;;
    *[Ss]onnet*) echo "Sonnet" ;;
    *[Hh]aiku*)  echo "Haiku" ;;
    *)           echo "$model_display" ;;
  esac
}

resolve_bg_color() {
  local agent_id="$1"
  local model_display="$2"
  local normalized
  normalized=$(_normalize_model_name "$model_display")
  case "$agent_id" in
    karo|gunshi) echo "#121214" ;;
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
  local normalized
  normalized=$(_normalize_model_name "$model_display")
  case "$normalized" in
    Opus*)   echo "#cba6f7" ;;  # 紫
    Sonnet*) echo "#89dceb" ;;  # 水色
    Codex*)  echo "#a6e3a1" ;;  # 緑
    Haiku*)  echo "#f9e2af" ;;  # 黄
    *)       echo "#89b4fa" ;;  # fallback = 汎用Claude
  esac
}
