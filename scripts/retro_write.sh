#!/bin/bash
# Append-only retrospective transport. Normal results are batched so they do
# not interrupt karo; only safety events bypass the batch boundary.
set -euo pipefail

ROOT="${RETRO_ROOT_OVERRIDE:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"
QUEUE_DIR="$ROOT/queue/retro"
mkdir -p "$QUEUE_DIR"

python3 - "$ROOT" "$@" <<'PY'
import datetime as dt, fcntl, hashlib, json, os, subprocess, sys

root, *args = sys.argv[1:]
if not args or args[0] not in {"submit", "final-checkpoint"}:
    raise SystemExit("usage: retro_write.sh submit <ninja> <parent_report_id> <deployed_at> <done_at> <report_at> <commit_at> <severity> <content> | final-checkpoint")
qdir = os.path.join(root, "queue", "retro")
os.makedirs(qdir, exist_ok=True)
lock_path = os.path.join(qdir, ".retro.lock")
events_path = os.path.join(qdir, "events.jsonl")
state_path = os.path.join(qdir, "state.json")

def parse_ts(value):
    if not value or value == "-": return None
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))

with open(lock_path, "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        state = json.load(open(state_path, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        state = {"event_ids": [], "pending": [], "notified_batches": []}
    notify = None
    if args[0] == "submit":
        if len(args) != 9: raise SystemExit("retro submit: expected 8 arguments")
        _, ninja, parent, deployed, done, report, commit, severity, content = args
        terminal = min(x for x in (parse_ts(done), parse_ts(report), parse_ts(commit)) if x is not None)
        started = parse_ts(deployed)
        if started is None or terminal < started: raise SystemExit("retro submit: malformed timestamps")
        duration = int((terminal - started).total_seconds())
        event_id = hashlib.sha256((parent + "\0" + ninja).encode()).hexdigest()
        if event_id in state["event_ids"]:
            print(f"DUPLICATE event_id={event_id}")
            raise SystemExit(0)
        event = {"event_id": event_id, "parent_report_id": parent, "ninja": ninja,
                 "deployed_at": deployed, "terminal_at": terminal.isoformat(),
                 "duration_seconds": duration, "severity": severity, "content": content,
                 "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat()}
        with open(events_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
            fh.flush(); os.fsync(fh.fileno())
        state["event_ids"].append(event_id)
        state["pending"].append(event_id)
        urgent = severity in {"data_loss", "security", "ci_red", "destructive_safety"}
        if urgent:
            notify = ("retro_urgent", [event_id])
        elif len(state["pending"]) >= 6:
            notify = ("retro_batch_ready", state["pending"][:6])
    elif state["pending"]:
        notify = ("retro_batch_ready", list(state["pending"]))

    if notify:
        kind, ids = notify
        batch_id = hashlib.sha256("\n".join(ids).encode()).hexdigest()
        if batch_id not in state["notified_batches"]:
            state["notified_batches"].append(batch_id)
            state["pending"] = [x for x in state["pending"] if x not in ids]
            payload = f"batch_id={batch_id} count={len(ids)} event_ids={','.join(ids)}"
        else:
            payload = None
    tmp = state_path + f".tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False, sort_keys=True); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, state_path)

if notify and payload:
    subprocess.run(["bash", os.path.join(root, "scripts", "inbox_write.sh"), "karo", payload,
                    notify[0], "retro_batcher", "review_retro_batch"], check=True)
print("STORED" if args[0] == "submit" else "CHECKPOINT")
PY
