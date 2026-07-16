#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_ROOT="$BATS_TEST_TMPDIR/root"
    export INBOX_WRITE_ROOT_OVERRIDE="$TEST_ROOT"
    export INBOX_WRITE_TEST=1
    export INBOX_CODEX_VERIFY_LOG_DIR="$TEST_ROOT/logs/verify"
    export CLI_ADAPTER_SETTINGS="$TEST_ROOT/config/settings.yaml"
    export TMUX_LOG="$TEST_ROOT/logs/tmux.log"

    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/config" \
        "$TEST_ROOT/queue/inbox" "$TEST_ROOT/queue/tasks" \
        "$TEST_ROOT/logs" "$TEST_ROOT/bin"
    cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_ROOT/scripts/inbox_write.sh"
    ln -s "$PROJECT_ROOT/scripts/lib" "$TEST_ROOT/scripts/lib"
    printf 'messages: []\n' > "$TEST_ROOT/queue/inbox/testninja.yaml"
    printf 'task:\n  status: assigned\n' > "$TEST_ROOT/queue/tasks/testninja.yaml"

    cat > "$TEST_ROOT/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML

    cat > "$TEST_ROOT/bin/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) printf 'shogun:agents.3 testninja\n' ;;
  capture-pane) printf '›\n' ;;
esac
exit 0
SH
    chmod +x "$TEST_ROOT/bin/tmux" "$TEST_ROOT/scripts/inbox_write.sh"
    export PATH="$TEST_ROOT/bin:$PATH"
}

wait_for_verify_result() {
    local pattern="$1"
    local tries="${2:-50}"
    local i
    for ((i = 0; i < tries; i++)); do
        if grep -Rqs "$pattern" "$INBOX_CODEX_VERIFY_LOG_DIR" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

elapsed_ms_for_write() {
    local mode="$1"
    local content="$2"
    local started finished captured
    started=$(date +%s%3N)
    if [ "$mode" = "async" ]; then
        captured="$(INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
            INBOX_CODEX_VERIFY_WAIT_SEC=1 \
            INBOX_CODEX_NUDGE_RETRIES=0 \
                bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "$content" task_assigned karo \
                2>&1)"
    else
        captured="$(INBOX_CODEX_DELIVERY_VERIFY_ASYNC=0 \
            INBOX_CODEX_VERIFY_WAIT_SEC=1 \
            INBOX_CODEX_NUDGE_RETRIES=0 \
                bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "$content" task_assigned karo \
                2>&1)"
    fi
    finished=$(date +%s%3N)
    printf '%s\n' "$((finished - started))"
}

@test "opted-in task_assigned returns after durable persistence without waiting for verifier" {
    local started finished elapsed
    started=$(date +%s%3N)
    run env \
        INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
        INBOX_CODEX_VERIFY_WAIT_SEC=2 \
        INBOX_CODEX_NUDGE_RETRIES=0 \
        bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "async-visible" task_assigned karo
    finished=$(date +%s%3N)
    elapsed=$((finished - started))

    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 1200 ]
    grep -q "async-visible" "$TEST_ROOT/queue/inbox/testninja.yaml"
    [[ "$output" == *"verification queued asynchronously"* ]]
}

@test "async verifier records eventual success and failure evidence" {
    INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
    INBOX_CODEX_VERIFY_WAIT_SEC=0.2 \
    INBOX_CODEX_NUDGE_RETRIES=0 \
        bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "will-fail" task_assigned karo \
        >/dev/null 2>&1
    wait_for_verify_result "ASYNC_VERIFY FAILURE"

    printf 'task:\n  status: in_progress\n' > "$TEST_ROOT/queue/tasks/testninja.yaml"
    INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
    INBOX_CODEX_VERIFY_WAIT_SEC=0.2 \
    INBOX_CODEX_NUDGE_RETRIES=0 \
        bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "will-succeed" task_assigned karo \
        >/dev/null 2>&1
    wait_for_verify_result "ASYNC_VERIFY SUCCESS"

    grep -Rqs "codex delivery remained unverified" "$INBOX_CODEX_VERIFY_LOG_DIR"
    grep -Rqs "ASYNC_VERIFY FAILURE" "$INBOX_CODEX_VERIFY_LOG_DIR"
    grep -Rqs "ASYNC_VERIFY SUCCESS" "$INBOX_CODEX_VERIFY_LOG_DIR"
}

@test "async opt-in removes the verifier wait while sync mode keeps it" {
    local sync_ms async_ms
    sync_ms=$(elapsed_ms_for_write sync "sync-timing")
    async_ms=$(elapsed_ms_for_write async "async-timing")
    printf '# sync_ms=%s async_ms=%s saved_ms=%s\n' \
        "$sync_ms" "$async_ms" "$((sync_ms - async_ms))" >&3

    [ "$sync_ms" -ge 900 ]
    [ "$async_ms" -lt 700 ]
    [ "$((sync_ms - async_ms))" -ge 700 ]
}

@test "non-task messages do not enter the async delivery verifier" {
    local started finished elapsed
    started=$(date +%s%3N)
    run env \
        INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
        INBOX_CODEX_VERIFY_WAIT_SEC=2 \
        bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "ordinary-message" wake_up karo
    finished=$(date +%s%3N)
    elapsed=$((finished - started))

    [ "$status" -eq 0 ]
    [ "$elapsed" -lt 1200 ]
    [[ "$output" != *"verification queued asynchronously"* ]]
    grep -q "ordinary-message" "$TEST_ROOT/queue/inbox/testninja.yaml"
    [ ! -d "$INBOX_CODEX_VERIFY_LOG_DIR" ]
}

@test "async opt-in preserves flocked concurrent appends without lost updates" {
    local i
    for i in $(seq 1 12); do
        INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1 \
        INBOX_CODEX_VERIFY_WAIT_SEC=0 \
        INBOX_CODEX_NUDGE_RETRIES=0 \
            bash "$TEST_ROOT/scripts/inbox_write.sh" testninja "parallel-$i" task_assigned karo \
            >/dev/null 2>&1 &
    done
    wait

    run python3 - "$TEST_ROOT/queue/inbox/testninja.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    messages = (yaml.safe_load(fh) or {}).get("messages", [])
parallel = [m.get("content") for m in messages if str(m.get("content", "")).startswith("parallel-")]
assert len(parallel) == 12, parallel
assert len(set(parallel)) == 12, parallel
PY
    [ "$status" -eq 0 ]
}

@test "deploy_task opts only task_assigned into asynchronous verification" {
    grep -q 'if \[ "$msg_type" = "task_assigned" \].*DEPLOY_TASK_ASYNC_CODEX_DELIVERY_VERIFY' \
        "$PROJECT_ROOT/scripts/deploy_task.sh"
    grep -q 'INBOX_CODEX_DELIVERY_VERIFY_ASYNC=1' "$PROJECT_ROOT/scripts/deploy_task.sh"
}
