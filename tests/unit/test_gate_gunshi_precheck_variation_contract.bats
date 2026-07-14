#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PRECHECK="$PROJECT_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
    [ -f "$PRECHECK" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/sg_pre_variation.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/tasks"
    cat > "$TEST_TMPDIR/tasks/sasuke.yaml" <<'YAML'
task:
  parent_cmd: cmd_variation_contract
  project: infra
  variation_checks_required: true
  binary_checks:
    AC1:
      - check: "契約テスト"
        result: ""
YAML
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

_write_report() {
    local variation_block="$1"
    cat > "$TEST_TMPDIR/report.yaml" <<YAML
worker_id: sasuke
parent_cmd: cmd_variation_contract
status: completed
files_modified:
  - path: scripts/gates/example.sh
    change: test
binary_checks:
  AC1:
    - check: "契約テスト"
      result: yes
${variation_block}
YAML
}

@test "SG-PRE33 detects a completely unperformed variation contract" {
    _write_report ""

    run env GUNSHI_PRECHECK_ONLY=SG-PRE33 GUNSHI_PRECHECK_TASKS_DIR="$TEST_TMPDIR/tasks" bash "$PRECHECK" "$TEST_TMPDIR/report.yaml"
    [[ "$output" == *"SG-PRE33"* ]]
    [[ "$output" == *"変形検査が全セル未実施"* ]]
}

@test "SG-PRE33 detects partially blank variation cells" {
    _write_report $'variation_checks:\n  normal_pass:\n    check: normal\n    result: yes\n  quoted_or_heredoc:\n    check: quoted\n    result: ""'

    run env GUNSHI_PRECHECK_ONLY=SG-PRE33 GUNSHI_PRECHECK_TASKS_DIR="$TEST_TMPDIR/tasks" bash "$PRECHECK" "$TEST_TMPDIR/report.yaml"
    [[ "$output" == *"変形検査欄の未記入: quoted_or_heredoc"* ]]
}

@test "SG-PRE33 passes when all five variation cells have binary results" {
    _write_report $'variation_checks:\n  normal_pass: {check: normal, result: yes}\n  quoted_or_heredoc: {check: quoted, result: yes}\n  linked_worktree: {check: worktree, result: yes}\n  parallel_or_respawn: {check: respawn, result: yes}\n  abnormal_exit: {check: exit, result: yes}'

    run env GUNSHI_PRECHECK_ONLY=SG-PRE33 GUNSHI_PRECHECK_TASKS_DIR="$TEST_TMPDIR/tasks" bash "$PRECHECK" "$TEST_TMPDIR/report.yaml"
    [[ "$output" == *"PASS: 変形検査5セルがyes/noで記入済み"* ]]
}
