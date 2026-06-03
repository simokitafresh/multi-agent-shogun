#!/usr/bin/env bats
# test_cmd_save_command_steps_vs_ac.bats — cmd_2212: command欄ステップ数 vs AC数WARNの回帰

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^extract_acceptance_criteria_block()/,/^}/p' "$SAVE_SCRIPT")"
    eval "$(sed -n '/^count_acceptance_criteria_items()/,/^}/p' "$SAVE_SCRIPT")"
    eval "check_command_steps_vs_ac() {
$(sed -n '/^# --- Check 22: command欄ステップ数 vs AC数/,/^# --- Check 22: ACにpush要求/{/^# --- Check 22: ACにpush要求/d;p}' "$SAVE_SCRIPT")
}"

    record_warn_reason() {
        local reason="${1:-}"
        WARN_COUNT=$((WARN_COUNT + 1))
        WARN_REASONS+=("$reason")
        printf 'notes: "%s"\n' "$reason" >> "$TEST_QUALITY_LOG"
    }

    export -f extract_acceptance_criteria_block count_acceptance_criteria_items check_command_steps_vs_ac record_warn_reason
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_CMD_BLOCK_NC=""
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export CMD_BLOCK_NC=""
    export WARN_COUNT=0
    declare -ga WARN_REASONS=()
    : > "$TEST_QUALITY_LOG"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_cmd_queue() {
    local acceptance_criteria_block="$1"
    local command_block="$2"

    TEST_CMD_BLOCK_NC="$(cat <<YAML
  cmd_steps:
    id: cmd_steps
    title: "infra — command step vs AC regression"
    purpose: "command欄ステップ数警告が acceptance_criteria の実項目数だけを比較することを確認する"
    project: infra
    depends_on: none
    origin: "[[cmd_2902]] [[command_steps_over_ac]]"
    task_type: impl
    command: |
${command_block}
${acceptance_criteria_block}
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "acceptance_criteria項目数だけを数える"
      q3_next_quality: "番号付きcommandとACの対応関係を誤判定しない"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — command欄とAC件数の対応確認であり表面的対処ではない"
      q7_definition_verified: "yes — AC件数はacceptance_criteria実項目数のみを数える"
      q8_why_what: "WHY: 殿指摘「AC数を正しく数えよ」 → WHAT: command欄5手順とAC件数の比較回帰を固定する → WHEN: command手順数とAC件数の警告を検証する時 → WHERE: tests/unit/test_cmd_save_command_steps_vs_ac.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: acceptance_criteria実項目数を基準に比較する回帰テストで固定する。複利: 正の複利"
      q_ambiguity: "none"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_command_steps_vs_ac.bats の検証範囲のみ使用"
      q11_not_already_done: "未達成。rg 'command_steps_over_ac' tests/unit/ で既存テストを確認し、string-list回帰テストは未追加と確認"
    assumptions:
      - claim: "2026-04-24時点で Check 22 は scripts/cmd_save.sh の command と acceptance_criteria を比較する"
        source: "command_steps_over_ac logic reviewed"
        trust: "verified"
YAML
)"
    cat > "$TEST_QUEUE" <<YAML
commands:
$TEST_CMD_BLOCK_NC
YAML
}

run_command_steps_check() {
    CMD_BLOCK_NC="$TEST_CMD_BLOCK_NC"
    run check_command_steps_vs_ac
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

    run_command_steps_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
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

    run_command_steps_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: command欄に3ステップあるがACは0個"* ]]

    run grep -n 'command_steps_over_ac' "$TEST_QUALITY_LOG"
    [ "$status" -eq 0 ]
}

@test "AC4: AC1形式3個+番号付きcommand3項目ならcommand_steps_over_ac WARNは出ない" {
    write_cmd_queue \
"    acceptance_criteria:
      AC1:
        description: \"step1を実装する\"
      AC2:
        description: \"step2を検証する\"
      AC3:
        description: \"step3を報告する\"" \
"      1. step1
      2. step2
      3. step3"

    run_command_steps_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"command欄に3ステップあるがACは0個"* ]]
    [[ "$output" != *"command_steps_over_ac"* ]]
}

@test "AC5: command本文後のacceptance_criteria内番号をcommandステップに混入しない" {
    write_cmd_queue \
"    acceptance_criteria:
      AC1:
        description: \"確認1: 実装結果が存在する\"
      AC2:
        description: \"確認2: 関連テストがPASSする\"" \
"      1. implementation
      2. verification"

    run_command_steps_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"command_steps_over_ac"* ]]
}

@test "AC6: command内の下位番号付き箇条書きはトップレベルステップに混入しない" {
    write_cmd_queue \
"    acceptance_criteria:
      - 'AC1: 偵察結果が報告されている'
      - 'AC2: 関連テストがPASSする'" \
"      1. 偵察する
        1. BE観点を確認
        2. FE観点を確認
        3. インフラ観点を確認
      2. 報告する"

    run_command_steps_check
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"command_steps_over_ac"* ]]
}
