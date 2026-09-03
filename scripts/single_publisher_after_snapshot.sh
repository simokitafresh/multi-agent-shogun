#!/usr/bin/env bash
# single_publisher_after_snapshot.sh — §11 after measurement artifact
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SINGLE_PUBLISHER_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
START_ISO="${1:-}"
END_ISO="${2:-$(date -Is)}"

if [[ -z "$START_ISO" ]]; then
    echo "usage: $0 <start-iso> [end-iso]" >&2
    exit 2
fi
start_epoch="$(date -d "$START_ISO" +%s 2>/dev/null)" || { echo "invalid start ISO: $START_ISO" >&2; exit 2; }
end_epoch="$(date -d "$END_ISO" +%s 2>/dev/null)" || { echo "invalid end ISO: $END_ISO" >&2; exit 2; }
(( end_epoch >= start_epoch )) || { echo "end ISO precedes start ISO" >&2; exit 2; }

date_key="$(date -d "@$start_epoch" +%Y%m%d)"
snapshot_dir="${SINGLE_PUBLISHER_AFTER_SNAPSHOT_DIR:-$HOME/.local/share/multi-agent-shogun/single_publisher_after_snapshot_${date_key}}"
if [[ -e "$snapshot_dir" && -z "${SINGLE_PUBLISHER_AFTER_SNAPSHOT_DIR:-}" ]]; then
    snapshot_dir="${snapshot_dir}_$(date +%H%M%S)"
fi
mkdir -p "$snapshot_dir"

extract_log_window() {
    local source="$1" destination="$2"
    python3 - "$source" "$destination" "$start_epoch" "$end_epoch" <<'PY'
import datetime as dt
import re
import sys
from pathlib import Path

source, destination, start, end = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
timestamp = re.compile(r"^\[?([^\]]{10,32})\]?")
formats = ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S")

def epoch(value):
    for fmt in formats:
        try:
            parsed = dt.datetime.strptime(value.strip(), fmt)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
            return int(parsed.timestamp())
        except ValueError:
            pass
    return None

lines = []
if Path(source).is_file():
    for line in Path(source).read_text(encoding="utf-8", errors="replace").splitlines():
        match = timestamp.match(line)
        current = epoch(match.group(1)) if match else None
        if current is not None and start <= current <= end:
            lines.append(line)
Path(destination).write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")
PY
}

push_lane_log="${SINGLE_PUBLISHER_PUSH_LANE_LOG:-$REPO_ROOT/logs/ninja_monitor.log}"
pre_push_log="${SINGLE_PUBLISHER_PRE_PUSH_LOG:-$REPO_ROOT/logs/pre_push.log}"
extract_log_window "$push_lane_log" "$snapshot_dir/push_lane.window.log"
extract_log_window "$pre_push_log" "$snapshot_dir/pre_push.window.log"

git -C "$REPO_ROOT" log origin/main --since="$START_ISO" --until="$END_ISO" --format='%H %P' > "$snapshot_dir/commits.window.txt"
git -C "$REPO_ROOT" log --merges origin/main --since="$START_ISO" --until="$END_ISO" --format='%H %P' > "$snapshot_dir/merges.window.txt"
(
    cd "$REPO_ROOT"
    if [[ -d tests ]]; then
        find tests -type f -name '*.bats' -print | sort
    fi
) > "$snapshot_dir/bats_files.txt"

(
    cd "$snapshot_dir"
    sha256sum push_lane.window.log pre_push.window.log commits.window.txt merges.window.txt bats_files.txt
) > "$snapshot_dir/SHA256SUMS"

before_dir="${SINGLE_PUBLISHER_BEFORE_SNAPSHOT_DIR:-$HOME/.local/share/multi-agent-shogun/single_publisher_before_snapshot_20260902}"
printf 'snapshot=%s start=%s end=%s\n' "$snapshot_dir" "$START_ISO" "$END_ISO"
for name in push_lane.window.log pre_push.window.log commits.window.txt merges.window.txt bats_files.txt; do
    before_count=0
    [[ -f "$before_dir/$name" ]] && before_count="$(wc -l < "$before_dir/$name")"
    after_count="$(wc -l < "$snapshot_dir/$name")"
    printf 'before_after file=%s before=%s after=%s delta=%+d\n' "$name" "$before_count" "$after_count" "$((after_count - before_count))"
done
