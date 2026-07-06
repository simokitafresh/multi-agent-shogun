#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export ENGINE="$PROJECT_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py"
    [ -f "$ENGINE" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/sg_pre9c_scope.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/tasks"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_report() {
    local purpose_gap="$1"
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
ninja: hanzo
task_id: cmd_test
status: completed
purpose_validation:
  cmd_purpose: "context freshness修正"
  fit: true
  purpose_gap: "$purpose_gap"
binary_checks:
  ac1:
    - check: "通常gate OK"
      result: yes
YAML
}

@test "SG-PRE9c allows not_in_scope aligned scope外 boundary text" {
    _write_report "対象ファイルは通常gateでOK。scope外修正しない。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects scope外 delegation to karo" {
    _write_report "scope外で家老が実施するため未完了。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"scope外で家老"* ]]
}

@test "SG-PRE9c allows unmet wording when explicitly outside scope" {
    _write_report "full 5分目標は未達(スコープ外)。今回ACは補完済み。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
    [[ "$output" == *"BC_YES_CLARITY_TERMS=''"* ]]
}

@test "SG-PRE9c still detects unmet wording when delegated later" {
    _write_report "full 5分目標は未達。後で家老が実施する。"

    run python3 "$ENGINE" --report "$TEST_TMPDIR/report.yaml" --tasks-dir "$TEST_TMPDIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"未達"* ]]
}
