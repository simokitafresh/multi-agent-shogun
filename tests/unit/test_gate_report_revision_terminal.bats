#!/usr/bin/env bats
# Regression: revision_requested is an editable state, never a successful terminal report.

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPORT="$BATS_TEST_TMPDIR/hayate_report_cmd_revision_terminal.yaml"
}

write_report() {
    local report_status="$1"
    cat > "$REPORT" <<YAML
worker_id: hayate
parent_cmd: cmd_revision_terminal
ac_version_read: abc12345
timestamp: 2026-07-14T20:00:00+09:00
status: ${report_status}
result:
  summary: revision terminal invariant regression
purpose_validation:
  cmd_purpose: prevent editable reports from passing as terminal
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/gates/gate_report_format_main.py
    change: enforce terminal status invariant
lesson_candidate:
  found: false
  no_lesson_reason: regression fixture
lessons_useful:
  - id: L604
    useful: false
    reason: unrelated to this fixture
binary_checks:
  AC1:
    - check: terminal status invariant is satisfied
      result: yes
verdict: PASS
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
YAML
}

@test "revision_requested plus PASS and all binary yes is blocked with completed hint" {
    write_report revision_requested

    run bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    [ "$status" -ne 0 ]
    [[ "$output" == *'status: "revision_requested" cannot carry terminal verdict PASS'* ]]
    [[ "$output" == *"report_field_set.sh <report> status completed"* ]]
}

@test "the same report passes after status is completed" {
    write_report completed

    run bash "$PROJECT_ROOT/scripts/gates/gate_report_format.sh" "$REPORT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
