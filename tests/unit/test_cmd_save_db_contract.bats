#!/usr/bin/env bats
# test_necessity: DB-operation vocabulary distinguishes documentation schemas from production mutations.
@test "schema docs pass and mutations classify" {
  body="$(sed -n '/^is_db_operation_command_text()/,/^}/p' "$BATS_TEST_DIRNAME/../../scripts/cmd_save.sh")"
  run bash -c "$body; CMD_BLOCK_NC=''; is_db_operation_command_text \"\$1\"" _ "contract schema and schema definition"
  [ "$status" -ne 0 ]
  for command in "ALTER SCHEMA app RENAME TO old" "schema migration apply" "ALTER TABLE x ADD y int" "DROP TABLE x" "DELETE FROM x"; do
    run bash -c "$body; CMD_BLOCK_NC=''; is_db_operation_command_text \"\$1\"" _ "$command"
    [ "$status" -eq 0 ]
  done
}
@test "markdown paths are excluded and mixed phase warning remains" {
  run grep -F 'md|sh|bash' "$BATS_TEST_DIRNAME/../../scripts/cmd_save.sh"; [ "$status" -eq 0 ]
  run grep -F 'record_warn_reason "ac_phase_mixing"' "$BATS_TEST_DIRNAME/../../scripts/cmd_save.sh"; [ "$status" -eq 0 ]
}
@test "numeric relaxation uses shared units" {
  run grep -F 'q.keys() & a.keys()' "$BATS_TEST_DIRNAME/../../scripts/cmd_save.sh"; [ "$status" -eq 0 ]
  run grep -F 'min(a[unit]) < max(q[unit])' "$BATS_TEST_DIRNAME/../../scripts/cmd_save.sh"; [ "$status" -eq 0 ]
}
