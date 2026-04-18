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
import os
import sys

insights_file = os.environ['INSIGHTS_FILE_ENV']
resolve_id = os.environ['RESOLVE_ID_ENV']
ts = os.environ['TS_ENV']

with open(insights_file, 'r', encoding='utf-8') as f:
    lines = f.readlines()

found = False
modified = []
in_target = False
resolved_at_written = False

for line in lines:
    if line.startswith('- id: '):
        if in_target and not resolved_at_written:
            modified.append(f'  resolved_at: "{ts}"\n')
        current_id = line[len('- id: '):].strip()
        in_target = current_id == resolve_id
        if in_target:
            found = True
            resolved_at_written = False
        modified.append(line)
        continue

    if in_target and line.startswith('  status:'):
        modified.append('  status: done\n')
        if not resolved_at_written:
            modified.append(f'  resolved_at: "{ts}"\n')
            resolved_at_written = True
        continue

    if in_target and line.startswith('  resolved_at:'):
        modified.append(f'  resolved_at: "{ts}"\n')
        resolved_at_written = True
        continue

    modified.append(line)

if in_target and not resolved_at_written:
    modified.append(f'  resolved_at: "{ts}"\n')

if not found:
    print(f'ERROR: id not found: {resolve_id}', file=sys.stderr)
    sys.exit(1)

with open(insights_file, 'w', encoding='utf-8') as f:
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

# Skip synthetic test fixtures. They are useful in tests, but must not pollute the real queue.
if [[ "$msg" == *"test_pattern"* || "$msg" == *"test_fix"* ]]; then
  echo "SKIP:test-fixture"
  exit 0
fi

status="pending"
resolved_at=""
if [[ "$msg" == *"修正済み"* || "$msg" == *"解消"* || "$msg" == *"登録済み"* || "$msg" == *"対処済み"* ]]; then
  status="done"
  resolved_at="$ts"
fi

# Generate ID: INS-YYYYMMDD-HHMMSSmmm-{4hex} (ミリ秒精度+UUID先頭4桁)
id="INS-$(date '+%Y%m%d-%H%M%S%3N')-$(cut -c1-4 /proc/sys/kernel/random/uuid)"

# flock for concurrent safety
(
  flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

  # Initialize file if empty or missing
  if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
    printf 'insights:\n' > "$INSIGHTS_FILE"
  elif grep -qx 'insights: \[\]' "$INSIGHTS_FILE"; then
    printf 'insights:\n' > "$INSIGHTS_FILE"
  fi

  # Dedup check + raw YAML append (avoids full-file YAML rewrite data loss).
  # Parse the controlled YAML shape directly to avoid importing PyYAML on every call.
  result=$(INSIGHTS_FILE_ENV="$INSIGHTS_FILE" MSG_ENV="$msg" PRIORITY_ENV="$priority" \
           SOURCE_INFO_ENV="$source_info" ID_ENV="$id" TS_ENV="$ts" STATUS_ENV="$status" \
           RESOLVED_AT_ENV="$resolved_at" \
           python3 - <<'PYEOF'
import json
import os
import sys

insights_file = os.environ['INSIGHTS_FILE_ENV']
msg = os.environ['MSG_ENV']
priority = os.environ['PRIORITY_ENV']
source_info = os.environ['SOURCE_INFO_ENV']
entry_id = os.environ['ID_ENV']
ts = os.environ['TS_ENV']
status = os.environ['STATUS_ENV']
resolved_at = os.environ['RESOLVED_AT_ENV']

def parse_scalar(raw):
    value = raw.strip()
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

with open(insights_file, 'r', encoding='utf-8') as f:
    current_id = None
    current_insight = None
    current_status = None

    for line in f:
        if line.startswith('- id: '):
            if current_status == 'pending' and current_insight is not None:
                if current_insight == msg or (msg and current_insight[:50] == msg[:50]):
                    print('SKIP:' + current_id)
                    sys.exit(0)
            current_id = line[len('- id: '):].strip()
            current_insight = None
            current_status = None
            continue
        if current_id is None:
            continue
        if line.startswith('  insight:'):
            current_insight = parse_scalar(line.split(':', 1)[1])
        elif line.startswith('  status:'):
            current_status = parse_scalar(line.split(':', 1)[1])

    if current_status == 'pending' and current_insight is not None:
        if current_insight == msg or (msg and current_insight[:50] == msg[:50]):
            print('SKIP:' + current_id)
            sys.exit(0)

# Append raw YAML entry (no full-file rewrite — preserves existing multiline strings)
def yaml_escape(s):
    """JSON double-quoted strings are valid YAML double-quoted scalars."""
    return json.dumps(s, ensure_ascii=False)

with open(insights_file, 'a', encoding='utf-8') as f:
    f.write(f'- id: {entry_id}\n')
    f.write(f'  ts: {yaml_escape(ts)}\n')
    f.write(f'  insight: {yaml_escape(msg)}\n')
    f.write(f'  priority: {yaml_escape(priority)}\n')
    f.write(f'  source: {yaml_escape(source_info)}\n')
    f.write(f'  status: {status}\n')
    if resolved_at:
        f.write(f'  resolved_at: {yaml_escape(resolved_at)}\n')

print(entry_id)
PYEOF
)

  echo "$result"

) 200>"$INSIGHTS_FILE.lock"
