#!/bin/bash
# insight_write.sh — 学習ループの「次の気づき」を即座に保存
# Usage: bash scripts/insight_write.sh "気づきの内容" [priority] [source]
#   priority: high/medium/low (default: medium)
#   source: 気づきの出所 (default: manual)
#
# 設計原則: 1コマンドで保存完了。コスト最小。/clear後も消えない。
# 消費: idle時 or セッション開始時にqueue/insights.yamlを確認→着手

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSIGHTS_FILE="$SCRIPT_DIR/queue/insights.yaml"

msg="${1:?Usage: insight_write.sh \"message\" [priority] [source]}"
priority="${2:-medium}"
source_info="${3:-manual}"
ts="$(date -Iseconds)"

# Generate ID: INS-YYYYMMDD-HHMMSS-RANDOM (秒精度+乱数で一意性保証)
id="INS-$(date '+%Y%m%d-%H%M%S')-$(printf '%04x' $RANDOM)"

# flock for concurrent safety
(
  flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

  # Initialize file if empty or missing
  if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
    echo "insights: []" > "$INSIGHTS_FILE"
  fi

  # Append entry via Python (safe YAML handling)
  python3 -c "
import yaml, sys

with open('$INSIGHTS_FILE', 'r') as f:
    data = yaml.safe_load(f) or {}

if 'insights' not in data or not isinstance(data['insights'], list):
    data['insights'] = []

data['insights'].append({
    'id': '$id',
    'ts': '$ts',
    'insight': '''$msg''',
    'priority': '$priority',
    'source': '$source_info',
    'status': 'pending'
})

with open('$INSIGHTS_FILE', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
"

  echo "$id"

) 200>"$INSIGHTS_FILE.lock"
