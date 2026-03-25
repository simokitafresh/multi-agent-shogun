#!/usr/bin/env bats
# test_report_field_set_validation.bats
# Purpose: report_field_set.sh の lessons_useful 型バリデーションテスト
# Origin: cmd_cycle_001 — dict/string形式BLOCK, list形式PASS

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/report_field_set.sh"
    [ -f "$SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rfs_val.XXXXXX")"
    export TEST_REPORT="$TEST_TMPDIR/report.yaml"
    cat > "$TEST_REPORT" <<'EOF'
worker_id: hayate
parent_cmd: cmd_test
ac_version_read: abc12345
EOF
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "lessons_useful: dict形式入力はexit 1" {
    run bash -c "echo '{0: {id: L001, useful: true}, 1: {id: L002, useful: false}}' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 1 ]
}

@test "lessons_useful: string形式入力はexit 1" {
    run bash -c "bash '$SCRIPT' '$TEST_REPORT' lessons_useful 'L001をreviewで使用した' 2>&1"
    [ "$status" -eq 1 ]
}

@test "lessons_useful: 正しいlist形式入力はexit 0" {
    run bash -c "echo '- {id: L074, useful: true, reason: テストで使用}' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 0 ]
}

@test "lessons_useful: エラーメッセージにCorrect/Wrong例が表示される" {
    run bash -c "echo '{0: {id: L001}}' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Correct:"* ]]
    [[ "$output" == *"Wrong:"* ]]
}

@test "lessons_useful: 空list入力はexit 0" {
    run bash -c "echo '[]' | bash '$SCRIPT' '$TEST_REPORT' lessons_useful - 2>&1"
    [ "$status" -eq 0 ]
}
