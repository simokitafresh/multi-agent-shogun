#!/usr/bin/env bash
# Connect existing observe/select/deploy/checkpoint/record/rerank CLIs.
set -euo pipefail

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
}
generation=1
if [[ -f "$state" ]]; then
  read -r prior generation < <(python3 - "$state" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d.get("state",""),d.get("lease_generation",1))
PY
)
  [[ "$prior" != COMPLETE && "$prior" != BLOCK ]] || { echo "BLOCK duplicate"; exit 0; }
  generation=$((generation + 1))
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
  if [[ ! -s "$wave/checkpoint.json" ]] && ! "$checkpoint" "$wave/deployed.json" "$wave/checkpoint.json"; then
    write_state stop:checkpoint_fail BLOCK "$candidate" "$task_id"
    append '{"event_id":"'"$current_event_id"'","state":"BLOCK","reason":"checkpoint_fail"}'
    echo "BLOCK checkpoint_fail"; exit 0
  fi
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
