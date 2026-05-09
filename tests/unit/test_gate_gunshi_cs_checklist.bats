#!/usr/bin/env bats
# test_gate_gunshi_cs_checklist.bats — gate_gunshi_cs_checklist.sh unit tests

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_gunshi_cs_checklist.sh"
    [ -f "$SRC_GATE_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gunshi_cs.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/logs"

    cp "$SRC_GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"

    export TEST_GATE="$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "all recent self_study entries have cs_checklist and causal_chain → PASS" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: idle_self_study
  review_type: self_study
  verdict: N/A
  observations:
    - "事実1"
  causal_chain: "因果"
  cs_checklist:
    cs1: "PASS"
  timestamp: "2026-04-18T00:00:00"
- cmd_id: cmd_2000
  review_type: draft
  verdict: APPROVE
  ambiguity_points: none
  observations:
    - "通常レビュー"
    - "別観測あり"
  timestamp: "2026-04-18T00:01:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS: 直近self_study/consultationエントリ全てにcs_checklist+causal_chain確認"* ]]
    [[ "$output" == *"PASS: APPROVE+FM許容パターンなし"* ]]
}

@test "missing cs_checklist is warned" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: self_study_S999
  review_type: self_study
  verdict: N/A
  observations:
    - "事実1"
  causal_chain: "因果"
  timestamp: "2026-04-18T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: 1件のエントリにcs_checklistなし:"* ]]
    [[ "$output" == *"self_study_S999"* ]]
}

@test "APPROVE plus FM tolerance pattern is warned" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_2999
  review_type: draft
  verdict: APPROVE
  observations:
    - "FMの懸念あり"
    - "現状は許容してv1で後追い対応"
  timestamp: "2026-04-18T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN: APPROVE+FM許容パターン検出"* ]]
    [[ "$output" == *"cmd_2999"* ]]
}

@test "single-scenario draft is warned" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_3001
  review_type: draft
  verdict: APPROVE
  ambiguity_points: none
  observations:
    - "事実1のみ"
  timestamp: "2026-04-18T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"1シナリオ観測のみ"* ]]
    [[ "$output" == *"cmd_3001"* ]]
}

@test "zero ambiguity only once emits INFO" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_3002
  review_type: draft
  verdict: APPROVE
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
  timestamp: "2026-04-18T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO: ambiguity_points=0 が1回だけのdraftを検出"* ]]
    [[ "$output" == *"cmd_3002"* ]]
}

@test "cold category from previous 10 reviews must be included in next finding_categories" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_4001
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4002
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4003
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4004
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4005
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4006
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4007
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4008
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4009
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4010
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4011
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"冷え観点がfinding_categoriesに未反映"* ]]
    [[ "$output" == *"cmd_4011: cold_categories=adversarial"* ]]
}

@test "cold category is satisfied when next finding_categories includes it" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_4101
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4102
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4103
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4104
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4105
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4106
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4107
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4108
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4109
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4110
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4111
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity, adversarial]
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"冷え観点がfinding_categoriesに未反映"* ]]
}
