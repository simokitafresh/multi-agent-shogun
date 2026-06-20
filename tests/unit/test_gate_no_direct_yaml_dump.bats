#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "gate_no_direct_yaml_dump blocks direct PyYAML dumps in shell scripts" {
    run bash "$PROJECT_ROOT/scripts/gates/gate_no_direct_yaml_dump.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"active hits = 0"* ]]
}
