#!/usr/bin/env bats
# test_lord_conversation.bats — lord_conversation.sh JSONL 単体テスト

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LORD_CONV_LIB="$PROJECT_ROOT/lib/lord_conversation.sh"
    [ -f "$LORD_CONV_LIB" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lord_conv_test.XXXXXX")"
    export LORD_CONVERSATION="$TEST_TMPDIR/lord_conversation.jsonl"
    export LORD_CONVERSATION_LOCK="$TEST_TMPDIR/lord_conversation.jsonl.lock"
    source "$LORD_CONV_LIB"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "T-LC-001: append_lord_conversation adds outbound entry with agent" {
    run append_lord_conversation "test outbound msg" "outbound" "shogun"
    [ "$status" -eq 0 ]
    [ -f "$LORD_CONVERSATION" ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("direction", ""))
print(obj.get("agent", ""))
print(obj.get("source", ""))
print(obj.get("detail", ""))
print(obj.get("summary", ""))
print("ts" in obj)
PY
)
    [ "${result[0]}" = "outbound" ]
    [ "${result[1]}" = "shogun" ]
    [ "${result[2]}" = "ntfy" ]
    [ "${result[3]}" = "test outbound msg" ]
    [ "${result[4]}" = "test outbound msg" ]
    [ "${result[5]}" = "True" ]
}

@test "T-LC-002: append_lord_conversation adds inbound entry without agent" {
    run append_lord_conversation "test inbound msg" "inbound"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("direction", ""))
print(obj.get("detail", ""))
print("agent" in obj)
PY
)
    [ "${result[0]}" = "inbound" ]
    [ "${result[1]}" = "test inbound msg" ]
    [ "${result[2]}" = "False" ]
}

@test "T-LC-003: append_lord_conversation fails when lock is held" {
    (
        flock -x 200
        sleep 10
    ) 200>"$LORD_CONVERSATION_LOCK" &
    local lock_pid=$!
    sleep 0.5

    run timeout 8 bash -c "
        source '$LORD_CONV_LIB'
        export LORD_CONVERSATION='$LORD_CONVERSATION'
        export LORD_CONVERSATION_LOCK='$LORD_CONVERSATION_LOCK'
        append_lord_conversation 'blocked msg' 'outbound' 'karo'
    "
    [ "$status" -ne 0 ]

    kill "$lock_pid" 2>/dev/null || true
    wait "$lock_pid" 2>/dev/null || true
}

@test "T-LC-004: append_lord_conversation rejects invalid direction" {
    run append_lord_conversation "test msg" "invalid-direction"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "snake_case"
}

@test "T-LC-005: append_lord_conversation fails when LORD_CONVERSATION is unset" {
    unset LORD_CONVERSATION
    run append_lord_conversation "test msg" "outbound"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "LORD_CONVERSATION"
}

@test "T-LC-006: append_lord_conversation preserves existing entries" {
    append_lord_conversation "first msg" "outbound" "shogun"
    append_lord_conversation "second msg" "inbound"

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 2 ]
    [ "${result[1]}" = "first msg" ]
    [ "${result[2]}" = "second msg" ]
}

@test "T-LC-007: append_lord_conversation recovers from corrupted JSONL line" {
    printf 'not-json-line\n' > "$LORD_CONVERSATION"
    run append_lord_conversation "recovery msg" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[-1].get("detail", ""))
print(rows[0].get("direction", ""))
PY
)
    [ "${result[0]}" -eq 2 ]
    [ "${result[1]}" = "recovery msg" ]
    [ "${result[2]}" = "invalid" ]
}

@test "T-LC-008: append_lord_conversation trims oldest entry when adding 501st" {
    python3 - <<PY
import json
with open("$LORD_CONVERSATION", "w", encoding="utf-8") as f:
    for i in range(1, 501):
        row = {
            "ts": f"2026-03-01T00:00:{i%60:02d}+09:00",
            "source": "ntfy",
            "direction": "outbound",
            "summary": f"seed-{i:03d}",
            "detail": f"seed-{i:03d}",
        }
        f.write(json.dumps(row, ensure_ascii=False) + "\\n")
PY

    run append_lord_conversation "seed-501" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[-1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 500 ]
    [ "${result[1]}" = "seed-002" ]
    [ "${result[2]}" = "seed-501" ]
}

@test "T-LC-009: append_lord_conversation keeps all entries when total is 500" {
    python3 - <<PY
import json
with open("$LORD_CONVERSATION", "w", encoding="utf-8") as f:
    for i in range(1, 500):
        row = {
            "ts": f"2026-03-01T00:00:{i%60:02d}+09:00",
            "source": "ntfy",
            "direction": "outbound",
            "summary": f"seed-{i:03d}",
            "detail": f"seed-{i:03d}",
        }
        f.write(json.dumps(row, ensure_ascii=False) + "\\n")
PY

    run append_lord_conversation "seed-500" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[-1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 500 ]
    [ "${result[1]}" = "seed-001" ]
    [ "${result[2]}" = "seed-500" ]
}

@test "T-LC-010: append_lord_conversation records explicit source" {
    run append_lord_conversation "terminal msg" "response" "shogun" "terminal"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("source", ""))
print(obj.get("direction", ""))
print(obj.get("detail", ""))
PY
)
    [ "${result[0]}" = "terminal" ]
    [ "${result[1]}" = "response" ]
    [ "${result[2]}" = "terminal msg" ]
}

@test "T-LC-011: append_lord_conversation defaults source to ntfy when omitted" {
    run append_lord_conversation "ntfy msg" "outbound" "shogun"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    obj = json.loads(f.read().strip().splitlines()[-1])
print(obj.get("source", ""))
print(obj.get("detail", ""))
PY
)
    [ "${result[0]}" = "ntfy" ]
    [ "${result[1]}" = "ntfy msg" ]
}

@test "T-LC-012: append_lord_conversation migrates legacy YAML when JSONL is empty" {
    cat > "$TEST_TMPDIR/lord_conversation.yaml" <<'YAML'
entries:
  - timestamp: "2026-03-05T20:00:00+09:00"
    direction: outbound
    channel: terminal
    agent: shogun
    message: legacy message
YAML
    : > "$LORD_CONVERSATION"

    run append_lord_conversation "new message" "response" "shogun" "terminal"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import json
with open("$LORD_CONVERSATION", "r", encoding="utf-8") as f:
    rows = [json.loads(line) for line in f if line.strip()]
print(len(rows))
print(rows[0].get("detail", ""))
print(rows[1].get("detail", ""))
PY
)
    [ "${result[0]}" -eq 2 ]
    [ "${result[1]}" = "legacy message" ]
    [ "${result[2]}" = "new message" ]
}
