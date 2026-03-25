#!/usr/bin/env bats
# test_lesson_write.bats - lesson_write.sh unit tests
# Created by: kotaro (cmd_cycle_002)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_LESSON_WRITE="$PROJECT_ROOT/scripts/lesson_write.sh"
    [ -f "$SRC_LESSON_WRITE" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lesson_write.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export EXT_PROJECT="$TEST_TMPDIR/extproj"

    mkdir -p \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/config" \
        "$TEST_PROJECT/logs" \
        "$TEST_PROJECT/projects/testproj" \
        "$TEST_PROJECT/context" \
        "$EXT_PROJECT/tasks"

    # Copy lesson_write.sh and its dependency sync_lessons.sh
    cp "$SRC_LESSON_WRITE" "$TEST_PROJECT/scripts/lesson_write.sh"
    chmod +x "$TEST_PROJECT/scripts/lesson_write.sh"

    if [ -f "$PROJECT_ROOT/scripts/sync_lessons.sh" ]; then
        cp "$PROJECT_ROOT/scripts/sync_lessons.sh" "$TEST_PROJECT/scripts/sync_lessons.sh"
        chmod +x "$TEST_PROJECT/scripts/sync_lessons.sh"
    fi

    # Create minimal projects.yaml pointing to EXT_PROJECT
    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: $EXT_PROJECT
    context_file: context/test-context.md
EOF

    # Create initial lessons.md with one existing lesson
    cat > "$EXT_PROJECT/tasks/lessons.md" <<'LESSONSEOF'
---
title: Test Lessons
---

## 教訓索引

### L001: 初期教訓サンプル
- **日付**: 2026-01-01
- **出典**: cmd_001
- **記録者**: karo
- **tags**: [universal]
- これは既存の教訓です。テスト用のサンプルエントリ。
LESSONSEOF

    # Create context file for context append testing
    cat > "$TEST_PROJECT/context/test-context.md" <<'CTXEOF'
# Test Context

## 教訓索引

- L001: 初期教訓サンプル（cmd_001）

## その他
CTXEOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# Helper: run lesson_write.sh from the test project directory
run_lesson_write() {
    # Override SCRIPT_DIR by running from within the test project
    cd "$TEST_PROJECT"
    # Patch the script to use TEST_PROJECT as SCRIPT_DIR
    local patched="$TEST_TMPDIR/lesson_write_patched.sh"
    sed "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEST_PROJECT\"|" "$TEST_PROJECT/scripts/lesson_write.sh" > "$patched"
    chmod +x "$patched"
    run bash "$patched" "$@"
}

# Helper: run lesson_write.sh with sync_lessons.sh also patched
run_lesson_write_with_sync() {
    cd "$TEST_PROJECT"
    # Patch lesson_write.sh
    local patched="$TEST_TMPDIR/lesson_write_patched.sh"
    sed "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEST_PROJECT\"|" "$TEST_PROJECT/scripts/lesson_write.sh" > "$patched"
    chmod +x "$patched"

    # Patch sync_lessons.sh
    if [ -f "$TEST_PROJECT/scripts/sync_lessons.sh" ]; then
        local sync_patched="$TEST_TMPDIR/sync_lessons_patched.sh"
        sed "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEST_PROJECT\"|" "$TEST_PROJECT/scripts/sync_lessons.sh" > "$sync_patched"
        chmod +x "$sync_patched"
        cp "$sync_patched" "$TEST_PROJECT/scripts/sync_lessons.sh"
    fi

    run bash "$patched" "$@"
}

# ============================================================
# 1. Normal lesson addition
# ============================================================

@test "normal lesson addition with title, detail, source_cmd" {
    run_lesson_write testproj "テスト教訓タイトル" "テスト教訓の詳細内容。10文字以上必要。" "cmd_100" "kotaro"
    [ "$status" -eq 0 ]

    # Verify L002 was added to lessons.md
    run grep "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"テスト教訓タイトル"* ]]
}

@test "lesson addition includes metadata fields (date, source, author)" {
    run_lesson_write testproj "メタデータ確認テスト" "メタデータが正しく書き込まれるかの確認テストです" "cmd_200" "hanzo"
    [ "$status" -eq 0 ]

    # Check metadata fields exist in lessons.md
    run grep -A5 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**日付**"* ]]
    [[ "$output" == *"**出典**: cmd_200"* ]]
    [[ "$output" == *"**記録者**: hanzo"* ]]
}

# ============================================================
# 2. lessons.md append verification
# ============================================================

@test "lesson is appended to lessons.md file" {
    run_lesson_write testproj "追記テスト" "lessons.mdファイルに教訓が追記されることを確認するテスト" "cmd_300"
    [ "$status" -eq 0 ]

    # File should now contain both L001 and L002
    run grep -c "^### L" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

# ============================================================
# 3. ID auto-generation (sequential)
# ============================================================

@test "auto-generates sequential ID (L002 after L001)" {
    run_lesson_write testproj "二番目の教訓" "既存L001の次にL002が自動採番されることの確認テスト" "cmd_400"
    [ "$status" -eq 0 ]

    run grep "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

@test "auto-generates L003 when L001 and L002 exist" {
    # Add L002 first
    run_lesson_write testproj "二番目" "二番目の教訓詳細内容。テスト用データです。" "cmd_500"
    [ "$status" -eq 0 ]

    # Add L003
    run_lesson_write testproj "三番目" "三番目の教訓詳細内容。連番の確認テストです。" "cmd_501"
    [ "$status" -eq 0 ]

    run grep "### L003:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

# ============================================================
# 4. Required argument validation
# ============================================================

@test "fails when project_id is missing" {
    run_lesson_write "" "タイトル" "詳細内容テスト用のダミーテキスト"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fails when title is missing" {
    run_lesson_write testproj "" "詳細内容テスト用のダミーテキスト"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fails when detail is missing" {
    run_lesson_write testproj "タイトル" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fails when project_id starts with cmd_" {
    run_lesson_write "cmd_123" "タイトル" "詳細内容テスト用のダミーテキスト"
    [ "$status" -eq 1 ]
    [[ "$output" == *"project_id"* ]]
}

@test "fails when detail is less than 10 characters" {
    run_lesson_write testproj "タイトル" "短い"
    [ "$status" -eq 1 ]
    [[ "$output" == *"10文字未満"* ]]
}

@test "fails when project_id is not in projects.yaml" {
    run_lesson_write "nonexistent" "タイトル" "詳細内容テスト用のダミーテキスト"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ============================================================
# 5. Duplicate title check
# ============================================================

@test "blocks duplicate title (similarity > 75%)" {
    run_lesson_write testproj "初期教訓サンプル" "これは重複タイトルのテスト。類似度が高いため拒否されるべき"
    [ "$status" -eq 1 ]
    [[ "$output" == *"類似教訓あり"* ]]
}

@test "duplicate check bypass with --force flag" {
    run_lesson_write testproj "初期教訓サンプル" "forceフラグにより重複チェックをバイパスして登録可能" "cmd_600" "karo" "" --force
    [ "$status" -eq 0 ]

    run grep "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

# ============================================================
# 6. Optional flags (--tags, --status, --if/--then/--because)
# ============================================================

@test "explicit --tags are written to lesson entry" {
    run_lesson_write testproj "タグテスト教訓" "タグオプション指定時に正しくタグが記録されるかの確認" "cmd_700" "karo" "" --tags "db,api"
    [ "$status" -eq 0 ]

    run grep "tags" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"db"* ]]
    [[ "$output" == *"api"* ]]
}

@test "draft status is written when --status draft specified" {
    run_lesson_write testproj "ドラフトテスト" "ステータスがdraftで記録されるかの確認テストです" "cmd_800" "karo" "" --status "draft"
    [ "$status" -eq 0 ]

    run grep "status.*draft" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

@test "invalid --status value is rejected" {
    run_lesson_write testproj "不正ステータス" "不正なステータス値が拒否されるかの確認テストです" "cmd_900" "karo" "" --status "invalid"
    [ "$status" -eq 1 ]
    [[ "$output" == *"draft"* ]] || [[ "$output" == *"confirmed"* ]]
}

@test "if-then-because fields are written to lesson entry" {
    run_lesson_write testproj "条件付き教訓" "IF-THEN-BECAUSE形式の教訓がの確認テスト" "cmd_1000" "karo" "" --if "条件A" --then "アクションB" --because "理由C"
    [ "$status" -eq 0 ]

    run cat "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"**if**: 条件A"* ]]
    [[ "$output" == *"**then**: アクションB"* ]]
    [[ "$output" == *"**because**: 理由C"* ]]
}

# ============================================================
# 7. Retire mode
# ============================================================

@test "retire mode marks existing lesson as retired" {
    # Patch sync_lessons.sh to no-op for retire test
    echo '#!/bin/bash' > "$TEST_PROJECT/scripts/sync_lessons.sh"
    echo 'exit 0' >> "$TEST_PROJECT/scripts/sync_lessons.sh"
    chmod +x "$TEST_PROJECT/scripts/sync_lessons.sh"

    run_lesson_write testproj --retire L001
    [ "$status" -eq 0 ]

    run grep "retired.*true" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

@test "retire mode fails for nonexistent lesson ID" {
    # Patch sync_lessons.sh to no-op
    echo '#!/bin/bash' > "$TEST_PROJECT/scripts/sync_lessons.sh"
    echo 'exit 0' >> "$TEST_PROJECT/scripts/sync_lessons.sh"
    chmod +x "$TEST_PROJECT/scripts/sync_lessons.sh"

    run_lesson_write testproj --retire L999
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# ============================================================
# 8. lessons.md not found
# ============================================================

@test "fails when lessons.md does not exist" {
    rm -f "$EXT_PROJECT/tasks/lessons.md"
    run_lesson_write testproj "タイトル" "教訓ファイルが存在しない場合のエラーハンドリングテスト"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}
