#!/usr/bin/env bats
# test_cmd_save_block_aggregation.bats — cmd_save.sh が複数BLOCK理由を1回で表示するか

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

run_cmd_save() {
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
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_multi_block
}

run_cmd_save_pass() {
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
        CMD_QUALITY_FAST_METADATA=1 \
        bash "$SAVE_SCRIPT" cmd_pass
}

@test "AC2: 1回の実行で複数BLOCK理由を一括表示する" {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_multi_block:
    id: cmd_multi_block
    title: "fix — cmd_save集約テスト"
    project: infra
    command: "複数BLOCK理由を1回で露出させる"
    status: pending
    acceptance_criteria:
      - id: AC1
        description: "集約表示を確認"
      - id: AC2
        description: "追加BLOCKを混在させる"
      - id: AC3
        description: "assumptionsも検証"
    quality_gate:
      q1_firefighting: "yes"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q4_depth: "medium"
      q5_verified_source: "code_reading"
      q8_why_what: "WHY: 「集約表示を壊すな」 → WHAT: 意図的にBLOCKを4種類混在させる → WHEN: cmd_saveのBLOCK集約回帰を検証する時 → WHERE: tests/unit/test_cmd_save_block_aggregation.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: 複数BLOCK理由を1回の出力で検証する。複利: 正の複利"
      q_ambiguity: "none"
    assumptions:
      - source: "nonexistent/path.sh code_reading"
        trust: "verified"
        detail: "存在しないパス"
YAML

    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$(printf '%s\n' "$output" | head -n 1)" == "止まるな、修正して再実行せよ" ]]
    [[ "$(printf '%s\n' "$output" | grep -c '^止まるな、修正して再実行せよ$')" -eq 1 ]]
    [[ "$output" == *"BLOCK: 必須項目 1件 未記入。全て記入してからcmd_save.shを再実行せよ"* ]]
    [[ "$output" == *"未記入: q11_not_already_done"* ]]
    [[ "$output" == *"BLOCK: q5=code_readingのみ。コード読みだけでは前提未検証。isolated_test/structure_verified/production_verifiedのいずれかで実確認せよ"* ]]
    [[ "$output" == *"BLOCK: 消火cmdなのにq9_firefighting_root_cause未記入。真因と再発防止を記載してからcmd_save.shを実行せよ"* ]]
    [[ "$output" == *"保存確認NG: cmd_multi_block"* ]]
}

@test "AC1: PASS時はBLOCKナッジを表示しない" {
    cat > "$TEST_QUEUE" <<'YAML'
commands:
  cmd_pass:
    id: cmd_pass
    title: "verify — cmd_save pass output"
    purpose: "cmd_save PASS時の出力静粛性を検証する"
    project: infra
    depends_on: none
    task_type: impl
    command: |
      1. scripts/cmd_save.sh の出力条件を確認する
      2. PASS時に余計なBLOCKナッジが混入しないことを確認する
    acceptance_criteria:
      - id: AC1
        description: "PASS時にBLOCKナッジが出ない"
      - id: AC2
        description: "保存確認OKが表示される"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "既存のBLOCK出力経路にだけ手を入れる"
      q3_next_quality: "PASS経路の静粛性を維持する"
      q4_depth: "shallow"
      q5_verified_source: "tests/unit/test_cmd_save_block_aggregation.bats structure_verified"
      q6_not_hiding: "no — BLOCK専用ナッジの出し分け確認であり、根因を隠す変更ではない"
      q7_definition_verified: "yes — PASS=exit 0かつ保存確認OK出力を本テストで固定する"
      q8_why_what: "WHY: PASS経路に余計なノイズを混ぜない → WHAT: BLOCK専用ナッジの非表示を確認する → WHEN: cmd_saveのPASS経路を検証する時 → WHERE: tests/unit/test_cmd_save_block_aggregation.bats → WHO: 将軍cmd保存ゲートを使う将軍 → HOW: exit 0と保存確認OKを固定し、この選択を10回繰り返しても正の複利になる形にする"
      q10_knowledge_boundary: "空間内。根拠: cmd_save.sh の既存出力経路と本Batsのみを使う"
      q11_not_already_done: "未達成。これからPASS経路の出力を確認する"
      q_ambiguity: "none"
    assumptions:
      - claim: "2026-04-25 テスト用QUEUE_FILEだけを参照する"
        source: "tests/unit/test_cmd_save_block_aggregation.bats"
        trust: "verified"
        verified_at: "2026-04-25"
        detail: "CMD_SAVE_QUEUE_FILEで差し替える"
YAML

    run_cmd_save_pass
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"保存確認OK: cmd_pass"* ]]
    [[ "$output" != *"止まるな、修正して再実行せよ"* ]]
}
