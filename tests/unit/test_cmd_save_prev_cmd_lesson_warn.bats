#!/usr/bin/env bats
# test_cmd_save_prev_cmd_lesson_warn.bats — cmd_2206: 前cmd BLOCK後の将軍教訓未記録WARN
# AC1: 前cmd BLOCK回数>0なら lessons_shogun.yaml の source_cmd=前cmd を確認
# AC2: 教訓未記録なら WARN を表示
# AC3: 教訓記録済み / BLOCKなし では何も表示しない

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_LAST_CMD="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export TEST_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    mkdir -p "$TEST_ARCHIVE_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_cmd_queue() {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_prev:
    id: cmd_prev
    title: "infra — 前cmd"
    project: infra
    command: "前cmd"
    status: delegated
  cmd_curr:
    id: cmd_curr
    title: "infra — Session State WARNテスト"
    project: infra
    command: "現cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — 前cmd教訓WARN確認であり表面的対処ではない"
      q7_definition_verified: "yes — lessons_shogun.yaml の source_cmd 一致だけを確認する"
      q8_why_what: "WHY: 殿指摘「前cmd BLOCK後の教訓記録を確認せよ」 → WHAT: Session Stateへ確認WARN追加。正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_prev_cmd_lesson_warn.bats の検証済み範囲のみ使用"
      q11_not_already_done: "未達成。grep 'warn_missing_prev_cmd_lesson' scripts/cmd_save.sh で未実装を確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "前cmd BLOCK回数と将軍教訓の source_cmd を照合する"
        source: "tests/unit/test_cmd_save_prev_cmd_lesson_warn.bats"
        trust: "verified"
YAML
    printf '%s\n' "cmd_prev" > "$TEST_LAST_CMD"
}

write_quality_log_with_prev_blocks() {
    local count="${1:-2}"
    {
        echo "entries:"
        i=1
        while [ "$i" -le "$count" ]; do
            cat <<YAML
  - cmd_id: cmd_prev
    gate_result: BLOCK
    source: cmd_save
    notes: "missing_field_$i"
YAML
            i=$((i + 1))
        done
    } > "$TEST_QUALITY_LOG"
}

write_lessons_file() {
    local source_cmd="${1:-}"
    cat > "$TEST_LESSONS" <<YAML
lessons:
- id: LS999
  title: "dummy"
  detail: "dummy"
  source_cmd: ${source_cmd:-cmd_other}
YAML
}

run_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_LESSONS" \
        bash "$SAVE_SCRIPT" cmd_curr
}

@test "AC2: 前cmd BLOCKあり + 教訓未記録 → WARN表示" {
    write_cmd_queue
    write_quality_log_with_prev_blocks 2
    write_lessons_file "cmd_other"

    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"WARN: 前cmd_prevで2回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ"* ]]
    [[ "$output" == *"保存確認NG"* ]]
}

@test "AC3-1: 前cmd BLOCKあり + 教訓記録済み → WARNなし" {
    write_cmd_queue
    write_quality_log_with_prev_blocks 3
    write_lessons_file "cmd_prev"

    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"教訓未記録"* ]]
}

@test "AC3-2: 前cmd BLOCKなし → WARNなし" {
    write_cmd_queue
    write_quality_log_with_prev_blocks 0
    write_lessons_file "cmd_other"

    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"教訓未記録"* ]]
}
