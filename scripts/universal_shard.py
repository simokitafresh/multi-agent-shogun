#!/usr/bin/env python3
"""Deterministic role/CLI/model-neutral shard planner and executor."""
import argparse, fcntl, hashlib, itertools, json, os, pathlib, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
import yaml

POLICY_KEYS={"role","roles","cli","llm","model","allowed_roles","allowed_cli"}
def load(path):
 d=yaml.safe_load(pathlib.Path(path).read_text()) or {}
 if POLICY_KEYS & set(d): raise ValueError("role/CLI/LLM policy branching is forbidden")
 return d
def plan(d):
 items=d.get("items") or []; workers=d.get("workers") or []
 ids=[str(x.get("id","")) for x in items]; wids=[str(x.get("id","")) for x in workers]
 if len(items)<2: raise ValueError("at least two independent items required")
 if any(not x for x in ids) or len(ids)!=len(set(ids)): raise ValueError("item IDs must be non-empty and unique")
 if any(not x for x in wids) or len(wids)!=len(set(wids)): raise ValueError("worker IDs must be non-empty and unique")
 caps={x.get("capability") for x in items}
 eligible=sorted([w for w in workers if w.get("idle") is True and caps.intersection(w.get("capabilities") or [])],key=lambda x:str(x["id"]))
 n=min(len(eligible),int(d.get("max_workers",len(eligible))))
 if n<2: raise ValueError("N<2: silent single-worker fallback is forbidden")
 if len(items)<n: raise ValueError("zero-assignment shard forbidden: items fewer than workers")
 selected=next((combo for combo in itertools.combinations(eligible,n) if caps.issubset(set().union(*(set(w.get("capabilities") or []) for w in combo)))),None)
 if selected is None: raise ValueError("no eligible worker set covers all required capabilities")
 bins={str(w["id"]):{"worker":w,"weight":0.0,"items":[]} for w in selected}
 for item in sorted(items,key=lambda x:(-float(x.get("weight",0)),str(x["id"]))):
  weight=float(item.get("weight",0)); cap=item.get("capability")
  if weight<0 or not cap: raise ValueError(f"item {item.get('id')} requires non-negative weight and capability")
  if weight==0 and item.get("measured",True) is not False:
   raise ValueError(f"item {item.get('id')} zero weight must be marked unmeasured")
  choices=[b for b in bins.values() if cap in (b["worker"].get("capabilities") or [])]
  if not choices: raise ValueError(f"no eligible worker for capability {cap}")
  target=min(choices,key=lambda b:(b["weight"],str(b["worker"]["id"])))
  target["items"].append(item); target["weight"]+=weight
 assigned=[str(i["id"]) for b in bins.values() for i in b["items"]]
 if sorted(assigned)!=sorted(ids) or len(assigned)!=len(set(assigned)): raise RuntimeError("assignment invariant failed")
 return {"worker_count":n,"item_count":len(items),"shards":list(bins.values())}
def process_start_token(pid):
 try: return pathlib.Path(f"/proc/{pid}/stat").read_text().split()[21]
 except (FileNotFoundError,IndexError,PermissionError): return None
def reserve_worker(root,worker_id):
 root.mkdir(parents=True,exist_ok=True); key=hashlib.sha256(worker_id.encode()).hexdigest(); lock_path=root/f"{key}.lock"; owner_path=root/f"{key}.owner.json"
 fd=os.open(lock_path,os.O_CREAT|os.O_RDWR,0o600)
 try: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
 except BlockingIOError: os.close(fd); raise RuntimeError(f"worker {worker_id} already live-reserved")
 payload={"worker_id":worker_id,"pid":os.getpid(),"start":process_start_token(os.getpid()),"created":time.time()}
 tmp=root/f".{key}.{os.getpid()}.tmp"; tmp.write_text(json.dumps(payload,sort_keys=True)); os.replace(tmp,owner_path)
 return fd,owner_path
def release_worker(lease):
 fd,owner_path=lease
 try: owner_path.unlink(missing_ok=True)
 finally: fcntl.flock(fd,fcntl.LOCK_UN); os.close(fd)
def item_fingerprint(d,item):
 contract={"version":1,"command":d.get("command"),"timeout":float(d.get("timeout",900)),"item":item}
 return hashlib.sha256(json.dumps(contract,sort_keys=True,separators=(",",":"),default=str).encode()).hexdigest()
def execute_shard(d,shard,root,prior):
 wid=str(shard["worker"]["id"]); reservation_root=pathlib.Path(d.get("reservation_root","/tmp/shogun-shard-worker-leases")).resolve()
 lease=reserve_worker(reservation_root,wid); results=[]
 try:
  for item in shard["items"]:
   iid=str(item["id"])
   fingerprint=item_fingerprint(d,item)
   if (prior.get(iid) or {}).get("status")=="success" and prior[iid].get("fingerprint")==fingerprint: results.append(prior[iid]); continue
   base=root/"shards"/iid; paths={k:base/k for k in ("workdir","tmpdir","output_dir","cache_dir","timing")}
   for p in paths.values(): p.mkdir(parents=True,exist_ok=True)
   vals={"item_id":iid,"item_path":str(item.get("path","")),"worker_id":wid,**{k:str(v) for k,v in paths.items()}}
   env=os.environ.copy(); env.update({"TMPDIR":str(paths["tmpdir"]),"SHARD_ITEM_ID":iid,"SHARD_WORKER_ID":wid,"SHARD_OUTPUT_DIR":str(paths["output_dir"]),"SHARD_CACHE_DIR":str(paths["cache_dir"]),"SHARD_TIMING_DIR":str(paths["timing"]),"SHARD_ITEM_JSON":json.dumps(item,sort_keys=True,separators=(",",":"))})
   started=time.monotonic(); status="success"; rc=0
   try:
    cp=subprocess.run(str(d["command"]).format(**vals),shell=True,cwd=paths["workdir"],env=env,text=True,capture_output=True,timeout=float(d.get("timeout",900)))
    rc=cp.returncode; status="success" if rc==0 else ("skip" if rc==77 else "fail")
    (paths["output_dir"]/"stdout").write_text(cp.stdout); (paths["output_dir"]/"stderr").write_text(cp.stderr)
   except subprocess.TimeoutExpired as e: status,rc="timeout",124; (paths["output_dir"]/"stderr").write_text(str(e))
   except OSError as e: status,rc="fail",126; (paths["output_dir"]/"stderr").write_text(f"OSError: {e}")
   except KeyboardInterrupt: status,rc="cancel",130
   results.append({"id":iid,"worker":wid,"status":status,"returncode":rc,"fingerprint":fingerprint,"elapsed_sec":round(time.monotonic()-started,6)})
 finally: release_worker(lease)
 return results
def run(d):
 p=plan(d); root=pathlib.Path(d.get("state_dir",".shard-state")).resolve(); root.mkdir(parents=True,exist_ok=True)
 lock=open(root/"coordinator.lock","w"); fcntl.flock(lock,fcntl.LOCK_EX); merged=root/"merged.json"
 old=json.loads(merged.read_text()).get("results",[]) if merged.exists() else []; prior={str(x["id"]):x for x in old}; results=[]
 with ThreadPoolExecutor(max_workers=p["worker_count"]) as pool:
  fs=[pool.submit(execute_shard,d,s,root,prior) for s in p["shards"] if s["items"]]
  for f in as_completed(fs): results.extend(f.result())
 results.sort(key=lambda x:x["id"]); expected=sorted(str(x["id"]) for x in d["items"]); actual=[x["id"] for x in results]
 out={"worker_count":p["worker_count"],"expected":len(expected),"actual":len(actual),"missing":sorted(set(expected)-set(actual)),"duplicate":sorted(x for x in set(actual) if actual.count(x)>1),"results":results,"counts":{s:sum(r["status"]==s for r in results) for s in ("success","fail","skip","timeout","cancel")}}
 tmp=merged.with_suffix(".tmp"); tmp.write_text(json.dumps(out,indent=2,sort_keys=True)); os.replace(tmp,merged); fcntl.flock(lock,fcntl.LOCK_UN); lock.close()
 if out["missing"] or out["duplicate"]: raise RuntimeError("merge invariant failed")
 return out
def main():
 ap=argparse.ArgumentParser(); ap.add_argument("manifest"); g=ap.add_mutually_exclusive_group(required=True); g.add_argument("--plan",action="store_true"); g.add_argument("--run",action="store_true"); a=ap.parse_args()
 try: out=plan(load(a.manifest)) if a.plan else run(load(a.manifest)); print(json.dumps(out,indent=2,sort_keys=True)); return 0 if a.plan or not any(out["counts"][x] for x in ("fail","skip","timeout","cancel")) else 1
 except (ValueError,RuntimeError,KeyError) as e: print(f"BLOCK: {e}",file=sys.stderr); return 2
if __name__=="__main__": raise SystemExit(main())
