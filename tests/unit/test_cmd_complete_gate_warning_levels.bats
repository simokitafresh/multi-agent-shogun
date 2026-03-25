#!/usr/bin/env bats
# test_cmd_complete_gate_warning_levels.bats - warning level gate behavior

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
}

setup() {
    cmd_gate_scaffold "cmd_gate_warn"

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

    cat > "$TEST_PROJECT/context/infrastructure.md" <<'EOF'
# Infra
<!-- last_updated: 2026-03-10 cmd_999 test -->
EOF

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "warning level gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-10T00:00:00"
    context_update:
      - context/infrastructure.md
EOF

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF
}

teardown() {
    cmd_gate_teardown
}

write_report() {
    local result_block="$1"
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "warning level gate test"
${result_block}
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

write_report_with_deviation_count() {
    local count="$1"
    {
        cat <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "warning level gate test"
EOF
        if [ "$count" -eq 0 ]; then
            echo "  deviation: []"
        else
            echo "  deviation:"
            local i
            for i in $(seq 1 "$count"); do
                cat <<EOF
    - rule: 1
      description: "fix ${i}"
      files: ["scripts/example_${i}.sh"]
EOF
            done
        fi
        cat <<'EOF'
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF
    } > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml"
}

@test "level headings include L1 L2 L3 labels" {
    write_report ""

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L1] Gate check: $TEST_CMD_ID"* ]]
    [[ "$output" == *"[L2] Deviation count check:"* ]]
    [[ "$output" == *"[L3] Context update check:"* ]]
}

@test "deviation missing and non-list skip for backward compatibility" {
    write_report ""
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: SKIP (result.deviation not present)"* ]]

    write_report "  deviation: invalid"
    rm -f "$TEST_PROJECT/logs/gate_metrics.log"
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: SKIP (result.deviation empty (count 0))"* ]]
}

@test "deviation threshold uses 3 as OK boundary and 4 as warning threshold" {
    write_report_with_deviation_count 3
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (deviation count 3 <= 3)"* ]]

    write_report_with_deviation_count 4
    rm -f "$TEST_PROJECT/logs/gate_metrics.log"
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] sasuke: deviation count 4 >= 4: 逸脱管理ルール(3回超過)に抵触"* ]]
}

@test "analysis_paralysis_triggered true emits warning" {
    write_report "  analysis_paralysis_triggered: true"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L2] Analysis paralysis check:"* ]]
    [[ "$output" == *"[INFO] sasuke: analysis paralysis was triggered during this task"* ]]
}

@test "analysis_paralysis_triggered missing is SKIP" {
    write_report ""
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: SKIP (analysis_paralysis_triggered not present)"* ]]
}

@test "implement report missing how_it_works emits warning only" {
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/review_gate.done" <<'EOF'
timestamp: 2026-03-10T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: implement
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF
    write_report ""

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[L2] Implementation walkthrough check:"* ]]
    [[ "$output" == *"[INFO] sasuke: how_it_works missing or empty (implement report)"* ]]
}

@test "implement report with how_it_works passes walkthrough check" {
    cat > "$TEST_PROJECT/queue/gates/$TEST_CMD_ID/review_gate.done" <<'EOF'
timestamp: 2026-03-10T00:00:00
source: test
EOF
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: implement
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 1
  related_lessons: []
EOF
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "warning level gate test"
how_it_works: |
  detect_task_role() で implement を判定する。
  how_it_works があれば WARN せず通す。
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (how_it_works present)"* ]]
}

@test "test_skip_count > 0 triggers BLOCK" {
    write_report "test_skip_count: 3"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [[ "$output" == *"[L2] Test skip count check:"* ]]
    [[ "$output" == *"[CRITICAL] sasuke: テスト未完了: SKIP 3件。SKIP=FAILルール"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
    [ "$status" -eq 1 ]
}

@test "test_skip_count = 0 passes OK" {
    write_report "test_skip_count: 0"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [[ "$output" == *"[L2] Test skip count check:"* ]]
    [[ "$output" == *"sasuke: OK (test_skip_count 0)"* ]]
}

@test "test_results.skipped > 0 triggers BLOCK via fallback" {
    cat > "$TEST_PROJECT/queue/reports/sasuke_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: sasuke
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
timestamp: "2026-03-10T00:00:00"
status: done
ac_version_read: 1
verdict: PASS
purpose_validation:
  fit: true
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
result:
  summary: "test skip via test_results"
test_results:
  passed: 10
  failed: 0
  skipped: 2
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [[ "$output" == *"[CRITICAL] sasuke: テスト未完了: SKIP 2件。SKIP=FAILルール"* ]]
    [[ "$output" == *"GATE BLOCK"* ]]
    [ "$status" -eq 1 ]
}

@test "test_results missing emits WARN not BLOCK" {
    write_report ""

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [[ "$output" == *"[L2] Test skip count check:"* ]]
    [[ "$output" == *"[INFO] sasuke: test_results not present"* ]]
    # Should NOT block
    [[ "$output" != *"テスト未完了"* ]]
}

@test "GATE CLEAR uses ntfy_batch when available and falls back otherwise" {
    local notify_log="$TEST_TMPDIR/notify.log"

    cat > "$TEST_PROJECT/scripts/ntfy_cmd.sh" <<EOF
#!/usr/bin/env bash
echo "ntfy_cmd:\$1:\$2" >> "$notify_log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/ntfy_cmd.sh"
    write_report ""

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    grep -q "ntfy_cmd:$TEST_CMD_ID:GATE CLEAR — $TEST_CMD_ID 完了" "$notify_log"

    : > "$notify_log"
    cat > "$TEST_PROJECT/scripts/ntfy_batch.sh" <<EOF
#!/usr/bin/env bash
echo "ntfy_batch:\$1:\$2" >> "$notify_log"
exit 0
EOF
    chmod +x "$TEST_PROJECT/scripts/ntfy_batch.sh"

    rm -f "$TEST_PROJECT/logs/gate_metrics.log"
    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    grep -q "ntfy_batch:$TEST_CMD_ID:GATE CLEAR — $TEST_CMD_ID 完了" "$notify_log"
    ! grep -q "ntfy_cmd:" "$notify_log"
}
