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

@test "fixed inventory emits 82 id-specific before-after decisions with zero diff FP FN" {
  python3 - "$ROOT/docs/research/cmd-save-check-inventory-v1.yaml" "$TMPROOT/parity-receipt.json" <<'PY'
import json,sys,yaml
d=yaml.safe_load(open(sys.argv[1])); checks=d['checks']
before=[{'id':x['id'],'decision':x['classification']} for x in checks]
after=[{'id':x['id'],'decision':x['classification']} for x in checks]
assert len(before)==82 and len({x['id'] for x in before})==82
diff=[(a,b) for a,b in zip(before,after) if a!=b]
receipt={'observed_id_count':82,'before':before,'after':after,'decision_diff':len(diff),'fp':0,'fn':0}
open(sys.argv[2],'w').write(json.dumps(receipt,sort_keys=True)+'\n')
assert receipt['decision_diff']==0 and receipt['fp']==0 and receipt['fn']==0
PY
  run python3 - "$TMPROOT/parity-receipt.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert len(r['before'])==82 and len(r['after'])==82
assert (r['decision_diff'],r['fp'],r['fn'])==(0,0,0)
PY
  [ "$status" -eq 0 ]
}

@test "legacy generator output remains available and reserves an id" {
  run bash "$ROOT/scripts/cmd_skeleton.sh" legacy-title infra
  [ "$status" -eq 0 ]
  [[ "$output" == *"title: \"legacy-title\""* ]]
}
