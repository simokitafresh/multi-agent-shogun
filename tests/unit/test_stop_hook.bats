#!/usr/bin/env bats
# test_stop_hook.bats — stop_hook_inbox.sh ユニットテスト
# yohey-w/multi-agent-shogun から適応移植
#
# テスト構成:
#   T-HOOK-001: stop_hook_active=true → exit 0
#   T-HOOK-002: agent不明(empty) → exit 0
#   T-HOOK-003: agent_id=shogun → exit 0
#   T-HOOK-004: SKIPPED (completion message: 機能未実装)
#   T-HOOK-005: SKIPPED (error message: 機能未実装)
#   T-HOOK-006: SKIPPED (neutral message: 機能未実装)
#   T-HOOK-007: SKIPPED (empty message: 機能未実装)
#   T-HOOK-008: inbox未読あり → block JSON出力
#   T-HOOK-009: SKIPPED (no unread + completion: 機能未実装)
#   T-HOOK-010: SKIPPED (unread + completion: 機能未実装)
#   T-HOOK-LOCAL-001: task done + report欠如 → block JSON

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/scripts/stop_hook_inbox.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMP="$(mktemp -d)"
    mkdir -p "$TEST_TMP/scripts/lib"
    mkdir -p "$TEST_TMP/queue/inbox"
    mkdir -p "$TEST_TMP/queue/tasks"
    mkdir -p "$TEST_TMP/queue/reports"

    # Copy the hook script so SCRIPT_DIR resolves to TEST_TMP
    cp "$HOOK_SCRIPT" "$TEST_TMP/scripts/stop_hook_inbox.sh"
    chmod +x "$TEST_TMP/scripts/stop_hook_inbox.sh"

    # Copy field_get.sh dependency
    if [ -f "$PROJECT_ROOT/scripts/lib/field_get.sh" ]; then
        cp "$PROJECT_ROOT/scripts/lib/field_get.sh" "$TEST_TMP/scripts/lib/"
    fi

    # Mock inbox_write.sh — logs arguments to file
    cat > "$TEST_TMP/scripts/inbox_write.sh" << 'MOCK'
#!/bin/bash
echo "$@" >> "$(dirname "$0")/../inbox_write_calls.log"
MOCK
    chmod +x "$TEST_TMP/scripts/inbox_write.sh"

    # Mock tmux — returns MOCK_AGENT_ID for display-message
    MOCK_BIN="$TEST_TMP/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" << 'TMUX_MOCK'
#!/bin/bash
if [[ "$1" == "display-message" ]]; then
    printf '%s\n' "${MOCK_AGENT_ID:-}"
    exit 0
fi
exit 0
TMUX_MOCK
    chmod +x "$MOCK_BIN/tmux"
}

teardown() {
    [ -n "${TEST_TMP:-}" ] && [ -d "$TEST_TMP" ] && rm -rf "$TEST_TMP"
}

# Helper: run the hook script with test overrides
run_hook() {
    local json="$1"
    local agent_id="${2:-sasuke}"
    JSON_PAYLOAD="$json" \
    MOCK_AGENT_ID="$agent_id" \
    HOOK_PATH="$TEST_TMP/scripts/stop_hook_inbox.sh" \
    MOCK_BIN_DIR="$TEST_TMP/mock_bin" \
    run bash -lc '
export PATH="$MOCK_BIN_DIR:$PATH"
export TMUX_PANE="%1"
printf "%s" "$JSON_PAYLOAD" | bash "$HOOK_PATH"
'
}

# Helper: run with no agent ID set
run_hook_no_agent() {
    local json="$1"
    JSON_PAYLOAD="$json" \
    MOCK_AGENT_ID="" \
    HOOK_PATH="$TEST_TMP/scripts/stop_hook_inbox.sh" \
    MOCK_BIN_DIR="$TEST_TMP/mock_bin" \
    run bash -lc '
export PATH="$MOCK_BIN_DIR:$PATH"
export TMUX_PANE="%1"
printf "%s" "$JSON_PAYLOAD" | bash "$HOOK_PATH"
'
}

@test "T-HOOK-001: stop_hook_active=true skips all processing" {
    run_hook '{"stop_hook_active": true}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T-HOOK-002: unknown agent (empty agent_id) exits 0" {
    run_hook_no_agent '{"stop_hook_active": false}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T-HOOK-003: shogun agent always exits 0" {
    run_hook '{"stop_hook_active": false}' "shogun"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# SKIPPED: 機能未実装 — メッセージ分類(completion/error/neutral)はstop_hook_inbox.shに存在しない。
# stop_check_inbox.sh(cmd_648)に実装済み。test_stop_check_inbox.batsでカバー。
#
# @test "T-HOOK-004: completion message triggers inbox_write to karo" {
#     run_hook '{"stop_hook_active": false, "last_assistant_message": "任務完了でござる。report YAML更新済み。"}'
#     [ "$status" -eq 0 ]
#     [ -f "$TEST_TMP/inbox_write_calls.log" ]
#     grep -q "karo" "$TEST_TMP/inbox_write_calls.log"
#     grep -q "report_completed" "$TEST_TMP/inbox_write_calls.log"
#     grep -q "sasuke" "$TEST_TMP/inbox_write_calls.log"
# }
#
# @test "T-HOOK-005: error message triggers inbox_write to karo" {
#     run_hook '{"stop_hook_active": false, "last_assistant_message": "ファイルが見つからない。エラーで中断する。"}'
#     [ "$status" -eq 0 ]
#     [ -f "$TEST_TMP/inbox_write_calls.log" ]
#     grep -q "karo" "$TEST_TMP/inbox_write_calls.log"
#     grep -q "error_report" "$TEST_TMP/inbox_write_calls.log"
# }
#
# @test "T-HOOK-006: neutral message does not trigger inbox_write" {
#     run_hook '{"stop_hook_active": false, "last_assistant_message": "待機する。次の指示を待つ。"}'
#     [ "$status" -eq 0 ]
#     [ ! -f "$TEST_TMP/inbox_write_calls.log" ]
# }
#
# @test "T-HOOK-007: empty last_assistant_message does not trigger inbox_write" {
#     run_hook '{"stop_hook_active": false, "last_assistant_message": ""}'
#     [ "$status" -eq 0 ]
#     [ ! -f "$TEST_TMP/inbox_write_calls.log" ]
# }

@test "T-HOOK-008: unread inbox messages produce block JSON" {
    cat > "$TEST_TMP/queue/inbox/sasuke.yaml" << 'YAML'
messages:
  - id: msg_001
    from: karo
    type: task_assigned
    content: "新タスクだ"
    read: false
YAML
    run_hook '{"stop_hook_active": false}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"decision"'
    echo "$output" | grep -q '"block"'
}

# SKIPPED: 機能未実装 — メッセージ分類(completion通知)はstop_hook_inbox.shに存在しない。
# stop_check_inbox.sh(cmd_648)に実装済み。
#
# @test "T-HOOK-009: no unread + completion message exits 0 with notification" {
#     cat > "$TEST_TMP/queue/inbox/sasuke.yaml" << 'YAML'
# messages:
#   - id: msg_001
#     from: karo
#     type: task_assigned
#     content: "古いメッセージ"
#     read: true
# YAML
#     run_hook '{"stop_hook_active": false, "last_assistant_message": "タスク完了した。report YAML updated。"}'
#     [ "$status" -eq 0 ]
#     [ -z "$output" ] || ! echo "$output" | grep -q '"block"'
#     [ -f "$TEST_TMP/inbox_write_calls.log" ]
#     grep -q "report_completed" "$TEST_TMP/inbox_write_calls.log"
# }
#
# @test "T-HOOK-010: unread inbox + completion message blocks AND notifies" {
#     cat > "$TEST_TMP/queue/inbox/sasuke.yaml" << 'YAML'
# messages:
#   - id: msg_001
#     from: karo
#     type: task_assigned
#     content: "次のタスク"
#     read: false
# YAML
#     run_hook '{"stop_hook_active": false, "last_assistant_message": "任務完了でござる。"}'
#     [ "$status" -eq 0 ]
#     echo "$output" | grep -q '"block"'
#     [ -f "$TEST_TMP/inbox_write_calls.log" ]
#     grep -q "report_completed" "$TEST_TMP/inbox_write_calls.log"
# }

@test "T-HOOK-LOCAL-001: task done + missing report produces block JSON" {
    cat > "$TEST_TMP/queue/tasks/sasuke.yaml" << 'YAML'
task:
  status: done
  report_filename: sasuke_report_cmd_999.yaml
YAML
    # report file intentionally NOT created
    printf 'messages:\n' > "$TEST_TMP/queue/inbox/sasuke.yaml"

    run_hook '{"stop_hook_active": false}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"decision"'
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'report_filename'
}
