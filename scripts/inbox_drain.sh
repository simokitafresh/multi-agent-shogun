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
output="$(mktemp "${TMPDIR:-/tmp}/inbox-drain-output.XXXXXX")"
cleanup() { rm -f "$snapshot" "$output"; }
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

while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    msg_id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$row")"
    INBOX_MARK_READ_ROOT_OVERRIDE="$root" bash "$mark_read" "$agent" "$msg_id" >/dev/null
    printf '%s\n' "$row" >>"$output"
done <"$snapshot"

cat "$output"
