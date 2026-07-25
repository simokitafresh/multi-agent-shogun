#!/bin/bash
# Append-only retrospective transport. Normal results are batched so they do
# not interrupt karo; only safety events bypass the batch boundary.
set -euo pipefail

ROOT="${RETRO_ROOT_OVERRIDE:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)}"
QUEUE_DIR="$ROOT/queue/retro"
mkdir -p "$QUEUE_DIR"

python3 - "$ROOT" "$@" <<'PY'
import datetime as dt, fcntl, hashlib, json, os, subprocess, sys
import yaml

root, *args = sys.argv[1:]
if not args or args[0] not in {"submit", "enqueue-trigger", "mark-delivered", "final-checkpoint"}:
    raise SystemExit("usage: retro_write.sh submit ... | enqueue-trigger ... | mark-delivered <ninja> <event_id> <delivered_at> | final-checkpoint")
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
    state.setdefault("deliveries", {})
    state.setdefault("unanswered_notified", [])
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
        for key in ("improvement_proposals", "hotfix_deployed"):
            marker = key + "="
            for token in content.split():
                if token.startswith(marker) and token[len(marker):].isdigit():
                    event[key] = int(token[len(marker):])
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
        # This identity is also passed to retro_verbatim_prompt_async by the
        # report_received caller, so delivery and answer ledgers share one key.
        event_id = "report_received:" + parent
        if event_id not in state["legacy_tombstones"]:
            state["legacy_tombstones"].append(event_id)
        state.setdefault("terminal_events", {})[event_id] = {
            "ninja": ninja, "terminal_at": triggered, "severity": severity,
        }
    elif args[0] == "mark-delivered":
        if len(args) != 4: raise SystemExit("retro mark-delivered: expected 3 arguments")
        _, ninja, event_id, delivered_at = args
        if parse_ts(delivered_at) is None: raise SystemExit("retro mark-delivered: malformed timestamp")
        terminal = state.get("terminal_events", {}).get(event_id, {})
        if terminal and terminal.get("ninja") != ninja:
            raise SystemExit("retro mark-delivered: ninja mismatch")
        state["deliveries"].setdefault(event_id, {
            "ninja": ninja, "delivered_at": delivered_at,
            "severity": terminal.get("severity", "normal"), "pane_idle": True,
        })

    # Reconcile answers from primary persisted transports at the finite
    # checkpoint only. enqueue-trigger must not race the answer delivery.
    # messages name their source event_id in content; E4 may append the same key
    # to answers.jsonl.  A delivery is answered by either source, exactly once.
    answered_ids = set()
    karo_inbox = os.path.join(root, "queue", "inbox", "karo.yaml")
    if args[0] == "final-checkpoint" and os.path.exists(karo_inbox):
        try:
            messages = (yaml.safe_load(open(karo_inbox, encoding="utf-8")) or {}).get("messages", [])
        except Exception:
            messages = []
        for message in messages if isinstance(messages, list) else []:
            # 回答族は送信側(scripts/inbox_write.sh inbox_is_retro_answer_type)と同一集合。
            # 片側だけ増やすと回答が再び機械判定に乗らないため、
            # tests/unit/test_retro_answer_type_parity.bats が両者の一致を強制する。
            if not isinstance(message, dict) or message.get("type") not in {
                "retro_answer", "infra_bug_suspected", "infra_bug_report", "infra_bug",
            }:
                continue
            structured = str(message.get("event_id") or "")
            if structured in state["deliveries"]:
                answered_ids.add(structured)
            else:
                text = str(message.get("content") or "")
                answered_ids.update(eid for eid in state["deliveries"] if f"event_id={eid}" in text)
    e4_answers = os.path.join(qdir, "answers.jsonl")
    if args[0] == "final-checkpoint" and os.path.exists(e4_answers):
        for raw in open(e4_answers, encoding="utf-8"):
            try: answer = json.loads(raw)
            except json.JSONDecodeError: continue
            if answer.get("event_id") in state["deliveries"]:
                answered_ids.add(answer["event_id"])
    for event_id in answered_ids:
        state["deliveries"][event_id]["answered_at"] = state["deliveries"][event_id].get(
            "answered_at", dt.datetime.now(dt.timezone.utc).isoformat())

    # Resolve only the answered visible event, then promote exactly one oldest
    # durable backlog item for the same ninja.
    if args[0] == "final-checkpoint" and answered_ids:
        pending_dir = os.path.join(qdir, "verbatim_pending")
        awaiting_dir = os.path.join(qdir, "verbatim_awaiting_answer")
        backlog_dir = os.path.join(qdir, "verbatim_backlog")
        reconciled_dir = os.path.join(qdir, "verbatim_reconciled")
        ledger_path = os.path.join(root, "logs", "retro_pane_prompt.tsv")
        for directory in (pending_dir, awaiting_dir, backlog_dir, reconciled_dir, os.path.dirname(ledger_path)):
            os.makedirs(directory, exist_ok=True)
        with open(os.path.join(qdir, "verbatim_pending.enqueue.lock"), "a+") as elock:
            fcntl.flock(elock, fcntl.LOCK_EX)
            targets = set()
            for name in os.listdir(awaiting_dir):
                path = os.path.join(awaiting_dir, name)
                try: fields = open(path, encoding="utf-8").read().splitlines()
                except OSError: continue
                if len(fields) >= 2 and fields[1] in answered_ids:
                    targets.add(fields[0]); os.replace(path, os.path.join(reconciled_dir, name))
            ledger_rows = []
            for target in sorted(targets):
                visible = False
                for directory in (pending_dir, awaiting_dir):
                    for name in os.listdir(directory):
                        try: first = open(os.path.join(directory, name), encoding="utf-8").readline().rstrip("\n")
                        except OSError: continue
                        if first == target: visible = True; break
                    if visible: break
                if visible: continue
                candidates = []
                for name in os.listdir(backlog_dir):
                    path = os.path.join(backlog_dir, name)
                    try: fields = open(path, encoding="utf-8").read().splitlines()
                    except OSError: continue
                    if len(fields) >= 2 and fields[0] == target:
                        candidates.append((fields[4] if len(fields) > 4 else "", name, fields[1]))
                if candidates:
                    _, name, next_event = min(candidates)
                    os.replace(os.path.join(backlog_dir, name), os.path.join(pending_dir, name))
                    ledger_rows.append(f"{dt.datetime.now().astimezone().isoformat()}\tpromoted_backlog\t{target}\t{next_event}\n")
            if ledger_rows:
                with open(ledger_path, "a", encoding="utf-8") as ledger:
                    ledger.writelines(ledger_rows); ledger.flush(); os.fsync(ledger.fileno())

    timeout_seconds = int(os.environ.get("RETRO_ANSWER_TIMEOUT_SECONDS", "600"))
    now = dt.datetime.now(dt.timezone.utc)
    unanswered = []
    for event_id, delivery in state["deliveries"].items():
        delivered = parse_ts(delivery.get("delivered_at"))
        if delivery.get("answered_at") or delivered is None:
            continue
        if args[0] == "final-checkpoint" and (now - delivered.astimezone(dt.timezone.utc)).total_seconds() >= timeout_seconds:
            unanswered.append(event_id)
            if event_id not in state["unanswered_notified"]:
                state["unanswered_notified"].append(event_id)
                notifications.append(("retro_unanswered", [event_id]))

    proposal_count = hotfix_count = 0
    if os.path.exists(events_path):
        for raw in open(events_path, encoding="utf-8"):
            try: event = json.loads(raw)
            except json.JSONDecodeError: continue
            proposal_count += int(event.get("improvement_proposals", 0) or 0)
            hotfix_count += int(event.get("hotfix_deployed", 0) or 0)
    if args[0] == "final-checkpoint" and proposal_count > hotfix_count:
        proposal_gate_id = f"proposal-gap:{proposal_count}:{hotfix_count}"
        if proposal_gate_id not in state["unanswered_notified"]:
            state["unanswered_notified"].append(proposal_gate_id)
            notifications.append(("retro_proposal_unactioned", [proposal_gate_id]))

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
            if kind == "retro_unanswered":
                ninja = state["deliveries"][ids[0]]["ninja"]
                payloads.append((kind, f"BLOCK_NEXT_TASK ninja={ninja} count={len(ids)} event_ids={','.join(ids)} action=reprompt"))
            elif kind == "retro_proposal_unactioned":
                payloads.append((kind, f"BLOCK proposal_count={proposal_count} hotfix_deployed={hotfix_count} unassigned={proposal_count-hotfix_count}"))
            else:
                payloads.append((kind, f"batch_id={batch_id} count={len(ids)} event_ids={','.join(ids)}"))
    tmp = state_path + f".tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh, ensure_ascii=False, sort_keys=True); fh.flush(); os.fsync(fh.fileno())
    os.replace(tmp, state_path)

for kind, payload in payloads:
    subprocess.run(["bash", os.path.join(root, "scripts", "inbox_write.sh"), "karo", payload,
                    kind, "retro_batcher", "hold_next_task" if kind in {"retro_unanswered", "retro_proposal_unactioned"} else "review_retro_batch"], check=True)
delivery_count = len(state["deliveries"])
answer_count = sum(bool(x.get("answered_at")) for x in state["deliveries"].values())
print(f"DELIVERED={delivery_count} ANSWERED={answer_count} UNANSWERED={delivery_count-answer_count} "
      f"PANE_IDLE_DELIVERED={sum(bool(x.get('pane_idle')) for x in state['deliveries'].values())} "
      f"PROPOSALS={proposal_count} HOTFIX_DEPLOYED={hotfix_count} GATE_FIRES={len(state['unanswered_notified'])}")
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
