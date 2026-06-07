#!/usr/bin/env bash
# shout.sh — 忍者のバトルクライを1行で出力するラッパー
# Usage: bash scripts/shout.sh <ninja_name>
# 引数は忍者名のみ。報告YAMLからsummaryを自動読込し、戦国風1行を生成。

set -euo pipefail

# SCRIPT_DIR: string ops instead of $(cd) subshell (~5ms savings on WSL2)
_sh_self="${BASH_SOURCE[0]}"
[[ "$_sh_self" != /* ]] && _sh_self="$PWD/$_sh_self"
SCRIPT_DIR="${_sh_self%/scripts/shout.sh}"
unset _sh_self
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"

ninja_name="${1:-}"

if [[ -z "$ninja_name" ]]; then
  echo "Usage: shout.sh <ninja_name>" >&2
  exit 1
fi

# 日本語名マッピング（settings.yamlから動的取得 — cmd_1136）
jp_name=$(get_japanese_name "$ninja_name")
if [[ "$jp_name" == "$ninja_name" ]]; then
  echo "Unknown ninja: $ninja_name" >&2
  exit 1
fi

TASK_FILE="$SCRIPT_DIR/queue/tasks/${ninja_name}.yaml"

# task YAML から rf / pcmd / echo_msg を一括読込（grep|sed×9 → while read 0 subprocess）
rf="" pcmd="" echo_msg=""
if [[ -f "$TASK_FILE" ]]; then
  while IFS= read -r _line; do
    case "$_line" in
      *'report_filename:'*)
        if [[ -z "$rf" ]]; then
          rf="${_line#*: }"; rf="${rf#[\"\']}"; rf="${rf%[\"\']}"
        fi ;;
      *'parent_cmd:'*)
        if [[ -z "$pcmd" ]]; then
          pcmd="${_line#*: }"; pcmd="${pcmd#[\"\']}"; pcmd="${pcmd%[\"\']}"
        fi ;;
      *'echo_message:'*)
        if [[ -z "$echo_msg" ]]; then
          echo_msg="${_line#*: }"; echo_msg="${echo_msg#[\"\']}"; echo_msg="${echo_msg%[\"\']}"
        fi ;;
    esac
  done < "$TASK_FILE"
fi

# 報告ファイル解決: task YAMLの report_filename → parent_cmd → glob最新 → レガシー固定名
REPORT_FILE=""
if [[ -n "$rf" ]]; then
  REPORT_FILE="$SCRIPT_DIR/queue/reports/${rf}"
fi
if [[ -z "$REPORT_FILE" || ! -f "$REPORT_FILE" ]] && [[ -n "$pcmd" ]]; then
  candidate="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${pcmd}.yaml"
  [[ -f "$candidate" ]] && REPORT_FILE="$candidate"
fi
if [[ -z "$REPORT_FILE" || ! -f "$REPORT_FILE" ]]; then
  # bash glob + -nt 比較（find|sort|head|cut 4 subprocesses → 0）
  _latest=""
  for _f in "$SCRIPT_DIR/queue/reports/${ninja_name}_report_"*.yaml; do
    [[ -f "$_f" ]] || continue
    [[ -z "$_latest" || "$_f" -nt "$_latest" ]] && _latest="$_f"
  done
  if [[ -n "$_latest" ]]; then
    REPORT_FILE="$_latest"
  else
    REPORT_FILE="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
  fi
fi

# 優先1: タスクYAMLの echo_message フィールド（既にwhile readで取得済み）
if [[ -n "$echo_msg" ]]; then
  echo "$echo_msg"
  exit 0
fi

# 優先2: 報告YAMLの result.summary（awk で python3 subprocess を排除）
if [[ -f "$REPORT_FILE" ]]; then
  summary=$(awk '
    /^result:/ { in_result=1; next }
    in_result && /^[^[:space:]]/ { in_result=0 }
    in_result && /^[[:space:]]+summary:/ {
      v = $0; sub(/^[[:space:]]+summary:[[:space:]]*/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      print v; exit
    }
  ' "$REPORT_FILE" 2>/dev/null || true)

  if [[ -n "$summary" ]]; then
    # 40文字で切る（bash substring = マルチバイト安全）
    truncated="${summary:0:40}"
    if [[ ${#summary} -gt 40 ]]; then
      truncated="${truncated}…"
    fi
    echo "🏯 ${jp_name}、${truncated}！"
    exit 0
  fi
fi

# フォールバック
echo "🏯 ${jp_name}、待機中"
