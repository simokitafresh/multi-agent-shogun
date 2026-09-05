#!/usr/bin/env bats
# test_necessity: an honest precondition-failed report (files_modified empty,
# every binary_check result=no, no commit claimed) must resolve to the
# "no-code-change" commit identity so its fingerprint, approval record and LGTM
# notification can exist; a report with any yes check, or with files, stays
# fail-closed. Root cause: 軍師 blt_20260905_183746 (kotaro ci_fix cycle).

setup() {
    TEST_ROOT="$(mktemp -d)"
    PROJECT_ROOT_SRC="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports"
    cp "$PROJECT_ROOT_SRC/scripts/lib/review_approval.sh" "$PROJECT_ROOT_SRC/scripts/lib/report_commit_identity.py" "$TEST_ROOT/scripts/lib/"
    export TEST_ROOT
}

teardown() {
    rm -rf "$TEST_ROOT"
}

write_report() {
    local path="$1" files="$2" commit_result="$3" other_result="$4"
    cat > "$path" <<EOF
report_id: rpt-test
task_type: ci_fix
parent_cmd: cmd_karo_ci_fix_test
status: completed
verdict: FAIL
files_modified: $files
commit_contract:
  required: true
binary_checks:
  commit:
    - check: git commit が完了したか
      result: $commit_result
  acceptance:
    - check: AC1 前提(CI run log 取得)が成立したか
      result: $other_result
EOF
}

identity_of() {
    PROJECT_ROOT="$TEST_ROOT" bash -c '
        source "$TEST_ROOT/scripts/lib/review_approval.sh"
        review_report_commit_identity "$1"
    ' _ "$1"
}

@test "precondition-failed honest report (no files, all checks no) resolves to no-code-change" {
    write_report "$TEST_ROOT/queue/reports/a.yaml" "[]" "no" "no"
    run identity_of "$TEST_ROOT/queue/reports/a.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "no-code-change" ]
}

@test "any yes check keeps the commit identity fail-closed" {
    write_report "$TEST_ROOT/queue/reports/b.yaml" "[]" "no" "yes"
    run identity_of "$TEST_ROOT/queue/reports/b.yaml"
    [ "$status" -ne 0 ]
}

@test "files_modified present keeps the commit identity fail-closed" {
    write_report "$TEST_ROOT/queue/reports/c.yaml" "[scripts/x.sh]" "no" "no"
    run identity_of "$TEST_ROOT/queue/reports/c.yaml"
    [ "$status" -ne 0 ]
}
