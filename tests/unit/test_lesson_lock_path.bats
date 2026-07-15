#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/scripts/gates" "$TEST_ROOT/projects/infra" "$TEST_ROOT/projects/testproj" "$TEST_ROOT/config" "$TEST_ROOT/ext/tasks"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$TEST_ROOT/scripts/lib/lock_path.sh"
    cp "$PROJECT_ROOT/scripts/gates/lesson_context_routes.sh" "$TEST_ROOT/scripts/gates/lesson_context_routes.sh"
    cp "$PROJECT_ROOT/scripts/lesson_write.sh" "$TEST_ROOT/scripts/lesson_write.sh"
    cp "$PROJECT_ROOT/scripts/lesson_write_karo.sh" "$TEST_ROOT/scripts/lesson_write_karo.sh"
    cp "$PROJECT_ROOT/scripts/lesson_write_shogun.sh" "$TEST_ROOT/scripts/lesson_write_shogun.sh"
    chmod +x "$TEST_ROOT/scripts/"*.sh
    printf '#!/bin/bash\nexit 0\n' > "$TEST_ROOT/scripts/sync_lessons.sh"
    chmod +x "$TEST_ROOT/scripts/sync_lessons.sh"

    cat > "$TEST_ROOT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: "$TEST_ROOT/ext"
    context_file: context/test.md
EOF

    cat > "$TEST_ROOT/projects/infra/lessons_karo.yaml" <<'EOF'
lessons:
- id: 'LK001'
  title: 'existing karo lesson'
  origin: '[[cmd_001]]'
  detail: 'existing detail for tests'
  source_cmd: 'cmd_001'
  when: 'existing'
  how: 'existing'
  created_at: '2026-01-01'
EOF

    cat > "$TEST_ROOT/projects/infra/lessons_shogun.yaml" <<'EOF'
lessons:
- id: 'LS001'
  title: 'existing shogun lesson'
  origin: '[[cmd_001]]'
  detail: 'existing incident detail with cause and fix for tests'
  source_cmd: 'cmd_001'
  created_at: '2026-01-01'
  automated: false
  enforcement: '未自動化'
EOF

    cat > "$TEST_ROOT/projects/testproj/lessons.yaml" <<'EOF'
lessons:
- id: L001
  title: existing project lesson
  summary: existing summary
EOF
}

hold_lock_for() {
    local target="$1"
    local seconds="$2"
    local lock_file
    lock_file="$(bash -c "source '$TEST_ROOT/scripts/lib/lock_path.sh'; lock_path '$target'")"
    (
        exec 209>"$lock_file"
        flock -x 209
        : > "$BATS_TEST_TMPDIR/lock-held"
        sleep "$seconds"
    ) &
    export LOCK_HOLDER_PID=$!
    for _ in {1..50}; do
        [ -f "$BATS_TEST_TMPDIR/lock-held" ] && return 0
        sleep 0.02
    done
    return 1
}

teardown() {
    if [ -n "${LOCK_HOLDER_PID:-}" ]; then
        wait "$LOCK_HOLDER_PID" 2>/dev/null || true
    fi
}

@test "lesson_write_karo waits on shared lock_path lock" {
    hold_lock_for "$TEST_ROOT/projects/infra/lessons_karo.yaml" 1
    start=$(date +%s)

    run bash "$TEST_ROOT/scripts/lesson_write_karo.sh" \
        "shared lock karo" \
        "shared lock path blocks concurrent karo lesson writes" \
        "cmd_3732" \
        --origin "[[cmd_3732]] -> [[lock_path]] -> [[karo_lesson_write]]"

    elapsed=$(( $(date +%s) - start ))
    [ "$status" -eq 0 ]
    [ "$elapsed" -ge 1 ]
    [[ "$output" == *"LK002 added"* ]]
}

@test "lesson_write_karo merges into an existing lesson at the 35-entry capacity" {
    for i in $(seq 2 35); do
        printf -- "- id: 'LK%03d'\n  title: 'capacity %03d'\n  detail: 'capacity detail %03d'\n" "$i" "$i" "$i" >> "$TEST_ROOT/projects/infra/lessons_karo.yaml"
    done

    run bash "$TEST_ROOT/scripts/lesson_write_karo.sh" \
        "selected PASS is not full-unit PASS" \
        "selected and full-unit stages must be counted separately; 83 of 83 regression checks passed" \
        "cmd_ga263" \
        --origin "[[GA-263]] -> [[selected-pass-full-unit-fail]] -> [[fixture-isolation]]" \
        --merge-into LK001

    [ "$status" -eq 0 ]
    [[ "$output" == *"LK001 merged"* ]]
    grep -q '^  detail: |$' "$TEST_ROOT/projects/infra/lessons_karo.yaml"
    run python3 - "$TEST_ROOT/projects/infra/lessons_karo.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
assert len(data["lessons"]) == 35
lesson = next(item for item in data["lessons"] if item["id"] == "LK001")
assert "existing detail for tests" in lesson["detail"]
assert "83 of 83 regression checks passed" in lesson["detail"]
assert "[[GA-263]] -> [[selected-pass-full-unit-fail]] -> [[fixture-isolation]]" in lesson["detail"]
PY
    [ "$status" -eq 0 ]
}

@test "lesson_write_karo missing merge target fails without changing the ledger" {
    before=$(sha256sum "$TEST_ROOT/projects/infra/lessons_karo.yaml")

    run bash "$TEST_ROOT/scripts/lesson_write_karo.sh" \
        "missing merge target" \
        "this detail must never be published to the role lesson ledger" \
        "cmd_ga263" \
        --merge-into LK999

    [ "$status" -ne 0 ]
    [[ "$output" == *"target must exist exactly once"* ]]
    [[ "$output" != *"Lock timeout"* ]]
    after=$(sha256sum "$TEST_ROOT/projects/infra/lessons_karo.yaml")
    [ "$before" = "$after" ]
}

@test "lesson_write_shogun waits on shared lock_path lock" {
    hold_lock_for "$TEST_ROOT/projects/infra/lessons_shogun.yaml" 1
    start=$(date +%s)

    run bash "$TEST_ROOT/scripts/lesson_write_shogun.sh" \
        "shared lock shogun" \
        "shared lock path blocks concurrent shogun lesson writes and preserves atomic append behavior" \
        "cmd_3732" \
        "type=gate; file=tests/unit/test_lesson_lock_path.bats; pattern=shared_lock" \
        "[[cmd_3732]] -> [[lock_path]] -> [[shogun_lesson_write]]"

    elapsed=$(( $(date +%s) - start ))
    [ "$status" -eq 0 ]
    [ "$elapsed" -ge 1 ]
    [[ "$output" == *"LS002 added"* ]]
}

@test "project YAML fallback waits on shared lock_path lock" {
    hold_lock_for "$TEST_ROOT/projects/testproj/lessons.yaml" 1
    start=$(date +%s)

    LESSON_WRITE_SCRIPT_DIR="$TEST_ROOT" run bash "$TEST_ROOT/scripts/lesson_write.sh" \
        "testproj" \
        "shared lock project yaml" \
        "shared lock path blocks project YAML fallback writes" \
        "cmd_3732" \
        "hanzo" \
        "" \
        --origin "[[cmd_3732]] -> [[lock_path]] -> [[project_lesson_yaml]]"

    elapsed=$(( $(date +%s) - start ))
    [ "$status" -eq 0 ]
    [ "$elapsed" -ge 1 ]
    [[ "$output" == *"L002 added"* ]]
}
