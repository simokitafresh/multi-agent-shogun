#!/usr/bin/env bats
# GP-190: waive_reason付きbc noでverdict=PASSがgate通過するテスト

setup() {
    export PROJECT_DIR="$BATS_TEST_DIRNAME/../.."
    GATE="$PROJECT_DIR/scripts/gates/gate_report_format.sh"
    TMPDIR_BATS="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMPDIR_BATS"
}

# Helper: 最小限の有効報告YAMLを生成
make_report() {
    local verdict="$1"
    local bc_section="$2"
    cat > "$TMPDIR_BATS/report.yaml" << YAML
worker_id: hayate
task_id: cmd_test_impl
parent_cmd: cmd_test
timestamp: '2026-04-14T09:00:00'
status: completed
ac_version_read: abc12345
result:
  summary: "テスト報告"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
files_modified:
- path: /tmp/test.py
  change: modified
lesson_candidate:
  found: false
  no_lesson_reason: "テストのため"
lessons_useful:
- id: L001
  useful: false
  reason: "テストのため不要"
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
${bc_section}
verdict: ${verdict}
YAML
}

@test "GP-190: verdict=PASS + bc no WITHOUT waive_reason → gate FAIL" {
    make_report "PASS" '  AC1:
  - check: "テスト確認"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "no"'

    run bash "$GATE" "$TMPDIR_BATS/report.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"PASS but binary_checks contain"* ]]
}

@test "GP-190: verdict=PASS + bc no WITH waive_reason → gate PASS" {
    make_report "PASS" '  AC1:
  - check: "テスト確認"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "no"
    waive_reason: "cmd制約: commit禁止"'

    run bash "$GATE" "$TMPDIR_BATS/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"PASS but binary_checks contain"* ]]
}

@test "GP-190: verdict=PASS + bc no with EMPTY waive_reason → gate FAIL" {
    make_report "PASS" '  AC1:
  - check: "テスト確認"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "no"
    waive_reason: ""'

    run bash "$GATE" "$TMPDIR_BATS/report.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"PASS but binary_checks contain"* ]]
}

@test "GP-190: verdict=PASS + all yes (no waive needed) → gate PASS" {
    make_report "PASS" '  AC1:
  - check: "テスト確認"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"'

    run bash "$GATE" "$TMPDIR_BATS/report.yaml"
    [ "$status" -eq 0 ]
}

@test "GP-190: verdict=FAIL + bc no without waive → gate PASS (FAIL is honest)" {
    make_report "FAIL" '  AC1:
  - check: "テスト確認"
    result: "no"
  commit:
  - check: "git commitが完了したか"
    result: "no"'

    run bash "$GATE" "$TMPDIR_BATS/report.yaml"
    # verdict=FAILはbc noと整合するのでgate自体はformat PASSのはず
    [[ "$output" != *"PASS but binary_checks contain"* ]]
}

@test "GP-190: multiple no items, only one waived → gate FAIL (unwaived no remains)" {
    make_report "PASS" '  AC1:
  - check: "テスト確認1"
    result: "no"
  - check: "テスト確認2"
    result: "no"
    waive_reason: "テスト免除"
  commit:
  - check: "git commitが完了したか"
    result: "yes"'

    run bash "$GATE" "$TMPDIR_BATS/report.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"PASS but binary_checks contain"* ]]
}
