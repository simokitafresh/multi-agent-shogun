#!/usr/bin/env bats
# test_cmd_save_numeric_relax_identifier_fp.bats — check_gunshi_design_num_relax
# 英字始まり識別子(float8send/sha256等)内の数字をAC/WHAT数値として誤抽出するFPの回帰防護
# origin: cmd_3850(2026-07-11) float8sendの8がAC最大値と誤認→数値緩和WARN誤発火

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cmd_save_numrelax.XXXXXX")"

    cat > "$TEST_TMPDIR/run_check.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -uo pipefail
CMD_BLOCK_NC="$1"
CMD_BLOCK="$CMD_BLOCK_NC"
AC_TEXT=""
WARN_FIRED=0

cmd_block_get_field() {
    local field="${1##*.}"
    echo "$CMD_BLOCK_NC" | grep -m1 "^[[:space:]]*${field}:" | sed "s/^[[:space:]]*${field}:[[:space:]]*//; s/^\"//; s/\"\$//"
}

record_warn_reason() {
    WARN_FIRED=1
    echo "WARN_RECORDED: $1" >&2
}
WRAPPER
    sed -n '/^check_gunshi_design_num_relax()/,/^}/p' \
        "$PROJECT_ROOT/scripts/cmd_save.sh" >> "$TEST_TMPDIR/run_check.sh"
    cat >> "$TEST_TMPDIR/run_check.sh" <<'CALL'
check_gunshi_design_num_relax
echo "WARN_FIRED=$WARN_FIRED"
CALL
    chmod +x "$TEST_TMPDIR/run_check.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "float8send等の識別子内数字はAC数値として抽出されずWARNしない" {
    run bash "$TEST_TMPDIR/run_check.sh" '  cmd_9001:
    scope_mode: FULL
    acceptance_criteria:
      AC1:
        description: "書込み後のfloat8send hexを採取し4系統artifactで確認する"
        binary_check: "float8send hexの採取が4系統で確認されているか"
    quality_gate:
      q5_verified_source: "isolated_test — 設計書v1.4.6を現物確認"
      q8_why_what: "WHY: 原因不明 / WHAT: 4系統のbit採取と3比較で局在 / WHEN: 今 / WHERE: clone / WHO: 忍者1名 / HOW: 実装 / 複利: 再利用"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN_FIRED=0"* ]]
}

@test "真の数値緩和(AC最大値がWHAT最大値超)は引き続きWARNする" {
    run bash "$TEST_TMPDIR/run_check.sh" '  cmd_9002:
    scope_mode: FULL
    acceptance_criteria:
      AC1:
        description: "処理を10秒以内で完了することを確認する"
        binary_check: "10秒以内で完了しているか"
    quality_gate:
      q5_verified_source: "isolated_test — 設計書v1.4.6を現物確認"
      q8_why_what: "WHY: 原因不明 / WHAT: 5秒以内の処理化 / WHEN: 今 / WHERE: clone / WHO: 忍者1名 / HOW: 実装 / 複利: 再利用"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN_FIRED=1"* ]]
}

@test "WHAT側の識別子内数字(sha256等)も設計数値として扱わない" {
    run bash "$TEST_TMPDIR/run_check.sh" '  cmd_9003:
    scope_mode: FULL
    acceptance_criteria:
      AC1:
        description: "処理を3比較で確認する"
        binary_check: "3比較が完了しているか"
    quality_gate:
      q5_verified_source: "isolated_test — 設計書v1.4.6を現物確認"
      q8_why_what: "WHY: 原因不明 / WHAT: sha256による2系統照合 / WHEN: 今 / WHERE: clone / WHO: 忍者1名 / HOW: 実装 / 複利: 再利用"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN_FIRED=1"* ]]
}
