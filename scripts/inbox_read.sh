#!/usr/bin/env bash
# Receipt contract provenance: cmd_karo_hotfix_inbox_processing_receipt_20260901.
set -euo pipefail

# Codex has no dedicated Read tool, while inbox_mark_read's safety guard
# requires a read receipt.  This helper makes the read observable and records
# the receipt only after the inbox contents were emitted successfully.

if (( $# != 1 )); then
  echo "Usage: $0 <agent_id>" >&2
  exit 2
fi

agent_id="$1"
if [[ ! "$agent_id" =~ ^[a-z_]+$ ]]; then
  echo "ERROR: invalid agent_id: $agent_id" >&2
  exit 2
fi

repo_root="${SHOGUN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
relative_inbox="queue/inbox/${agent_id}.yaml"
inbox_file="${repo_root}/${relative_inbox}"
read_log_dir="${INBOX_READ_LOG_DIR:-/tmp}"
read_log="${read_log_dir}/claude_read_log_${agent_id}.txt"
receipt_dir="${INBOX_READ_RECEIPT_DIR:-${repo_root}/logs/inbox_read_receipts}"

# Read and mark share this lock.  Generation excludes the read flag so one
# mark does not invalidate receipts for other messages, while a new or
# tampered message still invalidates the generation.
lock_path() {
  local file_path="$1" hash=5381 i c
  case "$file_path" in
    /mnt/c/*|/mnt/d/*)
      for ((i = 0; i < ${#file_path}; i++)); do
        printf -v c '%d' "'${file_path:$i:1}"
        ((hash = hash * 33 + c))
      done
      printf '/tmp/shogun_lock_%016x.lock' "$hash"
      ;;
    *)
      printf '%s.lock' "$file_path"
      ;;
  esac
}

if [[ ! -f "$inbox_file" ]]; then
  echo "ERROR: inbox not found: $relative_inbox" >&2
  exit 1
fi

# Match inbox_mark_read.sh's symlink resolution so both commands lock the
# same real file (especially queue/inbox symlink deployments).
resolved_inbox="$(readlink -f "$inbox_file" 2>/dev/null || true)"
if [[ -n "$resolved_inbox" ]]; then
  inbox_file="$resolved_inbox"
fi

mkdir -p -- "$receipt_dir" "$read_log_dir"
lock_file="$(lock_path "$inbox_file")"
exec 200>"$lock_file"
flock -w 5 200 || { echo "ERROR: inbox lock timeout: $relative_inbox" >&2; exit 1; }

metadata_file="$(mktemp "$receipt_dir/.${agent_id}.metadata.XXXXXX")"
cleanup() { rm -f -- "$metadata_file"; }
trap cleanup EXIT

# Validate and snapshot unread message identities before emitting the source.
# The receipt is published only after cat succeeds.
python3 - "$inbox_file" "$agent_id" "$metadata_file" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
import yaml

inbox, agent, output = sys.argv[1:]
with open(inbox, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
messages = data.get("messages", [])
if not isinstance(messages, list):
    raise SystemExit("ERROR: inbox messages must be a list")

def identity(message):
    return {key: str(message.get(key, "")) for key in ("id", "from", "timestamp", "type", "content")}

identities, entries, seen = [], [], set()
for message in messages:
    if not isinstance(message, dict):
        raise SystemExit("ERROR: inbox message must be a mapping")
    item = identity(message)
    if not item["id"]:
        raise SystemExit("ERROR: inbox message id is required")
    if item["id"] in seen:
        raise SystemExit(f"ERROR: duplicate inbox message id: {item['id']}")
    seen.add(item["id"])
    identities.append(item)
    if message.get("read") is False:
        entries.append({
            "msg_id": item["id"],
            "content_hash": hashlib.sha256(item["content"].encode("utf-8")).hexdigest(),
        })

generation = hashlib.sha256(json.dumps(
    identities, ensure_ascii=False, sort_keys=True, separators=(",", ":")
).encode("utf-8")).hexdigest()
payload = {
    "version": 1,
    "agent": agent,
    "generation": generation,
    "issued_at": datetime.now(timezone.utc).isoformat(),
    "entries": entries,
}
with open(output, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, sort_keys=True)
    fh.flush()
PY

cat -- "$inbox_file"

if python3 - "$metadata_file" "$receipt_dir/${agent_id}.json" <<'PY'
import json
import os
import sys
import tempfile

metadata, receipt = sys.argv[1:]
with open(metadata, encoding="utf-8") as fh:
    payload = json.load(fh)
if not payload["entries"]:
    raise SystemExit(0)
directory = os.path.dirname(receipt)
fd, temporary = tempfile.mkstemp(prefix=f".{os.path.basename(receipt)}.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, sort_keys=True)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(temporary, receipt)
except Exception:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
then
  printf '%s\n' "$relative_inbox" >> "$read_log"
else
  echo "ERROR: unable to publish inbox read receipt" >&2
  exit 1
fi
