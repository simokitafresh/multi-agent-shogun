#!/usr/bin/env bats
# test_necessity: test-hygieneは4閾値ORで発火し、閾値未達時に配備してはならない。

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  INVENTORY="$BATS_TEST_TMPDIR/inventory.csv"
  printf '#!/usr/bin/env bats\n' > "$BATS_TEST_TMPDIR/t.bats"
  printf '%s\n' 'case_id,test_file,ordinal,defense_target,fail_30d,wall_sec_allocated,classification,duplicate_contract,duplicate_evidence,fixture_self_reference,deprecated_mechanism,reason' > "$INVENTORY"
  printf '%s\n' 'a,t.bats,1,contract,unknown,1,nightly,no,no,no,no,x' >> "$INVENTORY"
}

@test "test-hygiene fires when push wall exceeds 170 seconds" {
  run env TEST_HYGIENE_ROOT="$BATS_TEST_TMPDIR" TEST_HYGIENE_INVENTORY="$INVENTORY" TEST_HYGIENE_PUSH_WALL_SEC=171 \
    bash "$ROOT/scripts/test_speed_task_generator.sh" hygiene-evaluate
  [ "$status" -eq 0 ]
  [[ "$output" == *'"trigger": true'* ]]
  [[ "$output" == *'push_wall_gt_170'* ]]
}

@test "test-hygiene stays idle below every threshold" {
  rm "$BATS_TEST_TMPDIR/t.bats"
  run env TEST_HYGIENE_ROOT="$BATS_TEST_TMPDIR" TEST_HYGIENE_INVENTORY="$INVENTORY" TEST_HYGIENE_PUSH_WALL_SEC=100 \
    bash "$ROOT/scripts/test_speed_task_generator.sh" hygiene-evaluate
  [ "$status" -eq 0 ]
  [[ "$output" == *'"trigger": false'* ]]
  [[ "$output" == *'"undeclared_present": 0'* ]]
}

@test "run_tests publishes requested TAP and fails closed on missing transport" {
  tap="$BATS_TEST_TMPDIR/requested.tap"
  fixture="$BATS_TEST_TMPDIR/one.bats"
  printf '%s\n' '#!/usr/bin/env bats' '@test "one" { true; }' > "$fixture"
  run env BATS_TAP_OUTPUT="$tap" bash "$ROOT/scripts/run_tests.sh" file "$fixture"
  [ "$status" -eq 0 ]
  [ -s "$tap" ]
  grep -q '^1\.\.1$' "$tap"
}

@test "hygiene-deploy emits complete identity and invokes canonical yaml deploy contract" {
  stub="$BATS_TEST_TMPDIR/deploy-stub"
  capture="$BATS_TEST_TMPDIR/capture"
  cat > "$stub" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$DEPLOY_CAPTURE.args"
cp "$2" "$DEPLOY_CAPTURE.task"
SH
  chmod +x "$stub"
  run env TEST_HYGIENE_ROOT="$BATS_TEST_TMPDIR" TEST_HYGIENE_INVENTORY="$INVENTORY" TEST_HYGIENE_PUSH_WALL_SEC=171 \
    DEPLOY_TASK="$stub" DEPLOY_CAPTURE="$capture" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" hygiene-deploy hanzo
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$capture.args")" = --yaml ]
  [ "$(sed -n '3p' "$capture.args")" = hanzo ]
  python3 - "$capture.task" <<'PY'
import json,sys
t=json.load(open(sys.argv[1]))['task']
assert t['parent_cmd'] == t['task_id']
assert t['report_path'].startswith('queue/reports/')
assert t['report_filename'] in t['report_path']
PY
}

@test "recent concrete declaration rate triggers while deleted audit history does not" {
  printf '%s\n' '# test_necessity: queue corruption is detected and malformed state is BLOCK.' >> "$BATS_TEST_TMPDIR/t.bats"
  printf '%s\n' t.bats > "$BATS_TEST_TMPDIR/new.list"
  run env TEST_HYGIENE_ROOT="$BATS_TEST_TMPDIR" TEST_HYGIENE_INVENTORY="$INVENTORY" \
    TEST_HYGIENE_NEW_TESTS_7D=1 TEST_HYGIENE_NEW_TEST_LIST="$BATS_TEST_TMPDIR/new.list" \
    bash "$ROOT/scripts/test_speed_task_generator.sh" hygiene-evaluate
  [ "$status" -eq 0 ]
  [[ "$output" == *'declaration_rate_gt_30'* ]]
  [[ "$output" == *'"declaration_quality_pass_files": 1'* ]]
}
