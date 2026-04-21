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
        bash "$SAVE_SCRIPT" cmd_multi_block
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
      q8_why_what: "WHY: 「集約表示を壊すな」 → WHAT: 意図的にBLOCKを4種類混在させる。正の複利"
      q_ambiguity: "none"
    assumptions:
      - source: "nonexistent/path.sh code_reading"
        trust: "verified"
        detail: "存在しないパス"
YAML

    run_cmd_save
    echo "$output" >&2

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: 必須項目 1件 未記入。全て記入してからcmd_save.shを再実行せよ"* ]]
    [[ "$output" == *"未記入: q11_not_already_done"* ]]
    [[ "$output" == *"BLOCK: q5=code_readingのみ。コード読みだけでは前提未検証。isolated_test/structure_verified/production_verifiedのいずれかで実確認せよ"* ]]
    [[ "$output" == *"BLOCK: 消火cmdなのにq9_firefighting_root_cause未記入。真因と再発防止を記載してからcmd_save.shを実行せよ"* ]]
    [[ "$output" == *"保存確認NG: cmd_multi_block"* ]]
}
