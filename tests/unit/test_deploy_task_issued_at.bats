#!/usr/bin/env bats

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "deploy_issued_at"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<'EOF'
task:
  status: idle
  parent_cmd: cmd_issue_fixture
EOF
}

teardown() {
    deploy_task_teardown
}

@test "issued_at is recorded once and preserved on same-command retry" {
    record_issued_at_once "$TEST_PROJECT/queue/tasks/sasuke.yaml" cmd_issue_fixture "2026-07-17T01:00:00"
    record_issued_at_once "$TEST_PROJECT/queue/tasks/sasuke.yaml" cmd_issue_fixture "2026-07-17T01:05:00"

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" issued_at ""
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-17T01:00:00" ]
}

@test "issued_at changes for a newly issued command" {
    record_issued_at_once "$TEST_PROJECT/queue/tasks/sasuke.yaml" cmd_issue_fixture "2026-07-17T01:00:00"
    yaml_field_set "$TEST_PROJECT/queue/tasks/sasuke.yaml" task parent_cmd cmd_next_fixture
    record_issued_at_once "$TEST_PROJECT/queue/tasks/sasuke.yaml" cmd_next_fixture "2026-07-17T01:05:00"

    run field_get "$TEST_PROJECT/queue/tasks/sasuke.yaml" issued_at ""
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-17T01:05:00" ]
}

@test "issue event persists terminal BLOCK reason for collision and delivery failures" {
    DEPLOY_TASK_ISSUE_ATTEMPT_ID="cmd_issue_fixture:sasuke:attempt"
    CMD_ID=cmd_issue_fixture
    NINJA_NAME=sasuke
    deploy_task_append_issue_event issued entry
    deploy_task_append_issue_event blocked exit_1

    run grep -c 'attempt_id: "cmd_issue_fixture:sasuke:attempt"' "$TEST_PROJECT/logs/deploy_issue_log.yaml"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
    run grep -F 'reason: "exit_1"' "$TEST_PROJECT/logs/deploy_issue_log.yaml"
    [ "$status" -eq 0 ]
}

@test "direct publish re-applies issued_at before quality and delivery stages" {
    run python3 - "$TEST_PROJECT/scripts/deploy_task.sh" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
publish = text.index('deploy_task_direct_yaml_publish "$task_yaml" "$YAML_FILE"')
issued = text.index('record_issued_at_once "$task_yaml" "$CMD_ID"', publish)
quality = text.index('deploy_task_direct_yaml_is_preinjected "$task_yaml"', publish)
assert publish < issued < quality
PY
    [ "$status" -eq 0 ]
}
