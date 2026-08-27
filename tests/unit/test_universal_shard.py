import importlib.util, json, pathlib, tempfile, unittest, yaml

ROOT=pathlib.Path(__file__).parents[2]
SPEC=importlib.util.spec_from_file_location("universal_shard", ROOT/"scripts/universal_shard.py")
M=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(M)
CONTRACT_SPEC=importlib.util.spec_from_file_location(
 "universal_shard_contract", ROOT/"scripts/lib/universal_shard_contract.py"
)
CONTRACT=importlib.util.module_from_spec(CONTRACT_SPEC)
CONTRACT_SPEC.loader.exec_module(CONTRACT)

def manifest(root, n=4):
    return {"max_workers": n, "state_dir": str(root/"state"), "command": "printf '%s' {item_id} > {output_dir}/value",
      "workers": [{"id": f"w{i}", "idle": True, "capabilities": ["any"], "adapter": {"backend": b}} for i,b in enumerate((["codex","claude","unknown","other","x","y"][:n]))],
      "items": [{"id": f"i{i}", "weight": (i%3)+1, "capability":"any", "path":str(root/f"p{i}")} for i in range(12)]}

class UniversalShardTest(unittest.TestCase):
 def test_before_fixture_has_no_common_entry(self):
  with tempfile.TemporaryDirectory() as d:
   x=manifest(pathlib.Path(d),2)
   self.assertNotIn("role",x); self.assertNotIn("model",x)
   self.assertEqual(M.plan(x)["worker_count"],2)
 def test_lpt_n_2_4_6_is_deterministic_exactly_once(self):
  with tempfile.TemporaryDirectory() as d:
   for n in (2,4,6):
    x=manifest(pathlib.Path(d),n); a=M.plan(x); b=M.plan(x)
    self.assertEqual(a,b); ids=[i["id"] for s in a["shards"] for i in s["items"]]
    self.assertEqual(len(ids),12); self.assertEqual(len(set(ids)),12)
 def test_unmeasured_zero_weight_item_is_still_assigned_once(self):
  with tempfile.TemporaryDirectory() as d:
   x=manifest(pathlib.Path(d),2); x["items"][0]["weight"]=0; x["items"][0]["measured"]=False
   out=M.plan(x); ids=[i["id"] for s in out["shards"] for i in s["items"]]
   self.assertEqual(sorted(ids),sorted(i["id"] for i in x["items"])); self.assertEqual(len(ids),len(set(ids)))
 def test_zero_assignment_shard_is_explicitly_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   x=manifest(pathlib.Path(d),4); x["items"]=x["items"][:2]
   with self.assertRaisesRegex(ValueError,"zero-assignment shard"):
    M.plan(x)
 def test_n_less_than_two_blocks(self):
  with tempfile.TemporaryDirectory() as d:
   x=manifest(pathlib.Path(d),2); x["workers"][1]["idle"]=False
   with self.assertRaisesRegex(ValueError,"N<2"): M.plan(x)
 def test_role_cli_model_policy_blocks_but_adapter_is_opaque(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/"m.yaml"; x=manifest(pathlib.Path(d))
   for caller in ("shogun","karo","gunshi","ninja"):
    x["caller"]={"identity":caller}; p.write_text(yaml.safe_dump(x)); self.assertEqual(M.plan(M.load(p))["item_count"],12)
   x["model"]="gpt"; p.write_text(yaml.safe_dump(x))
   with self.assertRaises(ValueError): M.load(p)
 def test_worker_growth_shrink_and_capability_filter(self):
  with tempfile.TemporaryDirectory() as d:
   x=manifest(pathlib.Path(d),6); x["workers"][0]["idle"]=False; x["workers"][1]["capabilities"]=["other"]
   self.assertEqual(M.plan(x)["worker_count"],4)
   x["workers"].append({"id":"w6","idle":True,"capabilities":["any"],"adapter":{"backend":"unknown"}})
   self.assertEqual(M.plan(x)["worker_count"],5)
 def test_three_workload_types_and_partial_retry(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d)
   for kind,cmd in (("test","true"),("research","test -d {workdir}"),("transform","printf x > {output_dir}/x")):
    x=manifest(root/kind,2); x["command"]=cmd; out=M.run(x); self.assertEqual(out["counts"]["success"],12); self.assertEqual(out["missing"],[])
   x=manifest(root/"retry",2); marker=root/"marker"; x["command"]=f"if [ '{{item_id}}' = i0 ] && [ ! -f {marker} ]; then touch {marker}; exit 1; fi"
   first=M.run(x); self.assertEqual(first["counts"]["fail"],1); second=M.run(x); self.assertEqual(second["counts"]["success"],12)
 def test_timeout_and_skip_are_losslessly_merged(self):
  with tempfile.TemporaryDirectory() as d:
   x=manifest(pathlib.Path(d),2); x["items"]=x["items"][:2]; x["timeout"]=.05; x["command"]="[ {item_id} = i0 ] && exit 77 || sleep 1"
   out=M.run(x); self.assertEqual(out["counts"]["skip"],1); self.assertEqual(out["counts"]["timeout"],1); self.assertEqual(out["actual"],2)


def contract_task(task_type, ac_count=3, estimated_minutes=5, serial=None):
    task = {
        "task_type": task_type,
        "estimated_minutes": estimated_minutes,
        "acceptance_criteria": [
            {"id": f"AC{i}", "description": f"condition {i}"}
            for i in range(1, ac_count + 1)
        ],
    }
    if serial is not None:
        task["serial_dependency_evidence"] = serial
    return task


class UniversalShardContractTest(unittest.TestCase):
    def test_full_and_hotfix_three_ac_block_even_when_short(self):
        for task_type in ("full", "hotfix"):
            with self.subTest(task_type=task_type):
                with self.assertRaisesRegex(ValueError, "3 or more acceptance criteria"):
                    CONTRACT.build(contract_task(task_type), [], f"{task_type}-3ac")

    def test_full_and_hotfix_two_ac_pass(self):
        for task_type in ("full", "hotfix"):
            with self.subTest(task_type=task_type):
                result = CONTRACT.build(contract_task(task_type, ac_count=2), [], f"{task_type}-2ac")
                self.assertEqual(result["status"], "not_required")

    def test_scout_and_recon_three_ac_are_exempt(self):
        for task_type in ("scout", "recon"):
            with self.subTest(task_type=task_type):
                result = CONTRACT.build(contract_task(task_type), [], f"{task_type}-3ac")
                self.assertEqual(result["status"], "not_required")

    def test_three_ac_with_strict_serial_evidence_passes(self):
        result = CONTRACT.build(
            contract_task("hotfix", serial="AC1 -> AC2 -> AC3"),
            [],
            "hotfix-3ac-serial",
        )
        self.assertEqual(result["status"], "serial")
        self.assertEqual(result["acceptance_criteria_count"], 3)
if __name__ == '__main__': unittest.main()
