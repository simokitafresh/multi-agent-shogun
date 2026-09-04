#!/usr/bin/env bash
# inbox_drain.sh — atomically drain the unread snapshot for one agent.

set -euo pipefail

self="${BASH_SOURCE[0]}"
[[ "$self" = /* ]] || self="$PWD/$self"
root="${INBOX_DRAIN_ROOT_OVERRIDE:-${self%/scripts/inbox_drain.sh}}"
agent="${1:-}"

if [[ ! "$agent" =~ ^[a-z_]+$ ]]; then
    echo "Usage: inbox_drain.sh <agent>" >&2
    exit 2
fi

inbox="$root/queue/inbox/$agent.yaml"
mark_read="$root/scripts/inbox_mark_read.sh"
[[ -f "$inbox" ]] || exit 0
[[ -f "$mark_read" ]] || { echo "BLOCK: inbox_mark_read.sh missing" >&2; exit 2; }

source "$root/scripts/lib/lock_path.sh"
drain_lock="$(lock_path "$inbox.drain")"
snapshot="$(mktemp "${TMPDIR:-/tmp}/inbox-drain.XXXXXX")"
cleanup() { rm -f "$snapshot"; }
trap cleanup EXIT

exec 9>>"$drain_lock"
flock -w "${INBOX_DRAIN_LOCK_TIMEOUT:-5}" 9 || {
    echo "BLOCK: inbox drain lock busy agent=$agent" >&2
    exit 3
}

python3 - "$inbox" "$snapshot" <<'PY'
import json, sys, yaml
inbox, snapshot = sys.argv[1:]
data = yaml.safe_load(open(inbox, encoding="utf-8")) or {}
rows = []
for msg in data.get("messages", []):
    if not isinstance(msg, dict) or msg.get("read") is True:
        continue
    required = ("id", "type", "from", "content")
    if any(msg.get(key) in (None, "") for key in required):
        raise SystemExit("BLOCK: unread message missing required field")
    rows.append({key: str(msg[key]) for key in required})
with open(snapshot, "w", encoding="utf-8") as fh:
    for row in rows:
        fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
PY

[[ -s "$snapshot" ]] || exit 0

# Mark every drained id in one inbox_mark_read.sh invocation instead of
# looping one call per id.  A single call with several explicit ids is the
# documented bulk-mark-read exemption (2026-09-01 15:44 家老報告
# blt_154408/bf13c13bd): the guard fires on *separate* process invocations
# within its window, not on the id count inside one call.  A per-id loop here
# is structurally identical to the "loop over read:false ids" anti-pattern
# the guard exists to catch, even though drain already read every message's
# content into the snapshot above — so a real drain of 3+ unread messages
# would otherwise trip the guard in production.
mapfile -t msg_ids < <(python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if line:
        print(json.loads(line)["id"])
' <"$snapshot")

INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$mark_read" "$agent" "${msg_ids[@]}" >/dev/null

cat "$snapshot"
