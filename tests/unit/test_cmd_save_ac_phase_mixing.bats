#!/usr/bin/env bats
# test_cmd_save_ac_phase_mixing.bats — Check 21.5: ACフェーズ混在検出

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1
}

setup() {
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export WARN_COUNT=0
    export WARN_REASONS=()
}

teardown() { true; }

_set_cmd_block_nc() {
    CMD_BLOCK_NC="$1"
    CMD_BLOCK="$1"
    export CMD_BLOCK CMD_BLOCK_NC
}

@test "実装ACと計測ACが別ACに分離されているとWARNしない(FP修正)" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      check: 'scripts/cmd_save.shにcheck_ac_phase_mixingを実装する'
    - id: AC2
      check: 'CDP計測でbefore/afterを確認する'"
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_phase_mixing()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_phase_mixing
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" != *"WARN: ACフェーズ混在を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "実装ACとcommit ACが別ACに分離されているとWARNしない(FP修正)" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      check: 'scripts/cmd_save.shにチェックを追加する'
    - id: AC2
      check: 'git commitが完了している'"
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_phase_mixing()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_phase_mixing
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" != *"WARN: ACフェーズ混在を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "同一AC内に実装と計測が共起するとWARNが発火する(TP)" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      check: '修正してCDP計測でbefore/afterを確認する'"
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_phase_mixing()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_phase_mixing
        echo "WARN_COUNT=$WARN_COUNT"
        printf "WARN_REASONS=%s\n" "${WARN_REASONS[*]}"
    '
    echo "$output" >&2
    [[ "$output" == *"WARN: ACフェーズ混在を検出"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
    [[ "$output" == *"check=check_ac_phase_mixing"* ]]
}

@test "同一AC内に実装とcommitが共起するとWARNが発火する(TP)" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      check: '追加してgit commitする'"
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_phase_mixing()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_phase_mixing
        echo "WARN_COUNT=$WARN_COUNT"
        printf "WARN_REASONS=%s\n" "${WARN_REASONS[*]}"
    '
    echo "$output" >&2
    [[ "$output" == *"WARN: ACフェーズ混在を検出"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
    [[ "$output" == *"check=check_ac_phase_mixing"* ]]
}

@test "実装のみのACはWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      check: 'scripts/cmd_save.shにチェック関数を追加する'
    - id: AC2
      check: 'grepでcheck_ac_phase_mixingの存在を確認する'"
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_phase_mixing()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_phase_mixing
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" != *"WARN: ACフェーズ混在を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "計測のみのACはWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      check: 'CDP計測を実行する'
    - id: AC2
      check: 'benchmark結果を記録する'"
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_phase_mixing()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_phase_mixing
        echo "WARN_COUNT=$WARN_COUNT"
    '
    echo "$output" >&2
    [[ "$output" != *"WARN: ACフェーズ混在を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}
