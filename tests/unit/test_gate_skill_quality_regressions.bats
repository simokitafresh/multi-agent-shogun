#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    GATE="$PROJECT_ROOT/scripts/gates/gate_skill_quality.sh"
    HEALTH_GATE="$PROJECT_ROOT/scripts/gates/gate_skill_health.sh"
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/skill-quality-regression.XXXXXX")"
    mkdir -p "$TEST_ROOT/skills"
}

@test "blank lines in block description do not hide TRIGGER from quality or health gates" {
    mkdir -p "$TEST_ROOT/skills/demo"
    cat > "$TEST_ROOT/skills/demo/SKILL.md" <<'EOF'
---
name: demo
description: |
  Search tool for current documentation.

  TRIGGER: /demo、documentation search

  DO NOT TRIGGER: local source-only inspection
allowed-tools:
  - Read
---
EOF

    run env SKILLS_DIR="$TEST_ROOT/skills" bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"What+When+NOT When 3/3"* ]]

    run env SKILL_HEALTH_DISABLE_CACHE=1 SKILLS_DIR="$TEST_ROOT/skills" bash "$HEALTH_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
}

teardown() {
    rm -r -- "$TEST_ROOT"
}

@test "HTML script-ref marker is not an angle-placeholder violation and English tool states What" {
    mkdir -p "$TEST_ROOT/skills/demo"
    cat > "$TEST_ROOT/skills/demo/SKILL.md" <<'EOF'
---
<!-- script_refs_checked_at: 2026-07-15T12:14:00+09:00 -->
name: demo
description: |
  Search tool for current documentation.
  TRIGGER: /demo、documentation search
  DO NOT TRIGGER: local source-only inspection
allowed-tools:
  - Read
---
EOF

    run env SKILLS_DIR="$TEST_ROOT/skills" bash "$GATE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"What+When+NOT When 3/3"* ]]
    [[ "$output" == *"フロントマターに < > なし"* ]]
}

@test "real angle placeholder remains fail-closed" {
    mkdir -p "$TEST_ROOT/skills/demo"
    cat > "$TEST_ROOT/skills/demo/SKILL.md" <<'EOF'
---
name: demo
argument-hint: "<name>"
description: |
  Search tool for current documentation.
  TRIGGER: /demo、documentation search
  DO NOT TRIGGER: local source-only inspection
allowed-tools:
  - Read
---
EOF

    run env SKILLS_DIR="$TEST_ROOT/skills" bash "$GATE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL: (4) フロントマターに < > を検出"* ]]
}
