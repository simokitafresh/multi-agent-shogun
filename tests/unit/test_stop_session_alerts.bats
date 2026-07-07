#!/usr/bin/env bats
# W3 (cmd_3748) stop_session_alerts.sh 自動通過の掲示板記録 検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/hooks/stop_session_alerts.sh"
    export BULLETIN_SCRIPT="$PROJECT_ROOT/scripts/bulletin_write.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    [ -f "$BULLETIN_SCRIPT" ] || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/stop_session_alerts.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/queue"
    export STOP_SESSION_ALERTS_ROOT="$TEST_TMPDIR"
    export STOP_SESSION_ALERTS_BULLETIN_SCRIPT="$BULLETIN_SCRIPT"
    export STOP_SESSION_ALERTS_FAIL_HASH_FILE="$TEST_TMPDIR/fail_hash"
    export MOCK_AGENT_ID="shogun"
    unset TMUX_PANE
    printf '[TODO] 三層記憶DB健全性チェック未実施\n' > "$TEST_TMPDIR/queue/session_alerts_shogun.txt"
}

teardown() {
    unset STOP_SESSION_ALERTS_ROOT STOP_SESSION_ALERTS_BULLETIN_SCRIPT STOP_SESSION_ALERTS_FAIL_HASH_FILE MOCK_AGENT_ID
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "stop_session_alerts does not post to bulletin before bypass threshold" {
    for i in 1 2 3 4; do
        run bash "$SRC_SCRIPT"
        [ "$status" -eq 0 ]
        [[ "$output" == *'"decision": "block"'* ]]
    done
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}

@test "stop_session_alerts posts bypass reason and remaining count to bulletin at threshold" {
    for i in 1 2 3 4; do
        run bash "$SRC_SCRIPT"
        [ "$status" -eq 0 ]
    done
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]

    # 5回目: 同一ハッシュがBLOCK_BYPASS_THRESHOLD(5)に到達し自動通過
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]

    [ -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
    grep -q "stop hook自動通過" "$TEST_TMPDIR/queue/bulletin_board.yaml"
    grep -q "shogunの同一BLOCKが5回連続到達し無条件通過" "$TEST_TMPDIR/queue/bulletin_board.yaml"
    grep -q "残件1件" "$TEST_TMPDIR/queue/bulletin_board.yaml"
    grep -q "三層記憶DB健全性チェック未実施" "$TEST_TMPDIR/queue/bulletin_board.yaml"
    [ ! -f "$STOP_SESSION_ALERTS_FAIL_HASH_FILE" ]
}

@test "stop_session_alerts skips ninja roles without touching bulletin" {
    export MOCK_AGENT_ID="hayate"
    run bash "$SRC_SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$TEST_TMPDIR/queue/bulletin_board.yaml" ]
}
