#!/usr/bin/env bats
# test_lesson_write.bats - lesson_write.sh unit tests
# Optimized: python3フル実行→bash native+ENV変数+共有setup方式

setup_file() {
    export REAL_PROJECT_ROOT
    REAL_PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_LESSON_WRITE="$REAL_PROJECT_ROOT/scripts/lesson_write.sh"
    [ -f "$SRC_LESSON_WRITE" ] || return 1

    # 共有ベースディレクトリ（setup_fileで1回のみ作成）
    export SHARED_DIR
    SHARED_DIR="$(mktemp -d "$BATS_TMPDIR/lw_shared.XXXXXX")"

    # scripts/ — no-op sync_lessons.sh込み
    mkdir -p "$SHARED_DIR/scripts"
    cp "$SRC_LESSON_WRITE" "$SHARED_DIR/scripts/lesson_write.sh"
    printf '#!/bin/bash\nexit 0\n' > "$SHARED_DIR/scripts/sync_lessons.sh"
    chmod +x "$SHARED_DIR/scripts/sync_lessons.sh"

    # 固定EXT_PROJECT（lessons.mdはtestごとにコピーで上書き）
    export EXT_PROJECT="$SHARED_DIR/extproj"
    mkdir -p "$EXT_PROJECT/tasks"

    # 固定TEST_PROJECT（config.yamlは固定パスで1回作成）
    export TEST_PROJECT="$SHARED_DIR/project"
    mkdir -p "$TEST_PROJECT/config" "$TEST_PROJECT/context" "$TEST_PROJECT/projects/testproj" "$TEST_PROJECT/logs"
    ln -s "$SHARED_DIR/scripts" "$TEST_PROJECT/scripts"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: $EXT_PROJECT
    context_file: context/test-context.md
EOF

    # lessons.mdテンプレート（各テストでここからコピー）
    export LESSONS_TEMPLATE="$SHARED_DIR/lessons_template.md"
    cat > "$LESSONS_TEMPLATE" <<'LESSONSEOF'
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

    # context.mdテンプレート
    export CONTEXT_TEMPLATE="$SHARED_DIR/context_template.md"
    cat > "$CONTEXT_TEMPLATE" <<'CTXEOF'
# Test Context

## 教訓索引

- L001: 初期教訓サンプル（cmd_001）

## その他
CTXEOF
}

teardown_file() {
    [ -d "$SHARED_DIR" ] && rm -rf "$SHARED_DIR"
}

setup() {
    # テンプレートからのコピーのみ（mktemp/mkdir不要）
    cp "$LESSONS_TEMPLATE" "$EXT_PROJECT/tasks/lessons.md"
    cp "$CONTEXT_TEMPLATE" "$TEST_PROJECT/context/test-context.md"
}

teardown() { true; }

# Helper: run lesson_write.sh via ENV (no sed patch)
run_lesson_write() {
    LESSON_WRITE_SCRIPT_DIR="$TEST_PROJECT" \
    LESSON_WRITE_SKIP_SYNC=1 \
    run bash "$SHARED_DIR/scripts/lesson_write.sh" "$@"
}

# Helper: retire tests
run_lesson_write_with_sync() {
    LESSON_WRITE_SCRIPT_DIR="$TEST_PROJECT" \
    LESSON_WRITE_SKIP_SYNC=1 \
    run bash "$SHARED_DIR/scripts/lesson_write.sh" "$@"
}

# ============================================================
# 1. Normal lesson addition
# ============================================================

@test "normal lesson addition with title, detail, source_cmd" {
    run_lesson_write testproj "テスト教訓タイトル" "テスト教訓の詳細内容。10文字以上必要。" "cmd_100" "kotaro"
    [ "$status" -eq 0 ]

    run grep "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"テスト教訓タイトル"* ]]
}

@test "lesson addition includes metadata fields (date, source, author)" {
    run_lesson_write testproj "メタデータ確認テスト" "メタデータが正しく書き込まれるかの確認テストです" "cmd_200" "hanzo"
    [ "$status" -eq 0 ]

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
    run_lesson_write testproj "二番目" "二番目の教訓詳細内容。テスト用データです。" "cmd_500"
    [ "$status" -eq 0 ]

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

@test "warns on similar title with Jaccard >= 0.6 but still writes lesson" {
    cat >> "$EXT_PROJECT/tasks/lessons.md" <<'EOF'

### L002: alpha beta gamma delta
- **日付**: 2026-01-02
- **出典**: cmd_002
- **記録者**: karo
- **tags**: [universal]
- similar title fixture
EOF

    run_lesson_write testproj "alpha beta gamma epsilon" "Jaccard閾値以上ではWARNを出しつつ登録を継続する確認テスト" "cmd_601" "saizo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 類似教訓候補: L002: alpha beta gamma delta (Jaccard: 0.60)"* ]]

    run grep "### L003: alpha beta gamma epsilon" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

@test "does not warn when similar title Jaccard is below 0.6" {
    cat >> "$EXT_PROJECT/tasks/lessons.md" <<'EOF'

### L002: alpha beta gamma delta
- **日付**: 2026-01-02
- **出典**: cmd_002
- **記録者**: karo
- **tags**: [universal]
- similar title fixture
EOF

    run_lesson_write testproj "alpha beta zeta eta" "Jaccard閾値未満ではWARNを出さず登録を継続する確認テスト" "cmd_602" "saizo"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: 類似教訓候補"* ]]

    run grep "### L003: alpha beta zeta eta" "$EXT_PROJECT/tasks/lessons.md"
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
    run_lesson_write_with_sync testproj --retire L001
    [ "$status" -eq 0 ]

    run grep "retired.*true" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

@test "retire mode fails for nonexistent lesson ID" {
    run_lesson_write_with_sync testproj --retire L999
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
