#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_lesson_health.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_lesson_health.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" \
             "$TEST_TMPDIR/config" \
             "$TEST_TMPDIR/context" \
             "$TEST_TMPDIR/projects/infra" \
             "$TEST_TMPDIR/tasks" \
             "$TEST_TMPDIR/logs" \
             "$TEST_TMPDIR/queue"

    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"
    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_lesson_health.sh"

    cat > "$TEST_TMPDIR/config/projects.yaml" <<'EOF'
projects:
  - id: infra
    path: "/tmp/test-project"
    context_file: "context/infrastructure.md"
    status: active
EOF

    cat > "$TEST_TMPDIR/context/infrastructure.md" <<'EOF'
<!-- last_synced_lesson: L001 -->

## 教訓索引（自動追記）
- L001 sample
EOF

    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: sample
  summary: sample
EOF

    cat > "$TEST_TMPDIR/tasks/lessons.md" <<'EOF'
# lessons

## L001
sample
EOF

    cat > "$TEST_TMPDIR/logs/lesson_impact.tsv" <<'EOF'
timestamp	cmd_id	lesson_id	action	result	referenced	project	extra
2026-04-24T00:00:00	cmd_1	L001	injected		true	infra	-
EOF
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "gate_lesson_health reports OK when SSOT has no conflict markers" {
    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: infra SSOT conflict markersなし"* ]]
    [[ "$output" == *"OK: infraのlesson統合状況は健全"* ]]
}

@test "gate_lesson_health warns and reports fill rate when lessons miss when/how" {
    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: infra when/how充足率: when=0/1(0.0%) how=0/1(0.0%)"* ]]
    [[ "$output" == *"WARN: infra when/how欠落教訓あり(when欠落:1, how欠落:1, total:1)"* ]]
}

@test "gate_lesson_health reports full when/how coverage" {
    cat > "$TEST_TMPDIR/projects/infra/lessons.yaml" <<EOF
ssot_path: $TEST_TMPDIR/tasks/lessons.md
last_synced: '2026-04-24T00:00:00'
archive_path: $TEST_TMPDIR/projects/infra/lessons_archive.yaml
lesson_count: 1
lessons:
- id: L001
  title: sample
  summary: sample
  when: 同種条件
  how: 実行手順
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: infra when/how充足率: when=1/1(100.0%) how=1/1(100.0%)"* ]]
    [[ "$output" != *"when/how欠落教訓あり"* ]]
}

@test "gate_lesson_health alerts when SSOT contains git conflict markers" {
    cat > "$TEST_TMPDIR/tasks/lessons.md" <<'EOF'
# lessons
<<<<<<< Updated upstream
alpha
=======
beta
>>>>>>> Stashed changes
EOF

    run bash "$TEST_GATE" infra
    [ "$status" -eq 1 ]
    [[ "$output" == *"ALERT: infra SSOTにgit conflict markers検出"* ]]
    [[ "$output" == *"tasks/lessons.md:2:<<<<<<< Updated upstream"* ]]
    [[ "$output" == *"tasks/lessons.md:4:======="* ]]
    [[ "$output" == *"tasks/lessons.md:6:>>>>>>> Stashed changes"* ]]
}
