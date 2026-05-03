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
    export TEST_REPORT="$TEST_TMPDIR/kagemaru_report_cmd_test.yaml"
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

@test "verdict status自動完了は再帰呼び出しではなく同一処理内で行う" {
    run grep -F 'bash "$0" "$REPORT_PATH" status completed' "$RFS"
    [ "$status" -ne 0 ]

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

@test "verdict FAIL書込み成功後にstatus completedへ自動設定される" {
    run bash "$RFS" "$TEST_REPORT" verdict FAIL
    [ "$status" -eq 0 ]

    run _field status
    [ "$status" -eq 0 ]
    [ "$output" = "completed" ]
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
