#!/usr/bin/env bats
# test_cmd_save_check19_fp.bats — Check 19過去形除外FP修正の回帰テスト
# AC2: 分析系title(修正版SQLite等の過去形表現)でCheck 19が非発火
# AC3: 本番DB操作系title(本番登録/recalculate sync等)でCheck 19が正当発火

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
    export -f trim_inline_yaml_scalar load_cmd_block_cache cmd_block_has_field cmd_block_get_field \
        build_warn_note warn_note_key warn_note_message record_warn_reason

    # Check 19インラインセクションを関数化
    eval "check_19_parity_ac() {
$(sed -n '/^# --- Check 19:/,/^# --- Check 20:/{/^# --- Check 20:/d;p}' "$SRC_SAVE_SCRIPT")
}"
    export -f check_19_parity_ac
}

setup() {
    export CMD_BLOCK=""
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_FOUND=1
    export CMD_BLOCK_CACHE_LOADED=0
    export WARN_COUNT=0
    export AC_TEXT=""
    declare -gA CMD_BLOCK_CACHE=()
    declare -ga WARN_REASONS=()
}

# --- AC2: 分析系title(過去形表現)でCheck 19が非発火 ---

@test "C19-FP-001: 修正版SQLite+recalculate syncを含む分析cmdはCheck 19を発火しない" {
    CMD_BLOCK='  title: 修正版SQLite recalculate sync分析
  purpose: 改善前後の性能比較'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    export CMD_BLOCK CMD_BLOCK_NC

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: パリティcmdのAC基準欠落"* ]]
}

@test "C19-FP-002: 修正済み本番登録を含む分析cmdはCheck 19を発火しない" {
    CMD_BLOCK='  title: 修正済み本番登録パリティ結果レビュー
  purpose: 先日の修正済みパリティ確認'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    export CMD_BLOCK CMD_BLOCK_NC

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: パリティcmdのAC基準欠落"* ]]
}

@test "C19-FP-003: 修正後recalculate syncを含む分析cmdはCheck 19を発火しない" {
    CMD_BLOCK='  title: 修正後recalculate sync結果確認
  purpose: 変更後の動作確認'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    export CMD_BLOCK CMD_BLOCK_NC

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: パリティcmdのAC基準欠落"* ]]
}

@test "C19-FP-004: 完了後パリティを含む分析cmdはCheck 19を発火しない" {
    CMD_BLOCK='  title: 実装完了後パリティ検証分析
  purpose: 完了後の確認作業'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    export CMD_BLOCK CMD_BLOCK_NC

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING: パリティcmdのAC基準欠落"* ]]
}

# --- AC3: 本番DB操作系cmdでCheck 19が正当発火 ---

@test "C19-TP-001: 本番登録recalculate syncを含むcmdはCheck 19を発火する" {
    CMD_BLOCK='  title: 本番登録 recalculate sync実行
  purpose: 全PF本番データ更新'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    AC_TEXT=""
    export CMD_BLOCK CMD_BLOCK_NC AC_TEXT

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: パリティcmdのAC基準欠落"* ]]
}

@test "C19-TP-002: パリティ確認cmdはCheck 19を発火する" {
    CMD_BLOCK='  title: パリティ確認 本番環境
  purpose: 本番DBとの整合性確認'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    AC_TEXT=""
    export CMD_BLOCK CMD_BLOCK_NC AC_TEXT

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: パリティcmdのAC基準欠落"* ]]
}

@test "C19-TP-003: 本番登録本番環境のparity cmdはCheck 19を発火する" {
    CMD_BLOCK='  title: parity check 本番登録
  purpose: シン忍法v3 本番登録実施'
    CMD_BLOCK_NC="$CMD_BLOCK"
    CMD_BLOCK_CACHE['scope_mode']=''
    AC_TEXT=""
    export CMD_BLOCK CMD_BLOCK_NC AC_TEXT

    run check_19_parity_ac
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: パリティcmdのAC基準欠落"* ]]
}
