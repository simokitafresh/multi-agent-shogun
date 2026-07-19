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
if not args or args[0] not in {"submit", "enqueue-trigger", "final-checkpoint"}:
    raise SystemExit("usage: retro_write.sh submit ... | enqueue-trigger <ninja> <parent_msg> <triggered_at> [severity] | final-checkpoint")
qdir = os.path.join(root, "queue", "retro")
os.makedirs(qdir, exist_ok=True)
lock_path = os.path.join(qdir, ".retro.lock")
events_path = os.path.join(qdir, "events.jsonl")
state_path = os.path.join(qdir, "state.json")
legacy_path = os.path.join(qdir, "pending.yaml")
BATCH_SIZE = 6
URGENT_SEVERITIES = {"data_loss", "security", "ci_red", "destructive_safety"}

def parse_ts(value):
    if not value or value == "-": return None
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))

with open(lock_path, "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        state = json.load(open(state_path, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        state = {"event_ids": [], "pending": [], "notified_batches": []}
    state.setdefault("legacy_tombstones", [])
    # Repair state written by the short-lived legacy bridge that treated empty
    # prompts as actionable results.  Preserve the append-only audit log, but
    # remove those identities from batching and remember them as tombstones.
    if not state.get("legacy_prompt_repair_v1") and os.path.exists(events_path):
        polluted_ids = []
        for raw in open(events_path, encoding="utf-8"):
            try: historical = json.loads(raw)
            except json.JSONDecodeError: continue
            if historical.get("kind") == "retro_prompt" and historical.get("event_id"):
                polluted_ids.append(historical["event_id"])
        if polluted_ids:
            polluted = set(polluted_ids)
            state["legacy_tombstones"].extend(x for x in polluted_ids if x not in state["legacy_tombstones"])
            state["event_ids"] = [x for x in state["event_ids"] if x not in polluted]
            state["pending"] = [x for x in state["pending"] if x not in polluted]
            polluted_batch_ids = {
                hashlib.sha256("\n".join(polluted_ids[i:i+BATCH_SIZE]).encode()).hexdigest()
                for i in range(0, len(polluted_ids), BATCH_SIZE)
            }
            state["notified_batches"] = [x for x in state["notified_batches"] if x not in polluted_batch_ids]
            correction = {"kind": "legacy_migration_correction", "tombstoned_count": len(polluted_ids),
                          "actionable": False, "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat()}
            with open(events_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(correction, ensure_ascii=False, sort_keys=True) + "\n")
                fh.flush(); os.fsync(fh.fileno())
        state["legacy_prompt_repair_v1"] = True
    notifications = []

    # One-time, idempotent bridge for the pre-state.json queue.  The legacy
    # format is deliberately parsed narrowly instead of loading and rewriting
    # operational YAML with a generic serializer.
    legacy = []
    if os.path.exists(legacy_path):
        current = {}
        for raw in open(legacy_path, encoding="utf-8"):
            line = raw.strip()
            if line.startswith("- ninja:"):
                if current: legacy.append(current)
                current = {"ninja": line.split(":", 1)[1].strip()}
            elif ":" in line and current:
                key, value = line.split(":", 1)
                current[key.strip()] = value.strip()
        if current: legacy.append(current)
    migrated_ids = []
    for item in legacy:
        ninja, parent = item.get("ninja", ""), item.get("parent_msg", "")
        if not ninja or not parent:
            continue
        event_id = hashlib.sha256(("trigger\0" + parent + "\0" + ninja).encode()).hexdigest()
        if event_id in state["legacy_tombstones"]:
            continue
        state["legacy_tombstones"].append(event_id)
        migrated_ids.append(event_id)
    if migrated_ids:
        event = {"kind": "legacy_migration_summary", "migrated_count": len(migrated_ids),
                 "identity_digest": hashlib.sha256("\n".join(sorted(migrated_ids)).encode()).hexdigest(),
                 "actionable": False, "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat()}
        with open(events_path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
            fh.flush(); os.fsync(fh.fileno())
    if legacy:
        tmp_legacy = legacy_path + f".tmp.{os.getpid()}"
        with open(tmp_legacy, "w", encoding="utf-8") as fh:
            fh.write("")
            fh.flush(); os.fsync(fh.fileno())
        os.replace(tmp_legacy, legacy_path)

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
        urgent = severity in URGENT_SEVERITIES
        if urgent:
            notifications.append(("retro_urgent", [event_id]))
    elif args[0] == "enqueue-trigger":
        if len(args) not in {4, 5}: raise SystemExit("retro enqueue-trigger: expected 3 or 4 arguments")
        _, ninja, parent, triggered, *severity_arg = args
        severity = severity_arg[0] if severity_arg else "normal"
        event_id = hashlib.sha256(("trigger\0" + parent + "\0" + ninja).encode()).hexdigest()
        if event_id not in state["legacy_tombstones"]:
            state["legacy_tombstones"].append(event_id)

    # Drain complete normal batches. final-checkpoint additionally flushes the
    # residual partial batch, while ordinary writes never interrupt early.
    urgent_ids = {event_id for kind, ids in notifications if kind == "retro_urgent" for event_id in ids}
    normal_pending = [event_id for event_id in state["pending"] if event_id not in urgent_ids]
    while len(normal_pending) >= BATCH_SIZE:
        notifications.append(("retro_batch_ready", normal_pending[:BATCH_SIZE]))
        normal_pending = normal_pending[BATCH_SIZE:]
    if args[0] == "final-checkpoint" and normal_pending:
        notifications.append(("retro_batch_ready", normal_pending))

    payloads = []
    for kind, ids in notifications:
        batch_id = hashlib.sha256("\n".join(ids).encode()).hexdigest()
        if batch_id not in state["notified_batches"]:
            state["notified_batches"].append(batch_id)
            state["pending"] = [x for x in state["pending"] if x not in ids]
            payloads.append((kind, f"batch_id={batch_id} count={len(ids)} event_ids={','.join(ids)}"))
    tmp = state_path + f".tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False, sort_keys=True); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, state_path)

for kind, payload in payloads:
    subprocess.run(["bash", os.path.join(root, "scripts", "inbox_write.sh"), "karo", payload,
                    kind, "retro_batcher", "review_retro_batch"], check=True)
print("STORED" if args[0] == "submit" else "CHECKPOINT")
PY

if [ "${1:-}" = submit ]; then
    # Ninja report terminal: retro transport remains authoritative; deep
    # telemetry is detached and cannot delay report delivery.
    # shellcheck source=scripts/lib/defense_overhead_writer.sh
    source "$ROOT/scripts/lib/defense_overhead_writer.sh"
    _retro_task="$(printf '%s' "${9:-}" | grep -oE 'cmd_[A-Za-z0-9_]+' | head -1 || true)"
    [ -n "$_retro_task" ] || _retro_task="${3:-}"
    [[ "$_retro_task" == cmd_* ]] || _retro_task="cmd_retro_${_retro_task//[^A-Za-z0-9_]/_}"
    self_retro_write_async ninja_report "$_retro_task" 0 '{"report_transport":0}' \
      report_completion "report accepted by append-only retro transport" \
      "aggregate repeated report completion causes into fix_known" \
      "event_id duplicate count remains 0" "[[ninja_report]] -> [[retro_transport]] -> [[fix_known]]"
fi
