#!/usr/bin/env bash
# model_colors.sh — モデル別ペイン色定義（DRY原則: ここが唯一の定義元）
# Usage: source scripts/lib/model_colors.sh

# モデル表示名を正規化（Codex/Claude表示名 → モデルファミリー）
_normalize_model_name() {
  local model_display="$1"
  if declare -F resolve_model_display >/dev/null 2>&1 && [[ -n "${1:-}" && -z "${2:-}" ]]; then
    model_display="$(resolve_model_display "$1" 2>/dev/null || printf '%s' "$1")"
  fi
  case "$model_display" in
    *[Cc]odex*) echo "Codex" ;;
    [Gg][Pp][Tt]-*) echo "Codex" ;;
    *[Oo]pus*) echo "Opus" ;;
    *[Ss]onnet*) echo "Sonnet" ;;
    *[Hh]aiku*) echo "Haiku" ;;
    *)           echo "$model_display" ;;
  esac
}

resolve_bg_color() {
  local agent_id="$1"
  local model_display="$2"
  case "$agent_id" in
    karo|gunshi) echo "#121214" ;;
    *)
      case "$(_normalize_model_name "$model_display")" in
        Codex) echo "#201a1e" ;;   # 深紫系
        Opus) echo "#1a1e28" ;;   # 紺系
        Sonnet) echo "#1a2420" ;;   # 深緑系
        Haiku) echo "#1e2420" ;;   # 薄緑系
        *)       echo "#1a1e28" ;;   # fallback = Opus
      esac
      ;;
  esac
}

resolve_border_fg_color() {
  local model_display="$1"
  case "$(_normalize_model_name "$model_display")" in
    Codex) echo "#a6e3a1" ;;  # 緑
    Opus) echo "#cba6f7" ;;  # 紫
    Sonnet) echo "#89dceb" ;;  # 水色
    Haiku) echo "#f9e2af" ;;  # 黄
    *)       echo "#89b4fa" ;;  # fallback = 汎用Claude
  esac
}
