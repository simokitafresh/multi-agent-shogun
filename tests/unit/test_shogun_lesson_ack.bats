#!/usr/bin/env bats
# test_shogun_lesson_ack.bats — shogun_lesson_ack.sh validation and append behavior

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export ACK_SCRIPT="$PROJECT_ROOT/scripts/shogun_lesson_ack.sh"
    [ -f "$ACK_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_ACK="$TEST_TMPDIR/shogun_lesson_ack.yaml"
    export TEST_ACK_LOCK="$TEST_TMPDIR/shogun_lesson_ack.lock"

    cat > "$TEST_LESSONS" <<'YAML'
lessons:
- id: LS-A05
  title: "遡及学習対応"
YAML
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: "cmd_9999"
    gate_result: "BLOCK"
    source: "cmd_save"
YAML
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

run_ack() {
    run env \
        SHOGUN_LESSON_ACK_LESSONS_FILE="$TEST_LESSONS" \
        SHOGUN_LESSON_ACK_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        SHOGUN_LESSON_ACK_FILE="$TEST_ACK" \
        SHOGUN_LESSON_ACK_LOCK_FILE="$TEST_ACK_LOCK" \
        bash "$ACK_SCRIPT" "$@"
}

@test "AC1: cmd_id + lesson_id を queue配下形式のackファイルへ追記する" {
    run_ack cmd_9999 LS-A05
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: recorded ack for cmd_9999 -> LS-A05"* ]]
    grep -q 'cmd_id: "cmd_9999"' "$TEST_ACK"
    grep -q 'lesson_id: "LS-A05"' "$TEST_ACK"
    grep -q 'block_count: 1' "$TEST_ACK"
}

@test "AC2: 存在しないlesson_idはBLOCKする" {
    run_ack cmd_9999 LS-NOTFOUND
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: lesson_id not found"* ]]
    [ ! -f "$TEST_ACK" ]
}

@test "AC2b: cmd_save BLOCK実績がないcmd_idはBLOCKする" {
    run_ack cmd_8888 LS-A05
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"has no cmd_save BLOCK entry"* ]]
    [ ! -f "$TEST_ACK" ]
}

@test "AC2c: 同一cmd_id+lesson_idの再実行は重複追記しない" {
    run_ack cmd_9999 LS-A05
    [ "$status" -eq 0 ]

    run_ack cmd_9999 LS-A05
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: ack already exists"* ]]
    [ "$(grep -c 'cmd_id: "cmd_9999"' "$TEST_ACK")" -eq 1 ]
}
