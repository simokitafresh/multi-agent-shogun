#!/usr/bin/env bats
# test_cmd_save_q7_definition.bats — cmd_save.sh q7_definition_verified WARNINGテスト

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_q7_definition_verified_warn()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    count_same_warn_pattern() { echo 0; }
    export -f trim_inline_yaml_scalar load_cmd_block_cache cmd_block_has_field cmd_block_get_field
    export -f build_warn_note warn_note_key warn_note_message record_warn_reason count_same_warn_pattern
    export -f check_q7_definition_verified_warn
}

setup() {
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_CACHE_LOADED=0
    export CMD_BLOCK_FOUND=1
    declare -gA CMD_BLOCK_CACHE=()
}

@test "Q7-T001: q7_definition_verified未記入でWARNING" {
    CMD_BLOCK_NC='    project: infra
    task_type: research
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"'
    export CMD_BLOCK_NC

    run check_q7_definition_verified_warn
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"q7_definition_verified未記入"* ]]
    [[ "$output" == *"High/Low"* ]]
}

@test "Q7-T002: q7_definition_verifiedありでWARNINGなし" {
    CMD_BLOCK_NC='    project: dm-signal
    task_type: impl
    quality_gate:
      q1_firefighting: "no"
      q2_learning: "奪わない"
      q3_next_quality: "上がる"
      q7_definition_verified: "yes — High=rolling maxをテスト期待値へ固定"'
    export CMD_BLOCK_NC

    run check_q7_definition_verified_warn
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"q7_definition_verified未記入"* ]]
}
