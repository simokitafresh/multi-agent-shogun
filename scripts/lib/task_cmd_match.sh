#!/usr/bin/env bash
# Exact task-to-command matching shared by lifecycle tools.

task_cmd_regex_escape() {
    printf '%s' "$1" | sed 's/[][\\.^$*+?{}()|/]/\\&/g'
}

task_file_matches_cmd() {
    local task_file="$1"
    local cmd_id="$2"
    local escaped
    escaped=$(task_cmd_regex_escape "$cmd_id")

    # parent_cmd is the lifecycle SSOT for current-format task files.  Idle
    # reset deliberately clears it while compatibility metadata such as
    # cmd_id/issued_cmd_id may remain for chronology.  Falling back to that
    # stale cmd_id made a completed command rediscover an idle worker and its
    # old pending report, permanently blocking two-phase review.
    if grep -qE "^[[:space:]]*parent_cmd:" "$task_file" 2>/dev/null; then
        grep -qE "^[[:space:]]*parent_cmd:[[:space:]]*['\"]?${escaped}['\"]?[[:space:]]*(#.*)?$" "$task_file" 2>/dev/null
        return
    fi

    # Legacy task documents without a parent_cmd field retain cmd_id support.
    grep -qE "^[[:space:]]*cmd_id:[[:space:]]*['\"]?${escaped}['\"]?[[:space:]]*(#.*)?$" "$task_file" 2>/dev/null
}

list_task_files_for_cmd() {
    local tasks_dir="$1"
    local cmd_id="$2"
    local task_file
    for task_file in "$tasks_dir"/*.yaml; do
        [ -f "$task_file" ] || continue
        task_file_matches_cmd "$task_file" "$cmd_id" && printf '%s\n' "$task_file"
    done
    return 0
}

# A task_id identifies one logical work unit.  Reassigning that work unit to a
# different ninja leaves the former worker's task YAML behind for chronology;
# lifecycle gates must not wait for both copies.  Keep only the newest
# deployed generation for duplicate, timestamped task_ids.  Missing or tied
# generation timestamps fail open to the original full set so genuinely
# sharded/ambiguous tasks are never hidden.
list_current_task_files_for_cmd() {
    local tasks_dir="$1"
    local cmd_id="$2"
    local candidates=()
    mapfile -t candidates < <(list_task_files_for_cmd "$tasks_dir" "$cmd_id" | sort -u)

    python3 - "${candidates[@]}" <<'PY'
import datetime as dt
import pathlib
import sys

import yaml


def generation(value):
    if value in (None, ""):
        return None
    if hasattr(value, "timestamp"):
        try:
            return float(value.timestamp())
        except Exception:
            return None
    text = str(value).strip().replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(text)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return float(parsed.timestamp())
    except ValueError:
        return None


rows = []
for raw_path in sys.argv[1:]:
    path = pathlib.Path(raw_path)
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        rows.append((raw_path, "", None))
        continue
    task = document.get("task", document) if isinstance(document, dict) else {}
    if not isinstance(task, dict):
        rows.append((raw_path, "", None))
        continue
    task_id = str(task.get("task_id") or task.get("_ac_task_id") or "").strip()
    stamp = generation(task.get("deployed_at") or task.get("issued_at"))
    rows.append((raw_path, task_id, stamp))

by_task_id = {}
for row in rows:
    if row[1]:
        by_task_id.setdefault(row[1], []).append(row)

excluded = set()
for grouped in by_task_id.values():
    if len(grouped) < 2 or any(row[2] is None for row in grouped):
        continue
    newest = max(row[2] for row in grouped)
    winners = [row for row in grouped if row[2] == newest]
    if len(winners) != 1:
        continue
    excluded.update(row[0] for row in grouped if row is not winners[0])

for path, _task_id, _stamp in rows:
    if path not in excluded:
        print(path)
PY
}
