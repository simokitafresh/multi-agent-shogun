#!/usr/bin/env bats
# test_cmd_complete_gate_gs_bench.bats
# AC2: run_077_nukimi.py変更cmdでgs-bench-gate未実行WARNが発火することを確認

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/cmd_complete_gate.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gs_bench.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export TEST_CMD_ID="cmd_999"
    export SCRIPT_DIR="$TEST_PROJECT"
    export TASKS_DIR="$TEST_PROJECT/queue/tasks"

    mkdir -p \
        "$TEST_PROJECT/queue/tasks" \
        "$TEST_PROJECT/queue/reports" \
        "$TEST_PROJECT/config"

    # config/projects.yaml（dm-signalのパスをTEST_PROJECTに向ける）
    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: infra
    path: $TEST_PROJECT
  - id: dm-signal
    path: $TEST_PROJECT
EOF

    # 関数をソース
    eval "$(sed -n '/^check_gs_bench_gate_warn()/,/^}/p' "$SRC_GATE_SCRIPT")"

    # モック関数
    level_heading() { echo "=== $2 ==="; }
    is_cmd_task() { grep -q "parent_cmd: ${TEST_CMD_ID}" "$1" 2>/dev/null; }
    resolve_report_file() {
        local ninja="$1"
        echo "$SCRIPT_DIR/queue/reports/${ninja}_report_${TEST_CMD_ID}.yaml"
    }
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_task() {
    local ninja="${1:-sasuke}"
    cat > "$TASKS_DIR/${ninja}.yaml" <<EOF
task:
  parent_cmd: $TEST_CMD_ID
  task_type: impl
EOF
}

write_report_with_run077() {
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

write_report_without_run077() {
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

# AC2: run_077_nukimi.py変更cmdでWARN発火
@test "AC2: files_modifiedにrun_077_nukimi.pyが含まれる場合WARNを出力する" {
    write_task "sasuke"
    write_report_with_run077 "sasuke" "run_077_nukimi.py"
    # gs_gate_after_nukimi.jsonは存在しない状態でテスト

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "\[WARN\]"
    echo "$output" | grep -q "run_077_nukimi.py"
    echo "$output" | grep -q "nukimi"
}

# WARNにgs-bench-gate実行手順が含まれる
@test "WARN出力に/gs-bench-gate after --ninjutsu nukimiが含まれる" {
    write_task "sasuke"
    write_report_with_run077 "sasuke" "run_077_nukimi.py"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "/gs-bench-gate after --ninjutsu nukimi"
}

# run_077_*.pyが含まれない場合はSKIP
@test "files_modifiedにrun_077_*.pyが含まれない場合はSKIPを出力する" {
    write_task "sasuke"
    write_report_without_run077 "sasuke"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SKIP"
    ! echo "$output" | grep -q "\[WARN\]"
}

# gs_gate_after JSONが存在する場合はWARN非発火（OKを出力）
@test "gs_gate_after JSONが存在する場合はWARNを出力しない" {
    write_task "sasuke"
    write_report_with_run077 "sasuke" "run_077_nukimi.py"

    # gs_gate_after_nukimi.jsonを作成（ベンチマーク実行済みを模擬）
    mkdir -p "$TEST_PROJECT/outputs/analysis"
    echo '{"ninjutsu":"nukimi","results":{"serial":{"ms_per_pattern":0.31}}}' \
        > "$TEST_PROJECT/outputs/analysis/gs_gate_after_nukimi.json"

    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "\[WARN\]"
    echo "$output" | grep -q "OK"
}

# タスクファイルが存在しない場合はSKIP
@test "タスクファイルが存在しない場合はSKIPを出力する" {
    # TASKS_DIRにタスクなし
    run check_gs_bench_gate_warn
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SKIP"
}
