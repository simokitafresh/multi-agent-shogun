#!/usr/bin/env bats
# test_cmd_save_red_flags.bats — mizchi Red flags helper tests for cmd_save.sh

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SAVE_SCRIPT="$PROJECT_ROOT/scripts/cmd_save.sh"
    [ -f "$SRC_SAVE_SCRIPT" ] || return 1

    eval "$(sed -n '/^trim_inline_yaml_scalar()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^load_cmd_block_cache()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_has_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^cmd_block_get_field()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^collect_primary_cmd_targets()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^record_warn_reason()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_self_reread_red_flag()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    eval "$(sed -n '/^check_bundle_red_flag()/,/^}/p' "$SRC_SAVE_SCRIPT")"
    export -f trim_inline_yaml_scalar load_cmd_block_cache cmd_block_has_field cmd_block_get_field \
        collect_primary_cmd_targets record_warn_reason check_self_reread_red_flag check_bundle_red_flag
}

setup() {
    export CMD_BLOCK_NC=""
    export CMD_BLOCK_FOUND=1
    export CMD_BLOCK_CACHE_LOADED=0
    export WARN_COUNT=0
    declare -gA CMD_BLOCK_CACHE=()
}

@test "self reread red flag: 自己確認ワードでWARNING" {
    CMD_BLOCK_NC='    title: "強化 — 曖昧さ自己確認"
    purpose: "将軍の自己申告を追加"
    command: |
      将軍が自分で読み直して曖昧点を自己申告せよ
      目視確認で不明瞭さを潰す'
    export CMD_BLOCK_NC

    run check_self_reread_red_flag
    [ "$status" -eq 0 ]
    [[ "$output" == *"自己再読パターンを検出"* ]]
}

@test "self reread red flag: 通常cmdでは静か" {
    CMD_BLOCK_NC='    title: "強化 — 軍師draftレビュー拡張"
    purpose: "別役割レビューを追加"
    command: |
      軍師が不明瞭点を列挙する'
    export CMD_BLOCK_NC

    run check_self_reread_red_flag
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "bundle red flag: 主要対象3本でWARNING" {
    CMD_BLOCK_NC='    title: "強化 — 5パターン統合"
    target_path: |
      scripts/cmd_save.sh
      scripts/gates/gate_gunshi_cs_checklist.sh
      scripts/deploy_task.sh'
    export CMD_BLOCK_NC

    run check_bundle_red_flag
    [ "$status" -eq 0 ]
    [[ "$output" == *"バンドルパターンを検出"* ]]
    [[ "$output" == *"scripts/cmd_save.sh"* ]]
    [[ "$output" == *"scripts/deploy_task.sh"* ]]
}

@test "bundle red flag: script+testだけではWARNINGしない" {
    CMD_BLOCK_NC='    title: "強化 — 単一修正"
    command: |
      scripts/cmd_save.sh を修正
      tests/unit/test_cmd_save_red_flags.bats を追加'
    export CMD_BLOCK_NC

    run check_bundle_red_flag
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "bundle red flag: docs_research+outputs/projects参照ではWARNINGしない" {
    CMD_BLOCK_NC='    title: "追記 — research note更新"
    target_path: docs/research/
    command: |
      outputs/analysis/cmd_2221_after.txt と projects/infra.yaml を参照して追記'
    export CMD_BLOCK_NC

    run check_bundle_red_flag
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
