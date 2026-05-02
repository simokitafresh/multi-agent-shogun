#!/usr/bin/env bats
# test_cmd_save_prev_cmd_lesson_warn.bats — cmd_2206/cmd_2456: 前cmd BLOCK後の将軍教訓未記録BLOCK
# AC1: 前cmd BLOCK回数>0なら lessons_shogun.yaml の source_cmd=前cmd を確認
# AC2: 教訓未記録なら BLOCK する
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
    local prev_cmd_id="${1:-cmd_prev}"
    local environment_change="${2:-}"
    local environment_change_yaml=""
    if [[ -n "$environment_change" ]]; then
        environment_change_yaml="    environment_change: \"$environment_change\""
    fi
    cat > "$TEST_QUEUE" <<'YAML'
commands:
YAML
    cat >> "$TEST_QUEUE" <<YAML
  ${prev_cmd_id}:
    id: ${prev_cmd_id}
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
${environment_change_yaml}
    assumptions:
      - claim: "2026-04-24時点で前cmd BLOCK回数と将軍教訓の source_cmd を照合する"
        source: "tests/unit/test_cmd_save_prev_cmd_lesson_warn.bats"
        trust: "verified"
YAML
    printf '%s\n' "$prev_cmd_id" > "$TEST_LAST_CMD"
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

write_quality_log_with_current_blocks() {
    local count="${1:-2}"
    {
        echo "entries:"
        i=1
        while [ "$i" -le "$count" ]; do
            cat <<YAML
  - cmd_id: cmd_curr
    gate_result: BLOCK
    source: cmd_save
    notes: "current_missing_field_$i"
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

write_quality_log_with_prior_warn() {
    local source_cmd="${1:-cmd_prev}"
    cat > "$TEST_QUALITY_LOG" <<YAML
entries:
  - cmd_id: "cmd_prev2"
    gate_result: BLOCK
    source: cmd_save
    notes: "missing_field_1"
  - cmd_id: "cmd_hist"
    gate_result: "WARN"
    source: "cmd_save_warn"
    notes: "missing_prev_cmd_lesson|source_cmd=${source_cmd}|check=warn_missing_prev_cmd_lesson|前${source_cmd}で2回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ"
YAML
}

run_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_LESSONS" \
        CMD_SAVE_LOCK_FILE="$TEST_TMPDIR/shogun_to_karo.lock" \
        bash "$SAVE_SCRIPT" cmd_curr
}

@test "AC2: 前cmd BLOCKあり + 教訓未記録 → 即BLOCK" {
    write_cmd_queue
    write_quality_log_with_prev_blocks 2
    write_lessons_file "cmd_other"

    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: 前cmd_prevで2回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ"* ]]
    [[ "$output" == *"保存確認NG"* ]]

    run grep -n 'notes: "前cmd_prevで2回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ' "$TEST_QUALITY_LOG"
    [ "$status" -eq 0 ]
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

@test "AC3-3: source_cmdが既に解消済みの過去WARNは累計昇格へ数えない" {
    write_cmd_queue "cmd_prev2" "type=gate; file=scripts/cmd_save.sh; pattern=warn_missing_prev_cmd_lesson"
    write_quality_log_with_prior_warn "cmd_prev"
    write_lessons_file "cmd_prev"

    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: 前cmd_prev2で1回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ"* ]]
    [[ "$output" != *"WARN累計昇格"* ]]
}

@test "AC1: CLEAR時に現cmd BLOCK履歴あり + 教訓未記録 → REMIND表示して通過" {
    write_cmd_queue "cmd_prev" "type=gate; file=scripts/cmd_save.sh; pattern=remind_missing_current_cmd_lesson_after_clear"
    printf '%s\n' "cmd_curr" > "$TEST_LAST_CMD"
    write_quality_log_with_current_blocks 2
    write_lessons_file "cmd_other"

    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_curr"* ]]
    [[ "$output" == *"REMIND: cmd_currで2回BLOCKされたが教訓未記録。lesson_write_shogun.shで記録せよ"* ]]
}

@test "AC2: CLEAR時に現cmd BLOCK履歴あり + 教訓記録済み → REMINDなし" {
    write_cmd_queue "cmd_prev" "type=gate; file=scripts/cmd_save.sh; pattern=remind_missing_current_cmd_lesson_after_clear"
    printf '%s\n' "cmd_curr" > "$TEST_LAST_CMD"
    write_quality_log_with_current_blocks 1
    write_lessons_file "cmd_curr"

    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_curr"* ]]
    [[ "$output" != *"REMIND:"* ]]
    [[ "$output" != *"教訓未記録"* ]]
}
