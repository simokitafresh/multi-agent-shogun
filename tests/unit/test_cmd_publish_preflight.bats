#!/usr/bin/env bats
# test_cmd_publish_preflight.bats — cmd_publish.sh pre-flight checks

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PUBLISH_SCRIPT="$PROJECT_ROOT/scripts/cmd_publish.sh"
    [ -f "$PUBLISH_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_LAST_CMD="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export TEST_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    export TEST_ACK="$TEST_TMPDIR/shogun_lesson_ack.yaml"
    export TEST_CMD_SAVE="$TEST_TMPDIR/cmd_save_stub.sh"
    export TEST_CMD_DELEGATE="$TEST_TMPDIR/cmd_delegate_stub.sh"
    cat > "$TEST_CMD_SAVE" <<'SH'
#!/usr/bin/env bash
echo "stub cmd_save $1"
exit 0
SH
    chmod +x "$TEST_CMD_SAVE"
    cat > "$TEST_CMD_DELEGATE" <<'SH'
#!/usr/bin/env bash
echo "stub cmd_delegate $1 $2"
exit 0
SH
    chmod +x "$TEST_CMD_DELEGATE"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_queue() {
    local status="${1:-draft}"
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_curr:
    id: cmd_curr
    status: ${status}
YAML
}

write_lessons() {
    local count="${1:-1}"
    echo "lessons:" > "$TEST_LESSONS"
    local i=1
    while [ "$i" -le "$count" ]; do
        printf -- '- id: LS%03d\n  title: "lesson %d"\n  detail: "detail %d"\n  source_cmd: cmd_other_%d\n' "$i" "$i" "$i" "$i" >> "$TEST_LESSONS"
        i=$((i + 1))
    done
}

write_quality_log_for_prev_block() {
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: "cmd_prev"
    gate_result: "BLOCK"
    source: "cmd_save"
    notes: missing_q11
YAML
}

run_publish() {
    run env \
        CMD_PUBLISH_QUEUE_FILE="$TEST_QUEUE" \
        CMD_PUBLISH_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_PUBLISH_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_PUBLISH_SHOGUN_LESSONS_FILE="$TEST_LESSONS" \
        CMD_PUBLISH_SHOGUN_LESSON_ACK_FILE="$TEST_ACK" \
        CMD_PUBLISH_SHOGUN_LESSON_LIMIT=35 \
        CMD_PUBLISH_CMD_SAVE_SCRIPT="$TEST_CMD_SAVE" \
        CMD_PUBLISH_CMD_DELEGATE_SCRIPT="$TEST_CMD_DELEGATE" \
        bash "$PUBLISH_SCRIPT" cmd_curr "cmd_currを書いた。配備せよ。"
}

@test "AC1: 教訓件数が上限-2以上ならcmd_save前にBLOCKする" {
    write_queue draft
    write_lessons 33
    : > "$TEST_QUALITY_LOG"

    run_publish
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"cmd_publish pre-flight"* ]]
    [[ "$output" == *"BLOCK: lessons_shogun.yaml が 33件"* ]]
    [[ "$output" == *"空きを2件以上確保"* ]]
    [[ "$output" != *"stub cmd_save"* ]]
}

@test "AC2: 前cmd BLOCK履歴あり + 教訓未記録なら具体的なlesson_write_shogun.sh例を表示する" {
    write_queue draft
    write_lessons 1
    write_quality_log_for_prev_block
    printf '%s\n' cmd_prev > "$TEST_LAST_CMD"

    run_publish
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: 前cmd_prevで1回BLOCKされたが教訓未記録"* ]]
    [[ "$output" == *'bash scripts/lesson_write_shogun.sh "cmd_prevのBLOCK教訓"'* ]]
    [[ "$output" == *"bash scripts/shogun_lesson_ack.sh cmd_prev LS-A05"* ]]
    [[ "$output" != *"stub cmd_save"* ]]
}

@test "AC3: pre-flight PASS時のみcmd_save gate検証に進む" {
    write_queue draft
    write_lessons 31
    write_quality_log_for_prev_block
    printf '%s\n' cmd_prev > "$TEST_LAST_CMD"
    cat >> "$TEST_LESSONS" <<'YAML'
- id: LS999
  title: "recorded"
  detail: "cmd_prev recorded"
  source_cmd: cmd_prev
YAML

    run_publish
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_publish pre-flight"* ]]
    [[ "$output" == *"cmd_save.sh gate検証"* ]]
    [[ "$output" == *"stub cmd_save cmd_curr"* ]]
    [[ "$output" == *"cmd_delegate.sh 委任"* ]]
}

@test "AC3c: ack記録済みなら前cmd BLOCK履歴があってもpre-flight PASSする" {
    write_queue draft
    write_lessons 1
    write_quality_log_for_prev_block
    printf '%s\n' cmd_prev > "$TEST_LAST_CMD"
    cat > "$TEST_ACK" <<'YAML'
acks:
- cmd_id: "cmd_prev"
  lesson_id: "LS-A05"
  block_count: 1
  timestamp: "2026-05-14T00:00:00Z"
YAML

    run_publish
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_save.sh gate検証"* ]]
    [[ "$output" == *"stub cmd_save cmd_curr"* ]]
    [[ "$output" != *"教訓未記録"* ]]
}

@test "AC3b: 教訓0件でもcount出力が単一整数になりpre-flight PASSする" {
    write_queue draft
    echo "lessons:" > "$TEST_LESSONS"
    : > "$TEST_QUALITY_LOG"

    run_publish
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_save.sh gate検証"* ]]
    [[ "$output" == *"stub cmd_save cmd_curr"* ]]
    [[ "$output" == *"cmd_delegate.sh 委任"* ]]
}

@test "AC4: on_hold cmdはstatusを更新せずにcmd_save gate検証へ進む" {
    write_queue on_hold
    write_lessons 1
    : > "$TEST_QUALITY_LOG"
    cat > "$TEST_CMD_SAVE" <<'SH'
#!/usr/bin/env bash
echo "stub cmd_save $1"
grep -m1 "status:" "$TEST_QUEUE"
exit 0
SH
    chmod +x "$TEST_CMD_SAVE"

    run_publish
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: cmd_curr on_hold保持"* ]]
    [[ "$output" == *"status: on_hold"* ]]
    [[ "$output" == *"OK: cmd_curr on_hold → pending"* ]]
    [[ "$output" == *"stub cmd_delegate cmd_curr"* ]]
    grep -q "status: pending" "$TEST_QUEUE"
}

@test "AC5: on_hold cmdのcmd_save gateがBLOCKしたらstatusはon_holdのまま" {
    write_queue on_hold
    write_lessons 1
    : > "$TEST_QUALITY_LOG"
    cat > "$TEST_CMD_SAVE" <<'SH'
#!/usr/bin/env bash
echo "stub cmd_save block $1"
exit 1
SH
    chmod +x "$TEST_CMD_SAVE"

    run_publish
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"OK: cmd_curr on_hold保持"* ]]
    [[ "$output" == *"KEEP: cmd_curr status=on_hold"* ]]
    [[ "$output" == *"BLOCK: cmd_save.sh failed for cmd_curr"* ]]
    [[ "$output" != *"stub cmd_delegate"* ]]
    grep -q "status: on_hold" "$TEST_QUEUE"
}
