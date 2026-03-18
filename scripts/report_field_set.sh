#!/usr/bin/env bash
# report_field_set.sh — 報告YAMLのフィールドをflock排他制御で安全に更新
# Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>
#        echo "multi-line value" | bash scripts/report_field_set.sh <report_path> <dot.notation.key> -
#
# - flock付き排他制御（inbox_write.sh同等パターン）
# - ドット記法でネストフィールドに対応（例: results.AC1.status）
# - 値が "-" ならstdinから読む
# - 存在しないキーは自動作成（中間dictも）
# - Python3 + PyYAML でYAML安全操作

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPORT_PATH="$1"
DOT_KEY="$2"
VALUE="$3"

if [ -z "$REPORT_PATH" ] || [ -z "$DOT_KEY" ] || [ -z "$VALUE" ]; then
    echo "Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>" >&2
    echo "  value が '-' ならstdinから読む" >&2
    echo "Examples:" >&2
    echo "  bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml results.AC1.status PASS" >&2
    echo "  echo 'long text' | bash scripts/report_field_set.sh queue/reports/sasuke_report_cmd_100.yaml results.AC1.notes -" >&2
    exit 1
fi

# Resolve to absolute path if relative
if [[ "$REPORT_PATH" != /* ]]; then
    REPORT_PATH="$SCRIPT_DIR/$REPORT_PATH"
fi

LOCKFILE="${REPORT_PATH}.lock"

# Read stdin if value is "-"
STDIN_VALUE=""
if [ "$VALUE" = "-" ]; then
    STDIN_VALUE="$(cat)"
fi

# flock + atomic write (3 retries)
MAX_RETRIES=3
for attempt in $(seq 1 $MAX_RETRIES); do
    (
        flock -w 5 200 || { echo "[report_field_set] flock failed (attempt $attempt)" >&2; exit 1; }

        python3 -c "
import sys, os, yaml, tempfile

report_path = sys.argv[1]
dot_key = sys.argv[2]
value = sys.argv[3]
stdin_value = sys.argv[4] if len(sys.argv) > 4 else ''

# Use stdin value if marker
if value == '-':
    value = stdin_value

# Load existing or create empty
if os.path.exists(report_path):
    with open(report_path, 'r') as f:
        data = yaml.safe_load(f) or {}
else:
    data = {}

# Navigate dot notation and set value
keys = dot_key.split('.')
current = data
for key in keys[:-1]:
    if key not in current or not isinstance(current.get(key), dict):
        current[key] = {}
    current = current[key]

# Auto-detect type: bool, int, float, or string
if value.lower() == 'true':
    value = True
elif value.lower() == 'false':
    value = False
elif value.lower() == 'null' or value.lower() == 'none':
    value = None
else:
    try:
        value = int(value)
    except (ValueError, TypeError):
        try:
            value = float(value)
        except (ValueError, TypeError):
            pass  # keep as string

current[keys[-1]] = value

# Atomic write: tempfile + os.replace
dir_name = os.path.dirname(report_path) or '.'
fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix='.tmp')
try:
    with os.fdopen(fd, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    os.replace(tmp_path, report_path)
except Exception:
    os.unlink(tmp_path)
    raise

print(f'[report_field_set] {dot_key} = {current[keys[-1]]}')
" "$REPORT_PATH" "$DOT_KEY" "$VALUE" "$STDIN_VALUE"

    ) 200>"$LOCKFILE" && break

    if [ "$attempt" -eq "$MAX_RETRIES" ]; then
        echo "[report_field_set] All $MAX_RETRIES attempts failed" >&2
        exit 1
    fi
    sleep 0.5
done
