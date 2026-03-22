#!/usr/bin/env bats
# Minimal inbox_write unit test for cmd_438 AC4.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/scripts/inbox_write.sh"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/inbox_write_unit.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/queue/inbox"

    cp "$SOURCE_SCRIPT" "$TEST_ROOT/scripts/inbox_write.sh"
    chmod +x "$TEST_ROOT/scripts/inbox_write.sh"

    export TEST_SCRIPT="$TEST_ROOT/scripts/inbox_write.sh"
    export TARGET_INBOX="$TEST_ROOT/queue/inbox/kirimaru.yaml"
}

teardown() {
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

@test "inbox_write creates unread message with required fields" {
    run bash "$TEST_SCRIPT" "kirimaru" "unit test message" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [ -f "$TARGET_INBOX" ]

    INBOX_PATH="$TARGET_INBOX" python3 - <<'PY'
import os
import yaml

inbox_path = os.environ["INBOX_PATH"]
with open(inbox_path, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

messages = data.get("messages", [])
assert len(messages) == 1, f"expected 1 message, got {len(messages)}"
msg = messages[0]

for key in ("id", "from", "timestamp", "type", "content", "read"):
    assert key in msg, f"missing key: {key}"

assert msg["from"] == "karo"
assert msg["type"] == "task_assigned"
assert msg["content"] == "unit test message"
assert msg["read"] is False
PY
}

