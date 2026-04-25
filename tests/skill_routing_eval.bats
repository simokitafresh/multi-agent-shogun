#!/usr/bin/env bats
# ============================================================
# skill_routing_eval.bats
# gate_skill_health.sh + スキルルーティングパターン検証
#
# チェック観点:
#   (A) 到達可能性: TRIGGER未定義 → WARN
#   (B) MECE: TRIGGERキーワード衝突 → WARN
#   (C) DRY: NOT TRIGGER参照先の実在確認 → WARN
#   統合: 実スキルディレクトリがFAILしないことを確認
# ============================================================

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export GATE="$PROJECT_ROOT/scripts/gates/gate_skill_health.sh"
    [ -f "$GATE" ] || { echo "GATE not found: $GATE" >&2; return 1; }
    command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; return 1; }
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_routing.XXXXXX")"
    export TEST_SKILLS_DIR="$TEST_TMPDIR/skills"
    mkdir -p "$TEST_SKILLS_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ─── ヘルパー ───────────────────────────────────────────────

# 最小有効スキルを作成するヘルパー
make_skill() {
    local name="$1"
    local trigger_keyword="${2:-処理をして}"
    local not_trigger="${3:-}"
    mkdir -p "$TEST_SKILLS_DIR/$name"
    cat > "$TEST_SKILLS_DIR/$name/SKILL.md" <<EOF
---
name: $name
description: |
  ${name}スキル。
  TRIGGER: /${name}、${trigger_keyword}
  DO NOT TRIGGER: ${not_trigger:-他の操作（対象外）}
allowed-tools:
  - Bash
---

# ${name}

Content here.
EOF
}

# TRIGGER未定義スキルを作成するヘルパー
make_skill_no_trigger() {
    local name="$1"
    mkdir -p "$TEST_SKILLS_DIR/$name"
    cat > "$TEST_SKILLS_DIR/$name/SKILL.md" <<EOF
---
name: $name
description: |
  ${name}スキル。トリガーなし。
  DO NOT TRIGGER: 全操作（対象外）
allowed-tools:
  - Bash
---

# ${name}
EOF
}

# ─── (A) 到達可能性チェック ────────────────────────────────

# SR-001: 有効なスキル1件 → exit 0 (PASS)
@test "SR-001: single skill with TRIGGER → PASS (exit 0)" {
    make_skill "skill-a" "処理Aをして"
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
}

# SR-002: TRIGGER未定義のスキル → exit 2 (WARN)
@test "SR-002: skill missing TRIGGER → WARN (exit 2)" {
    make_skill_no_trigger "no-trigger-skill"
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN [no-trigger-skill]: TRIGGER未定義"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# SR-009: スラッシュコマンドなしのスキル → exit 2 (WARN)
@test "SR-009: skill without slash command → WARN (exit 2)" {
    mkdir -p "$TEST_SKILLS_DIR/no-slash-skill"
    cat > "$TEST_SKILLS_DIR/no-slash-skill/SKILL.md" <<'EOF'
---
name: no-slash-skill
description: |
  スラッシュコマンドなしスキル。
  TRIGGER: キーワードA、キーワードB
  DO NOT TRIGGER: 他の操作
allowed-tools:
  - Bash
---

# no-slash-skill
EOF
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"スラッシュコマンドなし"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# ─── (B) MECEチェック ──────────────────────────────────────

# SR-003: 2スキルで同一TRIGGERキーワード → exit 2 (WARN, 衝突検出)
@test "SR-003: trigger keyword collision between two skills → WARN (exit 2)" {
    make_skill "skill-x" "記事を書いて"
    make_skill "skill-y" "記事を書いて"
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"衝突キーワード '記事を書いて'"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

# SR-003b: スラッシュコマンドは衝突対象外 (各スキル固有)
@test "SR-003b: slash commands not checked for MECE collision" {
    # 2スキルが /cmd1 /cmd2 と異なるスラッシュコマンドを持つ
    mkdir -p "$TEST_SKILLS_DIR/skill-slash-a"
    cat > "$TEST_SKILLS_DIR/skill-slash-a/SKILL.md" <<'EOF'
---
name: skill-slash-a
description: |
  スキルA。
  TRIGGER: /skill-slash-a、処理Aをして
  DO NOT TRIGGER: 処理Bは別スキル
allowed-tools:
  - Bash
---

# skill-slash-a
EOF
    mkdir -p "$TEST_SKILLS_DIR/skill-slash-b"
    cat > "$TEST_SKILLS_DIR/skill-slash-b/SKILL.md" <<'EOF'
---
name: skill-slash-b
description: |
  スキルB。
  TRIGGER: /skill-slash-b、処理Bをして
  DO NOT TRIGGER: 処理Aは別スキル
allowed-tools:
  - Bash
---

# skill-slash-b
EOF
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    # スラッシュコマンドの衝突はチェックしない → キーワード衝突もなし → PASS
    [ "$status" -eq 0 ]
    [[ "$output" == *"衝突なし"* ]]
}

# ─── (C) DRYチェック ──────────────────────────────────────

# SR-004: NOT TRIGGERの参照先スキルが存在する → exit 0 (PASS)
@test "SR-004: NOT TRIGGER cross-ref to existing skill → PASS (exit 0)" {
    make_skill "skill-p" "処理Pをして" "処理Qは（→skill-q）"
    make_skill "skill-q" "処理Qをして" "処理Pは（→skill-p）"
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
    [[ "$output" == *"全NOT TRIGGER参照先が実在"* ]]
}

# SR-005: NOT TRIGGERの参照先スキルが存在しない → exit 2 (WARN)
@test "SR-005: NOT TRIGGER cross-ref to non-existent skill → WARN (exit 2)" {
    mkdir -p "$TEST_SKILLS_DIR/skill-with-bad-ref"
    cat > "$TEST_SKILLS_DIR/skill-with-bad-ref/SKILL.md" <<'EOF'
---
name: skill-with-bad-ref
description: |
  参照先不在スキル。
  TRIGGER: /skill-with-bad-ref、処理をして
  DO NOT TRIGGER: 別処理（→ghost-skill）
allowed-tools:
  - Bash
---

# skill-with-bad-ref
EOF
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ghost-skill"* ]]
    [[ "$output" == *"が不在"* ]]
}

# SR-008: スクリプトファイル名(→foo_bar.sh)は参照対象外 (偽陽性なし)
@test "SR-008: script file cross-ref (→foo_bar.sh) not mistaken for skill ref" {
    mkdir -p "$TEST_SKILLS_DIR/skill-with-script-ref"
    cat > "$TEST_SKILLS_DIR/skill-with-script-ref/SKILL.md" <<'EOF'
---
name: skill-with-script-ref
description: |
  スクリプト参照スキル。
  TRIGGER: /skill-with-script-ref、処理をして
  DO NOT TRIGGER: スクリプト処理（→deploy_task.sh）、パス参照（→outputs/analysis/）
allowed-tools:
  - Bash
---

# skill-with-script-ref
EOF
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    # deploy_task.sh と outputs/analysis/ は誤検出しないのでPASS
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
    [[ "$output" == *"全NOT TRIGGER参照先が実在"* ]]
}

# SR-004b: スラッシュコマンド名での参照 (→/skill-name) も実在確認
@test "SR-004b: NOT TRIGGER slash-command cross-ref (→/skill-name) to existing skill → PASS" {
    make_skill "target-skill" "ターゲット処理をして"
    mkdir -p "$TEST_SKILLS_DIR/source-skill"
    cat > "$TEST_SKILLS_DIR/source-skill/SKILL.md" <<'EOF'
---
name: source-skill
description: |
  参照元スキル。
  TRIGGER: /source-skill、ソース処理をして
  DO NOT TRIGGER: ターゲット処理（→/target-skill）
allowed-tools:
  - Bash
---

# source-skill
EOF
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
}

# ─── 空ディレクトリ ──────────────────────────────────────────

# SR-006: スキルディレクトリが空 → exit 0 (PASS, 0スキル)
@test "SR-006: empty skills dir → PASS (exit 0) with 0 skills" {
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"走査: 0スキル"* ]]
    [[ "$output" == *"総合判定: PASS"* ]]
}

# ─── フロントマター解析エラー ─────────────────────────────────

# SR-011: フロントマターなしのSKILL.md → exit 1 (FAIL)
@test "SR-011: SKILL.md without frontmatter → FAIL (exit 1)" {
    mkdir -p "$TEST_SKILLS_DIR/no-frontmatter-skill"
    cat > "$TEST_SKILLS_DIR/no-frontmatter-skill/SKILL.md" <<'EOF'
# No Frontmatter Skill

This skill has no YAML frontmatter at all.
EOF
    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"フロントマターなし"* ]]
    [[ "$output" == *"総合判定: FAIL"* ]]
}

# ─── 統合テスト ──────────────────────────────────────────────

# SR-007: 実スキルディレクトリ → FAILしない (exit 0 or 2)
@test "SR-007: real skills dir passes health check (no FAIL)" {
    local real_skills_dir="$HOME/.claude/skills"
    if [ ! -d "$real_skills_dir" ]; then
        # CI環境: ~/.claude/skills不在 → mockスキルで検証
        real_skills_dir="$TEST_TMPDIR/mock_skills_sr007"
        mkdir -p "$real_skills_dir/mock-ci-skill"
        cat > "$real_skills_dir/mock-ci-skill/SKILL.md" <<'SKILLEOF'
---
description: |
  Mock skill for CI gate validation.
  TRIGGER: /mock-ci-skill, mock ci skill
  DO NOT TRIGGER: unrelated tasks
---
# Mock CI Skill
CI environment test skill.
SKILLEOF
    fi
    run env SKILLS_DIR="$real_skills_dir" bash "$GATE"
    # exit 0=PASS or exit 2=WARN は許容。exit 1=FAIL はNG
    [ "$status" -ne 1 ] || {
        echo "FAIL detected in real skills:"
        echo "$output"
        return 1
    }
    [[ "$output" != *"総合判定: FAIL"* ]]
}

# SR-010: 実スキルのTRIGGERキーワードが抽出できる
@test "SR-010: real skill TRIGGER keywords are extractable" {
    local real_skills_dir="$HOME/.claude/skills"
    if [ ! -d "$real_skills_dir" ]; then
        # CI環境: ~/.claude/skills不在 → mockスキルで検証
        real_skills_dir="$TEST_TMPDIR/mock_skills_sr010"
        mkdir -p "$real_skills_dir/mock-ci-skill"
        cat > "$real_skills_dir/mock-ci-skill/SKILL.md" <<'SKILLEOF'
---
description: |
  Mock skill for CI TRIGGER extraction test.
  TRIGGER: /mock-ci-skill, mock ci skill
  DO NOT TRIGGER: unrelated tasks
---
# Mock CI Skill
CI environment test skill.
SKILLEOF
    fi
    local result
    result=$(SKILLS_DIR_FOR_TEST="$real_skills_dir" python3 - <<'PYEOF'
import os, re, sys

skills_dir = os.environ.get("SKILLS_DIR_FOR_TEST", os.path.expanduser("~/.claude/skills"))
total = 0
with_trigger = 0
for entry in os.scandir(skills_dir):
    if not entry.is_dir():
        continue
    sf = os.path.join(entry.path, "SKILL.md")
    if not os.path.isfile(sf):
        continue
    total += 1
    with open(sf, encoding="utf-8") as f:
        text = f.read()
    if re.search(r"TRIGGER\s*:", text, re.IGNORECASE):
        with_trigger += 1
print(f"{with_trigger}/{total}")
PYEOF
    )
    local with_trigger="${result%%/*}"
    local total="${result##*/}"
    [ "$total" -gt 0 ]       # スキルが1件以上ある
    [ "$with_trigger" -gt 0 ]  # TRIGGER定義ありが1件以上ある
}
