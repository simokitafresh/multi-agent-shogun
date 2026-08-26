#!/usr/bin/env bats
# Purpose: report_field_set.sh verdict書込み時のstatus自動完了

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export RFS="$PROJECT_ROOT/scripts/report_field_set.sh"
    [ -f "$RFS" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/rfs_verdict_status.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/queue/tasks"
    export TEST_REPORT="$TEST_TMPDIR/queue/reports/kagemaru_report_cmd_test.yaml"
    cat > "$TEST_REPORT" <<'EOF'
worker_id: kagemaru
parent_cmd: cmd_test
ac_version_read: abc12345
status: pending
result:
  summary: done
lesson_candidate:
  found: false
  no_lesson_reason: covered by existing test
lessons_useful:
  - id: L001
    useful: true
    reason: used
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
verdict: ""
EOF
    cat > "$TEST_TMPDIR/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  related_lessons:
    - id: L001
YAML
}

_write_required_variation_task() {
    cat > "$TEST_TMPDIR/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  variation_checks_required: true
  related_lessons:
    - id: L001
YAML
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

_field() {
    python3 - "$TEST_REPORT" "$1" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
cur = data
for part in sys.argv[2].split('.'):
    cur = cur[part]
print(cur)
PY
}

@test "verdict PASS書込み成功後にstatus completedへ自動設定される" {
    run bash "$RFS" "$TEST_REPORT" verdict PASS
    [ "$status" -eq 0 ]
    [[ "$output" == *"status = completed (auto after verdict)"* ]]

    run _field status
    [ "$status" -eq 0 ]
    [ "$output" = "completed" ]
}

# test_necessity: explicit task-root overrides must win while the default remains fixture-local.
@test "verdict status自動完了は再帰呼び出しではなく同一処理内で行う" {
    run grep -F 'bash "$0" "$REPORT_PATH" status completed' "$RFS"
    [ "$status" -ne 0 ]

    mkdir -p "$TEST_TMPDIR/explicit-root/queue/tasks"
    cat > "$TEST_TMPDIR/explicit-root/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  related_lessons:
    - id: L999
YAML
    run env REPORT_FIELD_SET_TASK_ROOT="$TEST_TMPDIR/explicit-root" \
        bash "$RFS" "$TEST_REPORT" verdict PASS
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISMATCH"*"extra=L001"* ]]

    cat > "$TEST_TMPDIR/explicit-task.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  related_lessons:
    - id: L998
YAML
    run env RFS_TASK_FILE_PATH="$TEST_TMPDIR/explicit-task.yaml" \
        bash "$RFS" "$TEST_REPORT" verdict PASS
    [ "$status" -eq 1 ]
    [[ "$output" == *"MISMATCH"*"extra=L001"* ]]

    run bash "$RFS" "$TEST_REPORT" verdict PASS
    [ "$status" -eq 0 ]
    [[ "$output" == *"[report_field_set] verdict = PASS"* ]]
    [[ "$output" == *"[report_field_set] status = completed (auto after verdict)"* ]]

    run python3 - "$TEST_REPORT" <<'PY'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
print(f"{data.get('verdict')} {data.get('status')}")
PY
    [ "$status" -eq 0 ]
    [ "$output" = "PASS completed" ]
}

@test "verdict FAIL書込み成功後にstatus failedへ自動設定される" {
    run bash "$RFS" "$TEST_REPORT" verdict FAIL
    [ "$status" -eq 0 ]

    run _field status
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
}

@test "verdict PASS_NO_IMPROVEMENT書込み成功後にstatus completedへ自動設定される" {
    run bash "$RFS" "$TEST_REPORT" verdict PASS_NO_IMPROVEMENT
    [ "$status" -eq 0 ]

    run _field status
    [ "$status" -eq 0 ]
    [ "$output" = "completed" ]
}

@test "verdict空文字書込みではstatusは変更されない" {
    run bash "$RFS" "$TEST_REPORT" verdict ""
    [ "$status" -eq 0 ]

    run _field status
    [ "$status" -eq 0 ]
    [ "$output" = "pending" ]
}

@test "required variation 5項目が空ならverdict自動完了と直接completedをBLOCK" {
    _write_required_variation_task
    cat >> "$TEST_REPORT" <<'YAML'
variation_checks:
  normal_pass: {check: normal, result: ""}
  quoted_or_heredoc: {check: quoted, result: ""}
  linked_worktree: {check: worktree, result: ""}
  parallel_or_respawn: {check: parallel, result: ""}
  abnormal_exit: {check: abnormal, result: ""}
YAML

    run bash "$RFS" "$TEST_REPORT" verdict PASS
    [ "$status" -eq 1 ]
    [[ "$output" == *"variation_checks_required=true"* ]]
    [ "$(_field status)" = "pending" ]

    run bash "$RFS" "$TEST_REPORT" status completed
    [ "$status" -eq 1 ]
    [[ "$output" == *"variation_checks_required=true"* ]]
    [ "$(_field status)" = "pending" ]
}

@test "required variation 5項目がyes/noならverdict自動完了を許可" {
    _write_required_variation_task
    cat >> "$TEST_REPORT" <<'YAML'
variation_checks:
  normal_pass: {check: normal, result: yes}
  quoted_or_heredoc: {check: quoted, result: no}
  linked_worktree: {check: worktree, result: yes}
  parallel_or_respawn: {check: parallel, result: no}
  abnormal_exit: {check: abnormal, result: yes}
YAML

    run bash "$RFS" "$TEST_REPORT" verdict PASS
    [ "$status" -eq 0 ]
    [ "$(_field status)" = "completed" ]
}
