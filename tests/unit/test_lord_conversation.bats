#!/usr/bin/env bats
# test_lord_conversation.bats — lord_conversation.sh 単体テスト
# cmd_546: ntfy.sh/ntfy_listener.shの重複ロジック集約
#
# テスト構成:
#   T-LC-001: outbound追記（agentあり）
#   T-LC-002: inbound追記（agentなし）
#   T-LC-003: flock競合時のタイムアウト動作
#   T-LC-004: 不正なdirection拒否
#   T-LC-005: LORD_CONVERSATION未設定時エラー
#   T-LC-006: 既存エントリへの追記（データ保全）
#   T-LC-007: 壊れたYAML（非dict）の回復
#   T-LC-008: 301件目で最古エントリが削除される (MAX_ENTRIES=300)
#   T-LC-009: 300件以下では削除されない (MAX_ENTRIES=300)
#   T-LC-010: channel引数ありでterminalが記録されること
#   T-LC-011: channel引数なしでntfyがデフォルトになること
#   T-LC-012: MAX_ENTRIES=300でローテーション動作

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export LORD_CONV_LIB="$PROJECT_ROOT/lib/lord_conversation.sh"
    [ -f "$LORD_CONV_LIB" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/lord_conv_test.XXXXXX")"
    export LORD_CONVERSATION="$TEST_TMPDIR/lord_conversation.yaml"
    export LORD_CONVERSATION_LOCK="$TEST_TMPDIR/lord_conversation.yaml.lock"
    source "$LORD_CONV_LIB"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- T-LC-001: outbound追記（agentあり） ---

@test "T-LC-001: append_lord_conversation adds outbound entry with agent" {
    run append_lord_conversation "test outbound msg" "outbound" "shogun"
    [ "$status" -eq 0 ]

    [ -f "$LORD_CONVERSATION" ]
    local content
    content=$(cat "$LORD_CONVERSATION")

    echo "$content" | grep -q "direction: outbound"
    echo "$content" | grep -q "agent: shogun"
    echo "$content" | grep -q "message: test outbound msg"
    echo "$content" | grep -q "channel: ntfy"
    echo "$content" | grep -q "timestamp:"
}

# --- T-LC-002: inbound追記（agentなし） ---

@test "T-LC-002: append_lord_conversation adds inbound entry without agent" {
    run append_lord_conversation "test inbound msg" "inbound"
    [ "$status" -eq 0 ]

    [ -f "$LORD_CONVERSATION" ]
    local content
    content=$(cat "$LORD_CONVERSATION")

    echo "$content" | grep -q "direction: inbound"
    echo "$content" | grep -q "message: test inbound msg"
    # agentフィールドが存在しないことを確認
    ! echo "$content" | grep -q "agent:"
}

# --- T-LC-003: flock競合時のタイムアウト動作 ---

@test "T-LC-003: append_lord_conversation fails when lock is held" {
    # ロックを先に取得（バックグラウンドで保持）
    (
        flock -x 200
        sleep 10
    ) 200>"$LORD_CONVERSATION_LOCK" &
    local lock_pid=$!
    sleep 0.5

    # flock -w 5 で5秒待ちタイムアウト → 失敗
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

# --- T-LC-004: 不正なdirection拒否 ---

@test "T-LC-004: append_lord_conversation rejects invalid direction" {
    run append_lord_conversation "test msg" "invalid_direction"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "direction must be"
}

# --- T-LC-005: LORD_CONVERSATION未設定時エラー ---

@test "T-LC-005: append_lord_conversation fails when LORD_CONVERSATION is unset" {
    unset LORD_CONVERSATION
    run append_lord_conversation "test msg" "outbound"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "LORD_CONVERSATION"
}

# --- T-LC-006: 既存エントリへの追記（データ保全） ---

@test "T-LC-006: append_lord_conversation preserves existing entries" {
    # 先にエントリを1件追加
    append_lord_conversation "first msg" "outbound" "shogun"

    # 2件目を追加
    append_lord_conversation "second msg" "inbound"

    local content
    content=$(cat "$LORD_CONVERSATION")

    # 両方のエントリが存在すること
    echo "$content" | grep -q "first msg"
    echo "$content" | grep -q "second msg"

    # entriesリストに2件あること
    local count
    count=$(python3 -c "
import yaml
with open('$LORD_CONVERSATION') as f:
    data = yaml.safe_load(f)
print(len(data.get('entries', [])))
")
    [ "$count" -eq 2 ]
}

# --- T-LC-007: 壊れたYAML（非dict）の回復 ---

@test "T-LC-007: append_lord_conversation recovers from corrupted YAML" {
    # 壊れたYAML（文字列のみ）を書き込み
    echo "this is not valid yaml dict" > "$LORD_CONVERSATION"

    run append_lord_conversation "recovery msg" "outbound" "karo"
    [ "$status" -eq 0 ]

    local content
    content=$(cat "$LORD_CONVERSATION")
    echo "$content" | grep -q "recovery msg"
    echo "$content" | grep -q "entries:"
}

# --- T-LC-008: 301件目で最古エントリが削除される (MAX_ENTRIES=300) ---

@test "T-LC-008: append_lord_conversation trims oldest entry when adding 301st" {
    python3 - <<PY
import yaml

entries = [
    {
        "timestamp": f"2026-03-01T{i // 3600:02d}:{(i % 3600) // 60:02d}:{i % 60:02d}+09:00",
        "direction": "outbound",
        "channel": "ntfy",
        "message": f"seed-{i:03d}",
    }
    for i in range(1, 301)
]
with open("$LORD_CONVERSATION", "w") as f:
    yaml.dump({"entries": entries}, f, default_flow_style=False, allow_unicode=True, indent=2)
PY

    run append_lord_conversation "seed-301" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import yaml

with open("$LORD_CONVERSATION") as f:
    data = yaml.safe_load(f) or {}
entries = data.get("entries", [])
messages = [e.get("message", "") for e in entries]
print(len(entries))
print(messages[0] if messages else "")
print("seed-001" in messages)
print("seed-301" in messages)
PY
)
    [ "${result[0]}" -eq 300 ]
    [ "${result[1]}" = "seed-002" ]
    [ "${result[2]}" = "False" ]
    [ "${result[3]}" = "True" ]
}

# --- T-LC-009: 300件以下では削除されない (MAX_ENTRIES=300) ---

@test "T-LC-009: append_lord_conversation keeps all entries when total is 300" {
    python3 - <<PY
import yaml

entries = [
    {
        "timestamp": f"2026-03-01T{i // 3600:02d}:{(i % 3600) // 60:02d}:{i % 60:02d}+09:00",
        "direction": "outbound",
        "channel": "ntfy",
        "message": f"seed-{i:03d}",
    }
    for i in range(1, 300)
]
with open("$LORD_CONVERSATION", "w") as f:
    yaml.dump({"entries": entries}, f, default_flow_style=False, allow_unicode=True, indent=2)
PY

    run append_lord_conversation "seed-300" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import yaml

with open("$LORD_CONVERSATION") as f:
    data = yaml.safe_load(f) or {}
entries = data.get("entries", [])
messages = [e.get("message", "") for e in entries]
print(len(entries))
print(messages[0] if messages else "")
print("seed-001" in messages)
print("seed-300" in messages)
PY
)
    [ "${result[0]}" -eq 300 ]
    [ "${result[1]}" = "seed-001" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "True" ]
}

# --- T-LC-010: channel引数ありでterminalが記録されること ---

@test "T-LC-010: append_lord_conversation records terminal channel when specified" {
    run append_lord_conversation "terminal msg" "inbound" "" "terminal"
    [ "$status" -eq 0 ]

    [ -f "$LORD_CONVERSATION" ]
    local content
    content=$(cat "$LORD_CONVERSATION")

    echo "$content" | grep -q "channel: terminal"
    echo "$content" | grep -q "message: terminal msg"
    echo "$content" | grep -q "direction: inbound"
    # agentが空文字列の場合、agentフィールドは含まれない
    ! echo "$content" | grep -q "agent:"
}

# --- T-LC-011: channel引数なしでntfyがデフォルトになること ---

@test "T-LC-011: append_lord_conversation defaults channel to ntfy when omitted" {
    run append_lord_conversation "ntfy msg" "outbound" "shogun"
    [ "$status" -eq 0 ]

    local content
    content=$(cat "$LORD_CONVERSATION")

    echo "$content" | grep -q "channel: ntfy"
    echo "$content" | grep -q "message: ntfy msg"
}

# --- T-LC-012: MAX_ENTRIES=300でローテーション動作 ---

@test "T-LC-012: append_lord_conversation rotates at MAX_ENTRIES=300 boundary" {
    python3 - <<PY
import yaml

entries = [
    {
        "timestamp": f"2026-03-01T{i // 3600:02d}:{(i % 3600) // 60:02d}:{i % 60:02d}+09:00",
        "direction": "outbound",
        "channel": "ntfy",
        "message": f"seed-{i:03d}",
    }
    for i in range(1, 301)
]
with open("$LORD_CONVERSATION", "w") as f:
    yaml.dump({"entries": entries}, f, default_flow_style=False, allow_unicode=True, indent=2)
PY

    run append_lord_conversation "new-entry" "outbound" "karo"
    [ "$status" -eq 0 ]

    readarray -t result < <(python3 - <<PY
import yaml

with open("$LORD_CONVERSATION") as f:
    data = yaml.safe_load(f) or {}
entries = data.get("entries", [])
messages = [e.get("message", "") for e in entries]
print(len(entries))
print("seed-001" in messages)
print("new-entry" in messages)
print(messages[-1] if messages else "")
PY
)
    [ "${result[0]}" -eq 300 ]
    [ "${result[1]}" = "False" ]
    [ "${result[2]}" = "True" ]
    [ "${result[3]}" = "new-entry" ]
}
