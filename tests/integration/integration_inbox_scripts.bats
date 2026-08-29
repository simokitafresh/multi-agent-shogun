#!/usr/bin/env bats
# test_necessity: a clean-runner inbox write followed by mark-read must preserve exactly one message and transition its unread state atomically.

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMP
    TEST_TMP="$(mktemp -d)"

    mkdir -p "$TEST_TMP/scripts/lib" "$TEST_TMP/queue/inbox"
    cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMP/scripts/inbox_write.sh"
    cp "$PROJECT_ROOT/scripts/inbox_mark_read.sh" "$TEST_TMP/scripts/inbox_mark_read.sh"
    cp "$PROJECT_ROOT/scripts/lib/lock_path.sh" "$TEST_TMP/scripts/lib/lock_path.sh"
    cp "$PROJECT_ROOT/scripts/lib/report_completion_events.sh" "$TEST_TMP/scripts/lib/report_completion_events.sh"
    # inbox_write.sh sources this helper; copy it to keep the isolated fixture CI-complete.
    cp "$PROJECT_ROOT/scripts/lib/escalation_evidence.sh" "$TEST_TMP/scripts/lib/escalation_evidence.sh"
    chmod +x "$TEST_TMP/scripts/inbox_write.sh" "$TEST_TMP/scripts/inbox_mark_read.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "integration inbox scripts: write then mark-read preserves one message atomically" {
    run env INBOX_WRITE_TEST=1 bash "$TEST_TMP/scripts/inbox_write.sh" karo "task_id=commander_directive subject_task_id=cmd_integration_inbox_scripts_normal parent_cmd=cmd_integration_inbox_scripts integration smoke" wake_up test_runner
    [ "$status" -eq 0 ]

    [ -f "$TEST_TMP/queue/inbox/karo.yaml" ]
    grep -q "content: 'task_id=commander_directive subject_task_id=cmd_integration_inbox_scripts_normal parent_cmd=cmd_integration_inbox_scripts integration smoke'" "$TEST_TMP/queue/inbox/karo.yaml"
    grep -q "read: false" "$TEST_TMP/queue/inbox/karo.yaml"

    msg_id="$(awk -F"'" '/^[[:space:]]*id:/ { print $2; exit }' "$TEST_TMP/queue/inbox/karo.yaml")"
    [ -n "$msg_id" ]

    run bash "$TEST_TMP/scripts/inbox_mark_read.sh" karo "$msg_id"
    [ "$status" -eq 0 ]

    grep -q "read: true" "$TEST_TMP/queue/inbox/karo.yaml"
    ! grep -q "read: false" "$TEST_TMP/queue/inbox/karo.yaml"
}
