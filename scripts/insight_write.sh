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

    # Line-by-line edit: avoids full-file YAML rewrite data loss
    INSIGHTS_FILE_ENV="$INSIGHTS_FILE" RESOLVE_ID_ENV="$resolve_id" TS_ENV="$ts" \
    python3 - <<'PYEOF'
import sys, os

insights_file = os.environ['INSIGHTS_FILE_ENV']
resolve_id = os.environ['RESOLVE_ID_ENV']
ts = os.environ['TS_ENV']

with open(insights_file, 'r') as f:
    lines = f.readlines()

found = False
modified = []
i = 0
while i < len(lines):
    line = lines[i]
    # Detect target entry by id field
    if not found and 'id:' in line and resolve_id in line:
        found = True
        modified.append(line)
        i += 1
        # Process fields within this entry block
        while i < len(lines):
            line = lines[i]
            # New list entry at column 0 = end of current block
            if line.startswith('- '):
                break
            # Top-level key (not indented, not comment) = end of block
            if line[0:1] and not line[0:1].isspace() and not line.lstrip().startswith('#'):
                break
            if line.strip().startswith('status:'):
                indent = line[:len(line) - len(line.lstrip())]
                modified.append(f'{indent}status: done\n')
                modified.append(f'{indent}resolved_at: "{ts}"\n')
                i += 1
                continue
            modified.append(line)
            i += 1
        continue
    modified.append(line)
    i += 1

if not found:
    print(f'ERROR: id not found: {resolve_id}', file=sys.stderr)
    sys.exit(1)

with open(insights_file, 'w') as f:
    f.writelines(modified)
print(f'RESOLVED: {resolve_id}')
PYEOF
  ) 200>"$INSIGHTS_FILE.lock"
  exit 0
fi

msg="${1:?Usage: insight_write.sh \"message\" [priority] [source]}"
priority="${2:-medium}"
source_info="${3:-manual}"
ts="$(date -Iseconds)"

# Generate ID: INS-YYYYMMDD-HHMMSSmmm-{4hex} (ミリ秒精度+UUID先頭4桁)
id="INS-$(date '+%Y%m%d-%H%M%S%3N')-$(cut -c1-4 /proc/sys/kernel/random/uuid)"

# flock for concurrent safety
(
  flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

  # Initialize file if empty or missing
  if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
    echo "insights: []" > "$INSIGHTS_FILE"
  fi

  # Dedup check + raw YAML append (avoids full-file YAML rewrite data loss)
  # Pass values via env vars to prevent shell injection (cmd_1407 AC1)
  result=$(INSIGHTS_FILE_ENV="$INSIGHTS_FILE" MSG_ENV="$msg" PRIORITY_ENV="$priority" \
           SOURCE_INFO_ENV="$source_info" ID_ENV="$id" TS_ENV="$ts" \
           python3 - <<'PYEOF'
import yaml, json, sys, os

insights_file = os.environ['INSIGHTS_FILE_ENV']
msg = os.environ['MSG_ENV']
priority = os.environ['PRIORITY_ENV']
source_info = os.environ['SOURCE_INFO_ENV']
entry_id = os.environ['ID_ENV']
ts = os.environ['TS_ENV']

with open(insights_file, 'r') as f:
    data = yaml.safe_load(f) or {}

# Dedup: skip if exact match or first-50-char match with status=pending (single pass)
for existing in data.get('insights', []):
    if existing.get('status') != 'pending':
        continue
    ex_text = existing.get('insight', '')
    if ex_text == msg:
        print('SKIP:' + existing['id'])
        sys.exit(0)
    if len(msg) > 0 and ex_text[:50] == msg[:50]:
        print('SKIP:' + existing['id'] + ' (first-50-char dedup)', file=sys.stderr)
        print('SKIP:' + existing['id'])
        sys.exit(0)

# Handle empty insights: rewrite file header for append compatibility
if not data.get('insights'):
    with open(insights_file, 'w') as f:
        f.write('insights:\n')

# Append raw YAML entry (no full-file rewrite — preserves existing multiline strings)
def yaml_escape(s):
    """JSON double-quoted strings are valid YAML double-quoted scalars."""
    return json.dumps(s, ensure_ascii=False)

with open(insights_file, 'a') as f:
    f.write(f'- id: {entry_id}\n')
    f.write(f'  ts: {yaml_escape(ts)}\n')
    f.write(f'  insight: {yaml_escape(msg)}\n')
    f.write(f'  priority: {priority}\n')
    f.write(f'  source: {yaml_escape(source_info)}\n')
    f.write(f'  status: pending\n')

print(entry_id)
PYEOF
)

  echo "$result"

) 200>"$INSIGHTS_FILE.lock"
