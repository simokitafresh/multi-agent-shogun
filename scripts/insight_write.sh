#!/bin/bash
# insight_write.sh — 学習ループの「次の気づき」を即座に保存
# Usage: bash scripts/insight_write.sh "気づきの内容" [priority] [source]
#        bash scripts/insight_write.sh --resolve <id>
#   priority: high/medium/low (default: medium)
#   source: 気づきの出所 (default: manual)
#
# 設計原則: 1コマンドで保存完了。コスト最小。/clear後も消えない。
# 消費: idle時 or セッション開始時にqueue/insights.yamlを確認→着手

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSIGHTS_FILE="$SCRIPT_DIR/queue/insights.yaml"

# --resolve mode: mark insight as done
if [ "${1:-}" = "--resolve" ]; then
  resolve_id="${2:?Usage: insight_write.sh --resolve <id>}"
  ts="$(date -Iseconds)"

  (
    flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

    if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
      echo "ERROR: insights file not found or empty" >&2
      exit 1
    fi

    python3 -c "
import yaml, sys

with open('$INSIGHTS_FILE', 'r') as f:
    data = yaml.safe_load(f) or {}

insights = data.get('insights', [])
found = False
for item in insights:
    if item.get('id') == '$resolve_id':
        item['status'] = 'done'
        item['resolved_at'] = '$ts'
        found = True
        break

if not found:
    print('ERROR: id not found: $resolve_id', file=sys.stderr)
    sys.exit(1)

with open('$INSIGHTS_FILE', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
print('RESOLVED: $resolve_id')
"
  ) 200>"$INSIGHTS_FILE.lock"
  exit 0
fi

msg="${1:?Usage: insight_write.sh \"message\" [priority] [source]}"
priority="${2:-medium}"
source_info="${3:-manual}"
ts="$(date -Iseconds)"

# Generate ID: INS-YYYYMMDD-HHMMSSmmm-UUID8 (ミリ秒精度+UUID先頭8桁で衝突確率実用上ゼロ)
id="INS-$(date '+%Y%m%d-%H%M%S%3N')-$(cut -c1-8 /proc/sys/kernel/random/uuid)"

# flock for concurrent safety
(
  flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

  # Initialize file if empty or missing
  if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
    echo "insights: []" > "$INSIGHTS_FILE"
  fi

  # Append entry via Python (safe YAML handling + dedup check)
  result=$(python3 -c "
import yaml, sys

with open('$INSIGHTS_FILE', 'r') as f:
    data = yaml.safe_load(f) or {}

if 'insights' not in data or not isinstance(data['insights'], list):
    data['insights'] = []

# Dedup: skip if same insight text exists with status=pending
for existing in data['insights']:
    if existing.get('insight') == '''$msg''' and existing.get('status') == 'pending':
        print('SKIP:' + existing['id'])
        sys.exit(0)

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
print('$id')
")

  echo "$result"

) 200>"$INSIGHTS_FILE.lock"
