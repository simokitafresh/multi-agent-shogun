#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE_ROOT=${PYTEST_SPEED_STATE_ROOT:-$ROOT}
if [[ -n ${PYTEST_TIMING_LEDGER:-} ]]; then
  LEDGER=$PYTEST_TIMING_LEDGER
else
  DM_ROOT=$(python3 - "$ROOT/config/projects.yaml" <<'PY'
import sys,yaml
for item in (yaml.safe_load(open(sys.argv[1],encoding='utf-8')) or {}).get('projects',[]):
    if item.get('id')=='dm-signal': print(item['path']); break
else: raise SystemExit('BLOCK: dm-signal missing from config/projects.yaml')
PY
  )
  LEDGER="$DM_ROOT/backend/.pytest_cache/pytest_timing_ledger.tsv"
fi
usage(){ echo "usage: $0 [--ledger FILE] next|generate|deploy [args]" >&2; exit 2; }
if [[ ${1:-} == --ledger ]]; then LEDGER=$2; shift 2; fi
cmd=${1:-}; shift || true
next_rows(){ python3 - "$LEDGER" "$STATE_ROOT" <<'PY'
import csv,glob,os,subprocess,sys,yaml
ledger,root=sys.argv[1:]; required={'timestamp','nodeid','duration_sec','outcome','failures','skips'}
try:
 f=open(ledger,encoding='utf-8',newline=''); r=csv.DictReader(f,delimiter='\t')
 if not r.fieldnames or not required.issubset(r.fieldnames): raise SystemExit('BLOCK: malformed pytest timing ledger header')
 latest={}
 for order,row in enumerate(r):
  try:
   node=row['nodeid'].strip(); dur=float(row['duration_sec']); fails=int(row['failures']); skips=int(row['skips']); ts=row['timestamp'].strip()
   if not node or dur<0 or not ts: continue
  except (ValueError,TypeError): continue
  key=(ts,order)
  if node not in latest or key>latest[node][0]: latest[node]=(key,row,dur)
except OSError as e: raise SystemExit(f'BLOCK: cannot read ledger: {e}')
busy=set()
index_path=os.path.join(root,'queue','pytest_speed_nodeids.tsv')
try:
 with open(index_path,encoding='utf-8') as index:
  busy.update(line.rstrip('\n').split('\t',1)[-1] for line in index if line.strip())
except OSError:
 pass
state_dirs=[os.path.join(root,p) for p in ('queue/tasks','queue/reports') if os.path.isdir(os.path.join(root,p))]
paths=[]
if state_dirs:
 try:
  # Text prefilter only narrows candidates; YAML parsing below remains the authority.
  # Most archived reports have no target nodeid, so do not deserialize them all.
  found=subprocess.run(
   ['rg','-l','--glob','*.yaml',r'^\s*(target_nodeid|nodeid):',*state_dirs],
   check=False,capture_output=True,text=True,timeout=2,
  )
  if found.returncode not in (0,1): raise RuntimeError(found.stderr.strip())
  paths=[p for p in found.stdout.splitlines() if p]
 except (FileNotFoundError,subprocess.TimeoutExpired,RuntimeError):
  paths=[path for pat in ('queue/tasks/*.yaml','queue/reports/*.yaml') for path in glob.glob(os.path.join(root,pat))]
for path in paths:
  try: data=yaml.safe_load(open(path,encoding='utf-8')) or {}
  except Exception: continue
  if not isinstance(data,dict): continue
  obj=data.get('task',data)
  if not isinstance(obj,dict): continue
  status=str(obj.get('status','')).lower()
  if status in {'assigned','acknowledged','in_progress','active','completed','done'}:
   for k in ('nodeid','target_nodeid'):
    if obj.get(k): busy.add(str(obj[k]))
for node,(_,row,dur) in sorted(latest.items(),key=lambda x:(-x[1][2],x[0])):
 if row['outcome'].strip().lower() in {'pass','passed'} and int(row['failures'])==0 and int(row['skips'])==0 and node not in busy: print(f'{dur:g}\t{node}')
PY
}
case "$cmd" in
 next) next_rows;;
 generate)
  node=${1:-}; out=${2:-}; [[ -n "$node" && -n "$out" ]] || usage
  row=$(next_rows|awk -F '\t' -v n="$node" '$2==n{print;exit}'); [[ -n "$row" ]] || { echo 'BLOCK: ineligible nodeid' >&2; exit 1; }
  dur=${row%%$'\t'*}; file=${node%%::*}
  python3 - "$out" "$node" "$file" "$dur" <<'PY'
import json,sys
out,node,file,dur=sys.argv[1:]
t={'task':{'project':'dm-signal','task_type':'hotfix','purpose':f'Reduce pytest runtime for {node} without weakening expectations','status':'assigned','estimated_minutes':5,'target_path':file,'target_nodeid':node,'before_duration_sec':float(dur),'acceptance_criteria':[{'id':'AC1','description':f'Optimize {node} and measure below {dur}s'},{'id':'AC2','description':'Targeted pytest has failures=0 and skips=0'},{'id':'AC3','description':'Expectations are not removed, skipped, xfailed, or relaxed'}],'quality_gate':{'failures':0,'skips':0,'expectation_relaxation':'forbidden'}}}
with open(out,'x',encoding='utf-8') as f: json.dump(t,f,ensure_ascii=False,sort_keys=True,indent=2); f.write('\n')
PY
  echo "$out";;
 deploy)
  ninja=${1:-}; node=${2:-}; [[ -n "$ninja" && -n "$node" ]] || usage
  tmp=$(mktemp); rm -f "$tmp"; trap 'rm -f "$tmp"' EXIT
  "$0" --ledger "$LEDGER" generate "$node" "$tmp" >/dev/null
  deploy=${DEPLOY_TASK:-$ROOT/scripts/deploy_task.sh}
  set +e; bash "$deploy" --direct --yaml "$tmp" "$ninja"; rc=$?; set -e
  if [[ $rc -eq 0 ]]; then
    mkdir -p "$STATE_ROOT/queue"
    printf 'deployed\t%s\n' "$node" >>"$STATE_ROOT/queue/pytest_speed_nodeids.tsv"
  fi
  rm -f "$tmp"; trap - EXIT; exit "$rc";;
 *) usage;;
esac
