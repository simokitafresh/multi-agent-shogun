#!/usr/bin/env bats
# test_cmd_complete_gate.bats - cmd_543 context_update gate behavior

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
    export SRC_NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"
    [ -f "$SRC_NORMALIZE_SCRIPT" ] || return 1
}

setup() {
    cmd_gate_scaffold "cmd_gate_ctx"
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

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons: []
EOF
}

teardown() {
    cmd_gate_teardown
}

write_cmd_yaml() {
    local mode="$1"
    if [ "$mode" = "with_context" ]; then
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "context update gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
    context_update:
      - context/infrastructure.md
EOF
    else
        cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<EOF
commands:
  - id: $TEST_CMD_ID
    purpose: "context update gate test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF
    fi
}

write_context_file() {
    local last_updated_date="$1"
    cat > "$TEST_PROJECT/context/infrastructure.md" <<EOF
# Infra
<!-- last_updated: ${last_updated_date} cmd_000 test -->
EOF
}

write_report() {
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

@test "context_update present + stale last_updated: gate blocks" {
    write_cmd_yaml "with_context"
    write_context_file "2025-01-01"
    write_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"context_update:context/infrastructure.md:stale"* ]]
}

@test "context_update present + fresh last_updated: gate clears" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"OK: context/infrastructure.md: last_updated=2026-03-05 (cmd=2026-03-04)"* ]]
}

@test "context_update missing: gate skips and keeps existing behavior" {
    write_cmd_yaml "without_context"
    write_context_file "2025-01-01"
    write_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"SKIP (context_update not set)"* ]]
}

@test "GATE CLEAR emits non-blocking context freshness warning when project context is stale" {
    write_cmd_yaml "without_context"
    write_context_file "2026-03-01"
    write_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context freshness nudge (GATE CLEAR):"* ]]
    [[ "$output" == *"WARN: context/infrastructure.md last_updated"* ]]
}

@test "lesson_impact rows keyed by subtask_id are updated on gate clear" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_id: subtask_test
  subtask_id: subtask_test
  assigned_to: sasuke
  task_type: review
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L100
      summary: "first lesson"
    - id: L101
      summary: "second lesson"
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
lessons_useful:
  - id: L100
    useful: true
    reason: 'test'
EOF

    cat > "$TEST_PROJECT/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	ninja	lesson_id	action	result	referenced	project	task_type	bloom_level
2026-03-04T00:00:00	subtask_test	sasuke	L100	injected	pending	pending	infra	review	routine
2026-03-04T00:00:00	subtask_test	sasuke	L101	injected	pending	pending	infra	review	routine
2026-03-04T00:00:00	cmd_999	sasuke	L101	injected	pending	pending	infra	review	routine
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tCLEAR\tyes' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL101\tinjected\tCLEAR\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'cmd_999\tsasuke\tL101\tinjected\tCLEAR\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

# ─── B層 normalize_report テスト ───

@test "B層: normalize OK when report already dict format (exit 1)" {
    write_cmd_yaml "without_context"
    write_report

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (no normalization needed)"* ]]
}

@test "B層: normalize WARN when report has list-format lesson_candidate (exit 0)" {
    write_cmd_yaml "without_context"

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
  - "some lesson in list format"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
EOF

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] sasuke:"* ]]
    [[ "$output" == *"自動修正"* ]] || [[ "$output" == *"auto-fixed"* ]]
}

@test "B層: normalize ERROR when normalize_report.sh is missing (exit 127)" {
    write_cmd_yaml "without_context"
    write_report

    rm "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: ERROR"* ]]
    [[ "$output" == *"normalize_report.sh exit="* ]]
}

# ─── cmd_1045 lessons_useful形式検証テスト ───

write_report_with_lessons_useful() {
    local lu_block="$1"
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
${lu_block}
EOF
}

@test "cmd_1045: lessons_useful string_list format blocks gate" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L028
      summary: "test lesson"
EOF

    write_report_with_lessons_useful "$(cat <<'LUEOF'
lessons_useful:
  - L028
LUEOF
)"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid_lessons_useful_format"* ]] || [[ "$output" == *"形式が不正"* ]]
}

@test "cmd_1045: lessons_useful dict_no_useful format blocks gate" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L028
      summary: "test lesson"
EOF

    write_report_with_lessons_useful "$(cat <<'LUEOF'
lessons_useful:
  - id: L028
    note: "some note without useful field"
LUEOF
)"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid_lessons_useful_format"* ]] || [[ "$output" == *"形式が不正"* ]]
}

@test "cmd_1045: lessons_useful proper format passes gate" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L028
      summary: "test lesson"
EOF

    write_report_with_lessons_useful "$(cat <<'LUEOF'
lessons_useful:
  - id: L028
    useful: true
    reason: 'helped avoid counter bug'
LUEOF
)"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (lessons_useful present and non-empty)"* ]]
}

@test "cmd_1045: lessons_useful null blocks gate (regression)" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
  report_filename: sasuke_report_${TEST_CMD_ID}.yaml
  ac_version: 2
  related_lessons:
    - id: L028
      summary: "test lesson"
EOF

    write_report_with_lessons_useful "lessons_useful: null"

    run bash "$TEST_PROJECT/scripts/cmd_complete_gate.sh" "$TEST_CMD_ID"
    [ "$status" -eq 1 ]
    [[ "$output" == *"null_lessons_useful"* ]] || [[ "$output" == *"未記入(null)"* ]]
}
