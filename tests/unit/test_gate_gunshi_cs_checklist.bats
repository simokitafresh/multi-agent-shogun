#!/usr/bin/env bats
# test_necessity: within a single gunshi_review_log.yaml entry that has a
# duplicate gate_result key, gate_gunshi_cs_checklist.sh's L6/L4b checks
# must resolve gate_result to the last-matching value in scan order (YAML
# last-key-wins semantics) — never latch on an earlier value regardless of
# whether CLEAR or BLOCK appears first; violation is a missed BLOCK
# detection (L6) or a false-positive contradiction WARN (L4b).
# cmd_karo_impl_b42_yaml_latch_and_dup_field_20260726 (B42, 疾風偵察
# cmd_karo_recon_cs_lgtm_block_attribution_20260726由来)

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export GATE_SCRIPT="$PROJECT_ROOT/scripts/gates/gate_gunshi_cs_checklist.sh"
    [ -f "$GATE_SCRIPT" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_gunshi_cs.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/logs"
    # REPO_ROOT is derived from the script's own path (../..), so a sandbox
    # copy under TEST_TMPDIR/scripts/gates/ resolves LOG_FILE to
    # TEST_TMPDIR/logs/gunshi_review_log.yaml — fully isolated from the real log.
    cp "$GATE_SCRIPT" "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    export LOG_UNDER_TEST="$TEST_TMPDIR/logs/gunshi_review_log.yaml"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "B42陽性(見逃し側,合成データ): CLEAR→BLOCK順の重複gate_resultはL6(infra_no_verify)を正しく発火させる" {
    # 実データの6件重複キー(HEAD版logs/gunshi_review_log.yaml)は全てCLEAR→CLEARの
    # 同値重複であり、CLEAR→BLOCK順の実例は存在しない(家老・軍師と確認済み)。
    # よってこの陽性対照は合成データである(AC5の要求通り明記する)。
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_synth_miss
  review_type: report
  gate_result: CLEAR
  report_ninja: test
  verdict: LGTM
  observations:
    - scripts/deploy_task.sh looks fine, read only
  gate_result: BLOCK
  brainwash_check: "no numbers here at all"
  timestamp: "2026-07-26T00:00:00+09:00"
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" == *"BLOCK(L6-洗脳#2)"* ]]
    [[ "$output" == *"cmd_synth_miss"* ]]
}

@test "B42陰性(誤検知側,実データcmd_4171): BLOCK→CLEAR順の重複gate_resultはL4b(LGTM+BLOCK矛盾)WARNを発火させない" {
    # logs/gunshi_review_log.yaml のHEAD版(git show HEAD)に実在するcmd_4171の
    # エントリ構造をそのまま使う(gate_result BLOCK→CLEARの順、verdict: LGTM、
    # 最終値はCLEARなので verdict=LGTM と矛盾しない)。合成ではなく実データ。
    cat > "$LOG_UNDER_TEST" <<'EOF'
- cmd_id: cmd_4171
  review_type: report
  gate_result: BLOCK
  gate_synced_at: 2026-07-25T15:26:42+09:00
  report_ninja: hayate
  verdict: LGTM
  verified_files:
    - "queue/reports/hayate_report_cmd_4171.yaml:28"
  gate_result: CLEAR
  gate_prediction: CLEAR
  gate_prediction_reason: "precheck all checks passed"
  finding_categories: [assumptions, numbers, simulation, premortem, adversarial, ambiguity]
  brainwash_check: "#1no #2no #3no #4no #5no #6no #7no #8no"
  origin: "[[a]] -> [[b]] -> [[c]]"
  timestamp: "2026-07-25T15:26:42+09:00"
EOF
    run bash "$TEST_TMPDIR/scripts/gates/gate_gunshi_cs_checklist.sh"
    [[ "$output" != *"WARN(L4b-洗脳#4)"* ]]
}
