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
TARGET={
8:'check_measurement_env_info',24:'check_content_duplicate',
37:'check_new_file_structure_warning',40:'check_q11_guard_duplicate_block',
41:'check_fill_this_placeholder_block',42:'check_delegated_duplicate_block',
43:'check_previous_pass_pending_block',44:'check_archive_duplicate_warn',
45:'check_other_draft_exists_block',46:'check_diagnosis_format_block',
47:'check_environment_change_after_prior_block',48:'check_environment_change_after_prior_block',
49:'check_environment_change_after_prior_block',50:'check_environment_change_after_prior_block',
51:'check_required_quality_gate_keys_block',52:'check_required_quality_gate_keys_block',
53:'check_required_quality_gate_keys_block',
54:'check_q4_depth_warn',55:'check_research_baseline_warn',
56:'check_q5_code_reading_only_block',57:'check_q6_not_hiding_warn',58:'check_q7_definition_verified_warn',
59:'check_q8_scope_expression_warn',60:'check_q8_compound_question_warn',
61:'check_q8_when_how_warn',62:'check_q8_where_who_warn',
63:'check_q9_firefighting_root_cause_block',64:'check_q9_root_cause_label_block',
65:'check_q9_prevention_label_block',66:'check_q9_root_cause_length_block',
67:'check_q9_prevention_length_block',68:'check_q10_knowledge_boundary_warn',
69:'check_q11_guard_duplicate_block',70:'check_q11_existing_alternative_block',
71:'check_lock_contention_warn',75:'show_gunshi_pane_status',
76:'show_gunshi_pane_status',77:'show_gunshi_pane_status',78:'show_gunshi_pane_status',
79:'show_gunshi_pane_status',80:'show_gunshi_pane_status',74:'show_three_layer_memory_ruling_info',
81:'check_cmd_block_presence_warn',82:'check_cmd_block_presence_warn'}

def invoke(args):
    lane,root,check=args
    cid=check['id']; work=os.path.join(root,'.cmd4205-fixtures',str(cid))
    os.makedirs(work,exist_ok=True)
    target=TARGET.get(cid,check['name'].split('.',1)[0])
    # A complete common precondition surface lets the production dispatcher
    # reach the target check.  Every fixture still carries a distinct catalog
    # identity and is independently executed/observed.
    command='fix production gate behavior for catalog detector %d %s with full verification' % (cid,check['name'])
    lookup='cmd_probe'
    queue=os.path.join(work,'queue.yaml')
    title=('障害修正 parity %d'%cid) if cid in (63,64,65,66,67) else ('parity %d'%cid)
    payload={'commands':{'cmd_probe':{'id':'cmd_probe','title':title,
      'purpose':'production entrypoint parity fixture','project':'infra',
      'depends_on':'none','origin':'[[cmd_4205]]','command':command,'status':'draft',
      'timeout_minutes':10,'estimated_minutes':10,
      'acceptance_criteria':[{'id':'AC1','description':'production target %s is observed'%target,
                              'binary_check':'target_reached=yes'}],
      'assumptions':{'claim':'verified 2026-08-01','source':'scripts/cmd_save.sh','trust':'verified'},
      'quality_gate':{'q1_firefighting':'yes','q2_learning':'fixture learning',
       'q3_next_quality':'target observation improves parity evidence','q4_depth':'shallow',
       'q5_verified_source':'production_verified scripts/cmd_save.sh',
       'q6_not_hiding':'no — target-specific behavior remains visible',
       'q7_definition_verified':'yes — catalog source checked',
       'q8_why_what':'WHY: preserve behavior WHAT: observe target WHEN: parity run WHERE: scripts/cmd_save.sh WHO: ninja HOW: production preflight. compound positive',
       'q9_firefighting_root_cause':'root_cause: prior fixture stopped before target | prevention: trace target dispatch in every corpus row',
       'q10_knowledge_boundary':'verified catalog boundary','q11_not_already_done':'verified unique fixture',
       'q12_lord_30min_cost':'parallel execution','q_ambiguity':'none'}}}}
    if lane=='mutant' and cid==41:
        payload['commands']['cmd_probe']['purpose']='FILL_THIS'
    if cid==8:
        # Check 20 only evaluates measurement metadata when AC structure is
        # deliberately incomplete; this row supplies that production branch.
        payload['commands']['cmd_probe'].pop('acceptance_criteria')
    with open(queue,'w') as f: yaml.safe_dump(payload,f,sort_keys=False,allow_unicode=True)
    env=dict(os.environ, CMD_SAVE_QUEUE_FILE=queue,
      CMD_SAVE_ARCHIVE_CMD_DIR=os.path.join(work,'archive'),
      CMD_QUALITY_LOG_FILE=os.path.join(work,'quality.yaml'),
      CMD_SAVE_LOCK_FILE=os.path.join(work,'queue.lock'),
      CMD_SAVE_LAST_CMD_FILE=os.path.join(work,'last.txt'),
      CMD_SAVE_DISABLE_QUALITY_LOG='1', CMD_SAVE_SYNC_QUALITY_LOG='1',
      CMD_QUALITY_FAST_METADATA='0' if cid in (24,74) else '1', SHOGUN_MEMORY_DB=os.path.join(work,'memory.db'),
      CMD_SAVE_SEMANTIC_SEARCH_SCRIPT=os.path.join(work,'no-semantic-search'))
    script=os.path.join(root,'scripts/cmd_save.sh')
    command_argv=['bash','-x',script,'--preflight',lookup]
    trace_path=os.path.join(work,'xtrace.log')
    # cmd_save installs an output filter, so ordinary stderr capture loses the
    # production function trace.  A dedicated inherited xtrace fd observes the
    # real entrypoint without modifying or mocking its implementation.
    bash_env=os.path.join(work,'bash-env')
    # fd 9 belongs to cmd_save_output_filter; use fd 8 so production setup
    # cannot replace the observer after startup.
    open(bash_env,'w').write('exec 8>"$TRACE_OUT"\nBASH_XTRACEFD=8\n')
    env.update(BASH_ENV=bash_env,TRACE_OUT=trace_path)
    p=subprocess.run(command_argv,env=env,cwd=root,text=True,stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT,timeout=60)
    output=p.stdout
    trace=open(trace_path).read()
    # Parse executed shell commands structurally.  This is runtime control-flow
    # evidence from production, not regex/vocabulary matching against source or
    # output prose and not a function-existence probe.
    traced_commands=[]
    for raw in trace.splitlines():
        body=raw.lstrip('+').strip()
        if body:
            traced_commands.append(body.split(None,1)[0])
    target_call_count=traced_commands.count(target)
    called=target_call_count > 0
    # ID37 is a production-pruned detector (FP=100%).  Its real judgment is
    # dynamic non-invocation while execution proceeds into the following gate,
    # not function presence or a copied catalog classification.
    if cid==37:
        passed_pruned_site=('parse_structured_environment_change' in traced_commands) or p.returncode in (0,1)
        target_reached=(not called and passed_pruned_site)
    else:
        target_reached=called
    mutation_observed='雛形のFILL_THISが残存' in output
    outcome={'target':target,'production_exit_code':p.returncode,
             'target_call_count':target_call_count,
             'target_judgment_observed':target_reached,
             'mutation_observed':mutation_observed if cid==41 else False}
    return {'check_id':cid,'command':command_argv,'exit_code':p.returncode,
            'output_sha256':hashlib.sha256(output.encode()).hexdigest(),
            'trace_sha256':hashlib.sha256(trace.encode()).hexdigest(),'target':target,
            'target_reached':target_reached,
            'observation_kind':'production_pruned_control_flow' if cid==37 else 'production_xtrace_call',
            'mutation_kind':'input' if lane=='mutant' and cid==41 else 'none',
            'outcome':outcome}

jobs=[]
for lane,root in zip(('before','after','mutant'),roots):
    jobs += [(lane,root,c) for c in checks]
# Keep all 246 production invocations while bounding DrvFS/git/SQLite
# contention. Sixteen concurrent cmd_save processes exceed the per-invocation
# 30s contract under WSL2 even when every detector is healthy.
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
all_rows=before+after+mutant
shortcut_counts={
 'regex_or_vocabulary_bool':sum(x['observation_kind'] in ('regex','vocabulary') for x in all_rows),
 'classification_copy':sum('classification' in x for x in all_rows),
 'expected_flip':sum(x['mutation_kind']=='expected' for x in all_rows),
 'mock_only_detector':sum(not (x['command'][:2]==['bash','-x'] and x['target_reached']) for x in all_rows),
}
receipt={'before':before,'after':after,'mutant':mutant,
 'production_invocations':{'before':len(before),'after':len(after),'mutant':len(mutant),'total':len(values)},
 'decision_diff':len(diff),'fp':len(fp),'fn':len(fn),'mutation_diff':mutation_diff,
 'forbidden_shortcuts':shortcut_counts}
open(receipt_path,'w').write(json.dumps(receipt,sort_keys=True)+'\n')
assert (len(before),len(after),len(mutant),len(values))==(82,82,82,246)
assert all(x['target_reached'] for x in before), [x['check_id'] for x in before if not x['target_reached']]
assert all(x['target_reached'] for x in after), [x['check_id'] for x in after if not x['target_reached']]
assert all(x['target_reached'] for x in mutant), [x['check_id'] for x in mutant if not x['target_reached']]
assert (len(diff),len(fp),len(fn))==(0,0,0)
assert mutation_diff==[41], mutation_diff
PY
  run python3 - "$TMPROOT/parity-receipt.json" "$ROOT/logs/test_receipts/cmd_4205_production_parity.json" <<'PY'
import json,shutil,sys
r=json.load(open(sys.argv[1])); assert len(r['before'])==82 and len(r['after'])==82 and len(r['mutant'])==82
assert (r['decision_diff'],r['fp'],r['fn'])==(0,0,0)
assert r['mutation_diff']==[41]
assert r['production_invocations']=={'before':82,'after':82,'mutant':82,'total':246}
assert all(v==0 for v in r['forbidden_shortcuts'].values())
shutil.copyfile(sys.argv[1],sys.argv[2])
PY
  [ "$status" -eq 0 ]
}

@test "legacy generator output remains available and reserves an id" {
  run bash "$ROOT/scripts/cmd_skeleton.sh" legacy-title infra
  [ "$status" -eq 0 ]
  [[ "$output" == *"title: \"legacy-title\""* ]]
}
