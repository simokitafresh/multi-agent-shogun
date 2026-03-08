#!/usr/bin/env bats
# test_idle_flag.bats — idle flag file system unit tests
# ローカル適応版: yohey-w/multi-agent-shogun から移植
#
# テスト構成:
#   T-001〜T-008: コメントアウト (ローカル未実装機能)
#   T-009: rm -f flag_dir/shogun_idle_* で全フラグクリア (有効)
#
# SKIPPED理由:
#   T-001〜T-006: ローカルのstop_hook_inbox.shにidle flag作成機能なし
#     (yohey-w版はstop_hookでIDLE_FLAG_DIR/shogun_idle_{agent}を作成するが、
#      ローカル版はinbox未読チェック+報告パス検証のみ)
#   T-007: ローカルのinbox_watcher.shにagent_is_busy()関数なし
#     (ローカルはidle flag直接参照+@agent_state参照で判定)
#   T-008: ローカルのinbox_watcher.shに__INBOX_WATCHER_TESTING__ガードなし
#     (テストハーネスからsource不可。send_wakeup()自体は存在する)

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    export IDLE_FLAG_DIR="$(mktemp -d "$BATS_TMPDIR/idle_flag_test.XXXXXX")"
}

teardown() {
    rm -rf "$IDLE_FLAG_DIR"
}

# ─── T-001: SKIPPED: 機能未実装 — ローカルのstop_hook_inbox.shにidle flag作成機能なし ───

# @test "T-001: stop_hook creates idle flag when unread=0" {
#     # Empty inbox (no unread)
#     cat > "$TEST_HOOK_TMP/queue/inbox/test_idle_agent.yaml" << 'YAML'
# messages:
# - content: old message
#   from: karo
#   id: msg_001
#   read: true
#   timestamp: '2026-01-01T00:00:00'
#   type: task_assigned
# YAML
#
#     run_hook '{"stop_hook_active": false, "last_assistant_message": ""}'
#     [ "$status" -eq 0 ]
#
#     # Flag file should be created
#     [ -f "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent" ]
# }

# ─── T-002: SKIPPED: 機能未実装 — ローカルのstop_hook_inbox.shにidle flag作成機能なし ───

# @test "T-002: stop_hook preserves idle flag when unread>0" {
#     touch "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent"
#
#     cat > "$TEST_HOOK_TMP/queue/inbox/test_idle_agent.yaml" << 'YAML'
# messages:
# - content: new task
#   from: karo
#   id: msg_002
#   read: false
#   timestamp: '2026-01-01T00:00:00'
#   type: task_assigned
# YAML
#
#     run_hook '{"stop_hook_active": false, "last_assistant_message": ""}'
#     [ -f "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent" ]
# }

# ─── T-003: SKIPPED: 機能未実装 — ローカルのinbox_watcher.shにagent_is_busy()関数なし ───

# @test "T-003: agent_is_busy returns 0 (busy) when no flag file — claude CLI" {
#     rm -f "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent"
#
#     run bash -c "
#         source '$WATCHER_HARNESS'
#         LAST_CLEAR_TS=0
#         CLI_TYPE='claude'
#         agent_is_busy
#     "
#     [ "$status" -eq 0 ]
# }

# ─── T-004: SKIPPED: 機能未実装 — ローカルのinbox_watcher.shにagent_is_busy()関数なし ───

# @test "T-004: agent_is_busy returns 1 (idle) when flag file exists — claude CLI" {
#     touch "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent"
#
#     run bash -c "
#         source '$WATCHER_HARNESS'
#         LAST_CLEAR_TS=0
#         CLI_TYPE='claude'
#         agent_is_busy
#     "
#     [ "$status" -eq 1 ]
# }

# ─── T-005: SKIPPED: 機能未実装 — ローカルのinbox_watcher.shにagent_is_busy()関数なし ───

# @test "T-005: agent_is_busy uses pane fallback for non-claude CLI" {
#     touch "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent"
#
#     run bash -c "
#         MOCK_CAPTURE_PANE='◦ Working on task (5s • esc to interrupt)'
#         source '$WATCHER_HARNESS'
#         LAST_CLEAR_TS=0
#         CLI_TYPE='codex'
#         agent_is_busy
#     "
#     [ "$status" -eq 0 ]
# }

# ─── T-006: SKIPPED: 機能未実装 — ローカルのstop_hook_inbox.shにidle flag作成機能なし ───

# @test "T-006: stop_hook creates idle flag even when stop_hook_active=True" {
#     cat > "$TEST_HOOK_TMP/queue/inbox/test_idle_agent.yaml" << 'YAML'
# messages: []
# YAML
#
#     run_hook '{"stop_hook_active": true, "last_assistant_message": ""}'
#     [ "$status" -eq 0 ]
#     [ -f "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent" ]
# }

# ─── T-007: SKIPPED: 機能未実装 — ローカルのinbox_watcher.shにagent_is_busy()関数なし ───

# @test "T-007: /clear cooldown overrides idle flag (returns busy)" {
#     touch "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent"
#
#     run bash -c "
#         source '$WATCHER_HARNESS'
#         CLI_TYPE='claude'
#         now=\$(date +%s)
#         LAST_CLEAR_TS=\$((now - 10))
#         agent_is_busy
#     "
#     [ "$status" -eq 0 ]
# }

# ─── T-008: SKIPPED: 機能未実装 — ローカルのinbox_watcher.shに__INBOX_WATCHER_TESTING__ガードなし ───
# send_wakeup()は存在するがテストハーネスからsource不可

# @test "T-008: send_wakeup removes idle flag after sending nudge" {
#     touch "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent"
#
#     run bash -c "
#         source '$WATCHER_HARNESS'
#         LAST_CLEAR_TS=0
#         send_wakeup 1
#     "
#     [ "$status" -eq 0 ]
#     grep -q "send-keys.*inbox1" "$MOCK_LOG"
#     [ ! -f "$IDLE_FLAG_DIR/shogun_idle_test_idle_agent" ]
# }

# ─── T-009: shutsujin時に全フラグクリア ───

@test "T-009: rm -f flag_dir/shogun_idle_* clears all idle flags" {
    # Create multiple idle flags (simulate multiple agents)
    touch "$IDLE_FLAG_DIR/shogun_idle_karo"
    touch "$IDLE_FLAG_DIR/shogun_idle_sasuke"
    touch "$IDLE_FLAG_DIR/shogun_idle_kagemaru"
    touch "$IDLE_FLAG_DIR/shogun_idle_hanzo"

    # Verify they exist
    [ -f "$IDLE_FLAG_DIR/shogun_idle_karo" ]
    [ -f "$IDLE_FLAG_DIR/shogun_idle_sasuke" ]

    # Simulate shutsujin flag clear (pattern: rm -f /tmp/shogun_idle_*)
    rm -f "$IDLE_FLAG_DIR"/shogun_idle_*

    # All flags cleared
    [ ! -f "$IDLE_FLAG_DIR/shogun_idle_karo" ]
    [ ! -f "$IDLE_FLAG_DIR/shogun_idle_sasuke" ]
    [ ! -f "$IDLE_FLAG_DIR/shogun_idle_kagemaru" ]
    [ ! -f "$IDLE_FLAG_DIR/shogun_idle_hanzo" ]
}
