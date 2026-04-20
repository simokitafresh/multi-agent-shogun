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
    export TEST_QUEUE="$TEST_TMPDIR/shogun_to_karo.yaml"
    export TEST_ARCHIVE_DIR="$TEST_TMPDIR/archive"
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
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
  cmd_envtest:
    id: cmd_envtest
    title: "infra — environment_change必須テスト"
    project: infra
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + isolated_test"
      q8_why_what: "WHY: 殿指摘「environment_change必須化」 → WHAT: Check 3.6追加。正の複利"
      q11_not_already_done: "未達成。grep 'Check 3.6' scripts/cmd_save.sh で確認"
    assumptions:
      - claim: "environment_change必須チェックの動作を確認済み"
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
        bash "$SAVE_SCRIPT" cmd_envtest
}

# 1回目のBLOCKを作成(quality_logにBLOCK記録を残す)
create_prior_block() {
    # q11が未記入なcmd → BLOCK → quality_logに記録
    cat > "$TEST_QUEUE" <<YAML
commands:
  cmd_envtest:
    id: cmd_envtest
    title: "infra — environment_change必須テスト"
    project: infra
    command: "テスト用cmd"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "code_reading + isolated_test"
      q8_why_what: "WHY: 殿指摘「テスト」 → WHAT: テスト実施。正の複利"
    assumptions:
      - claim: "テスト前提"
        source: "tests/unit/test_cmd_save_environment_change.bats"
        trust: "verified"
YAML
    # cmd_save実行: q11未記入でBLOCK → quality_logに記録
    env CMD_SAVE_QUEUE_FILE="$TEST_QUEUE" \
        CMD_SAVE_ARCHIVE_CMD_DIR="$TEST_ARCHIVE_DIR" \
        CMD_QUALITY_LOG_FILE="$TEST_QUALITY_LOG" \
        bash "$SAVE_SCRIPT" cmd_envtest >/dev/null 2>&1 || true
}

# --- AC1: 初回はenvironment_change不要 ---

@test "AC1-1: 初回(PRIOR_ATTEMPT=0)はenvironment_changeなしでPASS" {
    write_full_cmd ""
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"environment_change"* ]]
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

@test "AC2-2: environment_change=「対策済み」→BLOCK" {
    create_prior_block
    write_full_cmd "対策済み"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"environment_changeが低品質"* ]]
}

@test "AC2-3: environment_change=「対策した」→BLOCK" {
    create_prior_block
    write_full_cmd "対策した"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"environment_changeが低品質"* ]]
}

@test "AC2-4: environment_change=「直した」→BLOCK" {
    create_prior_block
    write_full_cmd "直した"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"environment_changeが低品質"* ]]
}

@test "AC2-5: environment_change=「完了」→BLOCK" {
    create_prior_block
    write_full_cmd "完了"
    run_save
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"environment_changeが低品質"* ]]
}

# --- AC3: 具体的diff記載時はPASS ---

@test "AC3-1: environment_change=gate追加+ファイルパス→PASS" {
    create_prior_block
    write_full_cmd "type=gate;file=scripts/cmd_save.sh;pattern=environment_change強制"
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
}

@test "AC3-2: environment_change=lesson登録→PASS" {
    create_prior_block
    write_full_cmd "type=lesson;file=projects/infra/lessons.yaml;pattern=L053"
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
}

@test "AC3-3: environment_change=hook変更→PASS" {
    create_prior_block
    write_full_cmd "type=hook;file=scripts/hooks/pre-write-report-deny.sh;pattern=hookEventName"
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
}

@test "AC4-1: 構造化environment_changeでgrep検証PASSなら静かにPASS" {
    create_prior_block
    write_full_cmd "type=gate_add;file=scripts/cmd_save.sh;pattern=environment_change強制"
    run_save
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK"* ]]
    [[ "$output" != *"environment_change未実装"* ]]
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
