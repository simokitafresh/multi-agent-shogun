#!/usr/bin/env bats
# test_lesson_write_shogun.bats — lesson_write_shogun.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/lesson_write_shogun.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/projects/infra"
    cp "$SRC_SCRIPT" "$TEST_ROOT/scripts/lesson_write_shogun.sh"
    chmod +x "$TEST_ROOT/scripts/lesson_write_shogun.sh"
    cat > "$TEST_ROOT/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: 'LS001'
  title: '既存サンプル'
  detail: '既存サンプル詳細。事故状況と原因と修正を含むテスト用データ。'
  source_cmd: 'cmd_001'
  created_at: '2026-01-01'
  automated: false
  enforcement: '未自動化'
EOF
}

run_lesson_write_shogun() {
    run bash "$TEST_ROOT/scripts/lesson_write_shogun.sh" "$@"
}

@test "blocks enforcement that only references existing automation" {
    run_lesson_write_shogun \
        "既存参照のみを防ぐ" \
        "既存自動強制をenforcementに書くだけでは次サイクルを強化できないためBLOCKする確認。" \
        "cmd_2476" \
        "既存自動強制"

    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK: enforcement が既存参照のみ"* ]]
}

@test "allows enforcement with a concrete new environment change" {
    run_lesson_write_shogun \
        "新規環境変化を許可する" \
        "新しいgateファイルとチェック名をenforcementに含める場合は登録できることを確認する。" \
        "cmd_2476" \
        "type=gate; file=scripts/gates/gate_lesson_write_shogun_enforcement.sh; pattern=lesson_write_shogun_enforcement_new_check"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LS002 added"* ]]

    run grep -A6 "LS002" "$TEST_ROOT/projects/infra/lessons_shogun.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"automated: true"* ]]
    [[ "$output" == *"lesson_write_shogun_enforcement_new_check"* ]]
}

@test "preserves existing append and sequential ID behavior" {
    run_lesson_write_shogun \
        "基本追記は維持" \
        "enforcement未指定でも従来通り教訓追記とID採番が成功することを確認する。" \
        "cmd_2476"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LS002 added"* ]]

    run grep -A6 "LS002" "$TEST_ROOT/projects/infra/lessons_shogun.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"title: '基本追記は維持'"* ]]
    [[ "$output" == *"automated: false"* ]]
    [[ "$output" == *"enforcement: '未自動化'"* ]]
}
