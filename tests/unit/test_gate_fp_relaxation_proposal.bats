#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPT="$PROJECT_ROOT/scripts/gates/gate_fp_relaxation_proposal.py"
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export DQ_FILE="$TEST_TMPDIR/cmd_design_quality.yaml"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "AC1: high FP WARN gate prints rate and relaxation proposal" {
    cat > "$DQ_FILE" <<'YAML'
entries:
  - cmd_id: "cmd_a"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2026-05-19T00:00:00Z"
    notes: "ac_phase_mixing|check=check_ac_phase_mixing"
  - cmd_id: "cmd_a"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2026-05-19T00:01:00Z"
  - cmd_id: "cmd_b"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2026-05-19T00:02:00Z"
    notes: "ac_phase_mixing|check=check_ac_phase_mixing"
  - cmd_id: "cmd_b"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2026-05-19T00:03:00Z"
  - cmd_id: "cmd_c"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2026-05-19T00:04:00Z"
    notes: "ac_phase_mixing|check=check_ac_phase_mixing"
  - cmd_id: "cmd_c"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2026-05-19T00:05:00Z"
  - cmd_id: "cmd_c"
    gate_result: "BLOCK"
    source: "cmd_save"
    timestamp: "2026-05-19T00:06:00Z"
    notes: "WARN累計昇格: 「ac_phase_mixing|check=check_ac_phase_mixing」が3回繰り返されています"
YAML

    run python3 "$SCRIPT" "$DQ_FILE" --days 365 --limit 20 --min-count 3 --threshold 60

    [ "$status" -eq 0 ]
    [[ "$output" == *'ALERT: "ac_phase_mixing|check=check_ac_phase_mixing" FP率=100% (3/3)'* ]]
    [[ "$output" == *"提案: ac_phase_mixing / check_ac_phase_mixing の条件緩和cmdを起票"* ]]
    [[ "$output" == *"__FP_RELAXATION_REQUEST__"* ]]
}

@test "AC1: limit uses only recent cmd_design_quality entries" {
    cat > "$DQ_FILE" <<'YAML'
entries:
  - cmd_id: "cmd_old1"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2026-05-19T00:00:00Z"
    notes: "old_gate|check=check_old_gate"
  - cmd_id: "cmd_old1"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2026-05-19T00:01:00Z"
  - cmd_id: "cmd_new1"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2026-05-19T00:02:00Z"
    notes: "recent_gate|check=check_recent_gate"
  - cmd_id: "cmd_new1"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2026-05-19T00:03:00Z"
  - cmd_id: "cmd_new2"
    gate_result: "WARN"
    source: "cmd_save_warn"
    timestamp: "2026-05-19T00:04:00Z"
    notes: "recent_gate|check=check_recent_gate"
  - cmd_id: "cmd_new2"
    gate_result: "CLEAR"
    source: "cmd_complete_gate"
    timestamp: "2026-05-19T00:05:00Z"
YAML

    run python3 "$SCRIPT" "$DQ_FILE" --days 365 --limit 4 --min-count 2 --threshold 60

    [ "$status" -eq 0 ]
    [[ "$output" == *'ALERT: "recent_gate|check=check_recent_gate" FP率=100% (2/2)'* ]]
    [[ "$output" != *"old_gate"* ]]
}
