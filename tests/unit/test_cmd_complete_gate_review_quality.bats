#!/usr/bin/env bats
# test_cmd_complete_gate_review_quality.bats - review quality gate behavior

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
}

setup() {
    cmd_gate_scaffold "cmd_gate_review"
    mkdir -p "$TEST_PROJECT/tests/unit"

    # Extra gate flags for review quality tests
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/review_gate.done" <<'EOF'
timestamp: 2026-03-06T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/report_merge.done" <<'EOF'
timestamp: 2026-03-06T00:00:00
source: test
EOF

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

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "review quality gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-06T00:00:00"
EOF
}

teardown() {
    cmd_gate_teardown
}

write_task() {
    local ninja="$1"
    local task_type="$2"
    cat > "$TEST_PROJECT/queue/tasks/${ninja}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: $task_type
  task_id: subtask_test_${task_type}
  report_filename: ${ninja}_report_${TEST_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF
}

write_impl_report() {
    local ninja="$1"
    local worker_id="$2"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $worker_id
task_id: subtask_test_impl
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
ac_version_read: 1
purpose_validation:
  fit: true
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

write_review_report() {
    local ninja="$1"
    local worker_id="$2"
    local verdict_block="$3"
    local self_gate_block="$4"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $worker_id
task_id: subtask_test_review
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
ac_version_read: 1
${verdict_block}
purpose_validation:
  fit: true
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
${self_gate_block}
EOF
}

write_recon_report() {
    local ninja="$1"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test_recon
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
ac_version_read: 1
purpose_validation:
  fit: true
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

@test "review report without verdict blocks" {
    write_task "sasuke" "implement"
    write_task "hayate" "review"
    write_impl_report "sasuke" "sasuke"
    write_review_report "hayate" "hayate" "" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Review quality check:"* ]]
    [[ "$output" == *"[CRITICAL] hayate: NG ← verdict欠落または不正値"* ]]
    [[ "$output" == *"review report missing verdict field"* ]]
}

@test "review report with incomplete self_gate_check blocks" {
    write_task "sasuke" "implement"
    write_task "hayate" "review"
    write_impl_report "sasuke" "sasuke"
    write_review_report "hayate" "hayate" "verdict: PASS" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: FAIL
  status_valid: PASS
  purpose_fit: PASS"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] hayate: NG ← self_gate_check 4項目が不足またはPASS以外"* ]]
    [[ "$output" == *"review report self_gate_check incomplete or not all PASS"* ]]
}

@test "same worker as implementer and reviewer blocks" {
    write_task "sasuke" "implement"
    write_task "hayate" "review"
    write_impl_report "sasuke" "sasuke"
    write_review_report "hayate" "sasuke" "verdict: PASS" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] NG ← reviewer and implementer overlap: sasuke"* ]]
    [[ "$output" == *"reviewer is same as implementer"* ]]
}

@test "cmd without review report skips new review checks" {
    write_task "sasuke" "recon"
    write_recon_report "sasuke"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review quality check:"* ]]
    [[ "$output" == *"SKIP (no review reports for this cmd)"* ]]
}

@test "TODO in non-test files blocks gate" {
    write_task "sasuke" "recon"
    write_recon_report "sasuke"
    cat > "$TEST_PROJECT/scripts/sample.sh" <<EOF
#!/usr/bin/env bash
# TODO cmd_999
exit 0
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"TODO/FIXME residual check:"* ]]
    [[ "$output" == *"[CRITICAL] NG ← 1件のTODO/FIXMEが残存:"* ]]
}
