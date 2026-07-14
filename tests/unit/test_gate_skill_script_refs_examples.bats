#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE="$PROJECT_ROOT/scripts/gates/gate_skill_script_refs.sh"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/skill_refs_examples.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/skills/demo" "$TEST_TMPDIR/logs"
    cp "$SRC_GATE" "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_skill_script_refs.sh"
    export TEST_LOG="$TEST_TMPDIR/logs/gate_fire_log.yaml"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "db-check old example path is detected and logged" {
    cat > "$TEST_TMPDIR/skills/demo/SKILL.md" <<'EOF'
---
description: demo
---
```bash
python3 scripts/db_capability_launcher.py --credential-file /protected/path/dm-signal-db.env
```
EOF
    touch "$TEST_TMPDIR/scripts/db_capability_launcher.py"

    run env SKILL_REF_DISABLE_CACHE=1 GATE_FIRE_LOG_FILE="$TEST_LOG" bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"例示コードブロック内パス不在"* ]]
    [[ "$output" == *"/protected/path/dm-signal-db.env"* ]]
    grep -q 'gate: "skill_script_refs"' "$TEST_LOG"
    grep -q 'example_path_missing=1' "$TEST_LOG"
}

@test "template and runtime paths are excluded while an existing static path passes" {
    mkdir -p "$TEST_TMPDIR/scripts/tools"
    touch "$TEST_TMPDIR/scripts/tools/run.sh"
    cat > "$TEST_TMPDIR/skills/demo/SKILL.md" <<'EOF'
---
description: demo
---
```bash
bash scripts/tools/run.sh /tmp/dm-signal-db-$(date +%s).env <project>/YYYYMMDD.json
```
EOF

    run env SKILL_REF_DISABLE_CACHE=1 GATE_FIRE_LOG_FILE="$TEST_LOG" bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"総合判定: PASS"* ]]
    [ ! -e "$TEST_LOG" ]
}

@test "declared side-effect example requires dated execution marker" {
    cat > "$TEST_TMPDIR/skills/demo/SKILL.md" <<'EOF'
---
description: demo
---
<!-- example_side_effect: true -->
```bash
echo deploy
```
EOF

    run env SKILL_REF_DISABLE_CACHE=1 GATE_FIRE_LOG_FILE="$TEST_LOG" bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 2 ]
    [[ "$output" == *"副作用例示の実走検証マーカー不在"* ]]

    sed -i '/example_side_effect/a <!-- example_execution_verified_at: 2026-07-15T03:10:00+09:00 -->' "$TEST_TMPDIR/skills/demo/SKILL.md"
    run env SKILL_REF_DISABLE_CACHE=1 GATE_FIRE_LOG_FILE="$TEST_LOG" bash "$TEST_GATE" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
}
