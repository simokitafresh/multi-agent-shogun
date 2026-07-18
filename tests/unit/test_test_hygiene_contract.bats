#!/usr/bin/env bats
# test_necessity: test-hygieneは4閾値ORで発火し、閾値未達時に配備してはならない。

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  INVENTORY="$BATS_TEST_TMPDIR/inventory.csv"
  printf '%s\n' 'case_id,test_file,ordinal,defense_target,fail_30d,wall_sec_allocated,classification,duplicate_contract,duplicate_evidence,fixture_self_reference,deprecated_mechanism,reason' > "$INVENTORY"
  printf '%s\n' 'a,t.bats,1,contract,unknown,1,nightly,no,no,no,no,x' >> "$INVENTORY"
}

@test "test-hygiene fires when push wall exceeds 170 seconds" {
  run env TEST_HYGIENE_INVENTORY="$INVENTORY" TEST_HYGIENE_PUSH_WALL_SEC=171 \
    bash "$ROOT/scripts/test_speed_task_generator.sh" hygiene-evaluate
  [ "$status" -eq 0 ]
  [[ "$output" == *'"trigger": true'* ]]
  [[ "$output" == *'push_wall_gt_170'* ]]
}

@test "test-hygiene stays idle below every threshold" {
  run env TEST_HYGIENE_INVENTORY="$INVENTORY" TEST_HYGIENE_PUSH_WALL_SEC=100 \
    bash "$ROOT/scripts/test_speed_task_generator.sh" hygiene-evaluate
  [ "$status" -eq 0 ]
  [[ "$output" == *'"trigger": false'* ]]
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
