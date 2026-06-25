#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SKILL_FILE="$PROJECT_ROOT/skills/cmd-complete/SKILL.md"
}

@test "cmd-complete skill points to the real cmd_complete_gate path" {
    grep -q 'bash scripts/cmd_complete_gate.sh <cmd_id>' "$SKILL_FILE"
    ! grep -q 'scripts/gates/cmd_complete_gate.sh' "$SKILL_FILE"
}

@test "cmd-complete skill handles already archived commands via status gate evidence" {
    grep -q 'bash scripts/gates/gate_yaml_status.sh <cmd_id>' "$SKILL_FILE"
    grep -q 'active queueからarchive済み' "$SKILL_FILE"
    grep -q 'archive/dashboard/gate_metrics上のCLEAR' "$SKILL_FILE"
}
