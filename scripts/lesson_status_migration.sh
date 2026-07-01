#!/bin/bash
# lesson_status_migration.sh — add missing "- **status**: confirmed" to LNNN lessons.
# Usage: bash scripts/lesson_status_migration.sh <ssot_path> [<ssot_path> ...]

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
_scripts_dir="${_self%/*}"
SCRIPT_DIR="${_scripts_dir%/*}"
unset _self _scripts_dir
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/lock_path.sh"

if [ "$#" -lt 1 ]; then
    echo "Usage: bash scripts/lesson_status_migration.sh <ssot_path> [<ssot_path> ...]" >&2
    exit 1
fi

declare -A PROJECTS_TO_SYNC=()
TOTAL_INSERTED=0

migrate_one_file() {
    local input_path="$1"
    local ssot_path=""
    local lockfile=""
    local combined=""
    local inserted=""
    local project_id=""
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

    lockfile="$(lock_path "$ssot_path")"

    while [ "$attempt" -lt "$max_attempts" ]; do
        if combined="$(
            (
                flock -w 10 200 || exit 1
                # perf: migration + project_id resolution in a single python3 process
                # (was 2 separate python3 spawns per file; merging saves one interpreter
                # startup, ~90-100ms, per invocation — cmd_2063と同型のプロセス統合パターン)
                python3 - "$ssot_path" "$SCRIPT_DIR/config/projects.yaml" <<'PYEOF'
import os
import re
import sys
import tempfile

ssot_path = sys.argv[1]
config_path = sys.argv[2]

with open(ssot_path, encoding='utf-8', newline='') as f:
    content = f.read()

if not content:
    print(0)
    print("")
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

import yaml
_CLoader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
target = os.path.realpath(ssot_path)
with open(config_path, encoding='utf-8') as f:
    cfg = yaml.load(f, Loader=_CLoader) or {}
projects = cfg.get("projects", [])
project_id = ""
# perf: os.path.realpath() per candidate costs ~10ms/call on this WSL2 /mnt/c mount
# (measured: 15-project loop = ~150ms vs <1ms with normpath). Try the cheap,
# non-syscall normpath comparison first (correct whenever no project path is a
# symlink, true for all current entries); fall back to the syscall-heavy
# realpath comparison only if the fast path finds no match, so a future
# symlinked project path still resolves correctly.
for project in projects:
    ppath = project.get("path", "")
    candidate = os.path.normpath(os.path.join(ppath, "tasks", "lessons.md"))
    if candidate == target:
        project_id = project.get("id", "")
        break
if not project_id:
    for project in projects:
        ppath = project.get("path", "")
        candidate = os.path.realpath(os.path.join(ppath, "tasks", "lessons.md"))
        if candidate == target:
            project_id = project.get("id", "")
            break
print(project_id)
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

    inserted="$(printf '%s\n' "$combined" | sed -n '1p')"
    project_id="$(printf '%s\n' "$combined" | sed -n '2p')"

    if ! [[ "$inserted" =~ ^[0-9]+$ ]]; then
        echo "[migration] ERROR: invalid insert count for $ssot_path: $inserted" >&2
        return 1
    fi

    TOTAL_INSERTED=$((TOTAL_INSERTED + inserted))
    echo "[migration] $ssot_path: inserted $inserted"

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
