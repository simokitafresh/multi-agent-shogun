#!/usr/bin/env bats
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; T="$BATS_TEST_TMPDIR/project"
  mkdir -p "$T/queue/reports" "$T/queue/gates" "$T/scripts"; cp "$ROOT/scripts/review_bundle.py" "$T/scripts/"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >"$(dirname "$0")/../notify.log"' >"$T/scripts/inbox_write.sh"
  printf '%s\n' 'commands:' '  cmd_3931:' '    id: cmd_3931' '    project: infra' '    not_in_scope: [unrelated-runtime]' '    acceptance_criteria:' '      - {id: AC1}' '      - {id: AC2}' >"$T/queue/shogun_to_karo.yaml"
  printf '%s\n' 'parent_cmd: cmd_3931' 'worker_id: hayate' 'verdict: PASS' >"$T/queue/reports/hayate_report_cmd_3931.yaml"
}
@test "APPROVE bundle contains real summary and omits attention" {
  run python3 "$T/scripts/review_bundle.py" --root "$T" generate --cmd cmd_3931 --verdict APPROVE --report queue/reports/hayate_report_cmd_3931.yaml
  [ "$status" -eq 0 ]; [[ "$output" == *"acceptance_criteria_count=2"* ]]; [[ "$output" == *"scope=[\"unrelated-runtime\"]"* ]]; [[ "$output" == *"project=infra"* ]]
  grep -q 'karo cmd_3931 SG7 bundle.*bundle: queue/gates/cmd_3931/sg7_bundle.json.*acceptance_criteria_count=2.*project=infra report_review_result gunshi' "$T/notify.log"
  run python3 -c "import json; r=json.load(open('$T/queue/gates/cmd_3931/sg7_bundle.json'))['review']; assert r['cmd_spec_summary']=={'acceptance_criteria_count':2,'scope':['unrelated-runtime'],'project':'infra'}; assert 'karo_attention' not in r"
  [ "$status" -eq 0 ]
}
@test "FAIL bundle requires and stores attention" {
  run python3 "$T/scripts/review_bundle.py" --root "$T" generate --cmd cmd_3931 --verdict FAIL --report queue/reports/hayate_report_cmd_3931.yaml --no-notify; [ "$status" -eq 2 ]
  run python3 "$T/scripts/review_bundle.py" --root "$T" generate --cmd cmd_3931 --verdict FAIL --fail-reason "AC2 mismatch" --report queue/reports/hayate_report_cmd_3931.yaml --no-notify
  [ "$status" -eq 0 ]; [[ "$output" == *"karo_attention=AC2 mismatch"* ]]
}
@test "consumer returns values and fails closed on missing or contradictory fields" {
  python3 "$T/scripts/review_bundle.py" --root "$T" generate --cmd cmd_3931 --verdict APPROVE --report queue/reports/hayate_report_cmd_3931.yaml --no-notify >/dev/null
  run python3 "$T/scripts/review_bundle.py" --root "$T" consume --cmd cmd_3931 --bundle queue/gates/cmd_3931/sg7_bundle.json --expect-verdict APPROVE
  [ "$status" -eq 0 ]; [[ "$output" == *'"acceptance_criteria_count": 2'* ]]
  python3 -c "import json; p='$T/queue/gates/cmd_3931/sg7_bundle.json'; d=json.load(open(p)); d['review']['cmd_spec_summary'].pop('project'); open(p,'w').write(json.dumps(d))"
  run python3 "$T/scripts/review_bundle.py" --root "$T" consume --cmd cmd_3931 --bundle queue/gates/cmd_3931/sg7_bundle.json --expect-verdict APPROVE
  [ "$status" -eq 2 ]; [[ "$output" == *"project is missing"* ]]
  python3 "$T/scripts/review_bundle.py" --root "$T" generate --cmd cmd_3931 --verdict APPROVE --report queue/reports/hayate_report_cmd_3931.yaml --no-notify >/dev/null
  run python3 "$T/scripts/review_bundle.py" --root "$T" consume --cmd cmd_other --bundle queue/gates/cmd_3931/sg7_bundle.json --expect-verdict APPROVE
  [ "$status" -eq 2 ]; [[ "$output" == *"bundle cmd mismatch"* ]]
}
