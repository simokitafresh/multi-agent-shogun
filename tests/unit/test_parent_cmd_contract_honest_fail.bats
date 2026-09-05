#!/usr/bin/env bats
# test_necessity: parent AC coverage may include a failed binary check only when
# current SG7 attests the exact path and current-generation Karo ACCEPT records
# approved_honest_fail. Stale/path-mismatched/unaccepted reports stay BLOCKED.

setup() {
  ROOT_SRC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FIX="$BATS_TEST_TMPDIR/root"
  mkdir -p "$FIX/scripts/lib" "$FIX/queue/archive/parent_contracts" "$FIX/queue/reports" "$FIX/queue/gates/cmd_900/review_approvals/reports/key"
  cp "$ROOT_SRC/scripts/lib/parent_cmd_contract.py" "$FIX/scripts/lib/"
  cp "$ROOT_SRC/scripts/review_bundle.py" "$FIX/scripts/"
  python3 - "$FIX" <<'PY'
import hashlib, json, sys, yaml
from pathlib import Path
root=Path(sys.argv[1]); cmd='cmd_900'; purpose='fixture purpose'; acs=['AC1']
fp=hashlib.sha256(json.dumps({'cmd':cmd,'purpose':purpose,'acs':acs},ensure_ascii=False,sort_keys=True).encode()).hexdigest()[:16]
(root/'queue/shogun_to_karo.yaml').write_text(yaml.safe_dump({'commands':{cmd:{'purpose':purpose,'acceptance_criteria':[{'id':'AC1'}]}}},sort_keys=False))
(root/'queue/archive/parent_contracts/hayate__cmd_900.yaml').write_text(yaml.safe_dump({'worker_id':'hayate','parent_cmd':cmd,'parent_ac_coverage':['AC1'],'parent_contract_fingerprint':fp},sort_keys=False))
report={'worker_id':'hayate','report_id':'rpt-fixture','report_identity_version':2,'task_id':'cmd_900_full','parent_cmd':cmd,'status':'failed','verdict':'FAIL','parent_ac_coverage':['AC1'],'parent_contract_fingerprint':fp,'binary_checks':{'AC1':[{'check':'truthful failure','result':'no'}]}}
rp=root/'queue/reports/hayate_report_cmd_900.yaml'; rp.write_text(yaml.safe_dump(report,sort_keys=False)); gen=hashlib.sha256(rp.read_bytes()).hexdigest()
review={'cmd_id':cmd,'verdict':'APPROVE','report_verdict':'FAIL','reviewer':'gunshi','reviewed_at':'2026-09-05T00:00:00+09:00','report':'queue/reports/hayate_report_cmd_900.yaml','report_id':'rpt-fixture','report_fingerprint':gen,'report_generation':gen,'approved_failed_check_paths':['binary_checks.AC1[0]'],'cmd_spec_source':'queue/shogun_to_karo.yaml','cmd_spec_summary':{'acceptance_criteria_count':1,'project':'infra','scope':'fixture'},'dashboard_line':'- **cmd_900**: fixture'}
(root/'queue/gates/cmd_900/sg7_bundle.json').write_text(json.dumps({'review':review}))
(root/'queue/gates/cmd_900/review_approvals/reports/key/karo.yaml').write_text(yaml.safe_dump({'result':'ACCEPT','approval_mode':'approved_honest_fail','generation':gen,'report':'queue/reports/hayate_report_cmd_900.yaml'}))
PY
}

@test "current SG7 exact path plus Karo honest-fail ACCEPT covers parent AC" {
  run python3 "$FIX/scripts/lib/parent_cmd_contract.py" cmd_900 --root "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"parent_contract_ok"* ]]
}

@test "missing Karo acceptance and mismatched SG7 path remain fail-closed" {
  mv "$FIX/queue/gates/cmd_900/review_approvals/reports/key/karo.yaml" "$FIX/karo.saved"
  run python3 "$FIX/scripts/lib/parent_cmd_contract.py" cmd_900 --root "$FIX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent_ac_uncovered:AC1"* ]]
  mv "$FIX/karo.saved" "$FIX/queue/gates/cmd_900/review_approvals/reports/key/karo.yaml"
  python3 - "$FIX/queue/gates/cmd_900/sg7_bundle.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['review']['approved_failed_check_paths']=['binary_checks.AC1[1]']; open(p,'w').write(json.dumps(d))
PY
  run python3 "$FIX/scripts/lib/parent_cmd_contract.py" cmd_900 --root "$FIX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent_ac_uncovered:AC1"* ]]
}
