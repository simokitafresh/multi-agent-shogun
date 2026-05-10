#!/usr/bin/env bats
# test_cmd_save_environment_change.bats — cmd_2160: environment_change必須 + 禁止値チェック
# AC1: BLOCK後の再PASS時にenvironment_changeフィールド必須
# AC2: 禁止値(修正した/対策済み等)の正規表現検出でBLOCK
# AC3: 具体的diff(gate/lesson/hook等)記載時にPASS

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SAVE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    TEST_CMD_ID="cmd_envtest_${BATS_TEST_NUMBER:-0}_$$"
    export TEST_CMD_ID
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
    export TEST_LOCK="$TEST_TMPDIR/shogun_to_karo.lock"
    export TEST_LAST_CMD="$TEST_TMPDIR/cmd_save_last_cmd.txt"
    export TEST_SHOGUN_LESSONS="$TEST_TMPDIR/lessons_shogun.yaml"
    export TEST_PREFLIGHT_AUTOLEARN="$TEST_TMPDIR/preflight_autolearn.txt"
    export TEST_LORD_CONVERSATION="$TEST_TMPDIR/lord_conversation.jsonl"
    export TEST_CMD_CHRONICLE="$TEST_TMPDIR/cmd-chronicle.md"
    mkdir -p "$TEST_ARCHIVE_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- ヘルパー ---

# 完全なquality_gateを持つcmd(PASSする内容)。environment_changeのみ制御
write_full_cmd() {
    local env_change="${1:-}"
    local env_yaml=""
    if [[ -n "$env_change" ]]; then
        env_yaml="    environment_change: \"${env_change}\""
    fi
    cat > "$TEST_QUEUE" <<YAML
commands:
  ${TEST_CMD_ID}:
    id: ${TEST_CMD_ID}
    title: "infra — environment_change必須テスト"
    project: infra
    depends_on: none
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "shallow"
      q5_verified_source: "code_reading + isolated_test"
      q6_not_hiding: "no — environment_change検証であり問題を隠していない"
      q7_definition_verified: "yes — environment_changeは構造化形式(type/file/pattern)で検証する"
      q8_why_what: "WHY: 殿指摘「environment_change必須化」 → WHAT: Check 3.6追加 → WHEN: environment_change必須チェックを検証する時 → WHERE: tests/unit/test_cmd_save_environment_change.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: 初回PASSと再挑戦BLOCKをfixtureで固定する。複利: 正の複利"
      q10_knowledge_boundary: "tests/unit/test_cmd_save_environment_change.bats のfixture範囲のみ使用"
      q11_not_already_done: "未達成。grep 'Check 3.6' scripts/cmd_save.sh で確認"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-04-24時点でenvironment_change必須チェックの動作を確認済み"
        source: "tests/unit/test_cmd_save_environment_change.bats"
        trust: "verified"
${env_yaml}
YAML
}

run_save() {
    run env \
        CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        CMD_SAVE_LOCK_FILE="$TEST_LOCK" \
        CMD_SAVE_LAST_CMD_FILE="$TEST_LAST_CMD" \
        CMD_SAVE_SHOGUN_LESSONS_FILE="$TEST_SHOGUN_LESSONS" \
        CMD_SAVE_PREFLIGHT_AUTOLEARN_FILE="$TEST_PREFLIGHT_AUTOLEARN" \
        CMD_SAVE_LORD_CONVERSATION_FILE="$TEST_LORD_CONVERSATION" \
        CMD_SAVE_CMD_CHRONICLE_FILE="$TEST_CMD_CHRONICLE" \
        CMD_SAVE_ACCUMULATE_BLOCKS=0 \
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" "$TEST_CMD_ID"
}

# 1回目のBLOCKを作成(quality_logにBLOCK記録を残す)
create_prior_block() {
    # show_prior_attempts() が読む最小fixtureだけを置く。
    # ここで cmd_save.sh をもう1回起動すると、各テストが重い全チェックを二重実行してtimeoutする。
    cat > "$TEST_QUALITY_LOG" <<YAML
entries:
  - cmd_id: ${TEST_CMD_ID}
    gate_result: BLOCK
    source: cmd_save
    notes: "q11_not_already_done未記入"
    diagnosis: "BLOCK理由: q11未記入 対策: environment_changeを検証"
YAML
}

# --- AC1: 初回はenvironment_change不要 ---

@test "AC1-1: 初回(PRIOR_ATTEMPT=0)はenvironment_changeなしでPASS" {
    write_full_cmd ""
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"environment_change未記入"* ]]
    [[ "$output" != *"environment_changeが低品質"* ]]
    [[ "$output" != *"environment_changeが非構造化"* ]]
}

# --- AC1: BLOCK後はenvironment_change必須 ---

@test "AC1-2: BLOCK後の再挑戦でenvironment_change未記入→BLOCK" {
    create_prior_block
    write_full_cmd ""
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"environment_change未記入"* ]]
}

# --- AC2: 禁止値検出 ---

@test "AC2-1: environment_change=「修正した」→BLOCK" {
    create_prior_block
    write_full_cmd "修正した"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"environment_changeが低品質"* ]]
}

@test "AC2-2: 禁止値パターンは主要候補を全て含む" {
    local pattern
    pattern="$(grep '_ENV_VAGUE_PATTERN=' "$SAVE_SCRIPT" | head -1 | sed -E 's/.*_ENV_VAGUE_PATTERN="(.*)"/\1/')"

    [[ "修正した" =~ $pattern ]]
    [[ "対策済み" =~ $pattern ]]
    [[ "対策した" =~ $pattern ]]
    [[ "直した" =~ $pattern ]]
    [[ "完了" =~ $pattern ]]
}

# --- AC3: 具体的diff記載時はPASS ---

@test "AC3-1: environment_change=gate追加+ファイルパス→PASS" {
    create_prior_block
    write_full_cmd "type=gate;file=scripts/cmd_save.sh;pattern=environment_change強制"
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"environment_change未実装"* ]]
}

@test "AC3-2: environment_change=lesson登録→PASS" {
    create_prior_block
    local lesson_marker="$TEST_TMPDIR/lessons.yaml"
    printf '%s\n' 'lessons:' '- id: LTEST_ENV_CHANGE' > "$lesson_marker"
    write_full_cmd "type=lesson;file=$lesson_marker;pattern=LTEST_ENV_CHANGE"
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
}

@test "AC4-2: 構造化environment_changeでpattern不一致ならBLOCK" {
    create_prior_block
    write_full_cmd "type=gate_add;file=scripts/cmd_save.sh;pattern=THIS_PATTERN_DOES_NOT_EXIST_2173"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"environment_change未実装"* ]]
    [[ "$output" == *"THIS_PATTERN_DOES_NOT_EXIST_2173"* ]]
}

@test "AC4-3: 自由テキストenvironment_changeはBLOCK" {
    create_prior_block
    write_full_cmd "gate_X追加(scripts/cmd_save.sh L576)+lesson_Y追加(lessons_karo.yaml)"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"environment_changeが非構造化"* ]]
}
