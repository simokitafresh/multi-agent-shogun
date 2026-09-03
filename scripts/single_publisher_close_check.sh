#!/usr/bin/env bash
# single_publisher_close_check.sh — §15 five-condition binary close check
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SINGLE_PUBLISHER_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
RELOAD_ISO="${1:-}"
if [[ -z "$RELOAD_ISO" ]]; then
    echo "usage: $0 <reload-iso>" >&2
    exit 2
fi
reload_epoch="$(date -d "$RELOAD_ISO" +%s 2>/dev/null)" || { echo "invalid reload ISO: $RELOAD_ISO" >&2; exit 2; }

published_by="$(git -C "$REPO_ROOT" log origin/main --since="$RELOAD_ISO" --format='%B' 2>/dev/null | awk '/^Published-By:/ {n++} END {print n+0}')"
commits="$(git -C "$REPO_ROOT" rev-list --count --since="$RELOAD_ISO" origin/main 2>/dev/null || echo 0)"
if [[ "$published_by" == "$commits" ]]; then
    printf 'trailer_rate: PASS published_by=%s commits=%s\n' "$published_by" "$commits"
    c1=PASS
else
    printf 'trailer_rate: FAIL published_by=%s commits=%s\n' "$published_by" "$commits"
    c1=FAIL
fi

dirty="$(git -C "$REPO_ROOT" status --porcelain -uno 2>/dev/null | awk 'NF {n++} END {print n+0}')"
read -r remote_only local_only < <(git -C "$REPO_ROOT" rev-list --left-right --count origin/main...HEAD 2>/dev/null || echo '1 1')
remote_only="${remote_only:-1}"; local_only="${local_only:-1}"
if [[ "$dirty" == 0 && "$remote_only" == 0 && "$local_only" == 0 ]]; then
    printf 'root_sync: PASS dirty=%s origin_main_ahead=%s head_ahead=%s\n' "$dirty" "$remote_only" "$local_only"
    c2=PASS
else
    printf 'root_sync: FAIL dirty=%s origin_main_ahead=%s head_ahead=%s\n' "$dirty" "$remote_only" "$local_only"
    c2=FAIL
fi

watchdog_log="${DAEMON_WATCHDOG_LOG:-$REPO_ROOT/logs/daemon_watchdog.log}"
restarts="$(python3 - "$watchdog_log" "$reload_epoch" <<'PY'
import datetime as dt
import re
import sys
from pathlib import Path

path, start = sys.argv[1], int(sys.argv[2])
formats = ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S")
def parse(line):
    match = re.search(r"\[([^]]+)\]", line)
    if not match:
        return None
    for fmt in formats:
        try:
            parsed = dt.datetime.strptime(match.group(1), fmt)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.datetime.now().astimezone().tzinfo)
            return int(parsed.timestamp())
        except ValueError:
            pass
    return None
n = 0
if Path(path).is_file():
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        current = parse(line)
        if current is not None and current >= start and "RESTART: publisher.sh" in line and "reason=reload" not in line.lower():
            n += 1
print(n)
PY
)"
if [[ "$restarts" == 0 ]]; then
    printf 'publisher_self_restart: PASS restarts=%s\n' "$restarts"
    c3=PASS
else
    printf 'publisher_self_restart: FAIL restarts=%s\n' "$restarts"
    c3=FAIL
fi

snapshot_root="${SINGLE_PUBLISHER_AFTER_SNAPSHOT_ROOT:-$HOME/.local/share/multi-agent-shogun}"
snapshot="${SINGLE_PUBLISHER_AFTER_SNAPSHOT_DIR:-}"
if [[ -z "$snapshot" ]]; then
    snapshot="$(find "$snapshot_root" -maxdepth 1 -type d -name 'single_publisher_after_snapshot_*' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)"
fi
snapshot_ok=0
if [[ -n "$snapshot" && -f "$snapshot/SHA256SUMS" ]]; then
    snapshot_ok=1
    for name in push_lane.window.log pre_push.window.log commits.window.txt merges.window.txt bats_files.txt; do
        [[ -f "$snapshot/$name" ]] || snapshot_ok=0
    done
fi
if [[ "$snapshot_ok" == 1 ]]; then
    printf 'after_snapshot: PASS path=%s\n' "$snapshot"
    c4=PASS
else
    printf 'after_snapshot: FAIL path=%s\n' "${snapshot:-missing}"
    c4=FAIL
fi

direct_pushes="$(python3 - "$REPO_ROOT/scripts" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
allowed = {"publisher.sh", "publish_direct_commit.sh", "publisher_root_drain.sh"}
count = 0
for path in root.rglob("*"):
    if not path.is_file() or path.name in allowed:
        continue
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.lstrip().startswith("#"):
            continue
        if re.search(r"\bgit\s+push\b", line):
            count += 1
print(count)
PY
)"
if [[ "$direct_pushes" == 0 ]]; then
    printf 'root_direct_push: PASS calls=%s\n' "$direct_pushes"
    c5=PASS
else
    printf 'root_direct_push: FAIL calls=%s\n' "$direct_pushes"
    c5=FAIL
fi

if [[ "$c1$c2$c3$c4$c5" == PASSPASSPASSPASSPASS ]]; then
    echo 'TOTAL: PASS'
    exit 0
fi
echo 'TOTAL: FAIL'
exit 1
