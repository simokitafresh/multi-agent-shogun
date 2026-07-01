#!/usr/bin/env bats
# Consolidated single-check gate tests (D0 speed optimization: -625ms per merged file)
# Original files: test_gate_no_direct_yaml_dump.bats, test_gate_hooks_no_runtime_incident_ids.bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "gate_no_direct_yaml_dump blocks direct PyYAML dumps in shell scripts" {
    run bash "$PROJECT_ROOT/scripts/gates/gate_no_direct_yaml_dump.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"active hits = 0"* ]]
}

@test "gate_hooks_no_runtime_incident_ids allows comment provenance but blocks runtime incident ids" {
    run bash "$PROJECT_ROOT/scripts/gates/gate_hooks_no_runtime_incident_ids.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"runtime hook incident ID/date hits = 0"* ]]
}
