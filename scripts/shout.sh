#!/usr/bin/env bash
# shout.sh — 忍者のバトルクライを1行で出力するラッパー
# Usage: bash scripts/shout.sh <ninja_name>
# 引数は忍者名のみ。報告YAMLからsummaryを自動読込し、戦国風1行を生成。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# 報告ファイル解決: task YAMLの report_filename → glob最新 → レガシー固定名
REPORT_FILE=""
if [[ -f "$TASK_FILE" ]]; then
  rf=$(grep -m1 '^\s*report_filename:' "$TASK_FILE" 2>/dev/null | sed 's/^[^:]*:\s*//' | sed 's/^["'\'']\|["'\''"]$//g' || true)
  if [[ -n "$rf" ]]; then
    REPORT_FILE="$SCRIPT_DIR/queue/reports/${rf}"
  fi
fi
if [[ -z "$REPORT_FILE" || ! -f "$REPORT_FILE" ]] && [[ -f "$TASK_FILE" ]]; then
  # parent_cmdからレポートファイル名を構築（stale report防止）
  pcmd=$(grep -m1 '^\s*parent_cmd:' "$TASK_FILE" 2>/dev/null | sed 's/^[^:]*:\s*//' | sed "s/^[\"']\|[\"']$//g" || true)
  if [[ -n "$pcmd" ]]; then
    candidate="$SCRIPT_DIR/queue/reports/${ninja_name}_report_${pcmd}.yaml"
    [[ -f "$candidate" ]] && REPORT_FILE="$candidate"
  fi
fi
if [[ -z "$REPORT_FILE" || ! -f "$REPORT_FILE" ]]; then
  # glob最新: cmd番号付きレポートの最新ファイル（最終フォールバック）
  latest=$(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -name "${ninja_name}_report_*.yaml" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
  if [[ -n "$latest" ]]; then
    REPORT_FILE="$latest"
  else
    REPORT_FILE="$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
  fi
fi

# 優先1: タスクYAMLの echo_message フィールド
if [[ -f "$TASK_FILE" ]]; then
  echo_msg=$(grep -m1 '^\s*echo_message:' "$TASK_FILE" 2>/dev/null | sed 's/^[^:]*:\s*//' | sed 's/^["'\'']\|["'\''"]$//g' || true)
  if [[ -n "$echo_msg" ]]; then
    echo "$echo_msg"
    exit 0
  fi
fi

# 優先2: 報告YAMLの result.summary（yaml.safe_loadで全形式対応）
if [[ -f "$REPORT_FILE" ]]; then
  summary=$(python3 -c "
import yaml, sys
try:
    with open(sys.argv[1]) as f:
        d = yaml.safe_load(f)
    s = (d or {}).get('result', {}).get('summary', '') or ''
    print(s.split('\n')[0].strip())
except Exception:
    pass
" "$REPORT_FILE" 2>/dev/null || true)

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
