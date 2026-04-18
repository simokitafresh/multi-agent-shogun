#!/usr/bin/env bats
# test_gate_diagnose_check.bats — GP-195 Diagnose Step + GP-197 DIVERGENT テスト

setup() {
    export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
    GATE="$REPO_ROOT/scripts/gates/gate_diagnose_check.sh"
    TMPDIR_DIAG=$(mktemp -d)
    export GATE_FIRE_LOG_FILE="$TMPDIR_DIAG/gate_fire_log.yaml"
    export GATE_SESSION_STATE_TASK_DIR="$TMPDIR_DIAG/tasks"
    mkdir -p "$GATE_SESSION_STATE_TASK_DIR"
    touch "$GATE_FIRE_LOG_FILE"
}

teardown() {
    rm -rf "$TMPDIR_DIAG"
}

# --- GP-195: Diagnose Step ---

@test "GP-195: report不在 → exit 0 (SKIP)" {
    run bash "$GATE" "/nonexistent/path.yaml"
    [ "$status" -eq 0 ]
}

@test "GP-195: diagnose_reason空+初回BLOCK → exit 0 (警告のみ)" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_1000
verdict: PASS
binary_checks:
  AC1:
    - check: test
      result: "yes"
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml" "binary_checks_fail"
    [ "$status" -eq 0 ]
    [[ "$output" == *"診断推論"* ]]
    [[ "$output" == *"diagnose_reason"* ]]
}

@test "GP-195: diagnose_reason記入済み → exit 0 (OK)" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_1000
diagnose_reason: "テンプレートの必須フィールドを上書きで消してしまった。手動編集が原因"
verdict: PASS
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DIVERGENT"* ]]
}

@test "GP-195: diagnose_reasonがFIX hintコピペ → exit 1 (再BLOCK)" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: saizo
parent_cmd: cmd_1000
diagnose_reason: "FIX: bash scripts/report_field_set.sh report worker_id saizo"
verdict: PASS
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"コピペ検出"* ]]
}

# --- GP-197: DIVERGENT ---

@test "GP-197: 同一理由2回連続BLOCK+diagnose_reason空 → exit 1 (DIVERGENT)" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: hanzo
parent_cmd: cmd_1001
verdict: PASS
EOF
    # gate_fire_logに同一忍者の同一理由FAILを2件追加
    cat > "$GATE_FIRE_LOG_FILE" <<'EOF'
- ts: "2026-04-16T01:00:00", file: "queue/reports/hanzo_report_cmd_1001.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks_fail; AC1 check empty"
- ts: "2026-04-16T01:05:00", file: "queue/reports/hanzo_report_cmd_1001.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks_fail; AC1 check empty"
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml" "binary_checks_fail; AC1 check empty"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DIVERGENT"* ]]
}

@test "GP-197: 異なる理由のBLOCK → DIVERGENTにならない" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_1002
verdict: PASS
EOF
    cat > "$GATE_FIRE_LOG_FILE" <<'EOF'
- ts: "2026-04-16T01:00:00", file: "queue/reports/hayate_report_cmd_1002.yaml", gate: "gate_report_format", result: FAIL, reasons: "report_format error"
- ts: "2026-04-16T01:05:00", file: "queue/reports/hayate_report_cmd_1002.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks_fail"
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml" "lesson_candidate_missing"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DIVERGENT"* ]]
}

@test "GP-197: 2回連続BLOCK+diagnose_reason記入済み → exit 0 (思考した)" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: kotaro
parent_cmd: cmd_1003
diagnose_reason: "binary_checksのresult欄にPASSと書いたがyesが正しかった"
verdict: PASS
EOF
    cat > "$GATE_FIRE_LOG_FILE" <<'EOF'
- ts: "2026-04-16T01:00:00", file: "queue/reports/kotaro_report_cmd_1003.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks_fail"
- ts: "2026-04-16T01:05:00", file: "queue/reports/kotaro_report_cmd_1003.yaml", gate: "gate_report_format", result: FAIL, reasons: "binary_checks_fail"
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml" "binary_checks_fail"
    [ "$status" -eq 0 ]
}

@test "GP-2070: prior_attempts の diagnose_reason と approach_summary が類似 → DIVERGENT v2 BLOCK" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2070
diagnose_reason: "verdict を FAIL にすべきところを PASS のまま提出した"
result:
  summary: "verdict の判定条件を見直して再提出した"
verdict: PASS
EOF
    cat > "$GATE_SESSION_STATE_TASK_DIR/hayate.yaml" <<'EOF'
task:
  session_state:
    prior_attempts:
    - attempt: 1
      block_reason: "verdict_invalid"
      diagnose_reason: "verdict を FAIL にすべきところを PASS のまま提出した"
      approach_summary: "verdict の判定条件を見直して再提出した"
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml" "verdict_invalid"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DIVERGENT v2"* ]]
}

@test "GP-2070: prior_attempts と一部類似のみ → WARNで通す" {
    cat > "$TMPDIR_DIAG/report.yaml" <<'EOF'
worker_id: hayate
parent_cmd: cmd_2070
diagnose_reason: "verdict を FAIL にすべきところを PASS のまま提出した"
result:
  summary: "別の観点で result 集計を見直した"
verdict: PASS
EOF
    cat > "$GATE_SESSION_STATE_TASK_DIR/hayate.yaml" <<'EOF'
task:
  session_state:
    prior_attempts:
    - attempt: 1
      block_reason: "verdict_invalid"
      diagnose_reason: "verdict を FAIL にすべきところを PASS のまま提出した"
      approach_summary: "verdict の判定条件を見直して再提出した"
EOF
    run bash "$GATE" "$TMPDIR_DIAG/report.yaml" "verdict_invalid"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: prior_attempts"* ]]
}
