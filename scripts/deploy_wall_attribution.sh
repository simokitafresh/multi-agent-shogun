#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --artifact-dir DIR [--input LOG | -- command ...]" >&2
}

artifact_dir=""
input=""
while (($#)); do
  case "$1" in
    --artifact-dir) artifact_dir="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --) shift; break ;;
    *) usage; exit 2 ;;
  esac
done
[[ -n "$artifact_dir" ]] || { usage; exit 2; }
mkdir -p "$artifact_dir"
run_id="$(date -u +%Y%m%dT%H%M%S).$$"
log_file="$artifact_dir/$run_id.log"
meta_file="$artifact_dir/$run_id.meta.tsv"
started="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
start_ns="$(date +%s%N)"
rc=0
if [[ -n "$input" ]]; then
  cp -- "$input" "$log_file"
elif (($#)); then
  set +e
  "$@" >"$log_file" 2>&1
  rc=$?
  set -e
else
  usage; exit 2
fi
end_ns="$(date +%s%N)"
ended="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
printf 'started_at\t%s\nended_at\t%s\ncommand_rc\t%s\nwall_ms\t%s\n' \
  "$started" "$ended" "$rc" "$(((end_ns-start_ns)/1000000))" >"$meta_file"

python3 - "$log_file" "$artifact_dir/$run_id.json" "$artifact_dir/$run_id.tsv" <<'PY'
import json, math, re, statistics, sys
from pathlib import Path
log_path, json_path, tsv_path = map(Path, sys.argv[1:])
text = log_path.read_text(errors="replace")
receipt = [int(x) for x in re.findall(r"DEPLOY_RECEIPT\b[^\n]*?wall_ms=(\d+)", text)]
if not receipt:
    raise SystemExit("BLOCK: DEPLOY_RECEIPT missing")
total = receipt[-1]
durations = []
for m in re.finditer(r"TASK_MUTATION_PHASE\s+phase=([^\s]+)\s+wall_ms=(\d+)", text):
    durations.append((m.group(1), int(m.group(2)), "known_phase"))
intervals = []
for m in re.finditer(r"DEPLOY_WALL_EVENT\s+name=([^\s]+)\s+start_ms=(\d+)\s+end_ms=(\d+)", text):
    name, start, end = m.group(1), int(m.group(2)), int(m.group(3))
    if end < start or end > total:
        raise SystemExit(f"BLOCK: invalid interval {name}")
    intervals.append((start, end, name))
intervals.sort()
for left, right in zip(intervals, intervals[1:]):
    if right[0] < left[1]:
        raise SystemExit(f"BLOCK: overlapping intervals {left[2]}/{right[2]}")
def category(name):
    n=name.lower()
    if "lock" in n: return "lock_wait"
    if "delivery" in n or "nudge" in n: return "delivery_wait"
    if "preflight" in n: return "preflight"
    return "known_phase"
parts={"known_phase":sum(v for _,v,_ in durations),"phase_gap":0,"lock_wait":0,"delivery_wait":0,"preflight":0}
if intervals:
    parts["phase_gap"] = intervals[0][0] + sum(b[0]-a[1] for a,b in zip(intervals,intervals[1:])) + total-intervals[-1][1]
    for start,end,name in intervals: parts[category(name)] += end-start
    # Explicit intervals supersede duration-only records of the same phase.
    explicit_names={n for _,_,n in intervals}
    parts["known_phase"] -= sum(v for n,v,_ in durations if n in explicit_names)
accounted=sum(parts.values())
unattributed=total-accounted
if unattributed < 0:
    raise SystemExit(f"BLOCK: attribution exceeds total by {-unattributed}ms")
parts["unattributed"]=unattributed
error=abs(total-sum(parts.values()))/max(total,1)
top=max(parts, key=parts.get)
blocked=parts["unattributed"] > total*.05
vals=sorted(receipt)
def pct(p): return vals[math.ceil(p*len(vals))-1]
result={"log":str(log_path),"samples":len(vals),"p50_ms":pct(.50),"p95_ms":pct(.95),"total_wall_ms":total,
        "parts_ms":parts,"top_contributor":top,"top_contributor_ms":parts[top],"sum_error_ratio":error,
        "blocked":blocked,"block_reason":f"unattributed {unattributed}ms ({unattributed/max(total,1):.1%}) exceeds 5%" if blocked else ""}
json_path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
with tsv_path.open("w") as f:
    f.write("metric\tvalue\n")
    for k in ("samples","p50_ms","p95_ms","total_wall_ms","top_contributor","top_contributor_ms","sum_error_ratio","blocked"): f.write(f"{k}\t{result[k]}\n")
    for k,v in parts.items(): f.write(f"part.{k}\t{v}\n")
print(json.dumps(result,ensure_ascii=False))
if blocked: raise SystemExit(3)
PY

