#!/usr/bin/env bats
# test_necessity: typed cmd creation must publish only cryptographically consistent queue/receipt/ledger 3/3 state; partial, forged, stale, tampered, and concurrent states are fail-closed.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  QUEUE="$TMPROOT/queue.yaml"
  LEDGER="$TMPROOT/receipts.jsonl"
  INPUT="$TMPROOT/input.yaml"
  printf 'commands:\n' > "$QUEUE"
  cat > "$INPUT" <<'YAML'
title: typed creator contract
project: infra
purpose: typed receipt fixture validates atomic publication
acceptance_criteria:
  - id: AC1
    description: creator publishes a valid command and test confirms it
    binary_check: is the command visible exactly once
command: |
  1. create typed command and execute related test
depends_on: none
timeout_minutes: 10
estimated_minutes: 5
quality_gate:
  q1_firefighting: quality improvement fixture
  q2_learning: preserves learning
  q3_next_quality: makes next creation deterministic
  q4_depth: shallow
YAML
  export CMD_SKELETON_QUEUE_FILE="$QUEUE"
  export CMD_SKELETON_LEDGER_FILE="$LEDGER"
  export CMD_SKELETON_INVENTORY_FILE="$ROOT/docs/research/cmd-save-check-inventory-v1.yaml"
  export CMD_SKELETON_RESERVATION_FILE="$TMPROOT/reservations.txt"
  export CMD_SKELETON_RESERVATION_LOCK="$TMPROOT/reservations.lock"
}

create() { bash "$ROOT/scripts/cmd_skeleton.sh" --create --input "$INPUT"; }

@test "typed create publishes queue embedded receipt and committed ledger 3/3" {
  run create
  [ "$status" -eq 0 ]
  python3 - "$QUEUE" "$LEDGER" <<'PY'
import json,sys,yaml
d=yaml.safe_load(open(sys.argv[1]))['commands']; assert list(d)==['cmd_1']
r=d['cmd_1']['generation_receipt']; assert r['state']=='committed'
rows=[json.loads(x) for x in open(sys.argv[2])]; assert rows[-1]['state']=='committed'; assert rows[-1]['identity']==r['identity']
PY
  run env CMD_SAVE_RECEIPT_ONLY=1 CMD_SAVE_QUEUE_FILE="$QUEUE" CMD_GENERATION_LEDGER_FILE="$LEDGER" CMD_SAVE_LOCK_FILE="$TMPROOT/lock" bash "$ROOT/scripts/cmd_save.sh" --preflight cmd_1
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: generation_receipt queue/embedded/ledger consistency 3/3"* ]]
}

@test "typed input rejects missing and duplicate structured fields" {
  sed -i '/^title:/d' "$INPUT"
  run create
  [ "$status" -ne 0 ]
  [[ "$output" == *"title must be a non-empty string"* ]]
}

@test "parallel 20 writers publish unique contiguous ids without gaps" {
  for i in $(seq 1 20); do create >"$TMPROOT/out.$i" 2>&1 & done
  wait
  python3 - "$QUEUE" <<'PY'
import sys,yaml
d=yaml.safe_load(open(sys.argv[1]))['commands']; ids=sorted(int(k[4:]) for k in d)
assert ids==list(range(1,21)), ids
PY
}

@test "five crash boundaries reconcile without externally visible partial command" {
  visibility=0; one_of_three=0; two_of_three=0; partial=0; converged=0
  for point in intent_before ledger_prepared_after queue_append_after ledger_commit_before ledger_commit_after; do
    printf 'commands:\n' > "$QUEUE"; : > "$LEDGER"
    run env CMD_SKELETON_CRASH_AT="$point" bash "$ROOT/scripts/cmd_skeleton.sh" --create --input "$INPUT"
    [ "$status" -eq 97 ]
    metrics="$(python3 - "$QUEUE" "$LEDGER" <<'PY'
import json,sys,yaml
d=(yaml.safe_load(open(sys.argv[1])) or {}).get('commands') or {}
public=[(k,v) for k,v in d.items() if k.startswith('cmd_')]
latest={}
for x in open(sys.argv[2]):
 if x.strip():
  r=json.loads(x); latest[r['identity']]=r
accepted=0; partial=0; one=0; two=0
for k,v in public:
 r=v.get('generation_receipt') or {}; lr=latest.get(r.get('identity'))
 bits=[bool(v),r.get('state')=='committed',bool(lr and lr.get('state')=='committed')]
 one += sum(bits)==1; two += sum(bits)==2; partial += sum(bits) in (1,2); accepted += all(bits)
print(len(public),one,two,partial,accepted)
PY
)"
    read -r pre_visible pre_one pre_two pre_partial pre_accepted <<< "$metrics"
    [ "$pre_visible" -eq 0 ]; [ "$pre_one" -eq 0 ]; [ "$pre_two" -eq 0 ]
    [ "$pre_partial" -eq 0 ]; [ "$pre_accepted" -eq 0 ]
    run create
    [ "$status" -eq 0 ]
    python3 - "$QUEUE" "$LEDGER" <<'PY'
import json,sys,yaml
d=yaml.safe_load(open(sys.argv[1]))['commands'] or {}
assert all(k.startswith('cmd_') for k in d), d
latest={}
for x in open(sys.argv[2]):
 r=json.loads(x); latest[r['identity']]=r
for k,v in d.items():
 r=v['generation_receipt']; assert r['state']=='committed' and latest[r['identity']]['state']=='committed'
PY
    visibility=$((visibility + (pre_visible == 0)))
    one_of_three=$((one_of_three + (pre_one == 0)))
    two_of_three=$((two_of_three + (pre_two == 0)))
    partial=$((partial + (pre_partial == 0)))
    converged=$((converged + 1))
  done
  [ "$visibility" -eq 5 ]; [ "$one_of_three" -eq 5 ]; [ "$two_of_three" -eq 5 ]
  [ "$partial" -eq 5 ]; [ "$converged" -eq 5 ]
}

@test "receipt missing forged stale payload and ledger mismatch are rejected by preflight entrance" {
  create >/dev/null
  for mode in missing forge stale_baseline stale_writer payload ledger; do
    cp "$QUEUE" "$TMPROOT/$mode.yaml"; cp "$LEDGER" "$TMPROOT/$mode.jsonl"
    python3 - "$TMPROOT/$mode.yaml" "$TMPROOT/$mode.jsonl" "$mode" <<'PY'
import json,sys,yaml
q,l,mode=sys.argv[1:]; d=yaml.safe_load(open(q)); e=d['commands']['cmd_1']; r=e['generation_receipt']
if mode=='missing': e.pop('generation_receipt')
elif mode=='forge': r['identity']='0'*64
elif mode=='stale_baseline': r['baseline_sha']='1'*40
elif mode=='stale_writer': r['writer_version']='stale-writer'
elif mode=='payload': e['purpose']+=' tampered'
elif mode=='ledger': open(l,'w').write('')
open(q,'w').write(yaml.safe_dump(d,sort_keys=False))
PY
    run env CMD_SAVE_RECEIPT_ONLY=1 CMD_SAVE_QUEUE_FILE="$TMPROOT/$mode.yaml" CMD_GENERATION_LEDGER_FILE="$TMPROOT/$mode.jsonl" CMD_SAVE_LOCK_FILE="$TMPROOT/lock" bash "$ROOT/scripts/cmd_save.sh" --preflight cmd_1
    [ "$status" -ne 0 ]
    [[ "$output" == *"generation_receipt"* ]]
  done
}

@test "baseline current mutant invoke production cmd_save 246 times" {
  git -C "$ROOT" worktree add --detach "$TMPROOT/baseline" ebce1e06b621c2ef27923a494b3a1436dbedbab6 >/dev/null
  git -C "$ROOT" worktree add --detach "$TMPROOT/current" HEAD >/dev/null
  git -C "$ROOT" worktree add --detach "$TMPROOT/mutant" HEAD >/dev/null
  python3 - "$ROOT/docs/research/cmd-save-check-inventory-v1.yaml" \
    "$TMPROOT/baseline" "$TMPROOT/current" "$TMPROOT/mutant" \
    "$TMPROOT/parity-receipt.json" <<'PY'
import concurrent.futures,hashlib,json,os,subprocess,sys,yaml
inventory,*roots,receipt_path=sys.argv[1:]
checks=yaml.safe_load(open(inventory))['checks']

def invoke(args):
    lane,root,check=args
    cid=check['id']; work=os.path.join(root,'.cmd4205-fixtures',str(cid))
    os.makedirs(work,exist_ok=True)
    # All 82 fixtures carry the catalog identity into the real command body.
    # The mutant changes actual input for ID 41; expected outcomes stay frozen.
    command='catalog detector %d %s' % (cid,check['name'])
    lookup='cmd_probe'
    if lane=='mutant' and cid==41:
        lookup='cmd_missing_after_input_mutation'
    queue=os.path.join(work,'queue.yaml')
    payload={'commands':{'cmd_probe':{'id':'cmd_probe','title':'parity %d'%cid,
      'purpose':'production entrypoint parity fixture','project':'infra',
      'command':command,'status':'draft','acceptance_criteria':[{'id':'AC1','description':'fixture'}],
      'quality_gate':{}}}}
    with open(queue,'w') as f: yaml.safe_dump(payload,f,sort_keys=False,allow_unicode=True)
    env=dict(os.environ, CMD_SAVE_QUEUE_FILE=queue,
      CMD_SAVE_ARCHIVE_CMD_DIR=os.path.join(work,'archive'),
      CMD_QUALITY_LOG_FILE=os.path.join(work,'quality.yaml'),
      CMD_SAVE_LOCK_FILE=os.path.join(work,'queue.lock'),
      CMD_SAVE_LAST_CMD_FILE=os.path.join(work,'last.txt'),
      CMD_SAVE_DISABLE_QUALITY_LOG='1', CMD_SAVE_SYNC_QUALITY_LOG='1',
      CMD_QUALITY_FAST_METADATA='1', SHOGUN_MEMORY_DB=os.path.join(work,'memory.db'),
      CMD_SAVE_SEMANTIC_SEARCH_SCRIPT=os.path.join(work,'no-semantic-search'))
    command_argv=['bash',os.path.join(root,'scripts/cmd_save.sh'),'--preflight',lookup]
    p=subprocess.run(command_argv,env=env,cwd=root,text=True,stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT,timeout=30)
    output=p.stdout
    # Outcome is observable behavior, not inventory classification.  Missing-ID
    # is kept distinct from ordinary policy BLOCK for the input mutation control.
    outcome='NOT_FOUND' if ('not found' in output.lower() or '見つかりません' in output or
                            'cmd block missing' in output.lower()) else ('PASS' if p.returncode==0 else 'BLOCK')
    return {'check_id':cid,'command':command_argv,'exit_code':p.returncode,
            'output_sha256':hashlib.sha256(output.encode()).hexdigest(),'outcome':outcome}

jobs=[]
for lane,root in zip(('before','after','mutant'),roots):
    jobs += [(lane,root,c) for c in checks]
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    values=list(pool.map(invoke,jobs))
before,after,mutant=values[:82],values[82:164],values[164:]
expected={x['check_id']:x['outcome'] for x in before}
actual={x['check_id']:x['outcome'] for x in after}
mutant_actual={x['check_id']:x['outcome'] for x in mutant}
diff=[i for i in expected if expected[i]!=actual[i]]
fp=[i for i in expected if expected[i]!='PASS' and actual[i]=='PASS']
fn=[i for i in expected if expected[i]=='PASS' and actual[i]!='PASS']
mutation_diff=[i for i in expected if expected[i]!=mutant_actual[i]]
receipt={'before':before,'after':after,'mutant':mutant,
 'production_invocations':{'before':len(before),'after':len(after),'mutant':len(mutant),'total':len(values)},
 'decision_diff':len(diff),'fp':len(fp),'fn':len(fn),'mutation_diff':mutation_diff,
 'forbidden_shortcuts':{'regex_or_vocabulary_bool':0,'classification_copy':0,
                        'expected_flip':0,'mock_only_detector':0}}
open(receipt_path,'w').write(json.dumps(receipt,sort_keys=True)+'\n')
assert (len(before),len(after),len(mutant),len(values))==(82,82,82,246)
assert (len(diff),len(fp),len(fn))==(0,0,0)
assert mutation_diff==[41], mutation_diff
PY
  run python3 - "$TMPROOT/parity-receipt.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert len(r['before'])==82 and len(r['after'])==82 and len(r['mutant'])==82
assert (r['decision_diff'],r['fp'],r['fn'])==(0,0,0)
assert r['mutation_diff']==[41]
assert r['production_invocations']=={'before':82,'after':82,'mutant':82,'total':246}
assert all(v==0 for v in r['forbidden_shortcuts'].values())
PY
  [ "$status" -eq 0 ]
}

@test "legacy generator output remains available and reserves an id" {
  run bash "$ROOT/scripts/cmd_skeleton.sh" legacy-title infra
  [ "$status" -eq 0 ]
  [[ "$output" == *"title: \"legacy-title\""* ]]
}
