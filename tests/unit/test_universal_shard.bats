#!/usr/bin/env bats

setup() { REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

@test "before fixture proves no role-neutral variable-N entrypoint" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import os, pathlib
r=pathlib.Path(os.environ['ROOT'])
legacy=[r/'scripts/run_tests.sh', r/'scripts/deploy_task.sh']
assert all(p.exists() for p in legacy)
assert all('shard_work.sh' not in p.read_text(errors='ignore') for p in legacy)
print('before_common_entry=0 fixed_or_manual_entrypoints=2')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"before_common_entry=0"* ]]
}

@test "callers and backend metadata share one manifest contract" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util, os, pathlib, tempfile, yaml
p=pathlib.Path(os.environ['ROOT'])/'scripts/universal_shard.py'
s=importlib.util.spec_from_file_location('u',p); u=importlib.util.module_from_spec(s); s.loader.exec_module(u)
with tempfile.TemporaryDirectory() as d:
 x={'max_workers':3,'state_dir':d,'command':'true','items':[{'id':'a','weight':1,'capability':'x'},{'id':'b','weight':1,'capability':'x'}],
    'workers':[{'id':str(i),'idle':True,'capabilities':['x'],'adapter':{'backend':b}} for i,b in enumerate(('codex','claude','unknown'))]}
 q=pathlib.Path(d)/'m.yaml'
 for caller in ('shogun','karo','gunshi','ninja'):
  x['caller']={'identity':caller}; q.write_text(yaml.safe_dump(x)); assert u.plan(u.load(q))['item_count']==2
 x['model']='gpt'; q.write_text(yaml.safe_dump(x))
 try: u.load(q); raise AssertionError('model policy accepted')
 except ValueError: pass
 print('caller_backend_cells=12 policy_branch_accepts=0')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"caller_backend_cells=12 policy_branch_accepts=0"* ]]
}

@test "N 2 4 6 growth shrink and equal-weight LPT are deterministic exactly once" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util, os, pathlib
p=pathlib.Path(os.environ['ROOT'])/'scripts/universal_shard.py'; s=importlib.util.spec_from_file_location('u',p); u=importlib.util.module_from_spec(s); s.loader.exec_module(u)
for n in (2,4,6):
 x={'max_workers':n,'items':[{'id':f'i{i}','weight':1 if i<4 else i%3+1,'capability':'x'} for i in range(12)],
    'workers':[{'id':f'w{i}','idle':True,'capabilities':['x']} for i in range(n)]}
 a=u.plan(x); b=u.plan(x); assert a==b
 ids=[i['id'] for z in a['shards'] for i in z['items']]; assert len(ids)==len(set(ids))==12
x['workers'][0]['idle']=False; assert u.plan(x)['worker_count']==5
try: u.plan({'max_workers':1,'items':x['items'],'workers':x['workers'][:1]}); raise AssertionError('N<2 accepted')
except ValueError: pass
print('N_cells=3 missing=0 duplicate=0 deterministic=yes')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing=0 duplicate=0"* ]]
}

@test "executor preserves terminal states and retries only failed shard" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util, os, pathlib, tempfile
p=pathlib.Path(os.environ['ROOT'])/'scripts/universal_shard.py'; s=importlib.util.spec_from_file_location('u',p); u=importlib.util.module_from_spec(s); s.loader.exec_module(u)
with tempfile.TemporaryDirectory() as d:
 r=pathlib.Path(d); marker=r/'once'
 x={'max_workers':2,'state_dir':str(r/'state'),'command':f"if [ '{{item_id}}' = a ] && [ ! -f {marker} ]; then touch {marker}; exit 1; fi",
    'items':[{'id':'a','weight':2,'capability':'x'},{'id':'b','weight':1,'capability':'x'}],
    'workers':[{'id':'w0','idle':True,'capabilities':['x']},{'id':'w1','idle':True,'capabilities':['x']}]}
 first=u.run(x); assert first['counts']['fail']==1 and first['counts']['success']==1
 second=u.run(x); assert second['counts']['success']==2 and not second['missing'] and not second['duplicate']
 x['state_dir']=str(r/'term'); x['timeout']=.05; x['command']='[ {item_id} = a ] && exit 77 || sleep 1'
 term=u.run(x); assert term['counts']['skip']==1 and term['counts']['timeout']==1
 print('resume_success=2 skip=1 timeout=1 missing=0 duplicate=0')
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip=1 timeout=1"* ]]
}

@test "capability cover avoids prefix false block" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util, os, pathlib
p=pathlib.Path(os.environ['ROOT'])/'scripts/universal_shard.py'; s=importlib.util.spec_from_file_location('u',p); u=importlib.util.module_from_spec(s); s.loader.exec_module(u)
x={'max_workers':2,'items':[{'id':'x','weight':2,'capability':'x'},{'id':'y','weight':1,'capability':'y'}],
   'workers':[{'id':'A','idle':True,'capabilities':['x']},{'id':'B','idle':True,'capabilities':['x']},{'id':'C','idle':True,'capabilities':['y']}]}
out=u.plan(x); assert [s['worker']['id'] for s in out['shards']]==['A','C']; print('cover=A,C false_block=0')
PY
  [ "$status" -eq 0 ]
}

@test "fingerprint invalidates prior success after payload or command change" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util, os, pathlib, tempfile
p=pathlib.Path(os.environ['ROOT'])/'scripts/universal_shard.py'; s=importlib.util.spec_from_file_location('u',p); u=importlib.util.module_from_spec(s); s.loader.exec_module(u)
with tempfile.TemporaryDirectory() as d:
 r=pathlib.Path(d); log=r/'log'; x={'max_workers':2,'state_dir':str(r/'s'),'command':f'echo {{item_id}} >> {log}','items':[{'id':'a','weight':1,'capability':'x','path':'v1'},{'id':'b','weight':1,'capability':'x'}],'workers':[{'id':'A','idle':True,'capabilities':['x']},{'id':'B','idle':True,'capabilities':['x']}]}
 u.run(x); u.run(x); assert len(log.read_text().splitlines())==2
 x['items'][0]['path']='v2'; u.run(x); assert len(log.read_text().splitlines())==3
 x['command']=f'echo changed-{{item_id}} >> {log}'; u.run(x); assert len(log.read_text().splitlines())==5
 print('unchanged_reexec=0 payload_reexec=1 command_reexec=2')
PY
  [ "$status" -eq 0 ]
}

@test "stale reserve recovers and live reserve blocks" {
  run env ROOT="$REPO_ROOT" python3 - <<'PY'
import importlib.util, json, os, pathlib, tempfile
p=pathlib.Path(os.environ['ROOT'])/'scripts/universal_shard.py'; s=importlib.util.spec_from_file_location('u',p); u=importlib.util.module_from_spec(s); s.loader.exec_module(u)
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d)/'w'; p.write_text(json.dumps({'pid':99999999,'start':'0'})); u.reserve_worker(p); p.unlink()
 p.write_text(json.dumps({'pid':os.getpid(),'start':u.process_start_token(os.getpid())}))
 try: u.reserve_worker(p); raise AssertionError('live reserve accepted')
 except RuntimeError as e: assert 'live-reserved' in str(e)
 print('stale_recovered=1 live_double_blocked=1')
PY
  [ "$status" -eq 0 ]
}
