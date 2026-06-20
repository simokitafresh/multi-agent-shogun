#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "gate_hooks_no_runtime_incident_ids allows comment provenance but blocks runtime incident ids" {
    run bash "$PROJECT_ROOT/scripts/gates/gate_hooks_no_runtime_incident_ids.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"runtime hook incident ID/date hits = 0"* ]]
}
