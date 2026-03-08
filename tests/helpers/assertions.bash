#!/usr/bin/env bash
# Shared assertions for bats E2E tests.

yaml_field_value() {
    local file="$1"
    local field="$2"
    YAML_FILE="$file" YAML_FIELD="$field" python3 - <<'PY' 2>/dev/null
import os
import yaml

file_path = os.environ.get("YAML_FILE", "")
field_path = os.environ.get("YAML_FIELD", "")

if not file_path or not os.path.exists(file_path):
    print("")
    raise SystemExit(0)

try:
    with open(file_path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
except Exception:
    print("")
    raise SystemExit(0)

value = data
for key in field_path.split("."):
    if isinstance(value, dict):
        value = value.get(key)
    else:
        value = None
        break

if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
else:
    print(str(value))
PY
}

assert_yaml_field() {
    local file="$1"
    local field="$2"
    local expected="$3"
    local actual
    actual="$(yaml_field_value "$file" "$field")"
    if [ "$actual" != "$expected" ]; then
        echo "ASSERT FAIL: $file -> $field = '$actual' (expected '$expected')" >&2
        return 1
    fi
    return 0
}

wait_for_yaml_value() {
    local file="$1"
    local field="$2"
    local expected="$3"
    local timeout="${4:-30}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        local actual
        actual="$(yaml_field_value "$file" "$field")"
        if [ "$actual" = "$expected" ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "TIMEOUT: $file -> $field did not become '$expected' in ${timeout}s" >&2
    return 1
}

wait_for_file() {
    local file="$1"
    local timeout="${2:-10}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        [ -f "$file" ] && return 0
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "TIMEOUT: file not found after ${timeout}s: $file" >&2
    return 1
}

assert_inbox_unread_count() {
    local inbox_file="$1"
    local expected="$2"
    local actual
    actual="$(
        INBOX_FILE="$inbox_file" python3 - <<'PY' 2>/dev/null
import os
import yaml

inbox = os.environ.get("INBOX_FILE", "")
if not inbox or not os.path.exists(inbox):
    print("0")
    raise SystemExit(0)

try:
    with open(inbox, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    messages = data.get("messages", [])
    unread = sum(1 for msg in messages if not msg.get("read", False))
    print(str(unread))
except Exception:
    print("0")
PY
    )"

    if [ "$actual" -ne "$expected" ]; then
        echo "ASSERT FAIL: unread count=$actual (expected $expected) in $inbox_file" >&2
        return 1
    fi
    return 0
}

assert_inbox_message_exists() {
    local inbox_file="$1"
    local sender="$2"
    local msg_type="$3"
    INBOX_FILE="$inbox_file" MSG_FROM="$sender" MSG_TYPE="$msg_type" python3 - <<'PY' 2>/dev/null
import os
import sys
import yaml

inbox = os.environ.get("INBOX_FILE", "")
sender = os.environ.get("MSG_FROM", "")
msg_type = os.environ.get("MSG_TYPE", "")

if not inbox or not os.path.exists(inbox):
    print(f"ASSERT FAIL: inbox not found: {inbox}", file=sys.stderr)
    raise SystemExit(1)

with open(inbox, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

messages = data.get("messages", [])
found = any(m.get("from") == sender and m.get("type") == msg_type for m in messages)

if not found:
    print(
        f"ASSERT FAIL: no message from={sender} type={msg_type} in {inbox}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
}

wait_for_pane_text() {
    local pane="$1"
    local pattern="$2"
    local timeout="${3:-30}"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        if tmux capture-pane -t "$pane" -p -J -S - 2>/dev/null | grep -qE "$pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "TIMEOUT: pane=$pane missing pattern='$pattern' after ${timeout}s" >&2
    tmux capture-pane -t "$pane" -p -J -S - 2>/dev/null | tail -40 >&2 || true
    return 1
}

assert_file_contains() {
    local file="$1"
    local needle="$2"
    if ! grep -qF "$needle" "$file" 2>/dev/null; then
        echo "ASSERT FAIL: '$needle' not found in $file" >&2
        return 1
    fi
    return 0
}

dump_pane_for_debug() {
    local pane="$1" label="${2:-pane}"
    echo "=== DEBUG: $label ($pane) ===" >&2
    tmux capture-pane -t "$pane" -p -J 2>/dev/null >&2 || echo "(capture failed)" >&2
    echo "=== END: $label ===" >&2
}
