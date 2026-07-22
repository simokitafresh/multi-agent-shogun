#!/usr/bin/env bats
# test_necessity: lesson_writeは必須因果・重複・保存先契約を検証し、不正教訓を正本へ混入させず有効教訓を原子的に追記する。
# test_lesson_write.bats - lesson_write.sh unit tests
# Optimized: python3フル実行→bash native+ENV変数+共有setup方式

setup_file() {
    export REAL_PROJECT_ROOT
    REAL_PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_LESSON_WRITE="$REAL_PROJECT_ROOT/scripts/lesson_write.sh"
    [ -f "$SRC_LESSON_WRITE" ] || return 1

    # 共有ベースディレクトリ（read-only共有リソースのみ）
    export SHARED_DIR
    SHARED_DIR="$(mktemp -d "$BATS_TMPDIR/lw_shared.XXXXXX")"

    # scripts/ — no-op sync_lessons.sh込み
    mkdir -p "$SHARED_DIR/scripts/gates"
    cp "$SRC_LESSON_WRITE" "$SHARED_DIR/scripts/lesson_write.sh"
    printf '#!/bin/bash\nexit 0\n' > "$SHARED_DIR/scripts/sync_lessons.sh"
    chmod +x "$SHARED_DIR/scripts/sync_lessons.sh"

    # GA-216/GA-217: lesson_write.sh sources the shared subdomain routing SSOT.
    cp "$REAL_PROJECT_ROOT/scripts/gates/lesson_context_routes.sh" \
        "$SHARED_DIR/scripts/gates/lesson_context_routes.sh"

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
    # テストごとに独立したディレクトリを作成（--jobs並列実行の分離保証）
    export EXT_PROJECT="$BATS_TEST_TMPDIR/extproj"
    export TEST_PROJECT="$BATS_TEST_TMPDIR/project"

    mkdir -p "$EXT_PROJECT/tasks"
    mkdir -p "$TEST_PROJECT/config" "$TEST_PROJECT/context" "$TEST_PROJECT/projects/testproj" "$TEST_PROJECT/logs"
    ln -s "$SHARED_DIR/scripts" "$TEST_PROJECT/scripts"

    # Per-test pathだけをbuiltinで生成し、43回のheredoc一時ファイル作成を避ける。
    printf 'projects:\n  - id: testproj\n    path: %s\n    context_file: context/test-context.md\n' \
        "$EXT_PROJECT" > "$TEST_PROJECT/config/projects.yaml"

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

@test "default tags use inferred project tag when tags omitted" {
    run_lesson_write testproj "既定タグ確認テスト" "タグ未指定時にproject_id由来のタグが記録されることを確認する" "cmd_201" "hanzo"
    [ "$status" -eq 0 ]

    run grep -A5 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**tags**: [testproj]"* ]]
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

@test "allocates after the routed context maximum to prevent cross-layer ID collisions" {
    sed -i '/## その他/i - L009: context側で先行している教訓' "$TEST_PROJECT/context/test-context.md"

    run_lesson_write testproj "context衝突防止" "routed contextの既存IDを再利用せず次番号を採番する" "cmd_502"
    [ "$status" -eq 0 ]

    run grep "### L010: context衝突防止" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    run grep -- "- L010: context衝突防止" "$TEST_PROJECT/context/test-context.md"
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
    run_lesson_write testproj "初期教訓サンプル" "これは重複タイトルのテスト。類似度が高いため拒否されるべき" "cmd_599"
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

@test "--subdomain writes normalized subdomain field" {
    run_lesson_write testproj "サブドメイン教訓" "サブドメイン指定が正しく記録されるかの確認テストです" "cmd_701" "karo" "" --subdomain frontend
    [ "$status" -eq 0 ]

    run grep "subdomain" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**subdomain**: fe"* ]]
}

@test "--target-files writes target_files field" {
    run_lesson_write testproj "対象ファイル教訓" "target_files指定が正しく記録されるかの確認テストです" "cmd_702" "karo" "" --target-files "scripts/foo.sh, tests/foo.bats"
    [ "$status" -eq 0 ]

    run grep "target_files" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**target_files**: [scripts/foo.sh,tests/foo.bats]"* ]]
}

@test "--origin writes explicit origin field" {
    run_lesson_write testproj "origin明示教訓" "origin明示指定が正しく記録されるかの確認テストです" "cmd_703" "karo" "" --origin "[[cmd_703]] [[LG001]]"
    [ "$status" -eq 0 ]

    run grep "origin" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**origin**: [[cmd_703]] [[LG001]]"* ]]
}

@test "--enforcement writes explicit enforcement field" {
    run_lesson_write testproj "enforcement明示教訓" "enforcement明示指定が正しく記録されるかの確認テストです" "cmd_705" "karo" "" --enforcement "Level5: task YAMLへ自動注入"
    [ "$status" -eq 0 ]

    run grep "enforcement" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**enforcement**: Level5: task YAMLへ自動注入"* ]]
}

@test "enforcement defaults to 未自動化 when omitted" {
    run_lesson_write testproj "enforcement省略教訓" "enforcement省略時に未自動化が記録されるかの確認テストです" "cmd_706" "karo"
    [ "$status" -eq 0 ]

    run grep "enforcement" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**enforcement**: 未自動化"* ]]
}

@test "origin defaults from source_cmd when --origin omitted" {
    run_lesson_write testproj "origin自動教訓" "origin未指定時にsource_cmdから自動生成される確認テストです" "cmd_704" "karo"
    [ "$status" -eq 0 ]

    run grep "origin" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"**origin**: [[cmd_704]]"* ]]
}

@test "cmd_3127: blocks lesson registration when origin and source_cmd are empty" {
    run_lesson_write testproj "origin空BLOCK教訓" "originもsource_cmdもない登録は因果リンク断裂を防ぐため拒否される" "" "karo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"origin is required"* ]]
}

@test "--help mentions subdomain option" {
    run bash "$SHARED_DIR/scripts/lesson_write.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--subdomain fe|be|gs|infra"* ]]
    [[ "$output" == *"--target-files"* ]]
    [[ "$output" == *"--source-marker"* ]]
    [[ "$output" == *"--origin"* ]]
    [[ "$output" == *"--promote"* ]]
}

# ============================================================
# 6b. Existing lesson promotion (SSOT -> generated cache)
# ============================================================

@test "promote exact ID atomically updates enforcement only" {
    before_count=$(grep -c '^### L' "$EXT_PROJECT/tasks/lessons.md")
    run_lesson_write testproj --promote L001 --enforcement "Level5: task context injection"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^### L' "$EXT_PROJECT/tasks/lessons.md")" -eq "$before_count" ]
    [ "$(grep -c '^### L001:' "$EXT_PROJECT/tasks/lessons.md")" -eq 1 ]
    [ "$(grep -cF -- '- **enforcement**: Level5: task context injection' "$EXT_PROJECT/tasks/lessons.md")" -eq 1 ]
}

@test "promote missing ID fails without modifying SSOT" {
    before=$(sha256sum "$EXT_PROJECT/tasks/lessons.md")
    run_lesson_write testproj --promote L999 --enforcement "Level5: missing"
    [ "$status" -eq 1 ]
    [ "$(sha256sum "$EXT_PROJECT/tasks/lessons.md")" = "$before" ]
}

@test "promote duplicate ID fails without modifying SSOT" {
    cat "$LESSONS_TEMPLATE" >> "$EXT_PROJECT/tasks/lessons.md"
    before=$(sha256sum "$EXT_PROJECT/tasks/lessons.md")
    run_lesson_write testproj --promote L001 --enforcement "Level5: duplicate"
    [ "$status" -eq 1 ]
    [ "$(sha256sum "$EXT_PROJECT/tasks/lessons.md")" = "$before" ]
}

@test "promote malformed SSOT fails without partial write" {
    printf '\377\376\000' > "$EXT_PROJECT/tasks/lessons.md"
    before=$(sha256sum "$EXT_PROJECT/tasks/lessons.md")
    run_lesson_write testproj --promote L001 --enforcement "Level5: malformed"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$EXT_PROJECT/tasks/lessons.md")" = "$before" ]
}

@test "concurrent promote serializes and leaves one complete metadata line" {
    LESSON_WRITE_SCRIPT_DIR="$TEST_PROJECT" LESSON_WRITE_SKIP_SYNC=1 bash "$SHARED_DIR/scripts/lesson_write.sh" testproj --promote L001 --enforcement "Level5: first" &
    p1=$!
    LESSON_WRITE_SCRIPT_DIR="$TEST_PROJECT" LESSON_WRITE_SKIP_SYNC=1 bash "$SHARED_DIR/scripts/lesson_write.sh" testproj --promote L001 --enforcement "Level5: second" &
    p2=$!
    wait "$p1"; wait "$p2"
    [ "$(grep -cF -- '- **enforcement**: Level5:' "$EXT_PROJECT/tasks/lessons.md")" -eq 1 ]
}

@test "promote syncs flow and block enforcement into generated cache" {
    cp "$SHARED_DIR/scripts/sync_lessons.sh" "$BATS_TEST_TMPDIR/sync_lessons.backup"
    cat > "$SHARED_DIR/scripts/sync_lessons.sh" <<'EOF'
#!/bin/bash
set -e
root="${LESSON_WRITE_SCRIPT_DIR:?}"
mkdir -p "$root/projects/testproj"
cp "$root/../extproj/tasks/lessons.md" "$root/projects/testproj/lessons.yaml"
EOF
    chmod +x "$SHARED_DIR/scripts/sync_lessons.sh"
    LESSON_WRITE_SCRIPT_DIR="$TEST_PROJECT" LESSON_WRITE_SYNC_MODE=sync run bash "$SHARED_DIR/scripts/lesson_write.sh" testproj --promote L001 --enforcement "Level4: flow BLOCK"
    cp "$BATS_TEST_TMPDIR/sync_lessons.backup" "$SHARED_DIR/scripts/sync_lessons.sh"
    chmod +x "$SHARED_DIR/scripts/sync_lessons.sh"
    [ "$status" -eq 0 ]
    run grep -F -- '- **enforcement**: Level4: flow BLOCK' "$TEST_PROJECT/projects/testproj/lessons.yaml"
    [ "$status" -eq 0 ]
}

@test "promote refuses foreign dirty generated cache without SSOT change" {
    git -C "$TEST_PROJECT" init -q
    git -C "$TEST_PROJECT" config user.email test@example.com
    git -C "$TEST_PROJECT" config user.name test
    printf 'baseline\n' > "$TEST_PROJECT/projects/testproj/lessons.yaml"
    git -C "$TEST_PROJECT" add projects/testproj/lessons.yaml
    git -C "$TEST_PROJECT" commit -qm baseline
    printf 'foreign\n' >> "$TEST_PROJECT/projects/testproj/lessons.yaml"
    before=$(sha256sum "$EXT_PROJECT/tasks/lessons.md")
    run_lesson_write testproj --promote L001 --enforcement "Level5: blocked"
    [ "$status" -eq 1 ]
    [[ "$output" == *"foreign dirty"* ]]
    [ "$(sha256sum "$EXT_PROJECT/tasks/lessons.md")" = "$before" ]
}

@test "draft status is written when --status draft specified" {
    run_lesson_write testproj "ドラフトテスト" "ステータスがdraftで記録されるかの確認テストです" "cmd_800" "karo" "" --status "draft"
    [ "$status" -eq 0 ]

    run grep "status.*draft" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
}

@test "source marker is written when --source-marker specified" {
    run_lesson_write testproj "ソースマーカーテスト" "生成元マーカーが記録されるかの確認テストです" "cmd_801" "gate_auto" "" --status "draft" --source-marker "gate_auto_draft"
    [ "$status" -eq 0 ]

    run grep "source.*gate_auto_draft" "$EXT_PROJECT/tasks/lessons.md"
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

@test "when and how fields are always written to lesson entry" {
    run_lesson_write testproj "発動条件と手順の教訓" "when/howテンプレートが常時出力されることを確認するテスト" "cmd_1001" "karo" "" --when "条件A" --how "手順B"
    [ "$status" -eq 0 ]

    run cat "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"**when**: 条件A"* ]]
    [[ "$output" == *"**how**: 手順B"* ]]
}

@test "when and how default from if and then when explicit values omitted" {
    run_lesson_write testproj "発動条件の既定値教訓" "if/thenからwhen/how既定値を作る確認テスト" "cmd_1002" "karo" "" --if "条件X" --then "手順Y"
    [ "$status" -eq 0 ]

    run cat "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"**when**: 条件X"* ]]
    [[ "$output" == *"**how**: 手順Y"* ]]
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

@test "first write initializes project YAML fallback when lessons.md does not exist" {
    rm -f "$EXT_PROJECT/tasks/lessons.md"
    run_lesson_write testproj "タイトル" "教訓ファイルが存在しない場合のエラーハンドリングテスト"
    [ "$status" -eq 0 ]
    [ ! -f "$EXT_PROJECT/tasks/lessons.md" ]
    run grep -A8 "^- id: L001" "$TEST_PROJECT/projects/testproj/lessons.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"タイトル"* ]]
}

@test "project YAML fallback writes explicit enforcement and automated true" {
    rm -f "$EXT_PROJECT/tasks/lessons.md"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
- id: L001
  title: existing yaml lesson
  summary: existing yaml lesson
EOF

    run_lesson_write testproj "YAML明示enforcement教訓" "YAML直接書込みでenforcementが残ることを確認するテスト" "cmd_707" "karo" "" --enforcement "Level4: gate blocks invalid report"
    [ "$status" -eq 0 ]

    run grep -A14 "^- id: L002" "$TEST_PROJECT/projects/testproj/lessons.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement: >-"* ]]
    [[ "$output" == *"Level4: gate blocks invalid report"* ]]
    [[ "$output" == *"automated: true"* ]]
}

@test "project YAML fallback defaults enforcement to 未自動化 and automated false" {
    rm -f "$EXT_PROJECT/tasks/lessons.md"
    cat > "$TEST_PROJECT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
- id: L001
  title: existing yaml lesson
  summary: existing yaml lesson
EOF

    run_lesson_write testproj "YAML省略enforcement教訓" "YAML直接書込みで省略時の既定値が残ることを確認するテスト" "cmd_708" "karo"
    [ "$status" -eq 0 ]

    run grep -A14 "^- id: L002" "$TEST_PROJECT/projects/testproj/lessons.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enforcement: >-"* ]]
    [[ "$output" == *"未自動化"* ]]
    [[ "$output" == *"automated: false"* ]]
}

@test "project YAML fallback preserves existing file when YAML validation fails" {
    # test_necessity: a malformed lesson source must never be replaced by a
    # partially generated candidate; the last known bytes are the recovery evidence.
    rm -f "$EXT_PROJECT/tasks/lessons.md"
    mkdir -p "$TEST_PROJECT/projects/testproj"
    printf 'lessons:\n- id: L001\n  title: truncated\n  summary: "unterminated\n' \
        > "$TEST_PROJECT/projects/testproj/lessons.yaml"
    cp "$TEST_PROJECT/projects/testproj/lessons.yaml" "$BATS_TEST_TMPDIR/before.yaml"

    run_lesson_write testproj "原子公開検証" "破損した既存YAMLを不変に保つ検証用の十分長い詳細" "cmd_709" "hanzo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"existing lesson YAML is invalid"* ]]
    run cmp "$BATS_TEST_TMPDIR/before.yaml" "$TEST_PROJECT/projects/testproj/lessons.yaml"
    [ "$status" -eq 0 ]
}

# ============================================================
# 9. Subdomain tag inference from target-files
# ============================================================

@test "infer subdomain tag: scripts/gates/ → gate" {
    run_lesson_write testproj "ゲート推定タグ教訓" "scripts/gates配下のtarget_filesからgateタグが推定される確認テスト" "cmd_810" "karo" "" --target-files "scripts/gates/gate_foo.sh"
    [ "$status" -eq 0 ]

    run grep "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [ "$status" -eq 0 ]
    run grep "tags" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"gate"* ]]
}

@test "infer subdomain tag: tests/ → testing" {
    run_lesson_write testproj "テスト推定タグ教訓" "tests配下のtarget_filesからtestingタグが推定される確認テスト" "cmd_811" "karo" "" --target-files "tests/unit/test_foo.bats"
    [ "$status" -eq 0 ]

    run grep -A8 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"testing"* ]]
}

@test "infer subdomain tag: scripts/deploy_task → deploy-task" {
    run_lesson_write testproj "配備推定タグ教訓" "deploy_task関連のtarget_filesからdeploy-taskタグが推定される確認テスト" "cmd_812" "karo" "" --target-files "scripts/deploy_task.sh"
    [ "$status" -eq 0 ]

    run grep -A8 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"deploy-task"* ]]
}

@test "infer subdomain tag: skills/ → skill" {
    run_lesson_write testproj "スキル推定タグ教訓" "skills配下のtarget_filesからskillタグが推定される確認テスト" "cmd_813" "karo" "" --target-files "skills/foo/SKILL.md"
    [ "$status" -eq 0 ]

    run grep -A8 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"skill"* ]]
}

@test "subdomain tag combined with project tag" {
    run_lesson_write testproj "複合タグ教訓" "プロジェクトタグとサブドメインタグの両方が付与される確認テスト" "cmd_814" "karo" "" --target-files "scripts/gates/gate_bar.sh"
    [ "$status" -eq 0 ]

    run grep -A8 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"testproj"* ]]
    [[ "$output" == *"gate"* ]]
}

@test "explicit --tags override subdomain inference" {
    run_lesson_write testproj "明示タグ優先教訓" "明示タグ指定時はサブドメイン推定より優先される確認テスト" "cmd_815" "karo" "" --tags "custom-tag" --target-files "scripts/gates/gate_baz.sh"
    [ "$status" -eq 0 ]

    run grep "^\- \*\*tags\*\*:" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"custom-tag"* ]]
    [[ "$output" != *"gate"* ]]
}

@test "no target-files falls back to project tag only" {
    run_lesson_write testproj "フォールバック教訓" "target_files未指定時はプロジェクトタグのみが付与される確認テスト" "cmd_816" "karo"
    [ "$status" -eq 0 ]

    run grep -A8 "### L002:" "$EXT_PROJECT/tasks/lessons.md"
    [[ "$output" == *"[testproj]"* ]]
    [[ "$output" != *"gate"* ]]
    [[ "$output" != *"testing"* ]]
}

@test "reflux check skips runbook layer when docs/rule has no markdown files" {
    run_lesson_write testproj "inbox prune lock lesson" "inbox prune lock evidence must remain durable after cleanup" "cmd_817" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUNBOOK=SKIPPED"* ]]
    [[ "$output" != *"RUNBOOK=MISSING"* ]]
}

@test "reflux check skips an unrelated existing runbook layer" {
    mkdir -p "$TEST_PROJECT/docs/rule"
    printf '# Bash conventions\nShell quoting rules.\n' > "$TEST_PROJECT/docs/rule/bash-conventions.md"
    run_lesson_write testproj "context freshness lesson" "external source commit boundaries remain durable" "cmd_818" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUNBOOK=SKIPPED"* ]]
    [[ "$output" != *"RUNBOOK=MISSING"* ]]
}

@test "reflux check reports missing for a runbook-scoped lesson" {
    mkdir -p "$TEST_PROJECT/docs/rule"
    printf '# Bash conventions\nShell quoting rules.\n' > "$TEST_PROJECT/docs/rule/bash-conventions.md"
    run_lesson_write testproj "deployment runbook lesson" "deployment runbook must document rollback evidence" "cmd_819" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUNBOOK=MISSING"* ]]
}

@test "shogun lesson_write counts only active entries (superseded excluded)" {
    local tmp_lessons
    tmp_lessons="$(mktemp "$BATS_TMPDIR/lessons_shogun.XXXXXX.yaml")"
    # Generate 34 entries: 30 active + 4 superseded = 34 total
    printf 'lessons:\n' > "$tmp_lessons"
    for i in $(seq 1 30); do
        printf -- "- id: LS%03d\n  title: active %d\n  detail: d\n  created_at: '2026-01-01'\n  automated: true\n  enforcement: 'none'\n" "$i" "$i" >> "$tmp_lessons"
    done
    for i in $(seq 31 34); do
        printf -- "- id: LS%03d\n  title: superseded %d\n  detail: d\n  created_at: '2026-01-01'\n  automated: true\n  enforcement: 'none'\n  superseded_by: 'LS-A01'\n" "$i" "$i" >> "$tmp_lessons"
    done
    local total
    total=$(grep -c '^- id:' "$tmp_lessons")
    [ "$total" -eq 34 ]

    # lesson_write_shogun.sh should NOT block (30 active < 35 limit)
    run env LESSONS_SHOGUN_FILE="$tmp_lessons" \
        bash "$REAL_PROJECT_ROOT/scripts/lesson_write_shogun.sh" \
        "test lesson title for superseded exclusion" "2026-07-16: superseded entries should not count toward the 35-entry active limit. This is a regression test." "cmd_test" "none"
    echo "$output" >&2
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK"* ]]
    rm -f "$tmp_lessons"
}

@test "shogun lesson_write blocks at 35 active entries" {
    local tmp_lessons
    tmp_lessons="$(mktemp "$BATS_TMPDIR/lessons_shogun.XXXXXX.yaml")"
    printf 'lessons:\n' > "$tmp_lessons"
    for i in $(seq 1 35); do
        printf -- "- id: LS%03d\n  title: active %d\n  detail: d\n  created_at: '2026-01-01'\n  automated: true\n  enforcement: 'none'\n" "$i" "$i" >> "$tmp_lessons"
    done

    run env LESSONS_SHOGUN_FILE="$tmp_lessons" \
        bash "$REAL_PROJECT_ROOT/scripts/lesson_write_shogun.sh" \
        "test lesson title for active limit block" "2026-07-16: when 35 active entries exist the script must BLOCK. This prevents lesson file unbounded growth." "cmd_test" "none"
    echo "$output" >&2
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"active 35"* ]]
    [[ "$output" == *"ack: bash scripts/shogun_lesson_ack.sh cmd_test LS"* ]]
    [[ "$output" == *"統合: bash scripts/lesson_write_shogun.sh --supersedes LS"* ]]
    [[ "$output" != *"LS-A05"* ]]
    while read -r proposed_id; do
        grep -q -- "- id: ${proposed_id}$" "$tmp_lessons"
    done < <(printf '%s\n' "$output" | grep -oE 'shogun_lesson_ack\.sh cmd_test LS[0-9]+' | awk '{print $3}')
    rm -f "$tmp_lessons"
}

@test "role lesson append persists explicit enforcement metadata" {
    # test_necessity: role lesson startup injection depends on append preserving
    # both enforcement fields; silently dropping them weakens future reviews.
    local role_root="$BATS_TEST_TMPDIR/role-root"
    mkdir -p "$role_root/scripts/lib" "$role_root/projects/infra"
    cp "$REAL_PROJECT_ROOT/scripts/lesson_write_karo.sh" "$role_root/scripts/lesson_write_karo.sh"
    cp "$REAL_PROJECT_ROOT/scripts/lib/lock_path.sh" "$role_root/scripts/lib/lock_path.sh"
    printf 'lessons:\n- id: LG001\n  title: seed\n  detail: seed detail\n' > "$role_root/projects/infra/lessons_gunshi.yaml"

    run bash "$role_root/scripts/lesson_write_karo.sh" \
        "explicit enforcement contract" \
        "new role lessons must preserve structured enforcement metadata" \
        "cmd_test" \
        --role gunshi \
        --enforcement "Level5: startup context injection" \
        --enforcement-level 5
    [ "$status" -eq 0 ]

    run python3 -c "import yaml; x=yaml.safe_load(open('$role_root/projects/infra/lessons_gunshi.yaml'))['lessons'][-1]; assert x['enforcement']=='Level5: startup context injection'; assert x['enforcement_level']==5"
    [ "$status" -eq 0 ]
}
