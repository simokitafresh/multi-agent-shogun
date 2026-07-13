#!/usr/bin/env bats

setup() {
    TEST_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/logs" "$TEST_ROOT/queue/inbox"
    cp "$BATS_TEST_DIRNAME/../../scripts/workaround_pattern_check.sh" "$TEST_ROOT/scripts/"
    cat > "$TEST_ROOT/scripts/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "${0%/scripts/inbox_write.sh}/logs/notices.txt"
SH
    chmod +x "$TEST_ROOT/scripts/inbox_write.sh"
    printf 'notified:\n' > "$TEST_ROOT/logs/workaround_notified.yaml"
    printf 'patterns:\n' > "$TEST_ROOT/logs/workaround_patterns.yaml"
}

run_check() {
    run bash "$TEST_ROOT/scripts/workaround_pattern_check.sh"
}

@test "resolved and workaround=false entries are excluded from signature counts" {
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: a
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
  resolved_by_cmd: ''
- cmd_id: b
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
  resolved_by_cmd: cmd_fix
- cmd_id: c
  workaround: false
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
  resolved_by_cmd: ''
YAML
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"No new patterns detected"* ]]
    [ ! -e "$TEST_ROOT/logs/notices.txt" ]
}

@test "different root signatures in one category never combine into a pattern" {
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: a
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
- cmd_id: b
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::review_state'
- cmd_id: c
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::history_state'
YAML
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"No new patterns detected"* ]]
}

@test "three unresolved identical root signatures emit one signature-keyed pattern" {
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: a
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
- cmd_id: b
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
- cmd_id: c
  workaround: true
  category: gate_logic_gap
  root_signature: 'gate_logic_gap::publish_state'
YAML
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *'root_signature="gate_logic_gap::publish_state" 3回'* ]]
    [ "$(wc -l < "$TEST_ROOT/logs/notices.txt")" -eq 1 ]
    grep -q 'root_signature:gate_logic_gap::publish_state' "$TEST_ROOT/logs/workaround_notified.yaml"
}

@test "legacy entries without root_signature are excluded instead of inventing a shared cause" {
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: a
  workaround: true
  category: report_yaml_format
- cmd_id: b
  workaround: true
  category: report_yaml_format
- cmd_id: c
  workaround: true
  category: report_yaml_format
YAML
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"No new patterns detected"* ]]
    [ ! -e "$TEST_ROOT/logs/notices.txt" ]
}

@test "legacy deploy general entries are canonically split by structural cause" {
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: old_a
  workaround: true
  category: deploy_contract
  root_signature: 'deploy_contract::general'
  detail: 'karo_direct配備YAMLの自然境界契約不足で初回BLOCK'
  root_cause: 'estimated_minutes=15と構造化split_decisionを追加'
- cmd_id: old_b
  workaround: true
  category: deploy_contract
  root_signature: 'deploy_contract::general'
  detail: 'cmdにestimated_minutesと長時間契約構造がなく配備ゲートが3回BLOCK'
  root_cause: 'estimated_minutesを10分の自然境界へ補完'
- cmd_id: old_c
  workaround: true
  category: deploy_contract
  root_signature: 'deploy_contract::general'
  detail: 'karo_direct commandのBLOCK/FP文言が複数行にあり品質契約投影でaction/fp missing'
  root_cause: 'command第1行へQUALITY_CONTRACTを移した'
YAML
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"No new patterns detected"* ]]
    [ ! -e "$TEST_ROOT/logs/notices.txt" ]
    ! grep -q 'root_signature:deploy_contract::general' "$TEST_ROOT/logs/workaround_notified.yaml"
}

@test "three legacy general entries with one structural cause still emit one pattern deterministically" {
    cat > "$TEST_ROOT/logs/karo_workarounds.yaml" <<'YAML'
- cmd_id: x1
  workaround: true
  category: deploy_contract
  root_signature: 'deploy_contract::general'
  detail: '自然境界がなくestimated_minutes不足'
- cmd_id: x2
  workaround: true
  category: deploy_contract
  root_signature: 'deploy_contract::general'
  detail: '長時間契約に自然境界がない'
- cmd_id: x3
  workaround: true
  category: deploy_contract
  root_signature: 'deploy_contract::general'
  root_cause: 'split_decisionとestimated_minutesを補完'
YAML
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *'root_signature="deploy_contract::natural_boundary" 3回'* ]]
    [ "$(wc -l < "$TEST_ROOT/logs/notices.txt")" -eq 1 ]

    run_check
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TEST_ROOT/logs/notices.txt")" -eq 1 ]
}
