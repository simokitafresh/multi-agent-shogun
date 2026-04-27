#!/usr/bin/env bats
# test_gunshi_notify.bats — cmd_1665: gunshi_notify.sh関数単体テスト
# 独立sourceファイルを直接テスト（gate全体実行を回避 → 33s TIMEOUT解消）

setup_file() {
    export REAL_PROJECT_ROOT
    REAL_PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_LIB="$REAL_PROJECT_ROOT/scripts/lib/gunshi_notify.sh"
    [ -f "$SRC_LIB" ] || return 1
}

setup() {
    export TEST_TMPDIR
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gunshi_notify.XXXXXX")"
    export PROJECT_ROOT="$TEST_TMPDIR"

    mkdir -p \
        "$TEST_TMPDIR/scripts" \
        "$TEST_TMPDIR/queue/gates/cmd_999" \
        "$TEST_TMPDIR/queue/reports" \
        "$TEST_TMPDIR/logs"

    # inbox_write.sh stub
    cat > "$TEST_TMPDIR/scripts/inbox_write.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "$@" >> "$PROJECT_ROOT/logs/inbox_write_calls.log"
exit 0
STUBEOF
    chmod +x "$TEST_TMPDIR/scripts/inbox_write.sh"

    # source the extracted function
    source "$SRC_LIB"
}

teardown() {
    [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

write_report() {
    local ninja="$1"
    local status="${2:-completed}"
    cat > "$TEST_TMPDIR/queue/reports/${ninja}_report_cmd_999.yaml" <<EOF
worker_id: $ninja
status: $status
verdict: PASS
EOF
}

@test "completed report triggers gunshi notification" {
    write_report "sasuke" "completed"

    run notify_gunshi_for_report "sasuke" "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" "cmd_999"

    # inbox_write呼び出しログ確認
    [ -f "$TEST_TMPDIR/logs/inbox_write_calls.log" ]
    grep -q "gunshi" "$TEST_TMPDIR/logs/inbox_write_calls.log"
    grep -q "report_review" "$TEST_TMPDIR/logs/inbox_write_calls.log"
    grep -q "sasuke" "$TEST_TMPDIR/logs/inbox_write_calls.log"

    # フラグファイル作成確認
    [ -f "$TEST_TMPDIR/queue/gates/cmd_999/gunshi_report_review_notify_sasuke.done" ]

    # 出力確認
    [[ "$output" == *"gunshi_notify: SENT"* ]]
}

@test "training cmd skips gunshi notification" {
    write_report "hayate" "completed"
    mkdir -p "$TEST_TMPDIR/queue/gates/cmd_training_structural_001"

    run notify_gunshi_for_report "hayate" "$TEST_TMPDIR/queue/reports/hayate_report_cmd_999.yaml" "cmd_training_structural_001"

    [[ "$output" == *"gunshi_notify: SKIP (training cmd:"* ]]

    # inbox_writeが呼ばれていないことを確認
    if [ -f "$TEST_TMPDIR/logs/inbox_write_calls.log" ]; then
        ! grep -q "gunshi.*report_review" "$TEST_TMPDIR/logs/inbox_write_calls.log"
    fi
}

@test "duplicate notification prevented by flag file" {
    write_report "sasuke" "completed"

    # 1回目: 通知送信
    run notify_gunshi_for_report "sasuke" "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" "cmd_999"
    [[ "$output" == *"gunshi_notify: SENT"* ]]

    # 2回目: フラグ存在で重複通知なし
    run notify_gunshi_for_report "sasuke" "$TEST_TMPDIR/queue/reports/sasuke_report_cmd_999.yaml" "cmd_999"
    ! [[ "$output" == *"gunshi_notify: SENT"* ]]
}
