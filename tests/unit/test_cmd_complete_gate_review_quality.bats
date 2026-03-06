#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_FIELD_GET_SCRIPT="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET_SCRIPT="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET_SCRIPT" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_gate_review.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"

    mkdir -p \
        "$TEST_PROJECT/scripts/lib" \
        "$TEST_PROJECT/scripts/gates" \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/queue/gates/$TEST_CMD_ID" \
        "$TEST_PROJECT/queue/inbox" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/tasks" \
        "$TEST_PROJECT/tests/unit"

    cp "$SRC_GATE_SCRIPT" "$TEST_PROJECT/scripts/cmd_complete_gate.sh"
    cp "$SRC_FIELD_GET_SCRIPT" "$TEST_PROJECT/scripts/lib/field_get.sh"
    cp "$SRC_YAML_FIELD_SET_SCRIPT" "$TEST_PROJECT/scripts/lib/yaml_field_set.sh"

    cat > "$TEST_PROJECT/scripts/auto_draft_lesson.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/inbox_archive.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/dashboard_update.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gist_sync.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/ntfy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    chmod +x \
        "$TEST_PROJECT/scripts/cmd_complete_gate.sh" \
        "$TEST_PROJECT/scripts/lib/field_get.sh" \
        "$TEST_PROJECT/scripts/lib/yaml_field_set.sh" \
        "$TEST_PROJECT/scripts/auto_draft_lesson.sh" \
        "$TEST_PROJECT/scripts/inbox_archive.sh" \
        "$TEST_PROJECT/scripts/lesson_impact_analysis.sh" \
        "$TEST_PROJECT/scripts/dashboard_update.sh" \
        "$TEST_PROJECT/scripts/gist_sync.sh" \
        "$TEST_PROJECT/scripts/ntfy_cmd.sh" \
        "$TEST_PROJECT/scripts/ntfy.sh" \
        "$TEST_PROJECT/scripts/gates/gate_yaml_status.sh"

    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/archive.done" <<'EOF'
timestamp: 2026-03-06T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/lesson.done" <<'EOF'
timestamp: 2026-03-06T00:00:00
source: lesson_check
EOF
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
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
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
    [[ "$output" == *"hayate: NG ← verdict欠落または不正値"* ]]
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
    [[ "$output" == *"hayate: NG ← self_gate_check 4項目が不足またはPASS以外"* ]]
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
    [[ "$output" == *"reviewer and implementer overlap: sasuke"* ]]
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
    [[ "$output" == *"NG ← 1件のTODO/FIXMEが残存:"* ]]
}

@test "TODO in tests directory is ignored" {
    write_task "sasuke" "recon"
    write_recon_report "sasuke"
    cat > "$TEST_PROJECT/tests/unit/fake_test.sh" <<EOF
#!/usr/bin/env bash
# TODO cmd_999
exit 0
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TODO check: OK (0 remaining)"* ]]
}
