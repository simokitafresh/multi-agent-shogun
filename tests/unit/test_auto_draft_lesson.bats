#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_AUTO_DRAFT="$PROJECT_ROOT/scripts/auto_draft_lesson.sh"
    [ -f "$SRC_AUTO_DRAFT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/auto_draft_lesson.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export EXT_PROJECT="$TEST_TMPDIR/extproj"

    mkdir -p \
        "$TEST_PROJECT/scripts" \
        "$TEST_PROJECT/config" \
        "$EXT_PROJECT/tasks"

    cp "$SRC_AUTO_DRAFT" "$TEST_PROJECT/scripts/auto_draft_lesson.sh"
    chmod +x "$TEST_PROJECT/scripts/auto_draft_lesson.sh"

    cat > "$TEST_PROJECT/config/projects.yaml" <<EOF
projects:
  - id: testproj
    path: $EXT_PROJECT
EOF

    cat > "$EXT_PROJECT/tasks/lessons.md" <<'EOF'
---
title: Test Lessons
---
EOF

    cat > "$TEST_PROJECT/scripts/lesson_write.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$TEST_TMPDIR/lesson_write_args.txt"
cmd_id="${6:-}"
if [ -n "$cmd_id" ]; then
    mkdir -p "$TEST_PROJECT/queue/gates/$cmd_id"
    {
        echo "timestamp: test"
        echo "source: lesson_write"
    } > "$TEST_PROJECT/queue/gates/$cmd_id/lesson.done"
fi
EOF
    chmod +x "$TEST_PROJECT/scripts/lesson_write.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

run_auto_draft() {
    cd "$TEST_PROJECT"
    local patched="$TEST_TMPDIR/auto_draft_lesson_patched.sh"
    sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEST_PROJECT\"|" "$TEST_PROJECT/scripts/auto_draft_lesson.sh" > "$patched"
    chmod +x "$patched"
    run bash "$patched" "$@"
}

@test "registers found lesson candidates as draft for later review" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_123
worker_id: hayate
lesson_candidate:
  found: true
  project: testproj
  title: draft registration
  detail: auto_draft should enqueue this as a draft lesson for review.
EOF

    run_auto_draft "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Registering draft lesson"* ]]
    [[ "$output" == *"Draft lesson registered successfully"* ]]

    run grep -Fx -- "--status" "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]

    run grep -Fx -- "draft" "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]

    run grep -Fx -- "cmd_123" "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]

    run sed -n '6p' "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [ ! -f "$TEST_PROJECT/queue/gates/cmd_123/lesson.done" ]
}

@test "not_found skip creates lesson.done with auto_draft_skip reason" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_123
worker_id: hayate
lesson_candidate:
  found: false
  no_lesson_reason: existing lesson covered this task.
EOF

    run_auto_draft "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped: not_found"* ]]
    [ ! -f "$TEST_TMPDIR/lesson_write_args.txt" ]

    [ -f "$TEST_PROJECT/queue/gates/cmd_123/lesson.done" ]
    run grep -Fx -- "source: auto_draft_skip" "$TEST_PROJECT/queue/gates/cmd_123/lesson.done"
    [ "$status" -eq 0 ]
    run grep -Fx -- "reason: not_found" "$TEST_PROJECT/queue/gates/cmd_123/lesson.done"
    [ "$status" -eq 0 ]
}

@test "validation skip creates lesson.done with extracted skip reason" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_123
worker_id: hayate
lesson_candidate:
  found: true
  project: testproj
  title: missing detail
  detail: ""
EOF

    run_auto_draft "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped: no_title_or_detail"* ]]
    [ ! -f "$TEST_TMPDIR/lesson_write_args.txt" ]

    [ -f "$TEST_PROJECT/queue/gates/cmd_123/lesson.done" ]
    run grep -Fx -- "source: auto_draft_skip" "$TEST_PROJECT/queue/gates/cmd_123/lesson.done"
    [ "$status" -eq 0 ]
    run grep -Fx -- "reason: no_title_or_detail" "$TEST_PROJECT/queue/gates/cmd_123/lesson.done"
    [ "$status" -eq 0 ]
}

@test "duplicate lesson candidates create lesson.done as already registered" {
    cat > "$EXT_PROJECT/tasks/lessons.md" <<'EOF'
---
title: Test Lessons
---
### L001: draft registration
**出典**: cmd_123
EOF

    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
parent_cmd: cmd_123
worker_id: hayate
lesson_candidate:
  found: true
  project: testproj
  title: draft registration
  detail: auto_draft should detect this duplicate lesson for review.
EOF

    run_auto_draft "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Duplicate found"* ]]
    [ ! -f "$TEST_TMPDIR/lesson_write_args.txt" ]

    [ -f "$TEST_PROJECT/queue/gates/cmd_123/lesson.done" ]
    run grep -Fx -- "source: lesson_write" "$TEST_PROJECT/queue/gates/cmd_123/lesson.done"
    [ "$status" -eq 0 ]
}
