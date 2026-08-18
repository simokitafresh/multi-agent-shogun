#!/usr/bin/env bats
# test_necessity: Codex delivery success requires the unique message to become
# read or a pane state transition observed after persistence; pre-send generic
# Working evidence must never authorize ASYNC_VERIFY SUCCESS.

setup() {
    ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts" "$ROOT/queue/inbox" "$ROOT/queue/tasks" "$ROOT/config" "$ROOT/bin" "$ROOT/logs"
    ln -s "$BATS_TEST_DIRNAME/../../scripts/lib" "$ROOT/scripts/lib"
    printf 'task:\n  status: assigned\n' > "$ROOT/queue/tasks/testninja.yaml"
    cat > "$ROOT/config/settings.yaml" <<'YAML'
cli:
  default: codex
  agents:
    testninja:
      type: codex
YAML
    cat > "$ROOT/bin/pgrep" <<'SCRIPT'
#!/usr/bin/env bash
printf '123 bash /repo/scripts/inbox_watcher.sh testninja shogun:agents.3 codex\n'
SCRIPT
    cat > "$ROOT/bin/tmux" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = list-panes ]; then
    printf 'shogun:agents.3 testninja\n'
elif [ "$1" = capture-pane ]; then
    count=0
    [ -f "$CAPTURE_COUNT_FILE" ] && count=$(cat "$CAPTURE_COUNT_FILE")
    count=$((count + 1))
    printf '%s\n' "$count" > "$CAPTURE_COUNT_FILE"
    if [ "${CAPTURE_MODE:-static}" = changed ] && [ "$count" -lt 2 ]; then
        printf '›\n'
    elif [ "${CAPTURE_MODE:-static}" = changed ]; then
        printf 'inbox2 — タスクYAML: /tmp/fixture/queue/tasks/testninja.yaml delivery_msg=%s\n' "$EXPECTED_MSG_ID"
    else
        printf '• Working\n'
    fi
fi
exit 0
SCRIPT
    chmod +x "$ROOT/bin/pgrep" "$ROOT/bin/tmux"
    export PATH="$ROOT/bin:$PATH"
    export CLI_ADAPTER_SETTINGS="$ROOT/config/settings.yaml"
    export INBOX_WRITE_ROOT_OVERRIDE="$ROOT"
    export INBOX_WRITE_TEST=1
    export INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1
    export INBOX_CODEX_NUDGE_RETRIES=0
    export INBOX_CODEX_VERIFY_WAIT_SEC=0
    export EXPECTED_MSG_ID="msg_delivery_fixture"
    export INBOX_MESSAGE_ID="$EXPECTED_MSG_ID"
    export CAPTURE_COUNT_FILE="$ROOT/capture.count"
}

wait_for_log() {
    local pattern="$1" log="$2" i
    for i in $(seq 1 100); do
        grep -q "$pattern" "$log" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}

@test "unchanged pre-send Working evidence is a false positive" {
    export CAPTURE_MODE=static
    run bash "$BATS_TEST_DIRNAME/../../scripts/inbox_write.sh" \
        testninja 'delivery stale pane fixture' task_assigned karo notify
    [ "$status" -eq 0 ]
    log=$(find "$ROOT/logs/inbox_codex_delivery_verify" -type f -name '*.log' -print -quit)
    [ -n "$log" ]
    wait_for_log 'ASYNC_VERIFY FAILURE' "$log"
    ! grep -q 'ASYNC_VERIFY SUCCESS' "$log"
    grep -q 'read: false' "$ROOT/queue/inbox/testninja.yaml"
    printf 'old_fp=1 post_send_success=0 unread=1\n'
}

@test "post-send pane transition for the unique message succeeds" {
    export CAPTURE_MODE=changed
    run bash "$BATS_TEST_DIRNAME/../../scripts/inbox_write.sh" \
        testninja 'delivery transition fixture' task_assigned karo notify
    [ "$status" -eq 0 ]
    log=$(find "$ROOT/logs/inbox_codex_delivery_verify" -type f -name '*.log' -print -quit)
    [ -n "$log" ]
    wait_for_log 'ASYNC_VERIFY SUCCESS' "$log"
    ! grep -q 'ASYNC_VERIFY FAILURE' "$log"
    printf 'old_fp=0 post_send_success=1 message_identity=1\n'
}
