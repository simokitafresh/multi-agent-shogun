#!/usr/bin/env bats
# test_necessity: stop_session_alerts.sh は指揮官ロールのsession_alerts_{role}.txtに[TODO]が残っている間だけ decision:block を出力し、[TODO]が無ければ何も出力しない（対照fixture: 陽性1+陰性1）。
# cmd_karo_impl_control_fixture_stop_session_alerts_20260726
# 設計書v3.0 §1: 既知の陽性1件を検出し、既知の陰性1件を通すことを毎回証明できない検知器は存在してはならない。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$PROJECT_ROOT/scripts/hooks/stop_session_alerts.sh"
    [ -f "$HOOK" ] || return 1
    FAKE_ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$FAKE_ROOT/queue"
    ALERTS="$FAKE_ROOT/queue/session_alerts_shogun.txt"
    export PROJECT_ROOT HOOK FAKE_ROOT ALERTS
    # 実tmuxのagent_idを引かせない（実行者のpaneに依存させない）
    export TMUX_PANE=""
}

_run_hook() {
    run env STOP_SESSION_ALERTS_ROOT="$FAKE_ROOT" \
        MOCK_AGENT_ID="$1" \
        STOP_SESSION_ALERTS_FAIL_HASH_FILE="$BATS_TEST_TMPDIR/fail_hash_$1_$2" \
        TMUX_PANE="" \
        bash "$HOOK"
}

@test "陽性対照: 未完了[TODO]が残る指揮官セッションを検出しdecision:blockを出す" {
    printf '[TODO] startup gate ALERT未処理\n[DONE] 処理済み\n' > "$ALERTS"

    _run_hook shogun positive

    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"SESSION ALERTS 未完了あり(1件)"* ]]
}

@test "陰性対照: [TODO]が残っていない正常系は何も出力せず通す" {
    printf '[DONE] 処理済み\n[DONE] 処理済み2\n' > "$ALERTS"

    _run_hook shogun negative

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
