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
  operational_simulation: "実運用で自己学習結果を次レビューへ反映できる"
  cs_checklist:
    cs1: "PASS"
  timestamp: "2026-04-18T00:00:00"
- cmd_id: cmd_2000
  review_type: draft
  verdict: APPROVE
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
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
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1のみ"
  timestamp: "2026-04-18T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN(GP-262)"* ]]
    [[ "$output" == *"定型cmdでも最低2観測シナリオ"* ]]
    [[ "$output" == *"cmd_3001"* ]]
}

@test "draft without brainwash_check is warned" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_3034
  review_type: draft
  verdict: APPROVE
  confidence: HIGH
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
  timestamp: "2026-05-24T18:33:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"draftにbrainwash_check未記入"* ]]
    [[ "$output" == *"cmd_3034"* ]]
}

@test "confidence HIGH draft with brainwash_check does not warn" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_3035
  review_type: draft
  verdict: APPROVE
  confidence: HIGH
  brainwash_check:
    creator_position_talk: PASS
    hidden_hole: PASS
    deferred_cost: PASS
  ambiguity_points: none
  observations:
    - "事実1"
    - "事実2"
  timestamp: "2026-05-24T18:34:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"brainwash_check未記入"* ]]
}

@test "zero ambiguity only once emits INFO" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_3002
  review_type: draft
  verdict: APPROVE
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
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

@test "awk stderr is logged and empty result emits WARN" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_unreadable
  review_type: draft
YAML
    chmod 000 "$TEST_TMPDIR/logs/gunshi_review_log.yaml"

    run bash "$TEST_GATE"
    chmod 644 "$TEST_TMPDIR/logs/gunshi_review_log.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: review_log解析失敗(awk空結果)。CS観点チェックをスキップ"* ]]
    grep -F "review_log awk:" "$TEST_TMPDIR/logs/gate_gunshi_cs_checklist_stderr.log"
}

@test "cold category from previous 10 reviews must be included in next finding_categories" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_4001
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4002
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4003
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4004
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4005
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4006
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4007
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4008
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4009
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4010
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4011
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
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
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4102
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4103
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4104
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4105
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4106
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4107
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4108
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4109
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4110
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4111
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity, adversarial]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"冷え観点がfinding_categoriesに未反映"* ]]
}

@test "adversarial cold category reaches threshold and exits ERROR" {
    export GUNSHI_CS_ADVERSARIAL_STREAK_CACHE="$TEST_TMPDIR/adversarial_streak.cache"
    export GUNSHI_CS_ADVERSARIAL_STREAK_THRESHOLD=5
    printf '4\n' > "$GUNSHI_CS_ADVERSARIAL_STREAK_CACHE"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_4201
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4202
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4203
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4204
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4205
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4206
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4207
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4208
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4209
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4210
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4211
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR(L4-adversarial): adversarial冷え観点が5回連続未適用"* ]]
    [ "$(cat "$GUNSHI_CS_ADVERSARIAL_STREAK_CACHE")" = "5" ]
}

@test "adversarial finding category resets cold streak cache" {
    export GUNSHI_CS_ADVERSARIAL_STREAK_CACHE="$TEST_TMPDIR/adversarial_streak.cache"
    export GUNSHI_CS_ADVERSARIAL_STREAK_THRESHOLD=5
    printf '4\n' > "$GUNSHI_CS_ADVERSARIAL_STREAK_CACHE"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_4301
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4302
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4303
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4304
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4305
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4306
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4307
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4308
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4309
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4310
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_4311
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, simulation, premortem, north_star, ambiguity, adversarial]
  ambiguity_points: none
  brainwash_check: "PASS 洗脳#1-8確認"
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ERROR(L4-adversarial)"* ]]
    [ "$(cat "$GUNSHI_CS_ADVERSARIAL_STREAK_CACHE")" = "0" ]
}

@test "brainwash_check with no numbers in majority blocks with exit 2" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_6001
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "確認済み（数値なし）"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6002
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "確認済み（数値なし）"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6003
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "確認済み（数値なし）"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6004
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "確認済み（数値なし）"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6005
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "確認済み（数値なし）"
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(L6-数値なし)"* ]]
}

@test "brainwash_check with numbers present does not block" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_6101
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#2防止: bats 5/5 PASS。数値: AC 2件"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6102
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#2防止: grep確認。数値: 3件"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6103
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#1防止: MEDIUM判定。数値: AC 3件"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6104
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#2防止: 数値検算。数値: 10件確認"
  observations:
    - "事実1"
    - "事実2"
- cmd_id: cmd_6105
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#2防止: bash実行確認。数値: 2/2 verified"
  observations:
    - "事実1"
    - "事実2"
YAML

    run bash "$TEST_GATE"
    [ "$status" -ne 2 ] || [[ "$output" != *"BLOCK(L6-数値なし)"* ]]
    [[ "$output" != *"BLOCK(L6-数値なし)"* ]]
}

@test "report with recommended_skills but no matching skill execution is warned" {
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
reviews:
- cmd_id: cmd_5001
  review_type: report
  report_ninja: sasuke
  report_task_id: cmd_5001_impl
  verdict: LGTM
  observations:
    - "事実1"
    - "事実2"
YAML
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'YAML'
task:
  task_id: cmd_5001_impl
  report_path: queue/reports/sasuke_report_cmd_5001.yaml
  recommended_skills:
    - db-check
YAML
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_5001.yaml" <<'YAML'
worker_id: sasuke
task_id: cmd_5001_impl
verdict: PASS
YAML
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'YAML'
executions: []
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"recommended_skills未使用"* ]]
    [[ "$output" == *"cmd_5001: missing_skills=db-check"* ]]
}

@test "report with recommended_skills and matching skill execution passes" {
    mkdir -p "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports"
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
reviews:
- cmd_id: cmd_5002
  review_type: report
  report_ninja: sasuke
  report_task_id: cmd_5002_impl
  verdict: LGTM
  observations:
    - "事実1"
    - "事実2"
YAML
    cat > "$TEST_TMPDIR/queue/tasks/sasuke.yaml" <<'YAML'
task:
  task_id: cmd_5002_impl
  report_path: queue/reports/sasuke_report_cmd_5002.yaml
  recommended_skills:
    - db-check
YAML
    cat > "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_5002.yaml" <<'YAML'
worker_id: sasuke
task_id: cmd_5002_impl
verdict: PASS
YAML
    cat > "$TEST_TMPDIR/logs/skill_execution_log.yaml" <<'YAML'
executions:
- ts: "2026-05-15T00:00:00+0900"
  skill: "db-check"
  executor: "sasuke"
  result: "PASS"
  used: "true"
  source: "queue/reports/sasuke_report_cmd_5002.yaml"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"recommended_skills未使用"* ]]
}

@test "infra report without 実行 confirmation blocks with exit 2 (AC1 cmd_3372)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_7001
  review_type: report
  verdict: LGTM
  step3_5_verified: "PASS"
  finding_categories: [adversarial]
  observations:
    - "gate_gunshi_cs_checklist.sh のレビュー完了"
  timestamp: "2026-06-14T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(L6-洗脳#2)"* ]]
}

@test "infra report with 実行 confirmation does not block (AC1 cmd_3372)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_7002
  review_type: report
  verdict: LGTM
  step3_5_verified: "PASS"
  finding_categories: [adversarial]
  observations:
    - "gate_gunshi_cs_checklist.sh を実行して確認した"
  timestamp: "2026-06-14T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -ne 2 ]
    [[ "$output" != *"BLOCK(L6-洗脳#2)"* ]]
}

@test "report review without step3_5_verified blocks with exit 2 (AC2 cmd_3372)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_7003
  review_type: report
  verdict: LGTM
  observations:
    - "通常のレビュー完了"
  timestamp: "2026-06-14T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(L4-LG036)"* ]]
}

@test "report review with step3_5_verified does not block for step35 (AC2 cmd_3372)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_7004
  review_type: report
  verdict: LGTM
  step3_5_verified: "PASS"
  observations:
    - "通常のレビュー完了"
  timestamp: "2026-06-14T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -ne 2 ]
    [[ "$output" != *"BLOCK(L4-LG036)"* ]]
}

@test "cs_checklist present but empty blocks with exit 2 (AC1 cmd_3373)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: self_study_A001
  review_type: self_study
  verdict: N/A
  causal_chain: "因果"
  cs_checklist:
  operational_simulation: "シミュレーション完了"
  timestamp: "2026-06-14T00:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(AC1-cs空)"* ]]
    [[ "$output" == *"self_study_A001"* ]]
}

@test "cs_checklist with block content does not trigger AC1 block (AC1 cmd_3373)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: self_study_A002
  review_type: self_study
  verdict: N/A
  causal_chain: "因果"
  cs_checklist:
    CS1: "PASS - 品質向上あり"
    CS2: "PASS - 実運用確認済み"
  operational_simulation: "シミュレーション完了"
  timestamp: "2026-06-14T00:00:00"
YAML

    run bash "$TEST_GATE"
    [[ "$output" != *"BLOCK(AC1-cs空)"* ]]
}

@test "brainwash_check without Quality Check 3 questions blocks when majority missing (AC2 cmd_3373)" {
    {
        for i in $(seq -w 01 12); do
            printf -- '- cmd_id: cmd_qc_%s\n  review_type: draft\n  verdict: APPROVE\n  confidence: MEDIUM\n  ambiguity_points: none\n  brainwash_check: "確認済み（三問なし）"\n  observations:\n    - "事実1"\n    - "事実2"\n' "$i"
        done
    } > "$TEST_TMPDIR/logs/gunshi_review_log.yaml"

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(AC2-品質三問)"* ]]
}

@test "brainwash_check with Quality Check 3 questions does not block (AC2 cmd_3373)" {
    {
        for i in $(seq -w 01 12); do
            printf -- '- cmd_id: cmd_qc_%s\n  review_type: draft\n  verdict: APPROVE\n  confidence: MEDIUM\n  ambiguity_points: none\n  brainwash_check: "Q1:品質向上yes Q2:学習機会yes Q3:次品質向上yes #2防止確認"\n  observations:\n    - "事実1"\n    - "事実2"\n' "$i"
        done
    } > "$TEST_TMPDIR/logs/gunshi_review_log.yaml"

    run bash "$TEST_GATE"
    [[ "$output" != *"BLOCK(AC2-品質三問)"* ]]
}

@test "draft with minor fix pattern but no d0_applied warns (AC1 cmd_3374)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_8001
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#1防止: MEDIUM。数値: AC 2件"
  findings_summary: "6観点OK。typo修正1件。実装は正しい"
  observations:
    - "事実1: typoを発見した"
    - "事実2: 実装は正しい"
  timestamp: "2026-06-14T03:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN(AC1-D0未実施)"* ]]
    [[ "$output" == *"cmd_8001"* ]]
}

@test "draft with minor fix pattern and d0_applied set does not warn (AC1 cmd_3374)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_8002
  review_type: draft
  verdict: APPROVE
  confidence: MEDIUM
  ambiguity_points: none
  brainwash_check: "#1防止: MEDIUM。数値: AC 2件"
  findings_summary: "6観点OK。フォーマット不備を修正した"
  d0_applied: yes
  observations:
    - "事実1: フォーマット修正済み"
    - "事実2: 実装は正しい"
  timestamp: "2026-06-14T03:00:00"
YAML

    run bash "$TEST_GATE"
    [[ "$output" != *"WARN(AC1-D0未実施)"* ]]
}

@test "altruism_check not_needed without reason blocks with exit 2 (AC2 cmd_3374)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: idle_study_X001
  review_type: self_study
  verdict: N/A
  causal_chain: "因果"
  cs_checklist:
    CS1: "PASS"
  operational_simulation: "シミュレーション完了"
  altruism_check: not_needed
  timestamp: "2026-06-14T03:00:00"
YAML

    run bash "$TEST_GATE"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(AC2-利他理由なし)"* ]]
    [[ "$output" == *"idle_study_X001"* ]]
}

@test "altruism_check not_needed with reason does not block (AC2 cmd_3374)" {
    cat > "$TEST_TMPDIR/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: idle_study_X002
  review_type: self_study
  verdict: N/A
  causal_chain: "因果"
  cs_checklist:
    CS1: "PASS"
  operational_simulation: "シミュレーション完了"
  altruism_check: "not_needed — 既存lessonsに記載済みのため還流不要"
  timestamp: "2026-06-14T03:00:00"
YAML

    run bash "$TEST_GATE"
    [[ "$output" != *"BLOCK(AC2-利他理由なし)"* ]]
}
