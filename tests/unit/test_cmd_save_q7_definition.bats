#!/usr/bin/env bats
# test_cmd_save_q7_definition.bats — cmd_save.sh q7_definition_verified WARNINGテスト (cmd_1710)
#
# AC1: q7_definition_verified未記入 → WARNING
# AC2: q7_definition_verifiedあり → WARNINGなし

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    # Extract helper functions that check_q7_definition depends on
    _helpers="$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")
$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")
$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")
$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"

    eval "check_q7_definition() {
declare -A CMD_BLOCK_CACHE=()
CMD_BLOCK_CACHE_LOADED=0
CMD_BLOCK_FOUND=1
$_helpers
$(sed -n '/# q7_definition_verified:/,/^    fi/{p;/^    fi/q}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_q7_definition
}

setup() {
    export CMD_BLOCK_NC=""
}

@test "Q7-T001: q7_definition_verified未記入でWARNING" {
    CMD_BLOCK_NC='    q1_firefighting: "no"
    q2_learning: "奪わない"
    q3_next_quality: "上がる"'
    export CMD_BLOCK_NC

    run check_q7_definition
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"q7_definition_verified未記入"* ]]
    [[ "$output" == *"High/Low"* ]]
}

@test "Q7-T002: q7_definition_verifiedありでWARNINGなし" {
    CMD_BLOCK_NC='    q1_firefighting: "no"
    q2_learning: "奪わない"
    q3_next_quality: "上がる"
    quality_gate:
      q7_definition_verified: "yes — High=rolling maxをテスト期待値へ固定"'
    export CMD_BLOCK_NC

    run check_q7_definition
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"q7_definition_verified未記入"* ]]
}
