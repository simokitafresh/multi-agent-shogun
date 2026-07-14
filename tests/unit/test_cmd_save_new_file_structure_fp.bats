#!/usr/bin/env bats

setup() {
    export SRC_SAVE_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/cmd_save.sh"
}

@test "acceptance criteria extraction stops before quality_gate at matching indentation" {
    run bash -c '
        eval "$(sed -n '\''/^extract_acceptance_criteria_block()/,/^}/p'\'' "$SRC_SAVE_SCRIPT")"
        CMD_BLOCK_NC="  acceptance_criteria:
    - id: AC1
      description: 既存テストを全量実行する
  quality_gate:
    q5_existing_asset: 新規ファイル作成前に既存資産を確認する
    q11_structure: 新規構造を作らない理由を説明する"
        extract_acceptance_criteria_block
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"既存テストを全量実行する"* ]]
    [[ "$output" != *"新規ファイル"* ]]
    [[ "$output" != *"新規構造"* ]]
}

@test "quality gate q fields are excluded defensively from new-file hits" {
    run bash -c '
        SRC_SAVE_SCRIPT="$SRC_SAVE_SCRIPT"
        eval "$(sed -n '\''/^check_new_file_structure_warning()/,/^}/p'\'' "$SRC_SAVE_SCRIPT")"
        extract_acceptance_criteria_block() {
            printf "%s\n" "    - description: 既存テストを全量実行する" \
                "    - q5_existing_asset: 新規ファイル作成前に既存資産を確認する" \
                "      q11_structure_reason: 新規構造を作らない理由を説明する"
        }
        CMD_BLOCK_NC="command: echo ok"
        record_warn_reason() { printf "WARN_RECORDED\n"; }
        check_new_file_structure_warning
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN_RECORDED"* ]]
}
