#!/usr/bin/env bats
# test_cmd_save_q11_fp_reduction.bats — q11既存代替確認の偽陽性回帰

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^is_gate_or_hook_addition_cmd()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^q11_has_existing_alternative_verification()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block_cache cmd_block_has_field cmd_block_get_field \
        is_gate_or_hook_addition_cmd q11_has_existing_alternative_verification
}

setup() {
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_FOUND=1
    export CMD_BLOCK_CACHE_LOADED=0
    declare -gA CMD_BLOCK_CACHE=()
}

@test "Q11-FP-001: SCOUT cmdはgate文言を含んでも追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "偵察 — gate挙動確認"
    scope_mode: SCOUT
    scout_exempt: true
    purpose: "既存gateの偽陽性を観測する。コード変更なし"
    command: |
      logsを確認して偽陽性パターンを分析する
      is_gate_or_hook_addition_cmd() にscope_mode=SCOUT除外追加案を検討する'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-002: 既存gate精度改善cmdは詳細手順に追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — cmd_save.sh gate偽陽性一括修正"
    scope_mode: IMPL
    purpose: "既存gateの偽陽性率を下げる精度改善"
    command: |
      logs/cmd_design_quality.yamlの直近50件でFPを分析し共通根を修正せよ
      is_gate_or_hook_addition_cmd()にscope_mode=SCOUT除外追加'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-FP-003: 真のgate新設cmdは従来通り追加cmd扱いする" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: IMPL
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: |
      bash scripts/cmd_save.sh 9994'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 0 ]
}

@test "Q11-FP-004: grep根拠+偽陽性修正文言があれば既存代替確認済みとみなす" {
    run q11_has_existing_alternative_verification \
        "yes — grep 'FP率.*一括' context/cmd-chronicle.md→0件(2026-04-25確認) 既存gateの偽陽性修正(精度改善)であり初回"
    [ "$status" -eq 0 ]
}
