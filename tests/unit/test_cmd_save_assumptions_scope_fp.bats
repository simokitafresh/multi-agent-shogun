#!/usr/bin/env bats
# test_cmd_save_assumptions_scope_fp.bats — assumptions日付境界 + SCOUT除外回帰

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^build_warn_note()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_key()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^warn_note_message()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_assumption_claims_missing_dates()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_gunshi_design_num_relax()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block_cache cmd_block_has_field cmd_block_get_field \
        build_warn_note warn_note_key warn_note_message record_warn_reason \
        collect_assumption_claims_missing_dates check_gunshi_design_num_relax
}

setup() {
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_FOUND=1
    export CMD_BLOCK_CACHE_LOADED=0
    export WARN_COUNT=0
    declare -gA CMD_BLOCK_CACHE=()
    declare -ga WARN_REASONS=()
}

@test "AS-FP-001: 実装由来の安定claimは日付なしでもWARNING対象にしない" {
    CMD_BLOCK_NC='    assumptions:
      - claim: "AC数量指定WARNは cmd_save.sh の check_ac_param_sufficiency で検出される"
        source: "scripts/cmd_save.sh"
        trust: "verified"'
    export CMD_BLOCK_NC

    run collect_assumption_claims_missing_dates
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AS-FP-002: 状態主張のclaimは日付なしなら従来通りWARNING対象にする" {
    CMD_BLOCK_NC='    assumptions:
      - claim: "既存代替の確認は完了している"
        source: "tests/unit/test_cmd_save.bats"
        trust: "verified"'
    export CMD_BLOCK_NC

    run collect_assumption_claims_missing_dates
    [ "$status" -eq 0 ]
    [[ "$output" == *"既存代替の確認は完了している"* ]]
}

@test "AS-FP-003: SCOUT cmdは軍師設計書の数値比較WARNINGを出さない" {
    CMD_BLOCK_NC='    scope_mode: SCOUT
    scout_exempt: true
    quality_gate:
      q5_verified_source: "docs/research/gunshi_speed_design.md §2"
      q8_why_what: "WHY: 調査 → WHAT: 5ページの計測を記録する"
    acceptance_criteria:
      - ac: "全17ページの初回表示時間を報告"'
    export CMD_BLOCK_NC

    run check_gunshi_design_num_relax
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "AS-FP-004: IMPL cmdの軍師設計書数値緩和は従来通りWARNINGする" {
    CMD_BLOCK_NC='    scope_mode: IMPL
    quality_gate:
      q5_verified_source: "docs/research/gunshi_speed_design.md §2"
      q8_why_what: "WHY: 設計書遵守 → WHAT: 5ページを改善する"
    acceptance_criteria:
      - ac: "全17ページで改善する"'
    export CMD_BLOCK_NC

    run check_gunshi_design_num_relax
    [ "$status" -eq 0 ]
    [[ "$output" == *"数値緩和を検出"* ]]
}
