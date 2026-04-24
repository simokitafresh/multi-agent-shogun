#!/usr/bin/env bats
# test_cmd_save_ac_param_sufficiency.bats — Check 13: ACパラメータ充足度チェック
# cmd_1685: 数量指定+具体値列挙なし→WARN、具体値あり→WARNなし

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    # check_ac_param_sufficiency: Check 13 — 関数をそのまま抽出
    eval "$(sed -n '/^check_ac_param_sufficiency()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f build_warn_note warn_note_key warn_note_message record_warn_reason check_ac_param_sufficiency
}

setup() {
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export WARN_COUNT=0
}

teardown() { true; }

# --- ヘルパー: CMD_BLOCK_NCを直接設定 ---
_set_cmd_block_nc() {
    CMD_BLOCK_NC="$1"
    CMD_BLOCK="$1"
    export CMD_BLOCK CMD_BLOCK_NC
}

# ============================================================
# 異常系: 数量指定あり+具体値なし → WARN
# ============================================================

@test "異常系: 「4条件」のみ→WARNが出力される" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: '前処理4条件が実装されていること'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "output: $output" >&2
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"4条件"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
}

@test "異常系: 「3項目」のみ→WARNが出力される" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: '以下の3項目を満たすこと'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "output: $output" >&2
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
}

@test "異常系: 「5手法」のみ→WARNが出力される" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: '5手法の前処理を実装すること'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
}

# ============================================================
# 正常系: 数量指定あり+具体値列挙あり → WARNなし
# ============================================================

@test "正常系: 「4条件(EMA/SMA/Kalman/Bandpass)」→WARNなし" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: '前処理4条件(EMA/SMA/Kalman/Bandpass)が実装されていること'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "output: $output" >&2
    [[ "$output" != *"WARN: ACに数量指定"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "正常系: 「3項目(A,B,C)」→WARNなし" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: '3項目(条件A,条件B,条件C)を全て実装すること'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    [[ "$output" != *"WARN: ACに数量指定"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "正常系: 「2条件(X・Y)」→WARNなし（中点区切り）" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: '2条件(条件X・条件Y)を満たすこと'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    [[ "$output" != *"WARN: ACに数量指定"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "正常系: 数量指定なし→スキップ" {
    _set_cmd_block_nc "    acceptance_criteria:
    - ac: 'cmd_save.shにチェックが追加されていること'
    - ac: '既存テストが全PASS'"
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    [[ "$output" != *"WARN: ACに数量指定"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "正常系: CMD_BLOCKが空→スキップ" {
    CMD_BLOCK=""
    CMD_BLOCK_NC=""
    export CMD_BLOCK CMD_BLOCK_NC
    run bash -c '
        eval "$(sed -n '"'"'/^check_ac_param_sufficiency()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        check_ac_param_sufficiency
        echo "WARN_COUNT=$WARN_COUNT"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}
