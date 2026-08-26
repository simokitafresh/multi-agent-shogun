#!/usr/bin/env bats
# test_necessity: LGTM記載済みbundle欠落は検出されBLOCKされ、正規経路(bundle存在)は通過する不変量を守るcontract test。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LOG_APPEND_SCRIPT="$PROJECT_ROOT/scripts/gunshi_log_append.sh"
    [ -f "$LOG_APPEND_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lgtm_bundle_guard.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/logs" "$TEST_TMPDIR/queue/gates" "$TEST_TMPDIR/queue/reports"
    # review_log must exist
    touch "$TEST_TMPDIR/logs/gunshi_review_log.yaml"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# 最低限の有効なLGTMエントリ(bundle guard前の全チェックをパスする)
_lgtm_entry_block_fixture() {
    local cmd_id="${1:-cmd_block_fixture}"
    cat <<YAML
- cmd_id: $cmd_id
  review_type: report
  step3_5_verified: true
  verdict: LGTM
  observations:
    - "事実1: テスト観察"
  finding_categories:
    - adversarial
    - ambiguity
  brainwash_check: "1件 #1yes #2no"
YAML
}

# 全チェックをパスする完全なLGTMエントリ
_lgtm_entry_pass_fixture() {
    local cmd_id="${1:-cmd_pass_fixture}"
    cat <<YAML
- cmd_id: $cmd_id
  review_type: report
  step3_5_verified: true
  verdict: LGTM
  observations:
    - "事実1: テスト観察"
  finding_categories:
    - adversarial
    - ambiguity
  brainwash_check: "1件 #1yes #2no"
  gate_prediction: CLEAR
  gate_prediction_reason: all checks passed
  operational_simulation:
    command: "bash scripts/gunshi_log_append.sh"
    expected: "OK: appended"
    actual: "OK: appended"
    result: "PASS"
  verified_files:
    - "scripts/gunshi_log_append.sh:1"
YAML
}

@test "LGTM+bundle欠落はBLOCK(exit 2)されgate_fire_logに記録される" {
    local cmd_id="cmd_block_test_$(date +%s)"
    # bundle未作成
    run env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" \
        <<< "$(_lgtm_entry_block_fixture "$cmd_id")"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "BLOCK: lgtm_bundle_guard" ]]
    # gate_fire_logにBLOCK記録あり
    [ -f "$TEST_TMPDIR/logs/gate_fire_log.yaml" ]
    grep -q "lgtm_bundle_guard" "$TEST_TMPDIR/logs/gate_fire_log.yaml"
    grep -q "result: BLOCK" "$TEST_TMPDIR/logs/gate_fire_log.yaml"
    grep -q "$cmd_id" "$TEST_TMPDIR/logs/gate_fire_log.yaml"
}

@test "gate_fire_logエントリはdetector_fp_rateが期待するフォーマット(ts/file/gate/result)を持つ" {
    local cmd_id="cmd_format_test_$(date +%s)"
    env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" \
        <<< "$(_lgtm_entry_block_fixture "$cmd_id")" 2>/dev/null || true
    [ -f "$TEST_TMPDIR/logs/gate_fire_log.yaml" ]
    # detector_fp_rate.shのparse_fire_logが期待するフォーマット(ts/file/gate/result全フィールド存在)
    local log_line
    log_line=$(grep "lgtm_bundle_guard" "$TEST_TMPDIR/logs/gate_fire_log.yaml")
    [[ "$log_line" =~ 'ts: "' ]]
    [[ "$log_line" =~ 'file: "' ]]
    [[ "$log_line" =~ 'gate: "lgtm_bundle_guard"' ]]
    [[ "$log_line" =~ 'result: BLOCK' ]]
}

@test "LGTM+bundle存在の正規経路はreview_logへ追記される(BLOCK不発)" {
    local cmd_id="cmd_pass_test_$(date +%s)"
    # bundle作成
    mkdir -p "$TEST_TMPDIR/queue/gates/$cmd_id"
    echo '{"review":{"cmd_id":"'"$cmd_id"'","verdict":"APPROVE"}}' \
        > "$TEST_TMPDIR/queue/gates/$cmd_id/sg7_bundle.json"

    run env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" \
        <<< "$(_lgtm_entry_pass_fixture "$cmd_id")"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "OK: appended" ]]
    # review_logにエントリが追記されている
    grep -q "$cmd_id" "$TEST_TMPDIR/logs/gunshi_review_log.yaml"
    # gate_fire_logにlgtm_bundle_guardのBLOCKなし
    if [ -f "$TEST_TMPDIR/logs/gate_fire_log.yaml" ]; then
        ! grep -q "lgtm_bundle_guard" "$TEST_TMPDIR/logs/gate_fire_log.yaml"
    fi
}

@test "FAIL verdictはbundle guardを通過する(LGTMのみが対象)" {
    local cmd_id="cmd_fail_test_$(date +%s)"
    # bundle未作成のままFAIL
    local fail_entry
    fail_entry="$(cat <<YAML
- cmd_id: $cmd_id
  review_type: report
  step3_5_verified: true
  verdict: FAIL
  observations:
    - "事実1: テスト観察"
  finding_categories:
    - adversarial
    - ambiguity
  brainwash_check: "1件 #1yes #2no"
  gate_prediction: CLEAR
  gate_prediction_reason: all checks passed
  operational_simulation:
    command: "bash scripts/gunshi_log_append.sh"
    expected: "OK"
    actual: "OK"
    result: "PASS"
  verified_files:
    - "scripts/gunshi_log_append.sh:1"
YAML
)"
    run env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" \
        <<< "$fail_entry"
    [ "$status" -eq 0 ]
    # gate_fire_logにlgtm_bundle_guardなし
    if [ -f "$TEST_TMPDIR/logs/gate_fire_log.yaml" ]; then
        ! grep -q "lgtm_bundle_guard" "$TEST_TMPDIR/logs/gate_fire_log.yaml"
    fi
}

@test "軍師自身のgateをLGTMする場合はconflict_of_interest欠落をBLOCKする" {
    local cmd_id="cmd_conflict_missing_$(date +%s)"
    mkdir -p "$TEST_TMPDIR/queue/gates/$cmd_id"
    echo '{"review":{"cmd_id":"'"$cmd_id"'","verdict":"APPROVE"}}' \
        > "$TEST_TMPDIR/queue/gates/$cmd_id/sg7_bundle.json"
    local entry
    entry="$(_lgtm_entry_pass_fixture "$cmd_id" | sed 's|scripts/gunshi_log_append.sh:1|scripts/gates/gate_gunshi_report_precheck.sh:1|')"

    run env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" <<< "$entry"
    [ "$status" -eq 2 ]
    [[ "$output" == *"conflict_of_interestフィールドが必須"* ]]
}

@test "軍師自身のgateでもconflict_of_interest明記時はLGTMを受理する" {
    local cmd_id="cmd_conflict_present_$(date +%s)"
    mkdir -p "$TEST_TMPDIR/queue/gates/$cmd_id"
    echo '{"review":{"cmd_id":"'"$cmd_id"'","verdict":"APPROVE"}}' \
        > "$TEST_TMPDIR/queue/gates/$cmd_id/sg7_bundle.json"
    local entry
    entry="$(_lgtm_entry_pass_fixture "$cmd_id" | sed 's|scripts/gunshi_log_append.sh:1|scripts/gates/gate_gunshi_report_precheck.sh:1|')"
    entry+=$'\n  conflict_of_interest: "自作gateの評価であるため第三者最終検分が必要"'

    run env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" <<< "$entry"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: appended"* ]]
}

@test "precheck ERRORSが1以上ならscope外説明があってもLGTMをBLOCKする" {
    local cmd_id="cmd_precheck_errors_$(date +%s)"
    mkdir -p "$TEST_TMPDIR/queue/gates/$cmd_id"
    echo '{"review":{"cmd_id":"'"$cmd_id"'","verdict":"APPROVE"}}' \
        > "$TEST_TMPDIR/queue/gates/$cmd_id/sg7_bundle.json"
    local entry
    entry="$(_lgtm_entry_pass_fixture "$cmd_id")"
    entry="${entry/actual: \"OK: appended\"/actual: \"ERRORS=1(scope外変更)\"}"

    run env GUNSHI_SCRIPT_DIR="$TEST_TMPDIR" bash "$LOG_APPEND_SCRIPT" <<< "$entry"
    [ "$status" -eq 2 ]
    [[ "$output" == *"precheck ERRORS>0"* ]]
}
