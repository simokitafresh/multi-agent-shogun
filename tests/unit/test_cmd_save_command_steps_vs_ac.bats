#!/usr/bin/env bats
# test_cmd_save_command_steps_vs_ac.bats — cmd_2212: command欄ステップ数 vs AC数WARNの回帰

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
    local acceptance_criteria_block="$1"
    local command_block="$2"

    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_steps:
    id: cmd_steps
    title: "infra — command step vs AC regression"
    purpose: "command欄ステップ数警告が acceptance_criteria の実項目数だけを比較することを確認する"
    project: infra
    task_type: impl
    command: |
${command_block}
${acceptance_criteria_block}
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "acceptance_criteria項目数だけを数える"
      q3_next_quality: "番号付きcommandとACの対応関係を誤判定しない"
      q5_verified_source: "code_reading + isolated_test"
      q8_why_what: "WHY: 殿指摘「AC数を正しく数えよ」 → WHAT: command欄5手順とAC件数の比較回帰を固定する。正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_command_steps_vs_ac.bats の検証範囲のみ使用"
      q11_not_already_done: "未達成。command_steps_over_acのstring-list回帰テストは未追加"
    assumptions:
      - claim: "Check 22 は scripts/cmd_save.sh の command と acceptance_criteria を比較する"
        source: "scripts/cmd_save.sh code_reading"
        trust: "verified"
YAML
}

run_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_LESSONS" \
        bash "$SAVE_SCRIPT" cmd_steps
}

@test "AC2: AC5個+番号付きcommand5項目ならcommand_steps_over_ac WARNは出ない" {
    write_cmd_queue \
"    acceptance_criteria:
      - 'AC1: step1を実装する'
      - 'AC2: step2を実装する'
      - 'AC3: step3を実装する'
      - 'AC4: step4を実装する'
      - 'AC5: step5を実装する'" \
"      1. step1
      2. step2
      3. step3
      4. step4
      5. step5"

    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"command欄に5ステップあるがACは"* ]]
    if [ -f "$TEST_QUALITY_LOG" ]; then
        run grep -n 'notes: "command_steps_over_ac"' "$TEST_QUALITY_LOG"
        [ "$status" -ne 0 ]
    fi
}

@test "AC3: AC0個+番号付きcommand3項目ならcommand_steps_over_ac WARNが出る" {
    write_cmd_queue \
"" \
"      1. step1
      2. step2
      3. step3"

    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"WARN: command欄に3ステップあるがACは0個"* ]]

    run grep -n 'notes: "command_steps_over_ac"' "$TEST_QUALITY_LOG"
    [ "$status" -eq 0 ]
}
