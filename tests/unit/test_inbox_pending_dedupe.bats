#!/usr/bin/env bats

setup() {
    export ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export FIXTURE="$BATS_TEST_TMPDIR/root"
    mkdir -p "$FIXTURE/queue/inbox" "$FIXTURE/queue/tasks" "$FIXTURE/scripts"
    ln -s "$ROOT/scripts/lib" "$FIXTURE/scripts/lib"
    export INBOX_WRITE_ROOT_OVERRIDE="$FIXTURE"
    export INBOX_WRITE_TEST=1
}

@test "same sender and content has one pending entry while distinct content is retained" {
    for _ in 1 2 3; do
        run bash "$ROOT/scripts/inbox_write.sh" karo "same instruction" task_update tobisaru execute
        [ "$status" -eq 0 ]
    done
    run bash "$ROOT/scripts/inbox_write.sh" karo "different instruction" task_update tobisaru execute
    [ "$status" -eq 0 ]

    run python3 - "$FIXTURE/queue/inbox/karo.yaml" <<'PY'
import sys, yaml
messages = yaml.safe_load(open(sys.argv[1]))["messages"]
assert len(messages) == 2, messages
assert [m["content"] for m in messages] == ["same instruction", "different instruction"]
assert all(m["read"] is False for m in messages)
PY
    [ "$status" -eq 0 ]
}

@test "read entry does not suppress a new pending instruction" {
    cat > "$FIXTURE/queue/inbox/karo.yaml" <<'YAML'
messages:
- content: same instruction
  from: tobisaru
  id: old
  read: true
  timestamp: '2026-07-17T00:00:00'
  type: task_update
YAML
    run bash "$ROOT/scripts/inbox_write.sh" karo "same instruction" task_update tobisaru execute
    [ "$status" -eq 0 ]
    [ "$(grep -c '^- ' "$FIXTURE/queue/inbox/karo.yaml")" -eq 2 ]
}

@test "lord conversation keeps SESSION_ID continuation running until exit code" {
    local conversation="$BATS_TEST_TMPDIR/lord.jsonl"
    cat > "$conversation" <<'JSONL'
{"agent":"saizo","session_id":"77","detail":"completed envelope; SESSION_ID continues"}
{"agent":"saizo","session_id":"77","detail":"exit_code=0"}
JSONL
    run env LORD_CONVERSATION_FILE="$conversation" bash "$ROOT/scripts/lord_conversation_read.sh" saizo 2
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | jq -r 'select(.detail|contains("continues"))|.execution_state')" = running ]
    [ "$(printf '%s\n' "$output" | jq -r 'select(.detail|contains("exit_code"))|.execution_state')" = finished ]
}
