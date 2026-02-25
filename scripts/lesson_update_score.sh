#!/bin/bash
# lesson_update_score.sh — lessons.yaml のスコアフィールドを更新（排他ロック付き）
# Usage: bash scripts/lesson_update_score.sh <project> <lesson_id> helpful|harmful
# Example: bash scripts/lesson_update_score.sh infra L035 helpful

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${1:-}"
LESSON_ID="${2:-}"
SCORE_TYPE="${3:-}"

# Validate arguments
if [ -z "$PROJECT_ID" ] || [ -z "$LESSON_ID" ] || [ -z "$SCORE_TYPE" ]; then
    echo "Usage: lesson_update_score.sh <project> <lesson_id> helpful|harmful" >&2
    exit 1
fi

if [ "$SCORE_TYPE" != "helpful" ] && [ "$SCORE_TYPE" != "harmful" ]; then
    echo "ERROR: score_type must be 'helpful' or 'harmful' (got: $SCORE_TYPE)" >&2
    exit 1
fi

CACHE_FILE="$SCRIPT_DIR/projects/${PROJECT_ID}/lessons.yaml"
LOCKFILE="${CACHE_FILE}.lock"

if [ ! -f "$CACHE_FILE" ]; then
    echo "ERROR: $CACHE_FILE not found." >&2
    exit 1
fi

# Atomic update with flock (3 retries)
attempt=0
max_attempts=3

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        export CACHE_FILE LESSON_ID SCORE_TYPE
        python3 << 'PYEOF'
import yaml, os, tempfile
from datetime import datetime

cache_file = os.environ["CACHE_FILE"]
lesson_id = os.environ["LESSON_ID"]
score_type = os.environ["SCORE_TYPE"]

with open(cache_file, encoding='utf-8') as f:
    content = f.read()

data = yaml.safe_load(content)
if not data or 'lessons' not in data:
    print(f'ERROR: No lessons found in {cache_file}', flush=True)
    raise SystemExit(1)

# Find the target lesson
found = False
for lesson in data['lessons']:
    if lesson.get('id') == lesson_id:
        field = f'{score_type}_count'
        lesson[field] = lesson.get(field, 0) + 1
        lesson['last_referenced'] = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
        found = True
        print(f'{lesson_id} {field} → {lesson[field]}')
        break

if not found:
    print(f'ERROR: {lesson_id} not found in {cache_file}', flush=True)
    raise SystemExit(1)

# Preserve header comments
header_lines = []
for line in content.split('\n'):
    if line.startswith('#'):
        header_lines.append(line)
    else:
        break
header = '\n'.join(header_lines) + '\n' if header_lines else ''

# Atomic write
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(cache_file), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(header)
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2, sort_keys=False)
    os.replace(tmp_path, cache_file)
except Exception:
    os.unlink(tmp_path)
    raise
PYEOF

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_update_score] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_update_score] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
