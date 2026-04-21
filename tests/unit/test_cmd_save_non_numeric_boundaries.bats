#!/usr/bin/env bats
# test_cmd_save_non_numeric_boundaries.bats — 非数字cmd_id境界の unit test

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^load_cmd_block()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f load_cmd_block
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR
    export QUEUE_FILE="$TEST_TMPDIR/shogun_to_karo.yaml"
    CMD_BLOCK_LOADED=0
    CMD_BLOCK_FOUND=0
    CMD_BLOCK=""
    CMD_BLOCK_NC=""
    export CMD_BLOCK_LOADED CMD_BLOCK_FOUND CMD_BLOCK CMD_BLOCK_NC
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "load_cmd_block: 非数字cmd_idの次境界で正しく停止する" {
    cat > "$QUEUE_FILE" <<'YAML'
commands:
  cmd_training_alpha:
    title: "alpha"
    status: pending
  cmd_karo_beta:
    title: "beta"
    status: delegated
YAML
    CMD_ID="cmd_training_alpha"
    export CMD_ID

    load_cmd_block

    [ "$CMD_BLOCK_FOUND" -eq 1 ]
    [[ "$CMD_BLOCK" == *'title: "alpha"'* ]]
    [[ "$CMD_BLOCK" == *'status: pending'* ]]
    [[ "$CMD_BLOCK" != *'cmd_karo_beta'* ]]
    [[ "$CMD_BLOCK" != *'status: delegated'* ]]
}
