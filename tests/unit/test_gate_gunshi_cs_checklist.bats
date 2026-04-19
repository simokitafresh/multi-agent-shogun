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
