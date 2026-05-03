#!/usr/bin/env bats
# test_cmd_complete_gate_subsystems.bats
# Consolidated from:
#   test_cmd_complete_gate_review_quality (5 tests)
#   test_cmd_complete_gate_gs_bench (5 tests)
#   test_cmd_complete_gate_stk_status (3 tests)
# Total: 13 tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    export SRC_FIELD_GET="$PROJECT_ROOT/scripts/lib/field_get.sh"
    export SRC_YAML_FIELD_SET="$PROJECT_ROOT/scripts/lib/yaml_field_set.sh"

    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    [ -f "$SRC_FIELD_GET" ] || return 1
    [ -f "$SRC_YAML_FIELD_SET" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export SUBSYSTEM_HELPERS="$BATS_FILE_TMPDIR/cmd_complete_gate_subsystems_helpers.bash"
    {
        extract_function record_block_reason
        extract_function level_heading
        extract_function detect_task_role
        extract_function cmd_task_matches
        extract_function evaluate_review_report_status
        extract_function find_overlapping_workers
        extract_function run_review_quality_check
        extract_function run_todo_fixme_residual_check
        sed -n '/^check_gs_bench_gate_warn()/,/^}/p' "$SRC_GATE_SCRIPT"
        sed -n '/^update_status()/,/^}/p' "$SRC_GATE_SCRIPT"
    } > "$SUBSYSTEM_HELPERS"
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
    source "$SRC_FIELD_GET"
    source "$SRC_YAML_FIELD_SET"
    source "$SUBSYSTEM_HELPERS"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ═══════════════════════════════════════════════════════
# Section 1: Review Quality (from test_cmd_complete_gate_review_quality.bats)
# ═══════════════════════════════════════════════════════

_setup_review_quality() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/review_quality.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export TASKS_DIR="$TEST_TMPDIR/queue/tasks"
    export CMD_ID="cmd_999"
    export BLOCK_REASONS=()
    export ALL_CLEAR=true

    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/lib"

    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${CMD_ID}.yaml"
    }
}

_write_task() {
    local ninja="$1"
    local task_type="$2"
    cat > "$TASKS_DIR/${ninja}.yaml" <<EOF
task:
  parent_cmd: $CMD_ID
  task_type: $task_type
  task_id: subtask_test_${task_type}
EOF
}

_write_impl_report() {
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

_write_review_report() {
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

_write_recon_report() {
    local ninja="$1"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_${CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test_recon
parent_cmd: $CMD_ID
timestamp: "2026-03-06T00:00:00"
status: done
EOF
}

_run_review_quality_with_state() {
    run_review_quality_check
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

_run_todo_check_with_state() {
    run_todo_fixme_residual_check "$CMD_ID"
    echo "ALL_CLEAR=$ALL_CLEAR"
    echo "BLOCK_REASONS=${BLOCK_REASONS[*]}"
}

@test "review report without verdict blocks" {
    _setup_review_quality
    _write_task "sasuke" "implement"
    _write_task "hayate" "review"
    _write_impl_report "sasuke" "sasuke"
    _write_review_report "hayate" "hayate" "" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] hayate: NG ← verdict欠落または不正値"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "review report with incomplete self_gate_check blocks" {
    _setup_review_quality
    _write_task "sasuke" "implement"
    _write_task "hayate" "review"
    _write_impl_report "sasuke" "sasuke"
    _write_review_report "hayate" "hayate" "verdict: PASS" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: FAIL
  status_valid: PASS
  purpose_fit: PASS"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] hayate: NG ← self_gate_check 4項目が不足またはPASS以外"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "same worker as implementer and reviewer blocks" {
    _setup_review_quality
    _write_task "sasuke" "implement"
    _write_task "hayate" "review"
    _write_impl_report "sasuke" "sasuke"
    _write_review_report "hayate" "sasuke" "verdict: PASS" "self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] NG ← reviewer and implementer overlap: sasuke"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

@test "cmd without review report skips new review checks" {
    _setup_review_quality
    _write_task "sasuke" "recon"
    _write_recon_report "sasuke"

    run _run_review_quality_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP (no review reports for this cmd)"* ]]
    [[ "$output" == *"ALL_CLEAR=true"* ]]
}

@test "TODO in non-test files blocks gate" {
    _setup_review_quality
    mkdir -p "$TEST_TMPDIR/scripts"
    cat > "$TEST_TMPDIR/scripts/sample.sh" <<EOF
#!/usr/bin/env bash
# TODO cmd_999
exit 0
EOF

    run _run_todo_check_with_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"[CRITICAL] NG ← 1件のTODO/FIXMEが残存:"* ]]
    [[ "$output" == *"ALL_CLEAR=false"* ]]
}

# ═══════════════════════════════════════════════════════
# Section 2: GS Bench Gate (from test_cmd_complete_gate_gs_bench.bats)
# ═══════════════════════════════════════════════════════

_setup_gs_bench() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gs_bench.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/queue/reports" "$TEST_PROJECT/config"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
  - id: dm-signal
    path: $TEST_PROJECT
EOF

    level_heading() { echo "=== $2 ==="; }
    is_cmd_task() { grep -q "parent_cmd: ${TEST_CMD_ID}" "$1" 2>/dev/null; }
    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml"
    }
}

_write_gs_task() {
    local ninja="${1:-sasuke}"
    cat > "$TASKS_DIR/${ninja}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
EOF
}

_write_report_with_run077() {
    local ninja="${1:-sasuke}"
    local py_file="${2:-run_077_nukimi.py}"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
status: completed
verdict: PASS
files_modified:
  - scripts/analysis/grid_search/${py_file}
EOF
}

_write_report_without_run077() {
    local ninja="${1:-sasuke}"
    cat > "$TEST_PROJECT/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml" <<EOF
worker_id: $ninja
task_id: subtask_test
parent_cmd: $TEST_CMD_ID
status: completed
verdict: PASS
files_modified:
  - scripts/lib/field_get.sh
EOF
}

@test "AC2: files_modifiedにrun_077_nukimi.pyが含まれる場合WARNを出力する" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_with_run077 "sasuke" "run_077_nukimi.py"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "\[WARN\]"
    echo "$output" | grep -q "nukimi"
}

@test "WARN出力に/gs-bench-gate after --ninjutsu nukimiが含まれる" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_with_run077 "sasuke" "run_077_nukimi.py"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "/gs-bench-gate after --ninjutsu nukimi"
}

@test "files_modifiedにrun_077_*.pyが含まれない場合はSKIP" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_without_run077 "sasuke"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SKIP"
}

@test "gs_gate_after JSONが存在する場合はWARN非発火" {
    _setup_gs_bench
    _write_gs_task "sasuke"
    _write_report_with_run077 "sasuke" "run_077_nukimi.py"

    mkdir -p "$TEST_PROJECT/outputs/analysis"
    echo '{"ninjutsu":"nukimi"}' > "$TEST_PROJECT/outputs/analysis/gs_gate_after_nukimi.json"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "\[WARN\]"
    echo "$output" | grep -q "OK"
}

@test "タスクファイルが存在しない場合はSKIP" {
    _setup_gs_bench
    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SKIP"
}

# ═══════════════════════════════════════════════════════
# Section 3: STK Status (from test_cmd_complete_gate_stk_status.bats)
# ═══════════════════════════════════════════════════════

_setup_stk_status() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stk_status.XXXXXX")"
    export SCRIPT_DIR="$TEST_TMPDIR"
    export YAML_FILE="$TEST_TMPDIR/queue/shogun_to_karo.yaml"

    mkdir -p "$TEST_TMPDIR/queue" "$TEST_TMPDIR/scripts/lib"

}

@test "GATE CLEAR sets STK status to done (mapping format)" {
    _setup_stk_status
    cat > "$YAML_FILE" <<EOF
commands:
  cmd_999:
    purpose: "STK status update test"
    project: infra
    status: delegated
    timestamp: "2026-03-04T21:25:00+09:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]
    run grep "status: done" "$YAML_FILE"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR sets STK status to done (list format)" {
    _setup_stk_status
    cat > "$YAML_FILE" <<EOF
commands:
  - id: cmd_999
    purpose: "STK status update test"
    project: infra
    status: delegated
    delegated_at: "2026-03-04T21:25:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS UPDATED"* ]]
    run grep "status: done" "$YAML_FILE"
    [ "$status" -eq 0 ]
}

@test "GATE CLEAR skips update when STK status already done" {
    _setup_stk_status
    cat > "$YAML_FILE" <<EOF
commands:
  cmd_999:
    purpose: "STK status already done test"
    project: infra
    status: done
    timestamp: "2026-03-04T21:25:00+09:00"
EOF

    run update_status "cmd_999"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STATUS ALREADY COMPLETED"* ]]
}

# ═══════════════════════════════════════════════════════
# Section 4: AC Version (from test_cmd_complete_gate_ac_version.bats)
# ═══════════════════════════════════════════════════════

_setup_ac_version() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/acv_test.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    source "$SRC_FIELD_GET"
    check_ac_version() {
        local task_file="$1" report_file="$2" ninja_name="$3"
        local _acv_task _acv_read
        _acv_task=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")
        _acv_read=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "ac_version_read" "")
        case "${_acv_task,,}" in ""|null|none|"~") _acv_task="" ;; esac
        case "${_acv_read,,}" in ""|null|none|"~") _acv_read="" ;; esac
        if [ -z "$_acv_task" ]; then echo "  [INFO] ${ninja_name}: task.ac_version未設定のため照合SKIP"
        elif [[ "$_acv_task" =~ ^[0-9]+$ ]]; then echo "  [INFO] ${ninja_name}: 旧形式(数値)ac_version=${_acv_task}のため照合SKIP（後方互換）"
        elif [ -z "$_acv_read" ]; then echo "  [INFO] ${ninja_name}: ac_version_read未記載（task=${_acv_task}）。後方互換として非BLOCK"
        elif [ "$_acv_task" = "$_acv_read" ]; then echo "  ${ninja_name}: OK (ac_version task=${_acv_task}, report=${_acv_read})"
        else echo "  [CRITICAL] ${ninja_name}: NG ← ac_version不一致 (task=${_acv_task}, report=${_acv_read})"; return 1; fi
    }
}
_write_acv_task() { cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_999
  ac_version: $1
EOF
}
_write_acv_report() { cat > "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" <<EOF
worker_id: sasuke
parent_cmd: cmd_999
status: done
${1:+ac_version_read: $1}
verdict: PASS
EOF
}

@test "ac_version legacy numeric: gate skips" {
    _setup_ac_version; _write_acv_task "7"; _write_acv_report "7"
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]; [[ "$output" == *"旧形式(数値)"* ]]
}
@test "ac_version hash match: gate passes" {
    _setup_ac_version; _write_acv_task "a3f2b1c9"; _write_acv_report "a3f2b1c9"
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]; [[ "$output" == *"OK (ac_version task=a3f2b1c9"* ]]
}
@test "ac_version hash mismatch: gate blocks" {
    _setup_ac_version; _write_acv_task "d287147e"; _write_acv_report "519485d7"
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 1 ]; [[ "$output" == *"[CRITICAL] sasuke: NG ← ac_version不一致"* ]]
}
@test "ac_version missing report: warn only" {
    _setup_ac_version; _write_acv_task "a3f2b1c9"; _write_acv_report ""
    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]; [[ "$output" == *"ac_version_read未記載"* ]]
}
