#!/usr/bin/env bats
# gate_fp_relaxation_proposal.py regression tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export FP_PROPOSAL_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_fp_relaxation_proposal.py"
    [ -f "$FP_PROPOSAL_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export TEST_QUALITY_LOG="$TEST_TMPDIR/cmd_design_quality.yaml"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "escalated_to_block WARN is treated as TP, not FP" {
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: cmd_warn_repeat
    timestamp: "2099-01-01T00:00:00+00:00"
    source: cmd_save_warn
    gate_result: WARN
    notes: "q11_not_already_done|check=warn_q11_not_already_done_drift|未達成"
  - cmd_id: cmd_warn_repeat
    timestamp: "2099-01-01T00:00:01+00:00"
    source: cmd_save_block
    gate_result: BLOCK
    notes: "WARN累計昇格: 「q11_not_already_done|check=warn_q11_not_already_done_drift|未達成」が3回繰り返されています"
YAML

    run python3 "$FP_PROPOSAL_SCRIPT" "$TEST_QUALITY_LOG" --days 36500 --limit 100 --min-count 1 --threshold 60
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *'OK: "q11_not_already_done|check=warn_q11_not_already_done_drift|未達成" FP率=0% (0/1)'* ]]
    [[ "$output" != *"ALERT:"* ]]
    [[ "$output" != *"__FP_RELAXATION_REQUEST__"* ]]
}

@test "single WARN followed by CLEAR is still counted as FP" {
    cat > "$TEST_QUALITY_LOG" <<'YAML'
entries:
  - cmd_id: cmd_warn_cleared
    timestamp: "2099-01-01T00:00:00+00:00"
    source: cmd_save_warn
    gate_result: WARN
    notes: "q11_not_already_done|check=warn_q11_not_already_done_drift|未達成"
  - cmd_id: cmd_warn_cleared
    timestamp: "2099-01-01T00:00:01+00:00"
    source: cmd_complete_gate
    gate_result: CLEAR
    notes: "completed"
YAML

    run python3 "$FP_PROPOSAL_SCRIPT" "$TEST_QUALITY_LOG" --days 36500 --limit 100 --min-count 1 --threshold 60
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *'ALERT: "q11_not_already_done|check=warn_q11_not_already_done_drift|未達成" FP率=100% (1/1)'* ]]
    [[ "$output" == *"__FP_RELAXATION_REQUEST__"* ]]
}
