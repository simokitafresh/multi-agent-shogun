#!/usr/bin/env bats

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; TMPROOT="$(mktemp -d)"; }
teardown() { rm -rf "$TMPROOT"; }

@test "test research transform adapters share the manifest contract at N 2 and 4" {
  run env ROOT="$ROOT" TMPROOT="$TMPROOT" python3 - <<'PY'
import importlib.util, os, pathlib
r=pathlib.Path(os.environ['ROOT']); t=pathlib.Path(os.environ['TMPROOT'])
s=importlib.util.spec_from_file_location('a',r/'scripts/universal_shard_adapters.py'); a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
paths=[]
for i in range(8): p=t/f'i{i}';p.write_text(str(i));paths.append(str(p))
for n in (2,4):
 for kind,command in (('test',None),('research',None),('transform','cp {item_path} {output_dir}/result')):
  m=a.manifest(kind,paths,t/f'{kind}-{n}',n,command)
  assert m['max_workers']==n and len(m['items'])==len({x['id'] for x in m['items']})==8
print('cells=6 missing=0 duplicate=0')
PY
  [ "$status" -eq 0 ]
}

@test "research and transform results match at N 2 and 4" {
  run env ROOT="$ROOT" TMPROOT="$TMPROOT" python3 - <<'PY'
import importlib.util, os, pathlib
r=pathlib.Path(os.environ['ROOT']); t=pathlib.Path(os.environ['TMPROOT']);s=importlib.util.spec_from_file_location('a',r/'scripts/universal_shard_adapters.py');a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
paths=[]
for i in range(4): p=t/f'i{i}';p.write_text(str(i));paths.append(str(p))
for kind,command in (('research',None),('transform','cp {item_path} {output_dir}/result')):
 outs=[a.run_adapter(kind,paths,t/f'{kind}-{n}',n,command) for n in (2,4)]
 assert all(o['actual']==4 and not o['missing'] and not o['duplicate'] and o['counts']['success']==4 for o in outs)
 assert [x['id'] for x in outs[0]['results']]==[x['id'] for x in outs[1]['results']]
print('result_match=yes missing=0 duplicate=0')
PY
  [ "$status" -eq 0 ]
}

@test "resume reuses success and retries only failed item" {
  run env ROOT="$ROOT" TMPROOT="$TMPROOT" python3 - <<'PY'
import importlib.util, os, pathlib
r=pathlib.Path(os.environ['ROOT']);t=pathlib.Path(os.environ['TMPROOT']);s=importlib.util.spec_from_file_location('a',r/'scripts/universal_shard_adapters.py');a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
paths=[]
for i in range(2): p=t/f'i{i}';p.write_text(str(i));paths.append(str(p))
log=t/'runs';marker=t/'once';cmd=f"echo {{item_id}} >> {log}; if [ '{{item_path}}' = '{paths[0]}' ] && [ ! -e {marker} ]; then touch {marker}; exit 1; fi"
first=a.run_adapter('transform',paths,t/'state',2,cmd);second=a.run_adapter('transform',paths,t/'state',2,cmd)
counts={x:log.read_text().splitlines().count(x) for x in set(log.read_text().splitlines())}
assert first['counts']['fail']==1 and second['counts']['success']==2 and sorted(counts.values())==[1,2]
print('success_reexec=0 failed_reexec=1 final=pass')
PY
  [ "$status" -eq 0 ]
}
