#!/usr/bin/env bats
# test_necessity: 殿裁定 2026-09-06 21:23 の不変量『AC は忍者権限内で閉じる・可逆操作に回数制限を書かない』を
# cmd_save.sh の check_ac_authority_scope_warn が CLI/モデル/clear に依らず検出すること(正負対照)。

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FN="$(awk '/^check_ac_authority_scope_warn\(\) \{/,/^}/' "$ROOT/scripts/cmd_save.sh")"
    [ -n "$FN" ]
}

run_check() {
    local text="$1"
    bash -c "
        WARNS=()
        record_warn_reason() { WARNS+=(\"\$1\"); }
        $FN
        check_ac_authority_scope_warn \"\$1\" 2>/dev/null
        printf '%s\n' \"\${WARNS[@]}\"
    " _ "$text"
}

@test "positive: readonly 取得の回数制限を検出" {
    run run_check $'  cmd_x:\n    acceptance_criteria:\n      AC1:\n        description: "readonly_query で 1 回だけ取得する"\n    command: |\n      x'
    [[ "$output" == *"AC可逆操作の回数制限"* ]]
}

@test "positive: 本番書込の段を検出(lord_ok なし)" {
    run run_check $'  cmd_x:\n    acceptance_criteria:\n      AC1:\n        description: "本番 DB へ INSERT して反映する"\n    command: |\n      x'
    [[ "$output" == *"AC権限外の段"* ]]
}

@test "negative: lord_ok があれば権限外の段を許可" {
    run run_check $'  cmd_x:\n    lord_ok: "2026-09-06 20:29 事後承認"\n    acceptance_criteria:\n      AC1:\n        description: "本番 DB へ INSERT して反映する"\n    command: |\n      x'
    [[ "$output" != *"AC権限外の段"* ]]
}

@test "negative: 『本番 DB 書込 0』の証跡文言は誤検知しない" {
    run run_check $'  cmd_x:\n    acceptance_criteria:\n      AC1:\n        binary_check: "logs に『本番 DB 書込 0』の生貼付があるか"\n    command: |\n      x'
    [[ "$output" != *"AC権限外の段"* ]]
    [[ "$output" != *"回数制限"* ]]
}

@test "negative: command 節の『1 回』は AC 外なので対象外" {
    run run_check $'  cmd_x:\n    acceptance_criteria:\n      AC1:\n        description: "隔離 DB で A/B を突合する"\n    command: |\n      1. 取得は 1 回だけにまとめる'
    [[ "$output" != *"回数制限"* ]]
}
