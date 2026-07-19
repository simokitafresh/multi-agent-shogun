#!/usr/bin/env bash
# Connect existing observe/select/deploy/checkpoint/record/rerank CLIs.
set -euo pipefail

promote_hidden_infra() {
  local defense= retro= bulletin= gate= ready_ledger= output=
  shift
  while (($#)); do
    case "$1" in
      --defense-overhead) defense=${2:-}; shift 2;;
      --retro-events) retro=${2:-}; shift 2;;
      --bulletin-notify-failures) bulletin=${2:-}; shift 2;;
      --gate-fire-log) gate=${2:-}; shift 2;;
      --ready-ledger) ready_ledger=${2:-}; shift 2;;
      --output) output=${2:-}; shift 2;;
      *) echo "BLOCK hidden_infra_unknown_arg=$1" >&2; return 3;;
    esac
  done
  for value in "$defense" "$retro" "$bulletin" "$gate" "$ready_ledger" "$output"; do
    [[ -n "$value" ]] || { echo "BLOCK hidden_infra_missing_arg" >&2; return 3; }
  done
  for source in "$defense" "$retro" "$bulletin" "$gate"; do
    [[ -f "$source" ]] || { echo "BLOCK hidden_infra_source_missing=$source" >&2; return 3; }
  done
  mkdir -p "${ready_ledger%/*}" "${output%/*}"
  exec 8>>"$ready_ledger.lock"
  flock -x 8
  python3 - "$defense" "$retro" "$bulletin" "$gate" "$ready_ledger" "$output" <<'PY'
import hashlib,json,os,sys,time

def rows(path):
    text=open(path,encoding="utf-8").read()
    if not text.strip(): return []
    try:
        value=json.loads(text)
        return value if isinstance(value,list) else value.get("events",[value])
    except json.JSONDecodeError:
        out=[]
        for line in text.splitlines():
            line=line.strip()
            if not line or line.startswith(("#","---")): continue
            try: out.append(json.loads(line.lstrip("- ")))
            except json.JSONDecodeError: continue
        return out

paths=dict(zip(("defense_overhead","retro_event","bulletin_notify_failure","gate_fire"),sys.argv[1:5]))
ledger,output=sys.argv[5:7]
cost={"shogun":5,"karo":3,"gunshi":2,"ninja":1}
candidates=[]
for source,path in paths.items():
    for row in rows(path):
        wall=float(row.get("wall_ms",row.get("duration_ms",0)) or 0)
        retries=int(row.get("retries",row.get("retry_count",0)) or 0)
        fp=bool(row.get("false_positive",False))
        silent=bool(row.get("silent_failure",False)) or str(row.get("status","")).lower() in {"silent","failed","failure"}
        abnormal=(wall>=1000 or retries>0 or fp or silent)
        if not abnormal: continue
        cause=str(row.get("root_cause") or row.get("reason") or row.get("gate") or row.get("operation") or "unknown")
        role=str(row.get("role") or row.get("actor") or "ninja").lower()
        frequency=int(row.get("frequency",row.get("count",1)) or 1)
        signature=hashlib.sha256(f"{source}|{cause}".encode()).hexdigest()
        candidates.append({"schema_version":1,"source":source,"root_cause":cause,"root_cause_signature":signature,
          "frequency":frequency,"handling_cost":cost.get(role,1),"priority":frequency*cost.get(role,1),
          "signals":{"wall_ms":wall,"retries":retries,"false_positive":fp,"silent_failure":silent}})
processed=set()
if os.path.exists(ledger):
    for line in open(ledger,encoding="utf-8"):
        try: processed.add(json.loads(line)["root_cause_signature"])
        except (json.JSONDecodeError,KeyError): pass
unique={c["root_cause_signature"]:c for c in candidates if c["root_cause_signature"] not in processed}
ordered=sorted(unique.values(),key=lambda c:(-c["priority"],c["root_cause_signature"]))
if not ordered:
    print("BLOCK hidden_infra_no_unprocessed_candidate")
    raise SystemExit(4)
event_id="hidden-infra-"+hashlib.sha256("|".join(c["root_cause_signature"] for c in ordered).encode()).hexdigest()[:16]
event={"event_id":event_id,"lane":"hidden-infra-bug","state":"READY","candidate_id":ordered[0]["root_cause_signature"],"candidates":ordered,"created_at":time.time()}
tmp=output+f".tmp.{os.getpid()}"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(event,f,separators=(",",":")); f.flush(); os.fsync(f.fileno())
os.replace(tmp,output)
with open(ledger,"a",encoding="utf-8") as f:
    for c in ordered: f.write(json.dumps({"event_id":event_id,"root_cause_signature":c["root_cause_signature"]},separators=(",",":"))+"\n")
    f.flush(); os.fsync(f.fileno())
print(f"READY event_id={event_id} candidates={len(ordered)}")
PY
}

if [[ "${1:-}" == --promote-hidden-infra ]]; then
  promote_hidden_infra "$@"
  exit $?
fi

usage() {
  echo "usage: throughput_growth_loop.sh --event-id ID --ledger PATH --event PATH --observe CMD --select CMD --deploy CMD --checkpoint CMD --record CMD --rerank CMD [--idle yes|no] [--production yes|no]" >&2
  exit 2
}

event_id= ledger= event= observe= select= deploy= checkpoint= record= rerank=
idle=yes idle_cmd= production=no paused=no max_rounds=100
while (($#)); do
  case "$1" in
    --event-id) event_id=${2:-}; shift 2;; --ledger) ledger=${2:-}; shift 2;;
    --event) event=${2:-}; shift 2;; --observe) observe=${2:-}; shift 2;;
    --select) select=${2:-}; shift 2;; --deploy) deploy=${2:-}; shift 2;;
    --checkpoint) checkpoint=${2:-}; shift 2;; --record) record=${2:-}; shift 2;;
    --rerank) rerank=${2:-}; shift 2;; --idle) idle=${2:-}; shift 2;;
    --idle-cmd) idle_cmd=${2:-}; shift 2;; --production) production=${2:-}; shift 2;;
    --paused) paused=${2:-}; shift 2;; --max-rounds) max_rounds=${2:-}; shift 2;; *) usage;;
  esac
done
for value in "$event_id" "$ledger" "$event" "$observe" "$select" "$deploy" "$checkpoint" "$record" "$rerank"; do
  [[ -n "$value" ]] || usage
done
[[ -f "$event" ]] || { echo "BLOCK event_missing" >&2; exit 3; }
for cmd in "$observe" "$select" "$deploy" "$checkpoint" "$record" "$rerank"; do
  [[ -f "$cmd" ]] || { echo "BLOCK phase_unconnected command=$cmd" >&2; exit 3; }
done
[[ "$max_rounds" =~ ^[1-9][0-9]*$ ]] || { echo "BLOCK invalid_max_rounds" >&2; exit 3; }
mkdir -p "${ledger%/*}"
exec 9>>"$ledger.lock"
flock -x 9

safe_event_id=${event_id//[^A-Za-z0-9_.-]/_}
tmpdir="${ledger%/*}/events/$safe_event_id"
mkdir -p "$tmpdir"
state="$tmpdir/state.json"
append() { printf '%s\n' "$1" >>"$ledger"; }
maybe_failpoint() {
  local phase=$1
  if [[ "${THROUGHPUT_TEST_FAILPOINT:-}" == "$phase" ]]; then
    printf 'FAILPOINT phase=%s\n' "$phase" >&2
    exit "${THROUGHPUT_TEST_FAILPOINT_RC:-97}"
  fi
}
write_state() {
  local phase=$1 status=$2 candidate=${3:-} task=${4:-} tmp="$state.tmp.$$"
  python3 - "$tmp" "$event_id" "$status" "$phase" "${generation:-1}" "$candidate" "$task" <<'PY'
import json,os,sys,time
p,e,s,ph,g,c,t=sys.argv[1:]
with open(p,"w") as f:
 json.dump({"event_id":e,"state":s,"phase":ph,"lease_generation":int(g),"candidate_id":c or None,"task_id":t or None,"updated_at":time.time()},f,separators=(",",":")); f.flush(); os.fsync(f.fileno())
PY
  mv -f "$tmp" "$state"
}
run_phase() {
  local name=$1 input=$2 output=$3 command=$4 candidate=${5:-} task=${6:-}
  [[ -s "$output" ]] && return 0
  write_state "$name:before" RUNNING "$candidate" "$task"
  bash "$command" "$input" "$output.tmp"
  mv -f "$output.tmp" "$output"
  write_state "$name:after" RUNNING "$candidate" "$task"
  [[ "$name" == deploy ]] || maybe_failpoint "$name"
}
generation=1
if [[ -f "$state" ]]; then
  read -r prior generation < <(python3 - "$state" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d.get("state",""),d.get("lease_generation",1))
PY
)
  [[ "$prior" != COMPLETE && "$prior" != BLOCK ]] || { echo "BLOCK duplicate"; exit 0; }
  # A normal restart retains the lease generation. Only an explicit stale
  # lease marker may advance ownership; process death alone is not staleness.
  if [[ -f "$tmpdir/lease.stale" ]]; then
    generation=$((generation + 1))
    rm -f "$tmpdir/lease.stale"
  fi
fi
current_event_id=$event_id
current_event=$event
completed=0
while :; do
  completed=$((completed + 1))
  if (( completed > max_rounds )); then
    write_state stop:MAX_ROUNDS BLOCK; append '{"event_id":"'"$current_event_id"'","state":"BLOCK","reason":"MAX_ROUNDS"}'
    echo "BLOCK MAX_ROUNDS"; exit 0
  fi
  wave_idle=$idle; [[ -z "$idle_cmd" ]] || wave_idle=$(bash "$idle_cmd")
  if [[ "$wave_idle" != yes ]]; then
    write_state stop:no_idle_worker BLOCK
    append '{"event_id":"'"$current_event_id"'","state":"BLOCK","reason":"no_idle_worker"}'
    echo "BLOCK no_idle_worker"; exit 0
  fi
  if [[ "$paused" == yes ]]; then
    write_state stop:PAUSED_BY_LORD BLOCK; append '{"event_id":"'"$current_event_id"'","state":"BLOCK","reason":"PAUSED_BY_LORD"}'
    echo "BLOCK PAUSED_BY_LORD"; exit 0
  fi
  if [[ "$production" != no ]]; then
    write_state stop:production_or_irreversible BLOCK
    append '{"event_id":"'"$current_event_id"'","state":"BLOCK","reason":"production_or_irreversible"}'
    echo "BLOCK production_or_irreversible"; exit 0
  fi

  wave="$tmpdir/wave-$completed"; mkdir -p "$wave"
  run_phase observe "$current_event" "$wave/observed.json" "$observe"
  run_phase select "$wave/observed.json" "$wave/selected.json" "$select"
  candidate=$(python3 - "$wave/selected.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("candidate_id") or "")
PY
)
  [[ -n "$candidate" ]] || { write_state stop:no_candidate BLOCK; echo "BLOCK no_candidate"; exit 0; }
  run_phase deploy "$wave/selected.json" "$wave/deployed.json" "$deploy" "$candidate"
  task_id=$(python3 - "$wave/deployed.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d.get("task_id") or "")
PY
)
  write_state deploy:bound RUNNING "$candidate" "$task_id"
  maybe_failpoint deploy
  if [[ ! -s "$wave/checkpoint.json" ]] && ! "$checkpoint" "$wave/deployed.json" "$wave/checkpoint.json"; then
    write_state stop:checkpoint_fail BLOCK "$candidate" "$task_id"
    append '{"event_id":"'"$current_event_id"'","state":"BLOCK","reason":"checkpoint_fail"}'
    echo "BLOCK checkpoint_fail"; exit 0
  fi
  write_state checkpoint:after RUNNING "$candidate" "$task_id"
  maybe_failpoint checkpoint
  run_phase record "$wave/checkpoint.json" "$wave/recorded.json" "$record" "$candidate" "$task_id"
  run_phase rerank "$wave/recorded.json" "$wave/reranked.json" "$rerank" "$candidate" "$task_id"
  append '{"event_id":"'"$current_event_id"'","state":"COMPLETE","reason":"checkpoint_pass","task_id":"'"$task_id"'","lease_generation":'"$generation"'}'
  echo "COMPLETE event_id=$current_event_id"
  next_event_id=$(python3 - "$wave/reranked.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("next") or d.get("next_candidate_id") or "")
PY
)
  [[ -n "$next_event_id" ]] || { write_state terminal COMPLETE "$candidate" "$task_id"; break; }
  current_event_id=$next_event_id
  current_event="$wave/reranked.json"
done
