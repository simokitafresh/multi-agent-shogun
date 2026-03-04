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
