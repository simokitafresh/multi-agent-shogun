#!/usr/bin/env bats
# test_cmd_save_ac_test_scope.bats — Check 21.6: ACテストスコープ検証

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

_run_check() {
    run bash -c '
        eval "$(sed -n '"'"'/^build_warn_note()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_key()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^warn_note_message()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^record_warn_reason()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^extract_acceptance_criteria_block()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        eval "$(sed -n '"'"'/^check_ac_test_scope()/,/^}/p'"'"' "$SRC_SAVE_SCRIPT")"
        WARN_COUNT=0
        declare -a WARN_REASONS=()
        check_ac_test_scope
        echo "WARN_COUNT=$WARN_COUNT"
        printf "WARN_REASONS=%s\n" "${WARN_REASONS[*]}"
    '
}

@test "ACに「全テストPASS」が含まれるとWARNが発火する" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: '既存テスト全PASS'
    - id: AC2
      description: '関数が動作すること'"
    _run_check
    echo "$output" >&2
    [[ "$output" == *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
    [[ "$output" == *"check=check_ac_test_scope"* ]]
}

@test "ACに「0 failures」が含まれるとWARNが発火する" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: 'テスト実行で0 failures'
    - id: AC2
      description: '実装が完了していること'"
    _run_check
    echo "$output" >&2
    [[ "$output" == *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
}

@test "ACに「0 skips」が含まれるとWARNが発火する" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: 'bats実行でno skips'
    - id: AC2
      description: 'コードが動くこと'"
    _run_check
    echo "$output" >&2
    [[ "$output" == *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
}

@test "ACに「all tests pass」が含まれるとWARNが発火する" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: 'all tests pass after change'
    - id: AC2
      description: 'implementation done'"
    _run_check
    echo "$output" >&2
    [[ "$output" == *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=1"* ]]
}

@test "WARNメッセージにスコープ限定の具体的修正例が含まれる" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: '全テストPASS'
    - id: AC2
      description: '実装完了'"
    _run_check
    echo "$output" >&2
    [[ "$output" == *"変更対象(scripts/cmd_save.sh)の関連テストPASS"* ]]
    [[ "$output" == *"test_cmd_save*.bats"* ]]
}

@test "「変更対象の関連テストPASS」はスコープ済みなのでWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: '変更対象の関連テストPASS'
    - id: AC2
      description: '実装完了'"
    _run_check
    echo "$output" >&2
    [[ "$output" != *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "「pre-existing failure除外」はスコープ済みなのでWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: '既存テスト全PASS(変更対象の関連テスト。pre-existing failure除外)'
    - id: AC2
      description: '実装完了'"
    _run_check
    echo "$output" >&2
    [[ "$output" != *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "「DB依存テスト11件がPASS」はスコープ済みなのでWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: 'DB依存テスト11件(test_admin_tiers, test_password_expiry等)がPASSすること'
    - id: AC2
      description: 'PostgreSQLサービスが設定されること'"
    _run_check
    echo "$output" >&2
    [[ "$output" != *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "「CI固有テストがPASS」はスコープ済みなのでWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: 'CI固有テストがPASSすること'
    - id: AC2
      description: 'workflow設定が完了していること'"
    _run_check
    echo "$output" >&2
    [[ "$output" != *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "「退行確認テストがPASS」はスコープ済みなのでWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: '退行確認テストがPASSすること'
    - id: AC2
      description: '既存動作が維持されること'"
    _run_check
    echo "$output" >&2
    [[ "$output" != *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "テスト条件を含まないACはWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: 'scripts/cmd_save.shにcheck関数を追加'
    - id: AC2
      description: 'grepでcheck_ac_test_scopeの存在確認'"
    _run_check
    echo "$output" >&2
    [[ "$output" != *"WARN: ACにスコープ未指定のテスト全件条件を検出"* ]]
    [[ "$output" == *"WARN_COUNT=0"* ]]
}

@test "acceptance_criteriaが空のときWARNしない" {
    _set_cmd_block_nc "    acceptance_criteria:
    - id: AC1
      description: '実装'"
    _run_check
    echo "$output" >&2
    [[ "$output" == *"WARN_COUNT=0"* ]]
}
