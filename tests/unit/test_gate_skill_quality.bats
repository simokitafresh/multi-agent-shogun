#!/usr/bin/env bats
# test_gate_skill_quality.bats — gate_skill_quality.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_skill_quality.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_quality.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/skills"
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_skill_quality.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_skill_quality.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_skill_quality.sh"
    export TEST_SKILLS_DIR="$TEST_TMPDIR/skills"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "all checks pass → exit 0" {
    mkdir -p "$TEST_SKILLS_DIR/good-skill"
    cat > "$TEST_SKILLS_DIR/good-skill/SKILL.md" <<'EOF'
---
description: "What: 整理する。When: 定期的に使う。NOT When: 単発確認ではない。"
allowed-tools:
  - Read
  - Bash
---

# Good Skill
EOF

    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== good-skill ==="* ]]
    [[ "$output" == *"総合判定: OK"* ]]
}

@test "missing allowed-tools only → WARN exit 2" {
    mkdir -p "$TEST_SKILLS_DIR/warn-skill"
    cat > "$TEST_SKILLS_DIR/warn-skill/SKILL.md" <<'EOF'
---
description: "What: 計測する。When: 繰り返し時に使用。NOT When: 常時起動ではない。"
---

# Warn Skill
EOF

    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN: (5) allowed-tools が未定義"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "description missing → FAIL exit 1" {
    mkdir -p "$TEST_SKILLS_DIR/fail-skill"
    cat > "$TEST_SKILLS_DIR/fail-skill/SKILL.md" <<'EOF'
---
allowed-tools:
  - Read
---

# Fail Skill
EOF

    run env SKILLS_DIR="$TEST_SKILLS_DIR" bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL: (1) description が見つかりません"* ]]
    [[ "$output" == *"総合判定: FAIL"* ]]
}
