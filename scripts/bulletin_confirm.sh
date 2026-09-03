#!/usr/bin/env bash
# semantic-links: [[掲示板通信基盤]]
# bulletin_confirm.sh — 掲示板エントリの確認チェック
# Usage: bash scripts/bulletin_confirm.sh <agent_id> <entry_id>

set -euo pipefail

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$SCRIPT_DIR/scripts/lib/agent_config.sh" 2>/dev/null || true
export BULLETIN_ALL_AGENTS="shogun karo gunshi $(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"

if [[ $# -lt 2 ]]; then
    echo "Usage: bash scripts/bulletin_confirm.sh <agent_id> <entry_id>" >&2
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
    route="$(python3 - "$BULLETIN_FILE" "$ENTRY_ID" "$AGENT_ID" "$SCRIPT_DIR" <<'PY'
import glob, json, os, subprocess, sys, yaml
path, ident, agent, repo_root = sys.argv[1:5]
data = yaml.safe_load(open(path, encoding="utf-8")) or {}
target = next((e for e in (data.get("entries") or []) if isinstance(e, dict) and str(e.get("id", "")) == ident), None)

def entry_from_op_dir(op_dir):
    for op_path in sorted(glob.glob(os.path.join(op_dir, "*.yaml"))):
        try:
            op = json.load(open(op_path, encoding="utf-8"))
        except Exception:
            continue
        if op.get("op") == "append" and str(op.get("id", "")) == ident:
            parsed = yaml.safe_load(op.get("entry_text", "")) or []
            if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
                return parsed[0]
    return None

if target is None:
    # 2026-09-03 18:10 将軍 D0(T3-S-29): bulletin_write は ledger op を enqueue した直後に inbox notify を送る。
    # ledger 適用前に受け手が inbox_mark_read→本 script を呼ぶと board file に entry が無く confirm が消えていた
    # (18:0x 実測 4 件連続 WARN)。未適用の append op から entry を復元し、confirm を同じ ledger 順序で後続させる。
    pend_dir = os.environ.get("BULLETIN_LEDGER_PENDING_DIR", "")
    if not pend_dir:
        state = os.environ.get("SHOGUN_STATE_DIR") or os.path.expanduser("~/.local/share/multi-agent-shogun")
        pend_dir = os.path.join(state, "ledger_inbox", "bulletin")
    target = entry_from_op_dir(pend_dir)
if target is None:
    # 2026-09-03 T3-S-48: a task-worktree checkout is pinned to an old base
    # commit, and a plain root checkout can simply be behind an un-pulled
    # push. Neither ever receives the single publisher's write directly, so
    # after the pending queue also misses, check the applied-op ledger
    # (SHOGUN_STATE_DIR is shared across worktrees, unlike the repo tree).
    applied_dir = os.environ.get("BULLETIN_LEDGER_APPLIED_DIR", "")
    if not applied_dir:
        state = os.environ.get("SHOGUN_STATE_DIR") or os.path.expanduser("~/.local/share/multi-agent-shogun")
        applied_dir = os.path.join(state, "ledger_inbox", "bulletin", "applied")
    target = entry_from_op_dir(applied_dir)
if target is None:
    # Last resort: the entry may already be committed+pushed to origin/main
    # by the single publisher while this checkout's working copy predates
    # that commit (stale root, not just a pending/unapplied op).
    remote_ref = os.environ.get("BULLETIN_SOURCE_REMOTE_REF", "origin/main")
    try:
        shown = subprocess.run(
            ["git", "-C", repo_root, "show", f"{remote_ref}:queue/bulletin_board.yaml"],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        shown = None
    if shown is not None and shown.returncode == 0 and shown.stdout.strip():
        remote_data = yaml.safe_load(shown.stdout) or {}
        target = next(
            (e for e in (remote_data.get("entries") or []) if isinstance(e, dict) and str(e.get("id", "")) == ident),
            None,
        )
if target is None:
    raise SystemExit(f"ERROR: entry not found: {ident}")
confirmed = list(target.get("confirmed_by") or [])
if agent not in confirmed:
    confirmed.append(agent)
rc = target.get("requires_confirmation", False)
notify = target.get("notify_targets") or []
status = str(target.get("status", "open") or "open")
if isinstance(rc, list) and all(a in confirmed for a in rc):
    status = "closed"
elif notify and all(a in confirmed for a in notify):
    status = "closed"
print(f"{target.get('status', 'open')}\t{json.dumps(confirmed, ensure_ascii=False, separators=(',', ':'))}\t{status}")
PY
)"
    IFS=$'\t' read -r old_status confirmed_json new_status <<< "$route"
    LEDGER_SOURCE_FILE="$BULLETIN_FILE" bash "$LEDGER_WRITER" update bulletin "$ENTRY_ID" \
        "confirmed_by=$confirmed_json" "status=$new_status" --expect "status=$old_status"
    exit 0
fi

{
    flock -x 200
    python3 - "$BULLETIN_FILE" "$ENTRY_ID" "$AGENT_ID" "$SCRIPT_DIR/config/settings.yaml" <<'PY'
import os
import json
import sys
from datetime import datetime, timezone

bulletin_file, entry_id, agent_id, settings_file = sys.argv[1:5]
now_override = os.environ.get("BULLETIN_CONFIRM_NOW", "")

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

def default_confirm_agents():
    agents = ["shogun", "karo"]
    in_agents = False
    if not os.path.exists(settings_file):
        return os.environ.get("BULLETIN_ALL_AGENTS", "shogun karo gunshi hayate kagemaru hanzo saizo kotaro tobisaru").split()
    with open(settings_file, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("  agents:"):
                in_agents = True
                continue
            if in_agents and line and not line.startswith("    "):
                break
            if in_agents and line.startswith("    ") and line.strip().endswith(":"):
                name = line.strip()[:-1]
                if name not in agents:
                    agents.append(name)
    return agents

def parse_dt(value):
    text = str(value or "").strip().strip("'\"")
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt

def now_dt():
    parsed = parse_dt(now_override)
    return parsed if parsed is not None else datetime.now(timezone.utc)

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

confirmed = target.get("confirmed_by") or []
if not isinstance(confirmed, list):
    confirmed = []
if agent_id not in confirmed:
    confirmed.append(agent_id)
target["confirmed_by"] = confirmed

rc = target.get("requires_confirmation", False)
status = str(target.get("status", "open") or "open")
notify_targets = target.get("notify_targets") or []
if not isinstance(notify_targets, list):
    notify_targets = []

if str(target.get("action_type", "info")).strip() == "action_required" and str(target.get("actioned_by", "")).strip():
    status = "closed"
elif isinstance(rc, list):
    if all(agent in confirmed for agent in rc):
        status = "closed"
    else:
        status = "open"
elif notify_targets:
    if all(agent in confirmed for agent in notify_targets):
        status = "closed"
    else:
        status = "open"
else:
    confirm_agents = default_confirm_agents()
    posted_by = str(target.get("posted_by", "")).strip()
    posted_at = parse_dt(target.get("posted_at", ""))
    old_enough = posted_at is not None and (now_dt() - posted_at).total_seconds() >= 21600
    confirmed_others = [agent for agent in confirmed if agent and agent != posted_by]
    # For all-agent broadcasts (notify_targets=[]), waiting for every role to confirm
    # makes entries stale-open because not every recipient has a mark_read path.
    if posted_by and posted_by in confirmed and confirmed_others and old_enough:
        status = "closed"
    elif all(agent in confirmed for agent in confirm_agents):
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
print(f"{entry_id}|{len(confirmed)}|{status}")
PY
} 200>"$LOCK_FILE"
