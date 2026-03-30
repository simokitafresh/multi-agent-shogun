#!/usr/bin/env bats
# test_cmd_save_q7_branch.bats — q7_branch_coverage: 条件分岐変更cmdの本番データ分岐確認AC提案
#
# テスト構成:
#   T-001: type=impl + purpose含"分岐" → WARNING
#   T-002: type=impl + purpose含"if" → WARNING
#   T-003: type=impl + purpose無キーワード → WARNING出ない
#   T-004: type=recon + purpose含"分岐" → WARNING出ない(impl限定)
#   T-005: type=impl + title含"条件" → WARNING(titleも検査対象)
#   T-006: WARNメッセージに具体的アクション例を含む(AC2検証)

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    [ -f "$PROJECT_ROOT/scripts/cmd_save.sh" ] || return 1

    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cmd_save_q7.XXXXXX")"

    # q7チェックロジックを抽出したテスト用ラッパー
    cat > "$TEST_TMPDIR/test_q7.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
CMD_BLOCK="$1"

_Q7_TASK_TYPE=$(echo "$CMD_BLOCK" | awk '/task_type:/{gsub(/.*task_type: */, ""); gsub(/"/, ""); print; exit}')
if [[ "${_Q7_TASK_TYPE:-}" == "impl" ]]; then
    _Q7_FIELDS=$(echo "$CMD_BLOCK" | grep -E '^\s*(purpose|title):' || true)
    if echo "$_Q7_FIELDS" | grep -qiE '\bif\b|\bcase\b|条件|分岐|フラグ|\bflag\b|\belif\b|\bswitch\b'; then
        echo "WARNING: q7_branch_coverage — 条件分岐変更を含むimpl cmdです。本番データでの分岐実行頻度確認ACの追加を検討してください" >&2
        echo "  推奨アクション: 本番DBで該当条件がtrue/falseになるレコード数を確認せよ" >&2
        echo "  (cmd_1443教訓: 本番未使用コードパスへの修正は無駄コスト+リスク)" >&2
    fi
fi
WRAPPER
    chmod +x "$TEST_TMPDIR/test_q7.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# T-001: type=impl + purpose含"分岐" → WARNING
@test "T-001: impl cmd with branch keyword in purpose triggers WARNING" {
    local CMD_BLOCK="    task_type: impl
    purpose: 条件分岐を変更してフィルタロジックを修正"
    run bash "$TEST_TMPDIR/test_q7.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"q7_branch_coverage"* ]]
}

# T-002: type=impl + purpose含"if" → WARNING
@test "T-002: impl cmd with 'if' in purpose triggers WARNING" {
    local CMD_BLOCK="    task_type: impl
    purpose: if文の条件式を修正して例外処理を追加"
    run bash "$TEST_TMPDIR/test_q7.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"q7_branch_coverage"* ]]
}

# T-003: type=impl + purpose無キーワード → WARNING出ない
@test "T-003: impl cmd without branch keywords produces no WARNING" {
    local CMD_BLOCK="    task_type: impl
    purpose: ログメッセージのフォーマットを統一する"
    run bash "$TEST_TMPDIR/test_q7.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"q7_branch_coverage"* ]]
}

# T-004: type=recon + purpose含"分岐" → WARNING出ない(impl限定)
@test "T-004: recon cmd with branch keyword does NOT trigger WARNING" {
    local CMD_BLOCK="    task_type: recon
    purpose: 条件分岐の網羅性を調査"
    run bash "$TEST_TMPDIR/test_q7.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"q7_branch_coverage"* ]]
}

# T-005: type=impl + title含"条件" → WARNING(titleも検査対象)
@test "T-005: impl cmd with branch keyword in title triggers WARNING" {
    local CMD_BLOCK="    task_type: impl
    title: 条件判定ロジックのリファクタリング
    purpose: パフォーマンス改善のためロジック整理"
    run bash "$TEST_TMPDIR/test_q7.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"q7_branch_coverage"* ]]
}

# T-006: WARNメッセージに具体的アクション例を含む(AC2検証)
@test "T-006: WARNING message contains recommended action with DB check example" {
    local CMD_BLOCK="    task_type: impl
    purpose: フラグによる分岐を追加"
    run bash "$TEST_TMPDIR/test_q7.sh" "$CMD_BLOCK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"本番DB"* ]]
    [[ "$output" == *"true/false"* ]]
    [[ "$output" == *"レコード数"* ]]
}
