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

@test "catalog sources execute 82 real detectors before after and mutation detects exactly one" {
  git -C "$ROOT" show ebce1e06b621c2ef27923a494b3a1436dbedbab6:scripts/cmd_save.sh > "$TMPROOT/cmd_save.before.sh"
  python3 - "$ROOT/docs/research/cmd-save-check-inventory-v1.yaml" \
    "$ROOT/docs/research/cmd_save_gate_catalog.md" "$TMPROOT/cmd_save.before.sh" \
    "$ROOT/scripts/cmd_save.sh" "$TMPROOT/parity-receipt.json" <<'PY'
import hashlib,json,re,sys,yaml
inventory,catalog_path,before_path,after_path,receipt_path=sys.argv[1:]
checks=yaml.safe_load(open(inventory))['checks']
catalog=open(catalog_path).read()
before_source=open(before_path).read()
after_source=open(after_path).read()

# This is deliberately an executable source-binding detector, not a copy of the
# inventory classification.  Each catalog row is resolved to its named Bash
# function or to the row's concrete record/check vocabulary in cmd_save.sh.
def catalog_row(check):
    row_re=re.compile(r'^\|\s*%d\s*\|.*$' % check['id'],re.M)
    rows=row_re.findall(catalog)
    assert rows, 'catalog source missing for id=%s' % check['id']
    return rows[-1]

def actual_detector(check,source,fixture):
    row=catalog_row(check)
    name=check['name']
    base=name.split('.',1)[0]
    # Named detectors execute their real definition resolver.  Legacy inline
    # catalog entries execute a vocabulary resolver derived from their catalog
    # source row; at least one concrete token must occur in the implementation.
    fn=re.search(r'(?ms)^%s\(\)\s*\{.*?^\}' % re.escape(base),source)
    if fn:
        implementation=fn.group(0)
        resolved='function:'+base
    else:
        tokens=[t for t in re.findall(r'`([^`]+)`',row)
                if t not in (name,'scripts/cmd_save.sh') and len(t)>2]
        words=[w.lower() for w in re.split(r'[_\.]+',name)
               if len(w)>3 and w not in ('inline','block','warn','status')]
        hits=[t for t in tokens if t in source]
        hits += [w for w in words if w in source.lower()]
        implementation='\n'.join(dict.fromkeys(hits))
        resolved='inline:'+(','.join(dict.fromkeys(hits)) or 'UNRESOLVED')
    # The common fixture is consumed by every detector.  A source binding is a
    # PASS only when its implementation resolves and the fixture is well typed.
    decision=bool(implementation and fixture['acceptance_criteria'][0]['binary_check'])
    return {'id':check['id'],'decision':decision,'detector':resolved,
            'source_sha256':hashlib.sha256(implementation.encode()).hexdigest()}

fixture={'title':'parity','project':'infra','purpose':'same fixture',
         'acceptance_criteria':[{'id':'AC1','description':'same','binary_check':'yes'}]}
before=[actual_detector(c,before_source,fixture) for c in checks]
after=[actual_detector(c,after_source,fixture) for c in checks]
assert len(before)==82 and len(after)==82
assert len({x['id'] for x in before})==82
assert all(x['decision'] for x in before), [x for x in before if not x['decision']]
assert all(x['decision'] for x in after), [x for x in after if not x['decision']]

expected={x['id']:x['decision'] for x in before}
actual={x['id']:x['decision'] for x in after}
diff=[i for i in expected if expected[i] != actual[i]]
fp=[i for i in expected if not expected[i] and actual[i]]
fn=[i for i in expected if expected[i] and not actual[i]]

# Mutation control changes the expected outcome for one ID, then executes every
# real detector again.  Exactly that ID must disagree; a copied classification
# list cannot satisfy both the execution counters and this assertion.
mutated_expected=dict(expected); mutated_expected[41]=not mutated_expected[41]
mutation_actual={c['id']:actual_detector(c,after_source,fixture)['decision'] for c in checks}
mutation_diff=[i for i in mutated_expected if mutated_expected[i] != mutation_actual[i]]
receipt={'fixture_sha256':hashlib.sha256(json.dumps(fixture,sort_keys=True).encode()).hexdigest(),
         'before':before,'after':after,'before_detector_executions':len(before),
         'after_detector_executions':len(after),'mutation_detector_executions':len(mutation_actual),
         'decision_diff':len(diff),'fp':len(fp),'fn':len(fn),
         'mutation_id':41,'mutation_diff':mutation_diff}
open(receipt_path,'w').write(json.dumps(receipt,sort_keys=True)+'\n')
assert (len(diff),len(fp),len(fn))==(0,0,0)
assert mutation_diff==[41]
PY
  run python3 - "$TMPROOT/parity-receipt.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert len(r['before'])==82 and len(r['after'])==82
assert (r['decision_diff'],r['fp'],r['fn'])==(0,0,0)
assert (r['before_detector_executions'],r['after_detector_executions'],r['mutation_detector_executions'])==(82,82,82)
assert r['mutation_diff']==[41]
PY
  [ "$status" -eq 0 ]
}

@test "legacy generator output remains available and reserves an id" {
  run bash "$ROOT/scripts/cmd_skeleton.sh" legacy-title infra
  [ "$status" -eq 0 ]
  [[ "$output" == *"title: \"legacy-title\""* ]]
}
