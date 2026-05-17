#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/lesson_write_karo.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
}

setup() {
    TEST_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/projects/infra"
    cp "$SRC_SCRIPT" "$TEST_ROOT/scripts/lesson_write_karo.sh"
    chmod +x "$TEST_ROOT/scripts/lesson_write_karo.sh"
    cat > "$TEST_ROOT/projects/infra/lessons_karo.yaml" <<'EOF'
lessons:
- id: 'LK001'
  title: '既存サンプル'
  origin: '[[cmd_001]]'
  detail: '既存サンプル詳細。家老教訓のテスト用データ。'
  source_cmd: 'cmd_001'
  when: '既存条件'
  how: '既存手順'
  created_at: '2026-01-01'
EOF
}

run_lesson_write_karo() {
    run bash "$TEST_ROOT/scripts/lesson_write_karo.sh" "$@"
}

@test "lesson_write_karo writes explicit --origin field" {
    run_lesson_write_karo \
        "origin明示家老教訓" \
        "origin明示指定が家老教訓YAMLに書き込まれることを確認する。" \
        "cmd_2844" \
        --origin "[[cmd_2844]] -> [[因果NW全ロール拡大]]"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LK002 added"* ]]

    run grep -A6 "LK002" "$TEST_ROOT/projects/infra/lessons_karo.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"origin: '[[cmd_2844]] -> [[因果NW全ロール拡大]]'"* ]]
    [[ "$output" == *"source_cmd: 'cmd_2844'"* ]]
}

@test "lesson_write_karo defaults origin from source_cmd" {
    run_lesson_write_karo \
        "origin自動家老教訓" \
        "origin未指定時にsource_cmdから自動補完されることを確認する。" \
        "cmd_2844"

    [ "$status" -eq 0 ]

    run grep -A5 "LK002" "$TEST_ROOT/projects/infra/lessons_karo.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"origin: '[[cmd_2844]]'"* ]]
}
