#!/bin/bash
# lesson_status_migration.sh — add missing "- **status**: confirmed" to LNNN lessons.
# Usage: bash scripts/lesson_status_migration.sh <ssot_path> [<ssot_path> ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -lt 1 ]; then
    echo "Usage: bash scripts/lesson_status_migration.sh <ssot_path> [<ssot_path> ...]" >&2
    exit 1
fi

declare -A PROJECTS_TO_SYNC=()
TOTAL_INSERTED=0

resolve_project_id() {
    local ssot_path="$1"
    python3 - "$SCRIPT_DIR/config/projects.yaml" "$ssot_path" <<'PYEOF'
import os
import sys
import yaml

config_path = sys.argv[1]
target = os.path.realpath(sys.argv[2])

with open(config_path, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

for project in data.get("projects", []):
    ppath = project.get("path", "")
    candidate = os.path.realpath(os.path.join(ppath, "tasks", "lessons.md"))
    if candidate == target:
        print(project.get("id", ""))
        break
PYEOF
}

migrate_one_file() {
    local input_path="$1"
    local ssot_path=""
    local lockfile=""
    local inserted=""
    local attempt=0
    local max_attempts=3

    if ! ssot_path="$(realpath "$input_path" 2>/dev/null)"; then
        echo "[migration] ERROR: path not found: $input_path" >&2
        return 1
    fi
    if [ ! -f "$ssot_path" ]; then
        echo "[migration] ERROR: file not found: $ssot_path" >&2
        return 1
    fi

    lockfile="${ssot_path}.lock"

    while [ "$attempt" -lt "$max_attempts" ]; do
        if inserted="$(
            (
                flock -w 10 200 || exit 1
                python3 - "$ssot_path" <<'PYEOF'
import os
import re
import sys
import tempfile

ssot_path = sys.argv[1]

with open(ssot_path, encoding='utf-8', newline='') as f:
    content = f.read()

if not content:
    print(0)
    sys.exit(0)

newline = '\r\n' if '\r\n' in content else '\n'
lines = content.splitlines(keepends=True)

lesson_heading = re.compile(r'^### L\d{3}:')
next_heading = re.compile(r'^#{2,6}\s+')
status_line = re.compile(r'^\s*-\s+\*\*status\*\*:\s*', re.IGNORECASE)
date_line = re.compile(r'^\s*-\s+\*\*日付\*\*:\s*')

out = []
i = 0
inserted = 0

while i < len(lines):
    line = lines[i]
    out.append(line)

    if not lesson_heading.match(line):
        i += 1
        continue

    j = i + 1
    while j < len(lines) and not next_heading.match(lines[j]):
        j += 1
    block = lines[i + 1:j]

    has_status = any(status_line.match(b) for b in block)
    if has_status:
        out.extend(block)
        i = j
        continue

    date_idx = None
    for idx, bline in enumerate(block):
        if date_line.match(bline):
            date_idx = idx
            break

    if date_idx is None:
        out.extend(block)
        i = j
        continue

    out.extend(block[:date_idx])
    out.append(f'- **status**: confirmed{newline}')
    out.extend(block[date_idx:])
    inserted += 1
    i = j

updated = ''.join(out)
if inserted > 0 and updated != content:
    tmp_fd, tmp_path = tempfile.mkstemp(
        dir=os.path.dirname(ssot_path),
        prefix='.lesson_status_migration.',
        suffix='.tmp',
    )
    try:
        with os.fdopen(tmp_fd, 'w', encoding='utf-8', newline='') as f:
            f.write(updated)
        os.replace(tmp_path, ssot_path)
    except Exception:
        os.unlink(tmp_path)
        raise

print(inserted)
PYEOF
            ) 200>"$lockfile"
        )"; then
            break
        fi

        attempt=$((attempt + 1))
        if [ "$attempt" -lt "$max_attempts" ]; then
            echo "[migration] lock timeout ($attempt/$max_attempts): $ssot_path" >&2
            sleep 1
        else
            echo "[migration] failed to acquire lock: $ssot_path" >&2
            return 1
        fi
    done

    if ! [[ "$inserted" =~ ^[0-9]+$ ]]; then
        echo "[migration] ERROR: invalid insert count for $ssot_path: $inserted" >&2
        return 1
    fi

    TOTAL_INSERTED=$((TOTAL_INSERTED + inserted))
    echo "[migration] $ssot_path: inserted $inserted"

    local project_id=""
    project_id="$(resolve_project_id "$ssot_path" || true)"
    if [ -n "$project_id" ]; then
        PROJECTS_TO_SYNC["$project_id"]=1
    else
        echo "[migration] WARN: project id not found for $ssot_path (sync skipped)" >&2
    fi
}

for target in "$@"; do
    migrate_one_file "$target"
done

for project_id in "${!PROJECTS_TO_SYNC[@]}"; do
    echo "[migration] sync_lessons.sh $project_id"
    bash "$SCRIPT_DIR/scripts/sync_lessons.sh" "$project_id"
done

echo "[migration] total inserted: $TOTAL_INSERTED"
