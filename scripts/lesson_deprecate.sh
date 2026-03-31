#!/bin/bash
# lesson_deprecate.sh - Mark a lesson as deprecated in projects/<project>/lessons.yaml
# Usage: bash scripts/lesson_deprecate.sh <project> <lesson_id> "<reason>" [cmd_id]
# Example: bash scripts/lesson_deprecate.sh infra L044 "Injected 12x, referenced 0x" cmd_414

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${1:-}"
LESSON_ID="${2:-}"
REASON="${3:-}"
CMD_ID="${4:-}"

if [ -z "$PROJECT" ] || [ -z "$LESSON_ID" ] || [ -z "$REASON" ]; then
    echo "Usage: bash scripts/lesson_deprecate.sh <project> <lesson_id> \"<reason>\" [cmd_id]" >&2
    exit 1
fi

LESSONS_FILE="$SCRIPT_DIR/projects/${PROJECT}/lessons.yaml"
LOCKFILE="${LESSONS_FILE}.lock"

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: project '${PROJECT}' not found or lessons file missing: $LESSONS_FILE" >&2
    exit 1
fi

attempt=0
max_attempts=3
PY_EXIT_FILE=$(mktemp)
trap 'rm -f "$PY_EXIT_FILE"' EXIT

while [ $attempt -lt $max_attempts ]; do
    if (
        flock -w 10 200 || exit 1

        export PROJECT LESSONS_FILE LESSON_ID REASON CMD_ID PY_EXIT_FILE
        python3 << 'PYEOF'
import os
import sys
import tempfile
from datetime import datetime

import yaml

project = os.environ["PROJECT"]
lessons_file = os.environ["LESSONS_FILE"]
lesson_id = os.environ["LESSON_ID"]
reason = os.environ["REASON"]
cmd_id = os.environ.get("CMD_ID", "")
py_exit_file = os.environ["PY_EXIT_FILE"]

def fail(msg):
    print(msg, file=sys.stderr)
    with open(py_exit_file, "w", encoding="utf-8") as f:
        f.write("1")
    raise SystemExit(0)

try:
    with open(lessons_file, encoding="utf-8") as f:
        original = f.read()

    data = yaml.safe_load(original)
    if not isinstance(data, dict) or not isinstance(data.get("lessons"), list):
        fail(f"ERROR: No lessons list found in {lessons_file}")

    target = None
    for lesson in data["lessons"]:
        if isinstance(lesson, dict) and lesson.get("id") == lesson_id:
            target = lesson
            break

    if target is None:
        fail(f"ERROR: lesson_id '{lesson_id}' not found in {lessons_file}")

    # Append-only metadata: keep existing lesson content and add deprecation fields.
    target["deprecated"] = True
    target["deprecated_at"] = datetime.now().astimezone().replace(microsecond=0).isoformat()
    target["deprecated_reason"] = reason
    if cmd_id:
        target["deprecated_by"] = cmd_id

    header_lines = []
    for line in original.splitlines():
        if line.startswith("#"):
            header_lines.append(line)
        else:
            break
    header = "\n".join(header_lines)
    if header:
        header += "\n"

    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(lessons_file), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            if header:
                f.write(header)
            # yaml.dump禁止(CLAUDE.md): 手動YAML構築でデータ消失を防止
            def _sv(v):
                if isinstance(v, bool): return str(v).lower()
                if isinstance(v, (int, float)): return str(v)
                s = str(v)
                if '\n' in s:
                    return '|-\n' + '\n'.join('      ' + ln for ln in s.split('\n'))
                sq = chr(39)
                return sq + s.replace(sq, sq+sq) + sq

            top_scalars = ['ssot_path', 'last_synced', 'archive_path', 'lesson_count']
            for k in top_scalars:
                if k in data:
                    f.write(f'{k}: {_sv(data[k])}\n')
            for k in data:
                if k not in top_scalars and k != 'lessons':
                    f.write(f'{k}: {_sv(data[k])}\n')

            lessons = data.get('lessons', [])
            if not lessons:
                f.write('lessons: []\n')
            else:
                f.write('lessons:\n')
                l_keys = ['id', 'title', 'summary', 'tags',
                          'deprecated', 'deprecated_at', 'deprecated_reason', 'deprecated_by',
                          'helpful_count', 'harmful_count', 'last_referenced', 'retired']
                for lesson in lessons:
                    first = True
                    for k in l_keys + sorted(k2 for k2 in lesson if k2 not in l_keys):
                        if k not in lesson:
                            continue
                        p = '- ' if first else '  '
                        first = False
                        v = lesson[k]
                        if isinstance(v, list):
                            f.write(f'{p}{k}:\n')
                            for item in v:
                                f.write(f'  - {_sv(item)}\n')
                        else:
                            f.write(f'{p}{k}: {_sv(v)}\n')
        os.replace(tmp_path, lessons_file)
    except Exception:
        os.unlink(tmp_path)
        raise

except Exception as e:
    fail(f"ERROR: {e}")

with open(py_exit_file, "w", encoding="utf-8") as f:
    f.write("0")
print(f"DEPRECATED: {project}/{lesson_id} — {reason}")
PYEOF
    ) 200>"$LOCKFILE"; then
        PY_EXIT=$(cat "$PY_EXIT_FILE" 2>/dev/null || echo "1")
        if [ "$PY_EXIT" != "0" ]; then
            exit 1
        fi
        exit 0
    else
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo "[lesson_deprecate] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[lesson_deprecate] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
