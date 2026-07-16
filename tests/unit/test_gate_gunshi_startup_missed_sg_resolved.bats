#!/usr/bin/env bats

setup() {
    TEST_DIR="$BATS_TEST_TMPDIR/repo"
    mkdir -p \
        "$TEST_DIR/scripts/gates" \
        "$TEST_DIR/memory" \
        "$TEST_DIR/queue/inbox" \
        "$TEST_DIR/logs" \
        "$TEST_DIR/projects/infra" \
        "$TEST_DIR/docs/research"

    cp scripts/gates/gate_gunshi_startup.sh "$TEST_DIR/scripts/gates/gate_gunshi_startup.sh"
    cat > "$TEST_DIR/scripts/gates/gate_gunshi_cs_checklist.sh" <<'EOF'
#!/usr/bin/env bash
echo "PASS: CS checklist fixture"
exit 0
EOF
    chmod +x "$TEST_DIR/scripts/gates/gate_gunshi_startup.sh" \
        "$TEST_DIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    TEST_SCRIPT="$TEST_DIR/scripts/gates/gate_gunshi_startup.sh"

    cat > "$TEST_DIR/memory/deepdive_why_chain_20260321.md" <<'EOF'
## Phase 1
phase1
## Phase 2
phase2
EOF
    printf 'messages: []\n' > "$TEST_DIR/queue/inbox/gunshi.yaml"
    cat > "$TEST_DIR/logs/gunshi_stats.yaml" <<'EOF'
# total=1
# accuracy=100%
EOF
    cat > "$TEST_DIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
- id: LG001
  title: fixture
EOF
}

@test "missed_sg counts missing empty and whitespace resolution but excludes resolved entries" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: arbitrary_missing
  ninja: hayate
  workaround: true
  missed_sg: operational_simulation_missing
- cmd_id: arbitrary_empty
  ninja: hanzo
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: ''
- cmd_id: arbitrary_whitespace
  ninja: saizo
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: '   '
- cmd_id: arbitrary_resolved_1
  ninja: kotaro
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: generic_defence_A
- cmd_id: arbitrary_resolved_2
  ninja: kagemaru
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: generic_defence_B
- cmd_id: arbitrary_resolved_3
  ninja: tobisaru
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: generic_defence_C
EOF

    run bash "$TEST_SCRIPT"
    [[ "$output" == *"operational_simulation_missing: 3件"* ]]
    [[ "$output" == *"ALERT: missed_sg operational_simulation_missing が3件蓄積"* ]]
}

@test "missed_sg emits no debt after arbitrary agents are resolved" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: any_cmd_a
  ninja: hayate
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: shared_upstream_defence
- cmd_id: any_cmd_b
  ninja: hanzo
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: shared_upstream_defence
- cmd_id: any_cmd_c
  ninja: saizo
  workaround: true
  missed_sg: operational_simulation_missing
  resolved_by_cmd: shared_upstream_defence
EOF

    run bash "$TEST_SCRIPT"
    [[ "$output" != *"operational_simulation_missing:"* ]]
    [[ "$output" != *"ALERT: missed_sg operational_simulation_missing"* ]]
}
