#!/usr/bin/env bats
# test_necessity: gateは運用shellの直接PyYAML dumpとruntime incident ID混入を拒否する
# Consolidated single-check gate tests (D0 speed optimization: -625ms per merged file)
# Original files: test_gate_no_direct_yaml_dump.bats, test_gate_hooks_no_runtime_incident_ids.bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "deploy fixture dependency closure detects all three historical missing dependencies" {
    fixture_root="$BATS_TEST_TMPDIR/deploy-fixture-closure"
    mkdir -p "$fixture_root/scripts/lib"
    source_script="$fixture_root/deploy_task.sh"
    cat > "$source_script" <<'SH'
source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
source "$SCRIPT_DIR/scripts/lib/retro_verbatim_prompt.sh"
python3 - <<'PY'
from scripts.lib.yaml_atomic import atomic_yaml_write
PY
SH
    source "$PROJECT_ROOT/tests/helpers/deploy_task_scaffold.bash"

    run deploy_task_fixture_dependency_closure_check "$source_script" "$fixture_root/scripts/lib"
    [ "$status" -eq 1 ]
    [[ "$output" == *"defense_overhead_writer.sh"* ]]
    [[ "$output" == *"retro_verbatim_prompt.sh"* ]]
    [[ "$output" == *"yaml_atomic.py"* ]]

    touch "$fixture_root/scripts/lib/defense_overhead_writer.sh" \
        "$fixture_root/scripts/lib/retro_verbatim_prompt.sh" \
        "$fixture_root/scripts/lib/yaml_atomic.py"
    run deploy_task_fixture_dependency_closure_check "$source_script" "$fixture_root/scripts/lib"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3/3"* ]]
}

setup_runtime_incident_fixture() {
    local fixture_root="$BATS_TEST_TMPDIR/runtime-incident-fixture"
    mkdir -p "$fixture_root/scripts/gates" "$fixture_root/.claude/hooks"
    cp "$PROJECT_ROOT/scripts/gates/gate_hooks_no_runtime_incident_ids.sh" \
        "$fixture_root/scripts/gates/"
    printf '%s\n' "$fixture_root"
}

@test "gate_no_direct_yaml_dump blocks direct PyYAML dumps in shell scripts" {
    run bash "$PROJECT_ROOT/scripts/gates/gate_no_direct_yaml_dump.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"active hits = 0"* ]]
}

@test "gate_hooks_no_runtime_incident_ids allows comment provenance but blocks runtime incident ids" {
    fixture_root="$(setup_runtime_incident_fixture)"
    hook="$fixture_root/.claude/hooks/pre-bash-fixture.sh"

    printf '%s\n' '# Provenance: LG058, 2026-07-18' 'echo "BLOCK: invariant violation"' > "$hook"
    run bash "$fixture_root/scripts/gates/gate_hooks_no_runtime_incident_ids.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"runtime hook incident ID/date hits = 0"* ]]

    printf '%s\n' '# Provenance remains allowed.' 'echo "BLOCK(LG058): invariant violation"' > "$hook"
    run bash "$fixture_root/scripts/gates/gate_hooks_no_runtime_incident_ids.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pre-bash-fixture.sh:2"* ]]
}
