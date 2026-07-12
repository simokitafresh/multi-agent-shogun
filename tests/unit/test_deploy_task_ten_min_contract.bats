#!/usr/bin/env bats
# test_deploy_task_ten_min_contract.bats — cmd_karo_hotfix_ten_min_task_contract_tests_202607122006
# 配備前の自然境界契約をvalid/invalid corpusで固定する（10分目安、15分hard境界）。
# 発端: 殿指摘(2026-07-12 19:57)「10分程度のタスクを回す仕組みなら途中でエラーが出たときに対処しやすい」
# scope: deploy_task.shは無編集・無commit。実配備/inbox/tmux環境には触れない隔離テスト。

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "ten_min_contract"
    export FIXTURE_DIR="$TEST_TMPDIR/fixtures"
    mkdir -p "$FIXTURE_DIR"
}

teardown() {
    deploy_task_teardown
}

write_fixture() {
    local name="$1" content="$2"
    local path="$FIXTURE_DIR/$name.yaml"
    printf '%s\n' "$content" > "$path"
    echo "$path"
}

run_precheck() {
    local task_file="$1"
    run bash -lc '
        export DEPLOY_TASK_LIB_ONLY=1
        source "'"$TEST_PROJECT/scripts/deploy_task.sh"'"
        deploy_task_ten_min_contract_precheck "'"$task_file"'"
    '
}

# --- 分岐1: estimated_minutes<=10 → PASS ---

@test "ten_min_contract: estimated_minutes=5(10以下)はPASS(exit 0)" {
    local f
    f="$(write_fixture short_task 'task:
  task_id: cmd_test_short
  estimated_minutes: 5')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
}

@test "ten_min_contract: estimated_minutes=10(境界値)はPASS(exit 0)" {
    local f
    f="$(write_fixture boundary_task 'task:
  task_id: cmd_test_boundary
  estimated_minutes: 10')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
}

# --- 分岐2: 10分超15分以下は boundary=<reason>; split_cost=<reason> の一行構造が必須 ---

@test "ten_min_contract: estimated_minutes=11かつsplit理由なしはexit 2でBLOCK" {
    local f
    f="$(write_fixture no_evidence_task 'task:
  task_id: cmd_test_no_evidence
  estimated_minutes: 11')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: natural-boundary task contract failed"* ]]
}

@test "ten_min_contract: split_decision_reasonが単文字xならexit 2でBLOCK" {
    local f
    f="$(write_fixture one_char_reason_task 'task:
  task_id: cmd_test_one_char_reason
  estimated_minutes: 11
  split_decision_reason: x')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 15文字無意味列ならexit 2でBLOCK" {
    local f
    f="$(write_fixture meaningless_reason_task 'task:
  task_id: cmd_test_meaningless_reason
  estimated_minutes: 11
  split_decision_reason: xxxxxxxxxxxxxxx')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 構造なしの抽象的長文理由ならexit 2でBLOCK" {
    local f
    f="$(write_fixture abstract_reason_task 'task:
  task_id: cmd_test_abstract_reason
  estimated_minutes: 11
  split_decision_reason: "これは具体的な理由で必要だからです"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: キーワードを並べただけで構造(boundary=/split_cost=)なしならexit 2でBLOCK" {
    local f
    f="$(write_fixture keyword_only_task 'task:
  task_id: cmd_test_keyword_only
  estimated_minutes: 11
  split_decision_reason: "不可分 同一の二値検証境界 統合task review往復"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: boundary欠落(split_costのみ)ならexit 2でBLOCK" {
    local f
    f="$(write_fixture boundary_missing_task 'task:
  task_id: cmd_test_boundary_missing
  estimated_minutes: 11
  split_decision_reason: "split_cost=分割すると統合taskとreview往復が増える"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_cost欠落(boundaryのみ)ならexit 2でBLOCK" {
    local f
    f="$(write_fixture split_cost_missing_task 'task:
  task_id: cmd_test_split_cost_missing
  estimated_minutes: 11
  split_decision_reason: "boundary=単一validator変更と同じcorpus検証が不可分"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 両値がplaceholder(none/tbd)ならexit 2でBLOCK" {
    local f
    f="$(write_fixture placeholder_values_task 'task:
  task_id: cmd_test_placeholder_values
  estimated_minutes: 11
  split_decision_reason: "boundary=none; split_cost=tbd"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_decision_reasonが構造なしの複数行ならexit 2でBLOCK" {
    local f
    f="$(write_fixture multiline_reason_task 'task:
  task_id: cmd_test_multiline_reason
  estimated_minutes: 11
  split_decision_reason: |-
    単一validatorとcorpusが不可分
    分割するとreview往復が増える')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 構造ありでも複数行ならexit 2でBLOCK" {
    local f
    f="$(write_fixture multiline_structured_task 'task:
  task_id: cmd_test_multiline_structured
  estimated_minutes: 11
  split_decision_reason: |-
    boundary=単一validatorとcorpus検証が不可分
    split_cost=分割すると統合taskとreview往復が増える')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 順序入れ替え(split_costが先)ならexit 2でBLOCK" {
    local f
    f="$(write_fixture reversed_order_task 'task:
  task_id: cmd_test_reversed_order
  estimated_minutes: 11
  split_decision_reason: "split_cost=分割すると統合taskとreview往復が増える; boundary=単一validator変更と同じcorpus検証が不可分"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: boundaryキー重複ならexit 2でBLOCK" {
    local f
    f="$(write_fixture duplicate_key_task 'task:
  task_id: cmd_test_duplicate_key
  estimated_minutes: 11
  split_decision_reason: "boundary=単一validator変更と同じcorpus検証が不可分; boundary=分割すると統合taskとreview往復が増える"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 余剰keyが混在すればexit 2でBLOCK" {
    local f
    f="$(write_fixture extra_key_task 'task:
  task_id: cmd_test_extra_key
  estimated_minutes: 11
  split_decision_reason: "boundary=単一validator変更と同じcorpus検証が不可分; split_cost=分割すると統合taskとreview往復が増える; extra=x"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: セミコロンでなくカンマ区切りならexit 2でBLOCK" {
    local f
    f="$(write_fixture wrong_delimiter_task 'task:
  task_id: cmd_test_wrong_delimiter
  estimated_minutes: 11
  split_decision_reason: "boundary=単一validator変更と同じcorpus検証が不可分, split_cost=分割すると統合taskとreview往復が増える"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 日本語の自由な説明文でもboundary=/split_cost=構造が揃えばPASS" {
    local f
    f="$(write_fixture natural_boundary_task 'task:
  task_id: cmd_test_natural_boundary
  estimated_minutes: 11
  split_decision_reason: "boundary=単一validator変更と同じcorpus検証が不可分; split_cost=分割すると統合taskとreview往復が増える"')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
}

@test "ten_min_contract: 英語の自由な説明文でもboundary=/split_cost=構造が揃えばPASS" {
    local f
    f="$(write_fixture english_natural_boundary_task 'task:
  task_id: cmd_test_english_natural_boundary
  estimated_minutes: 11
  split_decision_reason: "boundary=the validator and corpus form an indivisible binary boundary; split_cost=splitting adds an integration task and review round trip"')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
}

@test "ten_min_contract: long_runtime_reasonがnullish値(none)はBLOCK" {
    local f
    f="$(write_fixture nullish_reason_task 'task:
  task_id: cmd_test_nullish
  estimated_minutes: 60
  execution_env:
    long_runtime_reason: "none"
    measured_runtime_sec: 600')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: measured_runtime_sec欠落はBLOCK" {
    local f
    f="$(write_fixture missing_runtime_task 'task:
  task_id: cmd_test_missing_runtime
  estimated_minutes: 60
  execution_env:
    long_runtime_reason: "GS全量グリッドサーチのため長時間計算が必要"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: measured_runtime_sec=0(正数でない)はBLOCK" {
    local f
    f="$(write_fixture zero_runtime_task 'task:
  task_id: cmd_test_zero_runtime
  estimated_minutes: 60
  execution_env:
    long_runtime_reason: "GS全量グリッドサーチのため長時間計算が必要"
    measured_runtime_sec: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: estimated_minutes欠落はfail-closedでBLOCK" {
    local f
    f="$(write_fixture missing_estimated_task 'task:
  task_id: cmd_test_missing_estimated')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: estimated_minutesが数値でない(文字列)はBLOCK" {
    local f
    f="$(write_fixture non_numeric_task 'task:
  task_id: cmd_test_non_numeric
  estimated_minutes: "soon"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

# --- 分岐3: 15分超は実測long-runtime根拠が必須 ---

@test "ten_min_contract: reason+measured_runtime_sec両方揃えばPASS(exit 0)" {
    local f
    f="$(write_fixture valid_exception_task 'task:
  task_id: cmd_test_valid_exception
  estimated_minutes: 60
  execution_env:
    long_runtime_reason: "GS全量グリッドサーチのため長時間計算が必要"
    measured_runtime_sec: 1200')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
}
