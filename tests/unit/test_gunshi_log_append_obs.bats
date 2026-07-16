#!/usr/bin/env bats
# test_gunshi_log_append_obs.bats - gunshi_log_append.sh observations必須チェックのunit test
# @covers: scripts/gunshi_log_append.sh lines 31-42

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export ORIG_SCRIPT="$PROJECT_ROOT/scripts/gunshi_log_append.sh"
    [ -f "$ORIG_SCRIPT" ] || return 1
}

setup() {
    # テスト用ディレクトリをプロジェクトルート構造に合わせて構築
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/log_append_obs.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/logs/archive"

    # スクリプトをコピーしてSCRIPT_DIRをテスト用に差し替え
    sed "s|SCRIPT_DIR=\"\$(cd \"\$(dirname \"\\\$0\")/..\" && pwd)\"|SCRIPT_DIR=\"$TEST_ROOT\"|" \
        "$ORIG_SCRIPT" > "$TEST_ROOT/scripts/gunshi_log_append.sh"
    chmod +x "$TEST_ROOT/scripts/gunshi_log_append.sh"

    # 最小限のログファイル
    printf '# gunshi review log\n' > "$TEST_ROOT/logs/gunshi_review_log.yaml"
}

@test "all review paths block missing structured operational simulation" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: cmd_missing_opsim
  review_type: consultation
  brainwash_check: "1/1 checked"
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"operational_simulation must contain"* ]]
}

@test "APPROVE blocks without file line or symbol verified evidence" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: cmd_missing_verified
  review_type: consultation
  verdict: APPROVE
  brainwash_check: "1/1 checked"
  operational_simulation: {command: "true", expected: pass, actual: pass, result: PASS}
  verified_files: ["mere prose"]
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"verified_files file:line or file:symbol"* ]]
}

@test "LG001 blocks existing-implementation claim without git show evidence" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: cmd_lg001_missing_git_show
  review_type: consultation
  verdict: REVISE
  observations: ["対象は既実装と判定"]
  brainwash_check: "1/1 checked"
  operational_simulation: {command: "sed -n 1,20p scripts/example.sh", expected: found, actual: found, result: PASS}
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"git show証跡が必須(LG001)"* ]]
}

@test "LG001 accepts existing-implementation claim with git show evidence" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: cmd_lg001_with_git_show
  review_type: consultation
  verdict: REVISE
  observations: ["対象は既実装と判定"]
  brainwash_check: "1/1 checked"
  operational_simulation: {command: "git show HEAD:scripts/example.sh", expected: found, actual: found, result: PASS}
ENTRY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

teardown() {
    rm -rf "$TEST_ROOT"
}

# --- observations未記入 → BLOCK ---

@test "report with no observations field → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t001
  review_type: report
  verdict: APPROVE
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "draft with no observations field → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t002
  review_type: draft
  verdict: FAIL
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK"* ]]
}

@test "self_study with no observations field → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t003
  review_type: self_study
  verdict: APPROVE
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK"* ]]
}

# --- observations空リスト → BLOCK ---

@test "report with empty observations list → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t004
  review_type: report
  observations: []
  verdict: APPROVE
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK"* ]]
}

# --- observations 1件以上 → OK ---

@test "report with 1 observation → OK exit 0" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t005
  review_type: report
  verdict: APPROVE
  finding_categories: [assumptions, numbers, premortem, adversarial, ambiguity]
  brainwash_check: "1/1確認済み 修正前0→修正後1"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:1"]
  observations:
    - 事実1: テスト実施済み
ENTRY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- finding_categories必須チェック(draft/report) ---

@test "draft without finding_categories → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_fc1
  review_type: draft
  verdict: APPROVE
  observations:
    - "test observation"
  brainwash_check: "1/1確認済み 修正前0→修正後1"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:test_case"]
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"finding_categories"* ]]
}

@test "report with finding_categories but no adversarial → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_fc2
  review_type: report
  verdict: LGTM
  finding_categories: [assumptions, numbers, premortem]
  observations:
    - "test observation"
  brainwash_check: "1/1確認済み 修正前0→修正後1"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:1"]
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"adversarial"* ]]
}

@test "draft with multiline finding_categories including adversarial+ambiguity → OK exit 0" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_fc3
  review_type: draft
  verdict: APPROVE
  finding_categories:
    - assumptions
    - numbers
    - adversarial
    - ambiguity
  ambiguity_points: none
  observations:
    - "test observation"
  brainwash_check: "1/1確認済み 修正前0→修正後1"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:test_fc3"]
ENTRY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "report with finding_categories but no ambiguity → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_fc4
  review_type: report
  verdict: LGTM
  finding_categories: [assumptions, numbers, premortem, adversarial]
  observations:
    - "test observation"
  brainwash_check: "1/1確認済み 修正前0→修正後1"
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"ambiguity"* ]]
}

# --- ambiguity_points必須チェック(draft) ---

@test "draft without ambiguity_points → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_ap1
  review_type: draft
  verdict: APPROVE
  finding_categories: [assumptions, numbers, premortem, adversarial, ambiguity]
  observations:
    - "test observation"
  brainwash_check: "1/1確認済み 修正前0→修正後1"
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"ambiguity_points"* ]]
}

@test "report without ambiguity_points → OK (report is exempt)" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_ap2
  review_type: report
  verdict: LGTM
  finding_categories: [assumptions, numbers, premortem, adversarial, ambiguity]
  observations:
    - "test observation"
  brainwash_check: "1/1確認済み 修正前0→修正後1"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:test_ap2"]
ENTRY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "report LGTM with gate_prediction BLOCK reason suffix → BLOCK exit 2" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_gate_contradiction
  review_type: report
  verdict: LGTM
  gate_prediction: BLOCK(test_triage)
  gate_prediction_reason: "CI check is red"
  finding_categories: [assumptions, numbers, premortem, adversarial, ambiguity]
  observations:
    - "test observation"
  brainwash_check: "3件中3件確認、矛盾1→0"
ENTRY
    [ "$status" -eq 2 ]
    [[ "$output" == *"verdict=LGTMとgate_prediction=BLOCKの矛盾"* ]]
    ! grep -q 't_gate_contradiction' "$TEST_ROOT/logs/gunshi_review_log.yaml"
}

@test "report LGTM with gate_prediction CLEAR remains allowed" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t_gate_clear
  review_type: report
  verdict: LGTM
  gate_prediction: CLEAR
  gate_prediction_reason: "all checks passed"
  finding_categories: [assumptions, numbers, premortem, adversarial, ambiguity]
  observations:
    - "test observation"
  brainwash_check: "3件中3件確認、誤BLOCK 0件"
  operational_simulation: {command: "bats test", expected: pass, actual: pass, result: PASS}
  verified_files: ["tests/example.bats:t_gate_clear"]
ENTRY
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- 非対象review_type → チェックなし ---

@test "review_type=gate_sync without observations → exit 0" {
    run bash "$TEST_ROOT/scripts/gunshi_log_append.sh" <<'ENTRY'
- cmd_id: t006
  review_type: gate_sync
  verdict: CLEAR
ENTRY
    [ "$status" -eq 0 ]
}
