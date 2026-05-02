#!/usr/bin/env bats
# test_gate_skill_script_refs.bats — gate_skill_script_refs.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_skill_script_refs.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_script_refs.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/skills/demo-skill" "$TEST_TMPDIR/scripts/tools"
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "existing script reference with newer SKILL.md passes" {
    cat > "$TEST_TMPDIR/scripts/tools/run_demo.sh" <<'EOF'
#!/usr/bin/env bash
echo demo
EOF
    sleep 1
    cat > "$TEST_TMPDIR/skills/demo-skill/SKILL.md" <<'EOF'
---
description: "Demo skill"
---

# Demo

Run `bash scripts/tools/run_demo.sh`.
EOF

    run bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"script参照 1件"* ]]
    [[ "$output" == *"全script参照先が実在"* ]]
    [[ "$output" == *"総合判定: PASS"* ]]
}

@test "missing script reference warns" {
    cat > "$TEST_TMPDIR/skills/demo-skill/SKILL.md" <<'EOF'
---
description: "Demo skill"
---

# Demo

Run `bash scripts/tools/missing.sh`.
EOF

    run bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"参照先不在"* ]]
    [[ "$output" == *"scripts/tools/missing.sh"* ]]
    [[ "$output" == *"総合判定: WARN"* ]]
}

@test "script newer than SKILL.md is listed as update candidate" {
    cat > "$TEST_TMPDIR/skills/demo-skill/SKILL.md" <<'EOF'
---
description: "Demo skill"
---

# Demo

Run `bash scripts/tools/run_demo.sh`.
EOF
    sleep 1
    cat > "$TEST_TMPDIR/scripts/tools/run_demo.sh" <<'EOF'
#!/usr/bin/env bash
echo changed
EOF

    run bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"要更新スキル一覧"* ]]
    [[ "$output" == *"skills/demo-skill/SKILL.md"* ]]
    [[ "$output" == *"scripts/tools/run_demo.sh"* ]]
}
