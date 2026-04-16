#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LESSON_HARVEST_SCRIPT="$PROJECT_ROOT/scripts/lesson_harvest.sh"
    [ -f "$LESSON_HARVEST_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    command -v rg >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/lesson_harvest_repo"
    export TEST_ARCHIVE="$TEST_ROOT/queue/archive/reports"
    export TEST_PROJECTS="$TEST_ROOT/projects"

    mkdir -p "$TEST_ARCHIVE" "$TEST_PROJECTS/app"

    cat > "$TEST_PROJECTS/app/lessons.yaml" <<'EOF'
lessons:
  - id: L001
    title: registered title
EOF

    cat > "$TEST_PROJECTS/app/lessons_archive.yaml" <<'EOF'
lessons:
  - id: L900
    title: archived title
EOF
}

run_harvest() {
    LESSON_HARVEST_REPO_ROOT="$TEST_ROOT" \
    run bash "$LESSON_HARVEST_SCRIPT"
}

@test "lists only unregistered lesson candidates from archived reports" {
    cat > "$TEST_ARCHIVE/hayate_report_cmd_501.yaml" <<'EOF'
worker_id: hayate
task_id: cmd_501_impl
parent_cmd: cmd_501
lesson_candidate:
  found: true
  title: new title
  detail: fresh lesson candidate detail
skill_candidate:
  found: false
EOF

    cat > "$TEST_ARCHIVE/hanzo_report_cmd_502.yaml" <<'EOF'
worker_id: hanzo
task_id: cmd_502_impl
parent_cmd: cmd_502
lesson_candidate:
  found: true
  title: registered title
  detail: should be filtered because already registered
decision_candidate:
  found: false
EOF

    cat > "$TEST_ARCHIVE/saizo_report_cmd_503.yaml" <<'EOF'
worker_id: saizo
task_id: cmd_503_impl
parent_cmd: cmd_503
lesson_candidate:
  found: false
  title: ignored title
  detail: ignored detail
EOF

    cat > "$TEST_ARCHIVE/not_a_report.yaml" <<'EOF'
worker_id: kotaro
lesson_candidate:
  found: true
  title: should not be scanned
  detail: filename does not match report archive pattern
EOF

    run_harvest
    [ "$status" -eq 0 ]
    [[ "$output" == *"未登録候補: 1件"* ]]
    [[ "$output" == *"cmd_501 | hayate | new title | fresh lesson candidate detail"* ]]
    [[ "$output" != *"registered title"* ]]
    [[ "$output" != *"should not be scanned"* ]]
}

@test "falls back to YAML load for block scalar lesson detail" {
    cat > "$TEST_ARCHIVE/kagemaru_report_task_900.yaml" <<'EOF'
worker_id: kagemaru
task_id: task_900
lesson_candidate:
  found: true
  title: block scalar title
  detail: |
    first line of detail
    second line of detail
skill_candidate:
  found: false
EOF

    run_harvest
    [ "$status" -eq 0 ]
    [[ "$output" == *"未登録候補: 1件"* ]]
    [[ "$output" == *"task_900 | kagemaru | block scalar title | first line of detail second line of detail"* ]]
}
