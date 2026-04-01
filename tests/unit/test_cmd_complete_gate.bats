#!/usr/bin/env bats
# test_cmd_complete_gate.bats - cmd_complete_gate.sh partial unit tests
# Optimized: gate全体実行をやめ、重い責務を関数/局所フェーズ単位で直接検証する

load '../helpers/cmd_gate_scaffold'

setup_file() {
    cmd_gate_setup_file
    export SRC_NORMALIZE_SCRIPT="$PROJECT_ROOT/scripts/lib/normalize_report.sh"
    [ -f "$SRC_NORMALIZE_SCRIPT" ] || return 1
}

setup() {
    cmd_gate_scaffold "cmd_gate_ctx"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"
    export LOG_DIR="$TEST_PROJECT/logs"
    export CMD_ID="$TEST_CMD_ID"

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

    source "$SRC_FIELD_GET_SCRIPT"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^level_heading()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^check_context_update()/,/^}/p' "$SRC_GATE_SCRIPT")"
    eval "$(sed -n '/^update_lesson_impact_tsv()/,/^}/p' "$SRC_GATE_SCRIPT")"

    ALL_CLEAR=true
    BLOCK_REASONS=()

    write_task_fixture "sasuke_report_${TEST_CMD_ID}.yaml"
}

teardown() {
    cmd_gate_teardown
}

reset_gate_state() {
    ALL_CLEAR=true
    BLOCK_REASONS=()
}

is_cmd_task() {
    local task_file="$1"
    grep -q "parent_cmd: ${TEST_CMD_ID}" "$task_file" 2>/dev/null
}

resolve_report_file() {
    local ninja_name="$1"
    local explicit_path report_parent
    local task_file="$TASKS_DIR/${ninja_name}.yaml"

    if [ -f "$task_file" ]; then
        explicit_path=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "report_filename" "")
        if [ -n "$explicit_path" ] && [ -f "$SCRIPT_DIR/queue/reports/$explicit_path" ]; then
            echo "$SCRIPT_DIR/queue/reports/$explicit_path"
            return 0
        fi
    fi

    if [ -f "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${TEST_CMD_ID}.yaml" ]; then
        echo "$SCRIPT_DIR/queue/reports/${ninja_name}_report_${TEST_CMD_ID}.yaml"
        return 0
    fi

    if [ -f "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml" ]; then
        report_parent=$(FIELD_GET_NO_LOG=1 field_get "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml" "parent_cmd" "")
        if [ "$report_parent" = "$TEST_CMD_ID" ]; then
            echo "$SCRIPT_DIR/queue/reports/${ninja_name}_report.yaml"
            return 0
        fi
    fi

    return 1
}

write_task_fixture() {
    local report_filename="${1:-sasuke_report_${TEST_CMD_ID}.yaml}"
    cat > "$TEST_PROJECT/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: review
  report_filename: $report_filename
  ac_version: 2
  related_lessons: []
EOF
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

run_context_update_check() {
    reset_gate_state
    check_context_update "$TEST_CMD_ID"
    [ "$ALL_CLEAR" = true ]
}

run_context_freshness_nudge() {
    local context_warn_lines

    echo "Context freshness nudge (GATE CLEAR):"
    if [ -f "$SCRIPT_DIR/scripts/context_freshness_check.sh" ]; then
        context_warn_lines=$(bash "$SCRIPT_DIR/scripts/context_freshness_check.sh" --cmd-warnings "$TEST_CMD_ID" 2>/dev/null || true)
        if [ -n "$context_warn_lines" ]; then
            while IFS= read -r warn_line; do
                [ -n "$warn_line" ] || continue
                echo "  ${warn_line}"
            done <<< "$context_warn_lines"
        else
            echo "  OK: no stale project context files"
        fi
    else
        echo "  [INFO] context_freshness_check.sh not found (skip)"
    fi
}

run_normalize_phase() {
    local task_file ninja_name report_file normalize_exit normalize_output

    export NORMALIZE_LOG="$SCRIPT_DIR/logs/normalize_report.log"
    echo "Normalize report candidates (B層):"
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        is_cmd_task "$task_file" || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name") || continue
        if [ -f "$report_file" ]; then
            normalize_exit=0
            normalize_output=$(bash "$SCRIPT_DIR/scripts/lib/normalize_report.sh" "$report_file" 2>&1) || normalize_exit=$?
            if [ "$normalize_exit" -eq 0 ]; then
                echo "  [INFO] ${ninja_name}: auto-fixed: ${normalize_output}"
            elif [ "$normalize_exit" -eq 1 ]; then
                echo "  ${ninja_name}: OK (no normalization needed)"
            else
                echo "  ${ninja_name}: ERROR — normalize_report.sh exit=${normalize_exit}: ${normalize_output}"
            fi
        fi
    done
}

run_report_format_validation() {
    local report_file task_file ninja_name gate_output

    REPORT_FORMAT_CHECKED=0
    REPORT_FORMAT_FAILED=0
    declare -A report_format_seen=()

    validate_report_format_file() {
        local candidate="$1"

        [ -n "$candidate" ] || return 0
        [ -f "$candidate" ] || return 0
        if [ -n "${report_format_seen["$candidate"]+x}" ]; then
            return 0
        fi

        report_format_seen["$candidate"]=1
        REPORT_FORMAT_CHECKED=$((REPORT_FORMAT_CHECKED + 1))
        "$SCRIPT_DIR/scripts/gates/gate_report_autofix.sh" "$candidate" 2>/dev/null || true
        gate_output=$("$SCRIPT_DIR/scripts/gates/gate_report_format.sh" "$candidate" 2>&1 || true)
        if echo "$gate_output" | grep -q "^FAIL"; then
            REPORT_FORMAT_FAILED=$((REPORT_FORMAT_FAILED + 1))
            echo "  [CRITICAL] $(basename "$candidate"): $gate_output"
        else
            echo "  $(basename "$candidate"): PASS"
        fi
    }

    level_heading "[L1]" "Report format validation (direct scan):"
    for task_file in "$TASKS_DIR"/*.yaml; do
        [ -f "$task_file" ] || continue
        is_cmd_task "$task_file" || continue
        ninja_name=$(basename "$task_file" .yaml)
        report_file=$(resolve_report_file "$ninja_name") || continue
        validate_report_format_file "$report_file"
    done

    for report_file in "$SCRIPT_DIR/queue/reports/"*_report_${TEST_CMD_ID}.yaml; do
        [ -f "$report_file" ] || continue
        validate_report_format_file "$report_file"
    done

    if [ "$REPORT_FORMAT_CHECKED" -eq 0 ]; then
        echo "  (no report files found for ${TEST_CMD_ID})"
    elif [ "$REPORT_FORMAT_FAILED" -eq 0 ]; then
        echo "  OK (全${REPORT_FORMAT_CHECKED}件フォーマット検証PASS)"
    fi

    [ "$REPORT_FORMAT_FAILED" -eq 0 ]
}

@test "context_update present + stale last_updated: gate blocks" {
    write_cmd_yaml "with_context"
    write_context_file "2025-01-01"
    write_report

    run run_context_update_check
    [ "$status" -eq 1 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"context_update:context/infrastructure.md:stale"* ]]
}

@test "context_update present + fresh last_updated: gate clears" {
    write_cmd_yaml "with_context"
    write_context_file "2026-03-05"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"OK: context/infrastructure.md: last_updated=2026-03-05 (cmd=2026-03-04)"* ]]
}

@test "context_update missing: gate skips and keeps existing behavior" {
    write_cmd_yaml "without_context"
    write_context_file "2025-01-01"
    write_report

    run run_context_update_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Context update check:"* ]]
    [[ "$output" == *"SKIP (context_update not set)"* ]]
}

@test "GATE CLEAR emits non-blocking context freshness warning when project context is stale" {
    write_cmd_yaml "without_context"
    write_context_file "2026-03-01"
    write_report

    run run_context_freshness_nudge
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

    run update_lesson_impact_tsv "$TEST_CMD_ID" "CLEAR"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL100\tinjected\tCLEAR\tyes' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'subtask_test\tsasuke\tL101\tinjected\tCLEAR\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]

    run grep -F $'cmd_999\tsasuke\tL101\tinjected\tCLEAR\tno' "$TEST_PROJECT/logs/lesson_impact.tsv"
    [ "$status" -eq 0 ]
}

@test "B層: normalize OK when report already dict format (exit 1)" {
    write_cmd_yaml "without_context"
    write_report

    run run_normalize_phase
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

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO] sasuke:"* ]]
    [[ "$output" == *"自動修正"* ]] || [[ "$output" == *"auto-fixed"* ]]
}

@test "B層: normalize ERROR when normalize_report.sh is missing (exit 127)" {
    write_cmd_yaml "without_context"
    write_report

    rm "$TEST_PROJECT/scripts/lib/normalize_report.sh"

    run run_normalize_phase
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: ERROR"* ]]
    [[ "$output" == *"normalize_report.sh exit=127"* ]]
}

@test "custom report_filename is included in direct report format validation" {
    write_cmd_yaml "without_context"

    cat > "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat > "$TEST_PROJECT/scripts/gates/gate_report_format.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == *"custom_gate_target.yaml" ]]; then
    echo "FAIL: custom report hit formatter"
    exit 1
fi
echo "PASS"
EOF
    chmod +x "$TEST_PROJECT/scripts/gates/gate_report_autofix.sh" "$TEST_PROJECT/scripts/gates/gate_report_format.sh"

    write_task_fixture "custom_gate_target.yaml"

    cat > "$TEST_PROJECT/queue/reports/custom_gate_target.yaml" <<EOF
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
result:
  summary: "custom report"
lesson_candidate:
  found: false
  no_lesson_reason: "test fixture"
skill_candidate:
  found: false
decision_candidate:
  found: false
lessons_useful: []
binary_checks:
  AC1:
    - check: "custom report validated"
      result: "yes"
EOF

    run run_report_format_validation
    [ "$status" -eq 1 ]
    [[ "$output" == *"custom_gate_target.yaml: FAIL: custom report hit formatter"* ]]
}
