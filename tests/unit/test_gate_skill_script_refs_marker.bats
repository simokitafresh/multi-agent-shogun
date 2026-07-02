#!/usr/bin/env bats
# gate_skill_script_refs.sh marker behavior

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_skill_script_refs.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_script_refs_marker.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts/tools" "$TEST_TMPDIR/skills/demo-skill"
    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "script_refs_checked_at marker is used instead of SKILL.md mtime" {
    cat > "$TEST_TMPDIR/scripts/tools/run_demo.sh" <<'EOF'
#!/usr/bin/env bash
echo changed
EOF
    cat > "$TEST_TMPDIR/skills/demo-skill/SKILL.md" <<'EOF'
---
description: "Demo skill"
---
<!-- script_refs_checked_at: 2026-01-01T00:00:10+00:00 -->

# Demo

Run `bash scripts/tools/run_demo.sh`.
EOF
    touch -d '2026-01-01 00:00:00 UTC' "$TEST_TMPDIR/skills/demo-skill/SKILL.md"
    touch -d '2026-01-01 00:00:03 UTC' "$TEST_TMPDIR/scripts/tools/run_demo.sh"

    run env SKILL_REF_DISABLE_CACHE=1 bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
}

@test "newest of multiple script_refs_checked_at markers wins (prepend convention leaves old markers at bottom)" {
    cat > "$TEST_TMPDIR/scripts/tools/run_demo.sh" <<'EOF'
#!/usr/bin/env bash
echo changed
EOF
    cat > "$TEST_TMPDIR/skills/demo-skill/SKILL.md" <<'EOF'
---
description: "Demo skill"
---
<!-- script_refs_checked_at: 2026-01-01T00:00:10+00:00 -->

# Demo

Run `bash scripts/tools/run_demo.sh`.

<!-- script_refs_checked_at: 2026-01-01T00:00:01+00:00 -->
EOF
    touch -d '2026-01-01 00:00:00 UTC' "$TEST_TMPDIR/skills/demo-skill/SKILL.md"
    touch -d '2026-01-01 00:00:03 UTC' "$TEST_TMPDIR/scripts/tools/run_demo.sh"

    run env SKILL_REF_DISABLE_CACHE=1 bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
}

@test "missing script_refs_checked_at marker keeps legacy SKILL.md mtime comparison" {
    cat > "$TEST_TMPDIR/scripts/tools/run_demo.sh" <<'EOF'
#!/usr/bin/env bash
echo changed
EOF
    cat > "$TEST_TMPDIR/skills/demo-skill/SKILL.md" <<'EOF'
---
description: "Demo skill"
---

# Demo

Run `bash scripts/tools/run_demo.sh`.
EOF
    touch -d '2026-01-01 00:00:00 UTC' "$TEST_TMPDIR/skills/demo-skill/SKILL.md"
    touch -d '2026-01-01 00:00:03 UTC' "$TEST_TMPDIR/scripts/tools/run_demo.sh"

    run env SKILL_REF_DISABLE_CACHE=1 bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"要更新スキル一覧"* ]]
    [[ "$output" == *"skills/demo-skill/SKILL.md"* ]]
}
