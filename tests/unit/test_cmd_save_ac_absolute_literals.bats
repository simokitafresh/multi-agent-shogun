#!/usr/bin/env bats
# test_cmd_save_ac_absolute_literals.bats — Check 21: AC内の数値絶対値WARN検出

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^check_ac_absolute_literals()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f check_ac_absolute_literals
}

setup() {
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export AC_TEXT=""
    export WARN_COUNT=0
}

teardown() { true; }

_set_ac_text() {
    AC_TEXT="$1"
    export AC_TEXT
}

@test "絶対値を含むACはWARN表示する" {
    _set_ac_text '      - id: AC2
        description: "テスト数=118を維持すること"'
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_absolute_literals()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_absolute_literals
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" == *"WARN: ACに数値絶対値パターンを検出"* ]]
    [[ "$output" == *"テスト数=118"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "相対条件のACはWARNしない" {
    _set_ac_text '      - id: AC2
        description: "既存テスト数が減少しないこと"'
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_absolute_literals()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_absolute_literals
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" != *"WARN: ACに数値絶対値パターンを検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "0件やゼロもWARN対象に含む" {
    _set_ac_text '      - id: AC3
        description: "警告が0件であること"
      - id: AC4
        description: "差分がゼロであること"'
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_absolute_literals()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_absolute_literals
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" == *"警告が0件であること"* ]]
    [[ "$output" == *"差分がゼロであること"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}
