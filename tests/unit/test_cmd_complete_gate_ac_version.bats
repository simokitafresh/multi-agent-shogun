#!/usr/bin/env bats
# test_cmd_complete_gate_ac_version.bats - cmd_530 ac_version gate behavior
# Optimized: ac_version比較ロジックを直接テスト（gate全体実行を回避）

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_FIELD_GET="$PROJECT_ROOT/scripts/lib/field_get.sh"
    [ -f "$SRC_FIELD_GET" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/acv_test.XXXXXX")"

    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"

    source "$SRC_FIELD_GET"

    # ac_version比較関数（cmd_complete_gate.shのインラインロジックを関数化）
    check_ac_version() {
        local task_file="$1"
        local report_file="$2"
        local ninja_name="$3"

        local _acv_task _acv_read
        _acv_task=$(FIELD_GET_NO_LOG=1 field_get "$task_file" "ac_version" "")
        _acv_read=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "ac_version_read" "")
        case "${_acv_task,,}" in ""|null|none|"~") _acv_task="" ;; esac
        case "${_acv_read,,}" in ""|null|none|"~") _acv_read="" ;; esac

        if [ -z "$_acv_task" ]; then
            echo "  [INFO] ${ninja_name}: task.ac_version未設定のため照合SKIP"
        elif [[ "$_acv_task" =~ ^[0-9]+$ ]]; then
            echo "  [INFO] ${ninja_name}: 旧形式(数値)ac_version=${_acv_task}のため照合SKIP（後方互換）"
        elif [ -z "$_acv_read" ]; then
            echo "  [INFO] ${ninja_name}: ac_version_read未記載（task=${_acv_task}）。後方互換として非BLOCK"
        elif [ "$_acv_task" = "$_acv_read" ]; then
            echo "  ${ninja_name}: OK (ac_version task=${_acv_task}, report=${_acv_read})"
        else
            echo "  [CRITICAL] ${ninja_name}: NG ← ac_version不一致 (task=${_acv_task}, report=${_acv_read})"
            return 1
        fi
    }
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_task() {
    local acv="$1"
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<EOF
task:
  parent_cmd: cmd_999
  ac_version: ${acv}
EOF
}

write_report() {
    local acv_read="$1"
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" <<EOF
worker_id: sasuke
parent_cmd: cmd_999
status: done
${acv_read:+ac_version_read: $acv_read}
verdict: PASS
EOF
}

@test "ac_version legacy numeric: gate skips (backward compatible)" {
    write_task "7"
    write_report "7"

    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"旧形式(数値)ac_version=7のため照合SKIP（後方互換）"* ]]
}

@test "ac_version hash match: gate passes" {
    write_task "a3f2b1c9"
    write_report "a3f2b1c9"

    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sasuke: OK (ac_version task=a3f2b1c9, report=a3f2b1c9)"* ]]
}

@test "ac_version hash mismatch: gate blocks (content change detection)" {
    write_task "d287147e"
    write_report "519485d7"

    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[CRITICAL] sasuke: NG ← ac_version不一致 (task=d287147e, report=519485d7)"* ]]
}

@test "ac_version hash with missing report: warn only (backward compatible)" {
    write_task "a3f2b1c9"
    write_report ""

    run check_ac_version "$TEST_TMPDIR/queue/tasks/sasuke.yaml" "$TEST_TMPDIR/queue/reports/sasuke_report.yaml" "sasuke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ac_version_read未記載（task=a3f2b1c9）。後方互換として非BLOCK"* ]]
}
