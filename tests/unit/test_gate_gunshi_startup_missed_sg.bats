#!/usr/bin/env bats
# gate_gunshi_startup.sh — missed_sg集計回帰テスト

setup() {
    export TMPDIR="${BATS_TMPDIR:-/tmp}"
    TEST_DIR=$(mktemp -d "$TMPDIR/gunshi_startup.XXXXXX")

    mkdir -p \
        "$TEST_DIR/scripts/gates" \
        "$TEST_DIR/memory" \
        "$TEST_DIR/queue/inbox" \
        "$TEST_DIR/queue" \
        "$TEST_DIR/logs" \
        "$TEST_DIR/projects/infra" \
        "$TEST_DIR/docs/research"

    cp scripts/gates/gate_gunshi_startup.sh "$TEST_DIR/scripts/gates/gate_gunshi_startup.sh"
    cp scripts/gates/gate_gunshi_cs_checklist.sh "$TEST_DIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    chmod +x "$TEST_DIR/scripts/gates/gate_gunshi_startup.sh"
    chmod +x "$TEST_DIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    TEST_SCRIPT="$TEST_DIR/scripts/gates/gate_gunshi_startup.sh"

    cat > "$TEST_DIR/memory/deepdive_why_chain_20260321.md" <<'EOF'
前文
## Phase 1
phase1
## Phase 2
phase2
EOF

    cat > "$TEST_DIR/queue/inbox/gunshi.yaml" <<'EOF'
messages: []
EOF

    cat > "$TEST_DIR/logs/gunshi_stats.yaml" <<'EOF'
# 累計: total=10
# accuracy公式: approved/total
# verdict分布: APPROVE=7 REQUEST_CHANGES=3
# workaround率推移: 10%
EOF

    cat > "$TEST_DIR/projects/infra/lessons_gunshi.yaml" <<'EOF'
- id: LG001
  title: sample
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "missed_sg Top3を集計表示する" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_1
  timestamp: '2026-04-19T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'detail'
  root_cause: 'cause'
  missed_sg: 'SG4'
  resolved_by_cmd: ''
- cmd_id: cmd_2
  timestamp: '2026-04-19T00:00:01Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  detail: 'detail'
  root_cause: 'cause'
  missed_sg: 'SG4'
  resolved_by_cmd: ''
- cmd_id: cmd_3
  timestamp: '2026-04-19T00:00:02Z'
  ninja: saizo
  workaround: true
  category: report_yaml_format
  detail: 'detail'
  root_cause: 'cause'
  missed_sg: 'SG2'
  resolved_by_cmd: ''
EOF

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"■ missed_sg Top3"* ]]
    [[ "$output" == *"SG4: 2件"* ]]
    [[ "$output" == *"SG2: 1件"* ]]
}

@test "missed_sgが3回以上ならALERT表示する" {
    cat > "$TEST_DIR/logs/karo_workarounds.yaml" <<'EOF'
- cmd_id: cmd_1
  timestamp: '2026-04-19T00:00:00Z'
  ninja: hayate
  workaround: true
  category: report_yaml_format
  detail: 'detail'
  root_cause: 'cause'
  missed_sg: 'SG7'
  resolved_by_cmd: ''
- cmd_id: cmd_2
  timestamp: '2026-04-19T00:00:01Z'
  ninja: hanzo
  workaround: true
  category: report_yaml_format
  detail: 'detail'
  root_cause: 'cause'
  missed_sg: 'SG7'
  resolved_by_cmd: ''
- cmd_id: cmd_3
  timestamp: '2026-04-19T00:00:02Z'
  ninja: saizo
  workaround: true
  category: report_yaml_format
  detail: 'detail'
  root_cause: 'cause'
  missed_sg: 'SG7'
  resolved_by_cmd: ''
EOF

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: missed_sg SG7 が3件蓄積"* ]]
    [[ "$output" == *"=== 総合判定: ALERT ==="* ]]
}

@test "CS checklistの冷え観点WARNをstartup総合判定へ反映する" {
    cat > "$TEST_DIR/logs/gunshi_review_log.yaml" <<'EOF'
- cmd_id: cmd_5001
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5002
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5003
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5004
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5005
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5006
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5007
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5008
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5009
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5010
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_5011
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
EOF

    run bash "$TEST_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 1件のdraft/reportで冷え観点がfinding_categoriesに未反映:"* ]]
    [[ "$output" == *"CS観点チェックリスト/冷え観点WARNあり"* ]]
    [[ "$output" == *"=== 総合判定: WARN ==="* ]]
}
