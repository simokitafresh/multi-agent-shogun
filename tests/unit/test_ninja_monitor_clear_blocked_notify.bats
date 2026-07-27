#!/usr/bin/env bats
# test_necessity: CLEAR-BLOCKEDが窓内でしきい値N回に達した時に家老へ通知1回のみ送り、
#   カウンタがリセットされるまで再送しないという不変量(cmd_karo_hotfix_auto_clear_recovery_20260727 T1/T2)を守る。
#   38時間1,136件が無通知だった事故の再発防止契約。

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    TMP_ROOT="$BATS_TEST_TMPDIR"
    mkdir -p "$TMP_ROOT/scripts"
    cat > "$TMP_ROOT/scripts/inbox_write.sh" <<'STUB'
#!/bin/bash
echo "INBOX_CALLED:$@" >> "${INBOX_CALL_LOG:-/dev/null}"
STUB
    chmod +x "$TMP_ROOT/scripts/inbox_write.sh"
    export INBOX_CALL_LOG="$TMP_ROOT/inbox_calls.log"
    touch "$INBOX_CALL_LOG"
}

@test "N=3到達で通知1件、N+1回目は再送抑止" {
    run bash -c '
NINJA_MONITOR_LIB_ONLY=1 source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
SCRIPT_DIR="'"$TMP_ROOT"'"; LOG="'"$TMP_ROOT"'/test.log"; touch "$LOG"
declare -A CLEAR_BLOCKED_TS CLEAR_BLOCKED_NOTIFIED
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
'
    [ "$status" -eq 0 ]
    calls=$(wc -l < "$INBOX_CALL_LOG")
    [ "$calls" -eq 1 ]
}

@test "成功リセット後は再びN回で通知される" {
    run bash -c '
NINJA_MONITOR_LIB_ONLY=1 source "'"$PROJECT_ROOT"'/scripts/ninja_monitor.sh"
SCRIPT_DIR="'"$TMP_ROOT"'"; LOG="'"$TMP_ROOT"'/test.log"; touch "$LOG"
declare -A CLEAR_BLOCKED_TS CLEAR_BLOCKED_NOTIFIED
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
_reset_clear_blocked_counter hayate
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
_record_clear_blocked_and_maybe_notify hayate
'
    [ "$status" -eq 0 ]
    calls=$(wc -l < "$INBOX_CALL_LOG")
    [ "$calls" -eq 2 ]
}
