#!/usr/bin/env bash
# semantic-links: [[掲示板通信基盤]]
# bulletin_action.sh — 掲示板エントリのactioned_byフィールドを更新
# Usage: bash scripts/bulletin_action.sh <agent_id> <entry_id>

set -euo pipefail

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"

if [[ $# -lt 2 ]]; then
    echo "Usage: bash scripts/bulletin_action.sh <agent_id> <entry_id>" >&2
    exit 1
fi

AGENT_ID="$1"
ENTRY_ID="$2"

if [[ ! -f "$BULLETIN_FILE" ]]; then
    echo "ERROR: bulletin file not found: $BULLETIN_FILE" >&2
    exit 1
fi

LEDGER_WRITER="$SCRIPT_DIR/scripts/ledger_writer.sh"
PUBLISHER_SINGLE_HELPER="$SCRIPT_DIR/scripts/lib/publisher_single_flag.sh"
if [[ -x "$LEDGER_WRITER" && -f "$PUBLISHER_SINGLE_HELPER" ]]; then
    # shellcheck source=lib/publisher_single_flag.sh
    source "$PUBLISHER_SINGLE_HELPER"
fi
if declare -f publisher_single_enabled >/dev/null 2>&1 && publisher_single_enabled "$SCRIPT_DIR"; then
    route="$(python3 - "$BULLETIN_FILE" "$ENTRY_ID" <<'PY'
import sys, yaml
path, ident = sys.argv[1:]
data = yaml.safe_load(open(path, encoding="utf-8")) or {}
target = next((e for e in data.get("entries", []) if str(e.get("id", "")) == ident), None)
if target is None:
    raise SystemExit(f"ERROR: entry not found: {ident}")
old_status = str(target.get("status", "open") or "open")
new_status = "closed" if str(target.get("action_type", "info")) == "action_required" else old_status
print(f"{old_status}\t{new_status}")
PY
)"
    IFS=$'\t' read -r old_status new_status <<< "$route"
    LEDGER_SOURCE_FILE="$BULLETIN_FILE" bash "$LEDGER_WRITER" update bulletin "$ENTRY_ID" \
        "actioned_by=$AGENT_ID" "status=$new_status" --expect "status=$old_status"
    exit 0
fi

{
    flock -x 200
    python3 - "$BULLETIN_FILE" "$ENTRY_ID" "$AGENT_ID" <<'PY'
import os
import json
import sys

bulletin_file, entry_id, agent_id = sys.argv[1:4]

def unquote(value):
    value = str(value).strip()
    if len(value) >= 2 and value[0] == "'" and value[-1] == "'":
        return value[1:-1].replace("''", "'")
    return value

def parse_scalar(value):
    value = str(value).strip()
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "[]":
        return []
    if value.startswith("["):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            pass
    return unquote(value)

def parse_bulletin(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    if not lines or not lines[0].startswith("entries:"):
        return None
    if lines[0].strip() == "entries: []":
        return []

    entries = []
    i = 1
    while i < len(lines):
        line = lines[i]
        if not line.startswith("- id:"):
            i += 1
            continue
        entry = {"id": unquote(line.split(":", 1)[1])}
        i += 1
        while i < len(lines) and not lines[i].startswith("- id:"):
            line = lines[i]
            if line == "  content: |-":
                i += 1
                content = []
                while i < len(lines) and lines[i].startswith("    "):
                    content.append(lines[i][4:])
                    i += 1
                entry["content"] = "\n".join(content)
                continue
            if line.startswith("  requires_confirmation:") or line.startswith("  confirmed_by:") or line.startswith("  notify_targets:"):
                key, raw = line.strip().split(":", 1)
                raw = raw.strip()
                if raw:
                    entry[key] = parse_scalar(raw)
                    i += 1
                    continue
                values = []
                i += 1
                while i < len(lines) and lines[i].startswith("    - "):
                    values.append(unquote(lines[i][6:]))
                    i += 1
                entry[key] = values
                continue
            if line.startswith("  ") and ":" in line:
                key, raw = line.strip().split(":", 1)
                entry[key] = parse_scalar(raw)
            i += 1
        entries.append(entry)
    return entries

entries = parse_bulletin(bulletin_file)
if not isinstance(entries, list):
    print("ERROR: entries list missing", file=sys.stderr)
    sys.exit(1)

target = None
for entry in entries:
    if isinstance(entry, dict) and str(entry.get("id", "")) == entry_id:
        target = entry
        break

if target is None:
    print(f"ERROR: entry not found: {entry_id}", file=sys.stderr)
    sys.exit(1)

target["actioned_by"] = agent_id
if str(target.get("action_type", "info")).strip() == "action_required":
    target["status"] = "closed"

def sq(value):
    return str(value).replace("'", "''")

tmp_file = f"{bulletin_file}.tmp"
with open(tmp_file, "w", encoding="utf-8") as fh:
    fh.write("entries:\n")
    for entry in entries:
        fh.write(f"- id: '{sq(entry.get('id', ''))}'\n")
        fh.write("  content: |-\n")
        text = str(entry.get("content", ""))
        lines = text.splitlines() or [""]
        for line in lines:
            fh.write(f"    {line}\n")
        fh.write(f"  posted_by: '{sq(entry.get('posted_by', ''))}'\n")
        fh.write(f"  posted_at: '{sq(entry.get('posted_at', ''))}'\n")
        rc = entry.get('requires_confirmation')
        if isinstance(rc, list):
            fh.write("  requires_confirmation:\n")
            for agent_name in rc:
                fh.write(f"    - '{sq(agent_name)}'\n")
        elif rc:
            fh.write("  requires_confirmation: true\n")
        else:
            fh.write("  requires_confirmation: false\n")
        at = entry.get("action_type", "info")
        if at not in {"info", "action_required"}:
            at = "info"
        fh.write(f"  action_type: '{sq(at)}'\n")
        fh.write(f"  actioned_by: '{sq(entry.get('actioned_by', ''))}'\n")
        notify_targets = entry.get("notify_targets") or []
        if notify_targets:
            fh.write("  notify_targets:\n")
            for agent in notify_targets:
                fh.write(f"    - '{sq(agent)}'\n")
        else:
            fh.write("  notify_targets: []\n")
        confirmed_list = entry.get("confirmed_by") or []
        if confirmed_list:
            fh.write("  confirmed_by:\n")
            for agent in confirmed_list:
                fh.write(f"    - '{sq(agent)}'\n")
        else:
            fh.write("  confirmed_by: []\n")
        fh.write(f"  status: '{sq(entry.get('status', 'open'))}'\n")

os.replace(tmp_file, bulletin_file)
print(f"{entry_id}|{agent_id}")
PY
} 200>"$LOCK_FILE"
