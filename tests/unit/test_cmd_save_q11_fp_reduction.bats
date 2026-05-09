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

@test "Q11-FP-005: 既存道具の接続cmdはgate追加語があっても追加cmd扱いしない" {
    CMD_BLOCK_NC='    title: "強化 — スキル成長ループ完結(PASS記録統一+注意ポイント適用+定期自走化)"
    scope_mode: EXACT
    purpose: "PASS記録を統一し、注意ポイントを適用し、定期自走化で永続的にループを回す"
    command: "gate_report_format.shのPASS分岐にskill_execution_log.sh呼出しを追加。ninja_monitor.shのメインループに週1でskill_auto_improve.sh --apply を実行する条件分岐を追加"
    quality_gate:
      q11_not_already_done: "未達成。既存代替の現物確認結果: grep -c skill_execution_log scripts/gates/gate_report_format.sh → 0件。grep -rn skill_auto_improve scripts/ → skill_auto_improve.sh自身のみ。既存道具の接続であり新規gate追加ではない。代替なし"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 1 ]
}

@test "Q11-TP-001: q11根拠なしの真のgate新設cmdは追加cmd扱いを維持する" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加する"
    quality_gate:
      q11_not_already_done: "未記入"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 0 ]
}

@test "Q11-TP-002: grepで未存在確認済みの真の新規gateは追加cmd扱いを維持する" {
    CMD_BLOCK_NC='    title: "強化 — 新規gate追加"
    scope_mode: EXACT
    purpose: "cmd_save.shへ新規gateを追加して未記入を自動検出する"
    command: "scripts/cmd_save.shに新規gateを追加する"
    quality_gate:
      q11_not_already_done: "未達成。grep -rn missing_required_field scripts/cmd_save.sh → 0件。代替なし。新規gateとして実装する"'
    export CMD_BLOCK_NC

    run is_gate_or_hook_addition_cmd
    [ "$status" -eq 0 ]
}
