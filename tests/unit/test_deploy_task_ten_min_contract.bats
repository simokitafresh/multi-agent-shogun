#!/usr/bin/env bats
# test_deploy_task_ten_min_contract.bats — cmd_karo_hotfix_task_natural_boundary_contract_rc4_202607122210
# 配備前の自然境界契約をvalid/invalid corpusで固定する（10分目安、15分hard境界）。
# 発端: 殿指摘(2026-07-12 19:57)「10分程度のタスクを回す仕組みなら途中でエラーが出たときに対処しやすい」
# RC4: split_decision_reasonの自由文構造(boundary=x; split_cost=x)はrc=0を通す抜け道だった。
#      split_decisionを構造化mappingへ変更し、boundary_ac_idsは同一taskのacceptance_criteria実在ID参照、
#      integration_tasks/review_round_tripsはboolでない非負整数かつ合計1以上をcross-field検証する。
# scope: deploy_task.shは無編集・無commit。実配備/inbox/tmux環境には触れない隔離テスト。

load '../helpers/deploy_task_scaffold'

setup_file() {
    deploy_task_setup_file
}

setup() {
    deploy_task_scaffold "ten_min_contract"
    export FIXTURE_DIR="$TEST_TMPDIR/fixtures"
    mkdir -p "$FIXTURE_DIR"
    printf 'task:\n  status: idle\n' > "$TEST_PROJECT/queue/tasks/sasuke.yaml"
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
    run deploy_task_ten_min_contract_precheck "$task_file"
}

run_source_precheck() {
    local task_file="$1" cmd_id="${2:-}"
    run deploy_task_source_contract_precheck "$task_file" "$cmd_id"
}

source_precheck_and_reset() {
    deploy_task_source_contract_precheck "$1" || return
    reset_stale_fields sasuke
    [ "${_STALE_RESET_DONE:-0}" = 1 ]
}

@test "source precheck: invalid direct YAML BLOCK keeps existing task sha256 exact" {
    local source="$FIXTURE_DIR/invalid.yaml" task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    printf 'task:\n  estimated_minutes: [\n' > "$source"
    local before after
    before="$(sha256sum "$task" | awk '{print $1}')"
    run_source_precheck "$source"
    [ "$status" -eq 2 ]
    after="$(sha256sum "$task" | awk '{print $1}')"
    [ "$before" = "$after" ]
}

@test "source precheck: normal CMD natural-boundary BLOCK keeps existing task sha256 exact" {
    local source="$FIXTURE_DIR/commands.yaml" task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    printf 'commands:\n  cmd_bad:\n    estimated_minutes: 11\n' > "$source"
    local before after
    before="$(sha256sum "$task" | awk '{print $1}')"
    run_source_precheck "$source" cmd_bad
    [ "$status" -eq 2 ]
    after="$(sha256sum "$task" | awk '{print $1}')"
    [ "$before" = "$after" ]
}

@test "source precheck: PASS fixture permits stale reset and preserves _STALE_RESET_DONE contract" {
    local source="$FIXTURE_DIR/pass.yaml" task="$TEST_PROJECT/queue/tasks/sasuke.yaml"
    printf 'task:\n  estimated_minutes: 10\n' > "$source"
    mkdir -p "$(dirname "$task")"
    printf 'task:\n  status: idle\n  stale_marker: old\n' > "$task"
    run source_precheck_and_reset "$source"
    [ "$status" -eq 0 ]
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

# --- 分岐2: 10分超15分以下は split_decision 構造化mappingが必須 ---

@test "ten_min_contract: estimated_minutes=11かつsplit_decisionなしはexit 2でBLOCK" {
    local f
    f="$(write_fixture no_evidence_task 'task:
  task_id: cmd_test_no_evidence
  estimated_minutes: 11')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: natural-boundary task contract failed"* ]]
}

@test "ten_min_contract: mapping形式acceptance_criteriaの実在AC参照はPASS" {
    local f
    f="$(write_fixture mapping_ac_task 'task:
  task_id: cmd_test_mapping_ac
  estimated_minutes: 11
  acceptance_criteria:
    AC1: "first"
    AC2: "second"
  split_decision:
    boundary_ac_ids: ["AC1", "AC2"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"boundary_ac_ids=['AC1', 'AC2']"* ]]
}

@test "ten_min_contract: mapping形式acceptance_criteriaでも未知AC参照はexit 2でBLOCK" {
    local f
    f="$(write_fixture mapping_unknown_ac_task 'task:
  task_id: cmd_test_mapping_unknown_ac
  estimated_minutes: 11
  acceptance_criteria:
    AC1: "first"
    AC2: "second"
  split_decision:
    boundary_ac_ids: ["AC3"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: mapping形式acceptance_criteriaの空IDは既知ACとして扱わずBLOCK" {
    local f
    f="$(write_fixture mapping_empty_ac_task 'task:
  task_id: cmd_test_mapping_empty_ac
  estimated_minutes: 11
  acceptance_criteria:
    "": "invalid"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 旧自由文split_decision_reason(boundary=/split_cost=)のみは移行抜け道にせずexit 2でBLOCK" {
    local f
    f="$(write_fixture legacy_free_text_task 'task:
  task_id: cmd_test_legacy_free_text
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  - id: AC2
    description: "second"
  split_decision_reason: "boundary=単一validator変更と同じcorpus検証が不可分; split_cost=分割すると統合taskとreview往復が増える"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_decision_reason=単一文字xでも移行抜け道にせずexit 2でBLOCK" {
    local f
    f="$(write_fixture one_char_reason_task 'task:
  task_id: cmd_test_one_char_reason
  estimated_minutes: 11
  split_decision_reason: "boundary=x; split_cost=x"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_decisionが未知ACを参照すればexit 2でBLOCK" {
    local f
    f="$(write_fixture unknown_ac_task 'task:
  task_id: cmd_test_unknown_ac
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC9"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: boundary_ac_idsが空配列ならexit 2でBLOCK" {
    local f
    f="$(write_fixture empty_ac_ids_task 'task:
  task_id: cmd_test_empty_ac_ids
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: []
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: boundary_ac_idsに重複があればexit 2でBLOCK" {
    local f
    f="$(write_fixture duplicate_ac_ids_task 'task:
  task_id: cmd_test_duplicate_ac_ids
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  - id: AC2
    description: "second"
  split_decision:
    boundary_ac_ids: ["AC1", "AC1"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: integration_tasksが負数ならexit 2でBLOCK" {
    local f
    f="$(write_fixture negative_integration_task 'task:
  task_id: cmd_test_negative_integration
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: -1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: review_round_tripsが負数ならexit 2でBLOCK" {
    local f
    f="$(write_fixture negative_review_task 'task:
  task_id: cmd_test_negative_review
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 0
    review_round_trips: -1')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: integration_tasksが文字列数値('1')ならexit 2でBLOCK" {
    local f
    f="$(write_fixture string_numeric_task 'task:
  task_id: cmd_test_string_numeric
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: "1"
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: review_round_tripsがboolならexit 2でBLOCK" {
    local f
    f="$(write_fixture bool_review_task 'task:
  task_id: cmd_test_bool_review
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 0
    review_round_trips: true')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: integration_tasksとreview_round_tripsが両方0(合計0)ならexit 2でBLOCK" {
    local f
    f="$(write_fixture both_zero_cost_task 'task:
  task_id: cmd_test_both_zero_cost
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 0
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_decisionに余剰keyが混在すればexit 2でBLOCK" {
    local f
    f="$(write_fixture extra_key_task 'task:
  task_id: cmd_test_extra_key
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 1
    review_round_trips: 0
    extra: "x"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_decisionでintegration_tasksキーが欠落すればexit 2でBLOCK" {
    local f
    f="$(write_fixture missing_key_task 'task:
  task_id: cmd_test_missing_key
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    review_round_trips: 1')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: taskにacceptance_criteria自体がなければsplit_decisionがあってもexit 2でBLOCK" {
    local f
    f="$(write_fixture no_ac_at_all_task 'task:
  task_id: cmd_test_no_ac_at_all
  estimated_minutes: 11
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: split_decisionがmapping以外(文字列)ならexit 2でBLOCK" {
    local f
    f="$(write_fixture non_mapping_task 'task:
  task_id: cmd_test_non_mapping
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision: "boundary_ac_ids=AC1"')"
    run_precheck "$f"
    [ "$status" -eq 2 ]
}

@test "ten_min_contract: 実在AC参照+integration_tasks正の整数+review_round_trips0(言語非依存)ならPASS" {
    local f
    f="$(write_fixture valid_integration_task 'task:
  task_id: cmd_test_valid_integration
  estimated_minutes: 11
  acceptance_criteria:
  - id: AC1
    description: "first"
  - id: AC2
    description: "second"
  split_decision:
    boundary_ac_ids: ["AC1", "AC2"]
    integration_tasks: 1
    review_round_trips: 0')"
    run_precheck "$f"
    [ "$status" -eq 0 ]
}

@test "ten_min_contract: 実在AC単一参照+integration_tasks0+review_round_trips正の整数ならPASS" {
    local f
    f="$(write_fixture valid_review_task 'task:
  task_id: cmd_test_valid_review
  estimated_minutes: 14
  acceptance_criteria:
  - id: AC1
    description: "first"
  split_decision:
    boundary_ac_ids: ["AC1"]
    integration_tasks: 0
    review_round_trips: 2')"
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
