#!/usr/bin/env bats

# test_necessity: malformed quoted ledger scalars must be repaired without field loss,
# and role usage denominators must keep unknown/missing executors outside known roles.

setup() {
  export TEST_TMPDIR="$BATS_TEST_TMPDIR/skill-ledger"
  mkdir -p "$TEST_TMPDIR/logs"
  export SHOGUN_REPO_ROOT="$TEST_TMPDIR"
  export SKILL_EXECUTION_LOG_FILE="$TEST_TMPDIR/logs/skill_execution_log.yaml"
  export SCRIPT="$BATS_TEST_DIRNAME/../../scripts/skill_execution_log.sh"
}

@test "repair preserves entries and role-summary isolates unknown and missing executors" {
  printf '%s\n' \
    'executions:' \
    '- ts: "2026-08-02T00:00:00+0900"' \
    '  skill: "note-draft"' \
    '  executor: "shogun"' \
    '  result: "FAIL"' \
    '  used: "true"' \
    '  stumbling_points: "File "<stdin>", line 1"' \
    '  source: "cmd_one"' \
    '- ts: "2026-08-02T00:00:01+0900"' \
    '  skill: "sample"' \
    '  executor: "tobisaru"' \
    '  result: "PASS"' \
    '  used: "false"' \
    '  source: "cmd_two"' \
    '- ts: "2026-08-02T00:00:02+0900"' \
    '  skill: "sample"' \
    '  executor: "mystery"' \
    '  result: "PASS"' \
    '  used: "true"' \
    '- ts: "2026-08-02T00:00:03+0900"' \
    '  skill: "sample"' \
    '  executor: ""' \
    '  result: "FAIL"' \
    '  used: "true"' > "$SKILL_EXECUTION_LOG_FILE"

  run bash "$SCRIPT" repair
  [ "$status" -eq 0 ]
  [[ "$output" == *"repair_count=1 entries=4"* ]]

  run python3 - "$SKILL_EXECUTION_LOG_FILE" <<'PY'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1]))['executions']
assert len(rows) == 4
assert rows[0]['stumbling_points'] == 'File "<stdin>", line 1'
assert rows[0]['source'] == 'cmd_one'
PY
  [ "$status" -eq 0 ]

  run bash "$SCRIPT" role-summary
  [ "$status" -eq 0 ]
  [[ "$output" == *$'shogun\t1\t0\t1\t1\t1\t100.00%'* ]]
  [[ "$output" == *$'ninja\t1\t1\t0\t0\t1\t0.00%'* ]]
  [[ "$output" == *$'unknown\t1\t1\t0\t1\t1\t100.00%'* ]]
  [[ "$output" == *$'missing\t1\t0\t1\t1\t1\t100.00%'* ]]
}
