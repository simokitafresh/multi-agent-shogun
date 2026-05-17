#!/usr/bin/env bats
# test_cmd_save_origin.bats — cmd_2819: origin根拠リンクWARN

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_origin_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field build_warn_note warn_note_key warn_note_message record_warn_reason check_origin_field

    count_same_warn_pattern() { echo 0; }
    export -f count_same_warn_pattern

    export TEST_SHARED_TMP
    TEST_SHARED_TMP="$(mktemp -d)"
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    export CMD_ID="cmd_origin_test"
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_LOADED=0
    export CMD_BLOCK_FOUND=0
    export CMD_BLOCK_CACHE_LOADED=0
    export WARN_COUNT=0
    declare -ga WARN_REASONS=()
    declare -gA CMD_BLOCK_CACHE=()
    export QUEUE_FILE="${TEST_SHARED_TMP}/shogun_to_karo_${BATS_TEST_NUMBER}.yaml"
}

create_queue_file() {
    cat > "$QUEUE_FILE"
}

@test "origin未記入→WARN" {
    create_queue_file <<'YAML'
commands:
  cmd_origin_test:
    status: pending
YAML

    run check_origin_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"origin未記入"* ]]
}

@test "originに[[ルールID]]形式リンクあり→WARNなし" {
    create_queue_file <<'YAML'
commands:
  cmd_origin_test:
    origin: "[[ルールLS017]] deepdive追体験"
    status: pending
YAML

    run check_origin_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"origin未記入"* ]]
    [[ "$output" != *"origin形式不正"* ]]
}

@test "originに[[殿裁定YYYY-MM-DD]]形式リンクあり→WARNなし" {
    create_queue_file <<'YAML'
commands:
  cmd_origin_test:
    origin: "[[殿裁定2026-04-15]] 因果をたどる仕組み"
    status: pending
YAML

    run check_origin_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"origin未記入"* ]]
    [[ "$output" != *"origin形式不正"* ]]
}

@test "originにリンク形式なし→WARN" {
    create_queue_file <<'YAML'
commands:
  cmd_origin_test:
    origin: "殿が言ったため"
    status: pending
YAML

    run check_origin_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"origin形式不正"* ]]
}
