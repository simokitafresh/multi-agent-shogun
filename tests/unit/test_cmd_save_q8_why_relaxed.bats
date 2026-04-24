#!/usr/bin/env bats
# test_cmd_save_q8_why_relaxed.bats — cmd_2248: q8 WHY引用チェックの偽陽性防止

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
    mkdir -p "$TEST_ARCHIVE_DIR"

    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_q8relax:
    id: cmd_q8relax
    title: "infra — q8 WHY検出緩和テスト"
    purpose: "WHYが明示されていれば引用記号なしでも不要WARNを出さない"
    project: infra
    task_type: impl
    command: "q8_why_what の回帰確認"
    acceptance_criteria:
      - "AC1: q8 WHY引用WARNが出ない"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "WHY文面の語彙差で偽陽性を出さない"
      q3_next_quality: "q8の意図確認が引用記号依存にならない"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — q8の偽陽性除去であり問題の隠蔽ではない"
      q7_definition_verified: "yes — q8はWHY/WHATの明示だけを要件とする"
      q8_why_what: "WHY: 学習ループを強化する必要がある → WHAT: q8の引用依存を外して正の複利にする"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_q8_why_relaxed.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。q8 WHY引用WARNが残っていないことを未確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "q8 WHY引用チェックの有無は cmd_save.sh の出力で判定できる"
        source: "tests/unit/test_cmd_save_q8_why_relaxed.bats"
        trust: "verified"
YAML
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "AC1: 引用記号なしのWHYでもq8_WHY引用WARNを出さない" {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        bash "$SAVE_SCRIPT" cmd_q8relax

    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"q8 WHYに殿の指示引用がありません"* ]]
    [[ "$output" != *"q8_WHY引用"* ]]
}
