#!/usr/bin/env bats
# test_necessity: bugfix/hotfix/ci_fix deployment must remain bound to an exact Gunshi pre-implementation receipt.

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  source <(sed -n '/^deploy_task_require_pre_implementation_review()/,/^}/p' "$ROOT/scripts/deploy_task.sh")
  TASK="$BATS_TEST_TMPDIR/task.yaml"
}

write_task() {
  local receipt="$1" ac="fp-current" tid="cmd_fixture_hotfix"
  cat >"$TASK" <<YAML
task:
  task_type: hotfix
  task_id: $tid
  ac_version: $ac
$receipt
YAML
}

@test "pre-review missing blocks" {
  write_task ""
  run deploy_task_require_pre_implementation_review "$TASK"
  [ "$status" -eq 2 ]
}

@test "receipt for another task blocks" {
  write_task $'  pre_implementation_review:\n    result: LGTM\n    reviewer: gunshi\n    task_id: cmd_other\n    task_fingerprint: fp-current\n    evidence_message_id: msg-1'
  run deploy_task_require_pre_implementation_review "$TASK"
  [ "$status" -eq 2 ]
}

@test "stale receipt after task change blocks" {
  write_task $'  pre_implementation_review:\n    result: LGTM\n    reviewer: gunshi\n    task_id: cmd_fixture_hotfix\n    task_fingerprint: fp-old\n    evidence_message_id: msg-1'
  run deploy_task_require_pre_implementation_review "$TASK"
  [ "$status" -eq 2 ]
}

@test "matching receipt passes" {
  write_task $'  pre_implementation_review:\n    result: LGTM\n    reviewer: gunshi\n    task_id: cmd_fixture_hotfix\n    task_fingerprint: fp-current\n    evidence_message_id: msg-1'
  run deploy_task_require_pre_implementation_review "$TASK"
  [ "$status" -eq 0 ]
}

@test "non incident task remains outside pre-review gate" {
  write_task ""
  sed -i 's/task_type: hotfix/task_type: docs/' "$TASK"
  run deploy_task_require_pre_implementation_review "$TASK"
  [ "$status" -eq 0 ]
}
