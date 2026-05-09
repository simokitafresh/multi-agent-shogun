#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_REPORT_MERGE="$PROJECT_ROOT/scripts/report_merge.sh"

    [ -f "$SRC_REPORT_MERGE" ] || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TEST_TMPDIR/report_merge.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports"
    cp "$SRC_REPORT_MERGE" "$TEST_ROOT/scripts/report_merge.sh"
    chmod +x "$TEST_ROOT/scripts/report_merge.sh"
}

write_task() {
    local ninja="$1"
    local status="$2"
    local task_type="${3:-recon}"
    cat > "$TEST_ROOT/queue/tasks/${ninja}.yaml" <<EOF
task:
  assigned_to: ${ninja}
  parent_cmd: cmd_test
  task_type: ${task_type}
  task_id: cmd_test_${ninja}_${task_type}
  status: ${status}
EOF
}

write_report() {
    local ninja="$1"
    local legacy_only="${2:-0}"
    local path="$TEST_ROOT/queue/reports/${ninja}_report_cmd_test.yaml"

    if [ "$legacy_only" = "1" ]; then
        path="$TEST_ROOT/queue/reports/${ninja}_report.yaml"
    fi

    cat > "$path" <<EOF
worker_id: ${ninja}
task_id: cmd_test_${ninja}_recon
parent_cmd: cmd_test
timestamp: "2026-04-18T21:20:00"
status: done
EOF
}

@test "READY: all recon tasks done writes pass and done flags" {
    write_task "sasuke" "done"
    write_task "saizo" "done"
    write_report "sasuke"
    write_report "saizo"

    run bash "$TEST_ROOT/scripts/report_merge.sh" cmd_test
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: done"* ]]
    [[ "$output" == *"saizo: done"* ]]
    [[ "$output" == *"READY: 並行偵察2件完了。統合分析(Step 1.5)を実施せよ"* ]]

    [ -f "$TEST_ROOT/queue/gates/cmd_test_report_merge.pass" ]
    [ -f "$TEST_ROOT/queue/gates/cmd_test/report_merge.done" ]
    run grep -F "result: READY" "$TEST_ROOT/queue/gates/cmd_test/report_merge.done"
    [ "$status" -eq 0 ]
}

@test "WAITING: pending ninja name is aggregated and legacy report path is shown" {
    write_task "sasuke" "done"
    write_task "saizo" "in_progress"
    write_report "sasuke"
    write_report "saizo" "1"

    run bash "$TEST_ROOT/scripts/report_merge.sh" cmd_test
    [ "$status" -eq 2 ]
    [[ "$output" == *"sasuke: done"* ]]
    [[ "$output" == *"saizo: in_progress ($TEST_ROOT/queue/reports/saizo_report.yaml)"* ]]
    [[ "$output" == *"WAITING: 偵察1/2件完了。saizoの報告待ち"* ]]

    [ ! -e "$TEST_ROOT/queue/gates/cmd_test_report_merge.pass" ]
    [ ! -e "$TEST_ROOT/queue/gates/cmd_test/report_merge.done" ]
}

@test "SKIP: no recon tasks writes skip flag" {
    write_task "sasuke" "done" "impl"

    run bash "$TEST_ROOT/scripts/report_merge.sh" cmd_test
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: cmd_testに偵察タスクなし"* ]]

    [ -f "$TEST_ROOT/queue/gates/cmd_test_report_merge.skip" ]
    [ -f "$TEST_ROOT/queue/gates/cmd_test/report_merge.done" ]
    run grep -F "result: SKIP" "$TEST_ROOT/queue/gates/cmd_test/report_merge.done"
    [ "$status" -eq 0 ]
}

@test "relative script path resolves project root from current working directory" {
    write_task "sasuke" "done"
    write_report "sasuke"

    (
        cd "$TEST_ROOT"
        run bash scripts/report_merge.sh cmd_test
        [ "$status" -eq 0 ]
        [[ "$output" == *"sasuke: done"* ]]
        [[ "$output" == *"READY: 並行偵察1件完了。統合分析(Step 1.5)を実施せよ"* ]]
    )

    [ -f "$TEST_ROOT/queue/gates/cmd_test_report_merge.pass" ]
    [ -f "$TEST_ROOT/queue/gates/cmd_test/report_merge.done" ]
}
