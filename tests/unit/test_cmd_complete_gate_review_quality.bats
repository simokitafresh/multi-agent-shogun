#!/usr/bin/env bats
# test_cmd_complete_gate_review_quality.bats - cmd_607 review quality gate behavior
# Optimized: review/TODO helper関数のみを直接テスト（gate全体実行を回避）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_FIELD_GET="$PROJECT_ROOT/scripts/lib/field_get.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

extract_function() {
    local name="$1"
    local start end

    start=$(awk -v name="$name" '$0 ~ "^" name "\\(\\) \\{" { print NR; exit }' "$SRC_GATE_SCRIPT")
    [ -n "$start" ] || return 1

    end=$(awk -v start="$start" '
        NR > start && /^[A-Za-z0-9_]+\(\) \{/ { print NR - 1; found = 1; exit }
        END { if (!found) print NR }
    ' "$SRC_GATE_SCRIPT")
    sed -n "${start},${end}p" "$SRC_GATE_SCRIPT"
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/review_quality.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export TASKS_DIR="$TEST_TMPDIR/queue/tasks"
    export CMD_ID="cmd_999"
    export BLOCK_REASONS=()
    export ALL_CLEAR=true

    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/lib"

    source "$SRC_FIELD_GET"

    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${CMD_ID}.yaml"
    }

    eval "$(extract_function record_block_reason)"
    eval "$(extract_function level_heading)"
    eval "$(extract_function detect_task_role)"
    eval "$(extract_function cmd_task_matches)"
    eval "$(extract_function evaluate_review_report_status)"
    eval "$(extract_function find_overlapping_workers)"
    eval "$(extract_function run_review_quality_check)"
    eval "$(extract_function run_todo_fixme_residual_check)"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_task() {
    local ninja="$1"
    local task_type="$2"
    cat > "$TASKS_DIR/${ninja}.yaml" <<EOF
task:
  parent_cmd: $CMD_ID
  task_type: $task_type
  task_id: subtask_test_${task_type}
EOF
}

write_impl_report() {
    local ninja="$1"
    local worker_id="$2"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $worker_id
task_id: subtask_test_impl
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
EOF
}

write_review_report() {
    local ninja="$1"
    local worker_id="$2"
    local verdict_block="$3"
    local self_gate_block="$4"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $worker_id
task_id: subtask_test_review
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
${verdict_block}
${self_gate_block}
EOF
}

write_recon_report() {
    local ninja="$1"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test_recon
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
EOF
}

run_review_quality_with_state() {
    run_review_quality_check
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

run_todo_check_with_state() {
    run_todo_fixme_residual_check "$CMD_ID"
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
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

    run run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review quality check:"* ]]
    [[ "$output" == *"[CRITICAL] hayate: NG ← verdict欠落または不正値"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=review report missing verdict field"* ]]
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

    run run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] hayate: NG ← self_gate_check 4項目が不足またはPASS以外"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=review report self_gate_check incomplete or not all PASS"* ]]
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

    run run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] NG ← reviewer and implementer overlap: sasuke"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=reviewer is same as implementer"* ]]
}

@test "cmd without review report skips new review checks" {
    write_task "sasuke" "recon"
    write_recon_report "sasuke"

    run run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"Review quality check:"* ]]
    [[ "$output" == *"SKIP (no review reports for this cmd)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "TODO in non-test files blocks gate" {
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/sample.sh" <<EOF
#!/usr/bin/env bash
# TODO cmd_999
exit 0
EOF

    run run_todo_check_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"TODO/FIXME residual check:"* ]]
    [[ "$output" == *"[CRITICAL] NG ← 1件のTODO/FIXMEが残存:"* ]]
    [[ "$output" == *"scripts/sample.sh:2:# TODO cmd_999"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
    [[ "$output" == *"BLOCK_REASONS=todo/fixme residual found"* ]]
}
