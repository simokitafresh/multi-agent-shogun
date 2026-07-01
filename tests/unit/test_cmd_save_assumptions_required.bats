#!/usr/bin/env bats
# test_cmd_save_assumptions_required.bats — Check 3: assumptions全cmd必須化

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^path_exists_for_cmd_source()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^parent_exists_for_cmd_source()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^display_parent_for_cmd_source()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_primary_cmd_targets()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^is_gate_or_hook_addition_cmd()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_existing_alternative_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_source_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^extract_guard_list_from_files()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_guard_duplicate_check()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_q11_guard_list()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_gate_hook_action_conversion()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_block_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_save_caller_check_name()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^abort_if_block_immediate()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_text_matches_pattern()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_q5_pair_missing_session_state()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_required_quality_gate_keys_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    check_origin_field() { :; }
    check_gate_script_execution_evidence() { :; }
    count_same_warn_pattern() { echo 0; }
    export -f trim_inline_yaml_scalar path_exists_for_cmd_source parent_exists_for_cmd_source display_parent_for_cmd_source
    export -f load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field collect_primary_cmd_targets
    export -f is_gate_or_hook_addition_cmd q11_has_existing_alternative_verification collect_assumption_source_files
    export -f extract_guard_list_from_files q11_has_guard_duplicate_check collect_q11_guard_list check_gate_hook_action_conversion
    export -f build_warn_note warn_note_key warn_note_message record_warn_reason record_block_reason cmd_save_caller_check_name
    export -f abort_if_block_immediate cmd_text_matches_pattern warn_q5_pair_missing_session_state
    export -f check_required_quality_gate_keys_block check_origin_field check_gate_script_execution_evidence count_same_warn_pattern

    local _qg_start _qg_end
    _qg_start=$(grep -n '# --- Check 3: quality_gate' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$(grep -n '# --- Check 4:' "$SRC_SAVE_SCRIPT" | head -1 | cut -d: -f1)
    _qg_end=$((_qg_end - 1))
    eval "check_quality_gate() {
local WARN_COUNT=0
$(sed -n "${_qg_start},${_qg_end}p" "$SRC_SAVE_SCRIPT")
if [[ \"\${BLOCK_COUNT:-0}\" -gt 0 ]]; then
    return 1
fi
echo \"保存確認OK: \${CMD_ID}\"
}"
    export -f check_quality_gate

    export TEST_SHARED_TMP
    TEST_SHARED_TMP="$(mktemp -d)"
    mkdir -p "${TEST_SHARED_TMP}/queue/archive/cmds"
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    export CMD_ID="cmd_assump_test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_LOADED=0
    export CMD_BLOCK_FOUND=0
    export CMD_BLOCK_CACHE_LOADED=0
    export CMD_SAVE_ACCUMULATE_BLOCKS=0
    export BLOCK_COUNT=0
    declare -ga BLOCK_REASONS=()
    declare -gA CMD_BLOCK_CACHE=()
    export QUEUE_FILE="${TEST_SHARED_TMP}/queue/shogun_to_karo_assump_${BATS_TEST_NUMBER}.yaml"
}

create_queue_file() {
    cat > "$QUEUE_FILE"
}

@test "AC2: AC数1のcmdでassumptions未記入→BLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_assump_test:
    id: cmd_assump_test
    command: "AC1個のcmdでassumptions必須テスト"
    status: pending
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: assumptions必須化確認 → WHAT: AC1個cmdでBLOCKを確認"
      q11_not_already_done: "未達成。AC1個でのassumptions必須化ケースを新規作成"
YAML

    run check_quality_gate
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"assumptions"* ]]
}

@test "AC2: AC数2のcmdでassumptions未記入→BLOCK" {
    create_queue_file << 'YAML'
commands:
  cmd_assump_test:
    id: cmd_assump_test
    command: "AC2個のcmdでassumptions必須テスト"
    status: pending
    acceptance_criteria:
      - description: "AC1: 処理1実装"
      - description: "AC2: 処理2実装"
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q5_verified_source: "コード確認"
      q8_why_what: "WHY: assumptions必須化確認 → WHAT: AC2個cmdでBLOCKを確認"
      q11_not_already_done: "未達成。AC2個でのassumptions必須化ケースを新規作成"
YAML

    run check_quality_gate
    echo "$output" >&2

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"assumptions"* ]]
}
