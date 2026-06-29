#!/bin/bash
# semantic-links: [[セマンティック辞書構想]]
# insight_write.sh — 学習ループの「次の気づき」を即座に保存
# Usage: bash scripts/insight_write.sh "気づきの内容" [priority] [source]
#        bash scripts/insight_write.sh --resolve <id>
#   priority: high/medium/low (default: medium)
#   source: 気づきの出所 (default: manual)
#
# 設計原則: 1コマンドで保存完了。コスト最小。/clear後も消えない。
# 消費: idle時 or セッション開始時にqueue/insights.yamlを確認→着手

set -euo pipefail

_insight_self="${BASH_SOURCE[0]:-$0}"
[[ "$_insight_self" != /* ]] && _insight_self="$PWD/$_insight_self"
SCRIPT_DIR="${_insight_self%/scripts/insight_write.sh}"
INSIGHTS_FILE="${INSIGHTS_FILE:-$SCRIPT_DIR/queue/insights.yaml}"
BULLETIN_SCRIPT="$SCRIPT_DIR/scripts/bulletin_write.sh"
MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert_async.py"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
  MEMORY_DB_LIVE_INSERT="$SCRIPT_DIR/scripts/memory_db_live_insert.py"
fi
SOURCE_REPEAT_THRESHOLD="${INSIGHT_SOURCE_REPEAT_THRESHOLD:-3}"

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

# Validate priority
if [[ ! "$priority" =~ ^(high|medium|low)$ ]]; then
  echo "ERROR: priority must be high/medium/low, got: '$priority'" >&2
  exit 1
fi
if [[ ! "$SOURCE_REPEAT_THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: INSIGHT_SOURCE_REPEAT_THRESHOLD must be a non-negative integer, got: '$SOURCE_REPEAT_THRESHOLD'" >&2
  exit 1
fi

# Skip synthetic test fixtures. They are useful in tests, but must not pollute the real queue.
if [[ "$msg" == *"test_pattern"* || "$msg" == *"test_fix"* ]]; then
  echo "SKIP:test-fixture"
  exit 0
fi

# Generate ID and ts in a single date call (eliminates redundant second subprocess).
# Placed after test-fixture exit to avoid date overhead on skipped calls.
read -r _insight_uuid < /proc/sys/kernel/random/uuid
_insight_now="$(date '+%Y%m%d-%H%M%S%3N %Y-%m-%dT%H:%M:%S%:z')"
id="INS-${_insight_now%% *}-${_insight_uuid:0:4}"
ts="${_insight_now#* }"

status="pending"
resolved_at=""
if [[ "$msg" == *"修正済み"* || "$msg" == *"解消"* || "$msg" == *"登録済み"* || "$msg" == *"対処済み"* ]]; then
  status="done"
  resolved_at="$ts"
fi

# flock for concurrent safety
(
  flock -w 5 200 || { echo "ERROR: lock timeout"; exit 1; }

  # Initialize file if empty or missing
  if [ ! -f "$INSIGHTS_FILE" ] || [ ! -s "$INSIGHTS_FILE" ]; then
    printf 'insights:\n' > "$INSIGHTS_FILE"
  else
    IFS= read -r _iw_first <"$INSIGHTS_FILE" || true
    [[ "$_iw_first" == 'insights: []' ]] && printf 'insights:\n' > "$INSIGHTS_FILE"
  fi

  # Dedup check + raw YAML append + source repeat count (single Python process).
  # Merging into one pass avoids a second python3 startup and second file read.
  # Parse the controlled YAML shape directly to avoid importing PyYAML on every call.
  raw_result=$(INSIGHTS_FILE_ENV="$INSIGHTS_FILE" MSG_ENV="$msg" PRIORITY_ENV="$priority" \
               SOURCE_INFO_ENV="$source_info" ID_ENV="$id" TS_ENV="$ts" STATUS_ENV="$status" \
               RESOLVED_AT_ENV="$resolved_at" \
               python3 - <<'PYEOF'
import json
import os
import re
import sys
import tempfile
import time

insights_file = os.environ['INSIGHTS_FILE_ENV']
msg = os.environ['MSG_ENV']
priority = os.environ['PRIORITY_ENV']
source_info = os.environ['SOURCE_INFO_ENV']
entry_id = os.environ['ID_ENV']
ts = os.environ['TS_ENV']
status = os.environ['STATUS_ENV']
resolved_at = os.environ['RESOLVED_AT_ENV']

def repair_trailing_partial_entry(path):
    """Quarantine an incomplete tail entry before scanning/appending."""
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    if not lines:
        return

    truncate_at = None
    current_start = None
    current_has_status = False
    known_fields = ('  ts:', '  insight:', '  priority:', '  source:', '  status:', '  resolved_at:')

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if idx == 0 and stripped == 'insights:':
            continue
        if not stripped:
            continue
        if line.startswith('- id: '):
            if current_start is not None and not current_has_status:
                truncate_at = current_start
                break
            current_start = idx
            current_has_status = False
            continue
        if current_start is None:
            truncate_at = idx
            break
        if line.startswith('  status:'):
            current_has_status = True
            continue
        if line.startswith(known_fields):
            continue
        truncate_at = idx
        break

    if truncate_at is None and current_start is not None and not current_has_status:
        truncate_at = current_start

    if truncate_at is None:
        return

    keep = lines[:truncate_at]
    corrupt = lines[truncate_at:]
    if not keep:
        keep = ['insights:\n']
    elif keep[-1] and not keep[-1].endswith('\n'):
        keep[-1] += '\n'

    corrupt_path = f"{path}.corrupt.{int(time.time() * 1000)}"
    with open(corrupt_path, 'w', encoding='utf-8') as f:
        f.writelines(corrupt)
    with open(path, 'w', encoding='utf-8') as f:
        f.writelines(keep)
        f.flush()
        os.fsync(f.fileno())

repair_trailing_partial_entry(insights_file)

def parse_scalar(raw):
    value = raw.strip()
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    return value

def normalize_text(value):
    return re.sub(r'\s+', ' ', value).strip().lower()

def direct_alias_key(value):
    match = re.search(r'\[\[[^\]]+\]\]\s*alias:\s*(.+)', value, flags=re.IGNORECASE)
    if not match:
        return None
    aliases = [normalize_text(part) for part in match.group(1).split(',')]
    aliases = [part for part in aliases if part]
    if not aliases:
        return None
    return 'direct_alias:' + '|'.join(sorted(aliases))

def semantic_query_key(value):
    direct = direct_alias_key(value)
    if direct:
        return direct
    normalized = normalize_text(value)
    if not normalized:
        return None
    return 'query:' + normalized

new_semantic_key = semantic_query_key(msg)

# Single-pass: dedup check + source repeat count
current_id = None
current_insight = None
current_status = None
current_source = None
current_semantic_key = None
source_pending_count = 0

with open(insights_file, 'r', encoding='utf-8') as f:
    for line in f:
        if line.startswith('- id: '):
            if current_status == 'pending':
                if current_insight is not None:
                    if current_insight == msg or (msg and current_insight[:50] == msg[:50]):
                        print('SKIP:' + current_id)
                        sys.exit(0)
                    if (
                        current_source == source_info
                        and new_semantic_key is not None
                        and current_semantic_key is not None
                        and (
                            current_semantic_key == new_semantic_key
                            or current_insight[:50] == msg[:50]
                        )
                    ):
                        print('SKIP:' + current_id)
                        sys.exit(0)
                if current_source == source_info:
                    source_pending_count += 1
            current_id = line[len('- id: '):].strip()
            current_insight = None
            current_status = None
            current_source = None
            current_semantic_key = None
            continue
        if current_id is None:
            continue
        if line.startswith('  insight:'):
            current_insight = parse_scalar(line.split(':', 1)[1])
            current_semantic_key = semantic_query_key(current_insight)
        elif line.startswith('  status:'):
            current_status = parse_scalar(line.split(':', 1)[1])
        elif line.startswith('  source:'):
            current_source = parse_scalar(line.split(':', 1)[1])

# Finalize last entry
if current_status == 'pending':
    if current_insight is not None:
        if current_insight == msg or (msg and current_insight[:50] == msg[:50]):
            print('SKIP:' + current_id)
            sys.exit(0)
        if (
            current_source == source_info
            and new_semantic_key is not None
            and current_semantic_key is not None
            and (
                current_semantic_key == new_semantic_key
                or current_insight[:50] == msg[:50]
            )
        ):
            print('SKIP:' + current_id)
            sys.exit(0)
    if current_source == source_info:
        source_pending_count += 1

# Count new entry itself if it will be pending
if status == 'pending':
    source_pending_count += 1

# Append raw YAML entry via atomic replace. This keeps raw YAML bytes intact while
# preventing a killed writer from leaving a half-written entry in the live file.
def yaml_escape(s):
    """JSON double-quoted strings are valid YAML double-quoted scalars."""
    return json.dumps(s, ensure_ascii=False)

entry_lines = [
    f'- id: {entry_id}\n',
    f'  ts: {yaml_escape(ts)}\n',
    f'  insight: {yaml_escape(msg)}\n',
    f'  priority: {yaml_escape(priority)}\n',
    f'  source: {yaml_escape(source_info)}\n',
    f'  status: {status}\n',
]
if resolved_at:
    entry_lines.append(f'  resolved_at: {yaml_escape(resolved_at)}\n')

directory = os.path.dirname(os.path.abspath(insights_file)) or '.'
fd, tmp_path = tempfile.mkstemp(prefix='.insights.', suffix='.tmp', dir=directory)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        with open(insights_file, 'r', encoding='utf-8') as src:
            for line in src:
                out.write(line)
        out.writelines(entry_lines)
        out.flush()
        os.fsync(out.fileno())
    os.replace(tmp_path, insights_file)
finally:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)

# Line 1: entry_id; Line 2: source_pending_count (for bulletin threshold check)
print(entry_id)
print(source_pending_count)
PYEOF
) || { echo "ERROR: insight write failed" >&2; exit 1; }

  result="${raw_result%%$'\n'*}"
  echo "$result"

  if [[ "$result" == INS-* && -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    memory_db_args=(
      insight
      --entry-id "$result"
      --ts "$ts"
      --insight "$msg"
      --priority "$priority"
      --source "$source_info"
      --status "$status"
      --resolved-at "$resolved_at"
      --source-file "$INSIGHTS_FILE"
    )
    if [[ -n "${SHOGUN_MEMORY_DB:-}" ]]; then
      if ! python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null; then
        echo "WARN: insight DB INSERT skipped" >&2
      fi
    else
      python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null 2>&1 200>&- &
      disown 2>/dev/null || true
    fi
  fi

  # Escalate repeated pending insights from the same source so important patterns
  # do not remain buried in queue/insights.yaml. Keep this out of the write path:
  # bulletin failures must not break normal insight recording.
  if [[ "$result" == INS-* && "$SOURCE_REPEAT_THRESHOLD" -gt 0 ]]; then
    repeat_count="${raw_result##*$'\n'}"
    if [[ "$repeat_count" -ge "$SOURCE_REPEAT_THRESHOLD" && -f "$BULLETIN_SCRIPT" ]]; then
      # デバウンス: 同一sourceのINSIGHT_REPEATを24時間以内に重複投稿しない (10分→24h: 2026-06-29 INSIGHT_REPEAT 17件蓄積→確認負荷→先送り誘発の対策)
      _repeat_debounce_file="/tmp/shogun_insight_repeat_${source_info//[^a-zA-Z0-9_]/_}.last"
      _repeat_now=$(date +%s)
      _repeat_last=0
      [[ -f "$_repeat_debounce_file" ]] && _repeat_last=$(cat "$_repeat_debounce_file" 2>/dev/null || echo 0)
      if (( _repeat_now - _repeat_last > 86400 )); then
        printf '%s' "$_repeat_now" > "$_repeat_debounce_file"
        BULLETIN_NOTIFY=shogun bash "$BULLETIN_SCRIPT" saizo \
          "INSIGHT_REPEAT: source=${source_info} pending_count=${repeat_count} threshold=${SOURCE_REPEAT_THRESHOLD} latest=${result} priority=${priority}" \
          false action_required \
          >/dev/null || echo "WARN: insight repeat bulletin failed for source=$source_info" >&2
      fi
    fi
  fi

) 200>"$INSIGHTS_FILE.lock"
