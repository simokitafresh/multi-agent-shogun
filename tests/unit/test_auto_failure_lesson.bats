#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_AUTO_FAILURE="$PROJECT_ROOT/scripts/auto_failure_lesson.sh"
    [ -f "$SRC_AUTO_FAILURE" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/auto_failure_lesson.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"

    mkdir -p "$TEST_PROJECT/scripts" "$TEST_PROJECT/queue"

    cp "$SRC_AUTO_FAILURE" "$TEST_PROJECT/scripts/auto_failure_lesson.sh"
    chmod +x "$TEST_PROJECT/scripts/auto_failure_lesson.sh"

    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'EOF'
commands:
  - id: cmd_123
    project: testproj
EOF

    cat > "$TEST_PROJECT/scripts/lesson_write.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$TEST_TMPDIR/lesson_write_args.txt"
EOF
    chmod +x "$TEST_PROJECT/scripts/lesson_write.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

run_auto_failure() {
    cd "$TEST_PROJECT"
    local patched="$TEST_TMPDIR/auto_failure_lesson_patched.sh"
    sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$TEST_PROJECT\"|" "$TEST_PROJECT/scripts/auto_failure_lesson.sh" > "$patched"
    chmod +x "$patched"
    run bash "$patched" "$@"
}

@test "registers failed reports as confirmed lessons" {
    local report="$TEST_TMPDIR/report.yaml"
    cat > "$report" <<'EOF'
status: failed
task_id: task_abc
parent_cmd: cmd_123
worker_id: saizo
result:
  summary: acceptance criteria was not met
failure_analysis:
  root_cause: missing verification
  what_would_prevent: run the exact check before reporting
EOF

    run_auto_failure "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Registering confirmed lesson"* ]]
    [[ "$output" == *"Confirmed lesson registered successfully"* ]]

    run grep -Fx -- "--status" "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]

    run grep -Fx -- "confirmed" "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]

    run grep -Fx -- "cmd_123" "$TEST_TMPDIR/lesson_write_args.txt"
    [ "$status" -eq 0 ]
}
