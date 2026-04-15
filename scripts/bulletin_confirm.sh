#!/usr/bin/env bash
# bulletin_confirm.sh — 掲示板エントリの確認チェック
# Usage: bash scripts/bulletin_confirm.sh <agent_id> <entry_id>

set -euo pipefail

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"

if [[ $# -lt 2 ]]; then
    echo "Usage: bash scripts/bulletin_confirm.sh <agent_id> <entry_id>" >&2
    exit 1
fi

AGENT_ID="$1"
ENTRY_ID="$2"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"

ALL_AGENTS_RAW="$(get_all_agents)"
CONFIRM_AGENTS=(shogun)
for agent in $ALL_AGENTS_RAW; do
    skip=false
    for existing in "${CONFIRM_AGENTS[@]}"; do
        if [[ "$existing" == "$agent" ]]; then
            skip=true
            break
        fi
    done
    [[ "$skip" == false ]] && CONFIRM_AGENTS+=("$agent")
done
CONFIRM_AGENTS_CSV="$(IFS=,; echo "${CONFIRM_AGENTS[*]}")"

if [[ ! -f "$BULLETIN_FILE" ]]; then
    echo "ERROR: bulletin file not found: $BULLETIN_FILE" >&2
    exit 1
fi

{
    flock -x 200
    python3 - "$BULLETIN_FILE" "$ENTRY_ID" "$AGENT_ID" "$CONFIRM_AGENTS_CSV" <<'PY'
import os
import sys
import yaml

bulletin_file, entry_id, agent_id, agents_csv = sys.argv[1:5]
confirm_agents = [agent for agent in agents_csv.split(",") if agent]

with open(bulletin_file, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = data.get("entries")
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

confirmed = target.get("confirmed_by") or []
if not isinstance(confirmed, list):
    confirmed = []
if agent_id not in confirmed:
    confirmed.append(agent_id)
target["confirmed_by"] = confirmed

requires_confirmation = bool(target.get("requires_confirmation", False))
status = str(target.get("status", "open") or "open")
if requires_confirmation:
    if all(agent in confirmed for agent in confirm_agents):
        status = "closed"
    else:
        status = "open"
target["status"] = status

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
        fh.write(f"  requires_confirmation: {'true' if entry.get('requires_confirmation') else 'false'}\n")
        confirmed_list = entry.get("confirmed_by") or []
        if confirmed_list:
            fh.write("  confirmed_by:\n")
            for agent in confirmed_list:
                fh.write(f"    - '{sq(agent)}'\n")
        else:
            fh.write("  confirmed_by: []\n")
        fh.write(f"  status: '{sq(entry.get('status', 'open'))}'\n")

os.replace(tmp_file, bulletin_file)
print(f"{entry_id}|{len(confirmed)}|{status}")
PY
} 200>"$LOCK_FILE"
