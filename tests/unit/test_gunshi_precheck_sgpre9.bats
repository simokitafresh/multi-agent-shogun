#!/usr/bin/env bats
# test_gunshi_precheck_sgpre9.bats — GP-193 SG-PRE9 binary_checks no検出テスト
# T1違反予防: LGTM + result:no → gate_prediction BLOCK予告

PRECHECK="scripts/gates/gate_gunshi_report_precheck.sh"
TMPDIR_BATS=""

setup() {
    TMPDIR_BATS=$(mktemp -d)
}

teardown() {
    rm -rf "$TMPDIR_BATS"
}

# Helper: create report with binary_checks result:no
create_report_with_bc_no() {
    cat > "$TMPDIR_BATS/report.yaml" << 'YAML'
worker_id: hayate
parent_cmd: cmd_test_9999
status: completed
ac_version_read: abc12345
result:
  summary: test report
  verdict: PASS
purpose_validation:
  cmd_purpose: test
  fit: true
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: test
lessons_useful: []
binary_checks:
  AC1:
    - check: commit
      result: "no"
  AC2:
    - check: test_pass
      result: "yes"
verdict: PASS
YAML
}

# Helper: create report with all binary_checks result:yes
create_report_all_yes() {
    cat > "$TMPDIR_BATS/report.yaml" << 'YAML'
worker_id: saizo
parent_cmd: cmd_test_8888
status: completed
ac_version_read: def67890
result:
  summary: test report all pass
  verdict: PASS
purpose_validation:
  cmd_purpose: test
  fit: true
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: test
lessons_useful: []
binary_checks:
  AC1:
    - check: implementation
      result: "yes"
  AC2:
    - check: test_pass
      result: "yes"
verdict: PASS
YAML
}

@test "SG-PRE9: binary_checks result:no → WARN検出" {
    create_report_with_bc_no
    run env GUNSHI_PRECHECK_ONLY=SG-PRE9 bash "$PRECHECK" "$TMPDIR_BATS/report.yaml"
    # SG-PRE9 should detect result:no and output WARN
    [[ "$output" == *"SG-PRE9"* ]]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"binary_checks result:no検出"* ]]
    [[ "$output" == *"AC1/commit"* ]]
}

@test "SG-PRE9: binary_checks全result:yes → PASS" {
    create_report_all_yes
    run env GUNSHI_PRECHECK_ONLY=SG-PRE9 bash "$PRECHECK" "$TMPDIR_BATS/report.yaml"
    # SG-PRE9 should show PASS
    [[ "$output" == *"SG-PRE9"* ]]
    [[ "$output" == *"PASS: binary_checks全result:yes"* ]]
}

@test "SG-PRE9: GP-128 BLOCK予告メッセージを含む" {
    create_report_with_bc_no
    run env GUNSHI_PRECHECK_ONLY=SG-PRE9 bash "$PRECHECK" "$TMPDIR_BATS/report.yaml"
    # Should include GP-128 reference and gate_prediction guidance
    [[ "$output" == *"GP-128"* ]]
    [[ "$output" == *"gate_prediction"* ]]
}
