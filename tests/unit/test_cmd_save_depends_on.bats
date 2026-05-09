#!/usr/bin/env bats
# test_cmd_save_depends_on.bats — cmd_2627: depends_on明示WARN

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
    eval "$(sed -n '/^check_depends_on_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block load_cmd_block_cache cmd_block_has_field cmd_block_get_field build_warn_note warn_note_key warn_note_message record_warn_reason check_depends_on_field

    count_same_warn_pattern() { echo 0; }
    export -f count_same_warn_pattern

    export TEST_SHARED_TMP
    TEST_SHARED_TMP="$(mktemp -d)"
}

teardown_file() {
    rm -rf "$TEST_SHARED_TMP"
}

setup() {
    export CMD_ID="cmd_depends_test"
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

_setup_cmd_block() {
    local cid="${1:-$CMD_ID}"
    local line found=0
    CMD_BLOCK_LOADED=1
    CMD_BLOCK_FOUND=0
    CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()

    CMD_BLOCK=""
    CMD_BLOCK_NC=""
    while IFS= read -r line; do
        if (( found == 0 )); then
            [[ "$line" == "  ${cid}:" ]] && found=1
            continue
        fi

        [[ "$line" =~ ^\ \ cmd_[0-9A-Za-z_]+: ]] && break
        CMD_BLOCK+="${line}"$'\n'
        [[ "$line" =~ ^[[:space:]]*# ]] || CMD_BLOCK_NC+="${line}"$'\n'
    done < "$QUEUE_FILE"

    CMD_BLOCK="${CMD_BLOCK%$'\n'}"
    CMD_BLOCK_NC="${CMD_BLOCK_NC%$'\n'}"
    [[ -n "$CMD_BLOCK" ]] && CMD_BLOCK_FOUND=1
    export CMD_BLOCK CMD_BLOCK_NC
}

@test "depends_on: cmd_XXXX 記入あり→WARNなし" {
    create_queue_file <<'YAML'
commands:
  cmd_depends_test:
    depends_on: cmd_2624
    status: pending
YAML

    run check_depends_on_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"depends_on未記入"* ]]
    [[ "$output" != *"depends_on形式不正"* ]]
}

@test "depends_on未記入→WARN" {
    create_queue_file <<'YAML'
commands:
  cmd_depends_test:
    status: pending
YAML

    run check_depends_on_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" == *"depends_on未記入"* ]]
}

@test "depends_on: none 記入あり→WARNなし" {
    create_queue_file <<'YAML'
commands:
  cmd_depends_test:
    depends_on: none
    status: pending
YAML

    run check_depends_on_field
    echo "$output" >&2

    [ "$status" -eq 0 ]
    [[ "$output" != *"depends_on未記入"* ]]
    [[ "$output" != *"depends_on形式不正"* ]]
}
