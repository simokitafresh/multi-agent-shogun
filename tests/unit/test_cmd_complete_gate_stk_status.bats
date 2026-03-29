#!/usr/bin/env bats
# test_cmd_complete_gate_stk_status.bats - cmd_1561: GATE CLEAR時にSTK statusがdoneに更新されることを確認

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
    export SRC_NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"
    [ -f "$SRC_NORMALIZE_SCRIPT" ] || return 1
}

setup() {
    cmd_gate_scaffold "stk_status"
    cp "$SRC_NORMALIZE_SCRIPT" "$TEST_PROJECT/scripts/lib/normalize_report.sh"
    chmod +x "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
EOF

    cat > "$TEST_PROJECT/tasks/lessons.md" <<'EOF'
# Lessons
- **status**: confirmed
EOF

    cat > "$TEST_PROJECT/queue/inbox/karo.yaml" <<'EOF'
messages:
  - id: msg_test
    read: false
EOF
}

teardown() {
    cmd_gate_teardown
}

write_mapping_stk() {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  $TEST_CMD_ID:
    purpose: "STK status update test"
    project: infra
    status: delegated
    timestamp: "2026-03-04T21:25:00+09:00"
EOF
}

write_list_stk() {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "STK status update test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF
}

write_task_and_report() {
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons: []
EOF

    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-04T00:00:00"
status: done
ac_version_read: 2
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
}

@test "GATE CLEAR sets STK status to done (mapping format)" {
    write_mapping_stk
    write_task_and_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]
    [[ "$output" == *"done"* ]]

    # Verify STK YAML has status: done (mapping format: field is indented under cmd block)
    run grep "status: done" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR sets STK status to done (list format)" {
    write_list_stk
    write_task_and_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]
    [[ "$output" == *"done"* ]]

    # Verify STK YAML has status: done
    run grep "status: done" "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR skips update when STK status already done" {
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  $TEST_CMD_ID:
    purpose: "STK status already done test"
    project: infra
    status: done
    timestamp: "2026-03-04T21:25:00+09:00"
EOF
    write_task_and_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS ALREADY COMPLETED"* ]]
}
