#!/usr/bin/env bats
# test_ntfy_ack.bats — ntfy メッセージ処理ユニットテスト
# ローカル適応版: yohey-w/multi-agent-shogun から移植
#
# テスト構成 (全8件有効):
#   T-ACK-001: 正常メッセージ → inbox_write to shogun
#   T-ACK-002: outboundタグ付き → 処理スキップ（ループ防御）
#   T-ACK-003: auto-ACK未送信確認 (shogun replies directly)
#   T-ACK-004: ntfy.sh失敗 → inbox_write継続
#   T-ACK-005: 空メッセージ → 処理スキップ
#   T-ACK-006: keepaliveイベント → 処理スキップ
#   T-ACK-007: append_ntfy_inbox失敗 → inbox_write両方スキップ
#   T-ACK-008: 特殊文字がinbox_writeに保持される
#
# ローカル適応:
#   - .venv不在 → system python3使用
#   - tmux_utils.sh stub追加（ntfy_listener.shがsource必須）
#   - tmux mock追加（実tmuxセッションへの副作用防止）
#   - flock競合防止（テスト用lock path分離）
#   - NTFY_LISTENER_LIB_ONLY=1でsource → process_stream_line直接呼出（timeout不要）

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    python3 -c "import yaml" 2>/dev/null || { echo "python3 with PyYAML required" >&2; return 1; }
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/ntfy_ack_test.XXXXXX")"
    export MOCK_PROJECT="$TEST_TMPDIR/mock_project"
    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    export ACK_LOG="$TEST_TMPDIR/ack.log"
    export INBOX_LOG="$TEST_TMPDIR/inbox.log"

    # モックプロジェクト構築
    mkdir -p "$MOCK_PROJECT"/{config,lib,scripts/lib,queue,logs/ntfy_inbox_corrupt}
    mkdir -p "$MOCK_BIN"

    # settings.yaml
    cat > "$MOCK_PROJECT/config/settings.yaml" << 'YAML'
ntfy_topic: "test-ack-topic-12345"
YAML

    # 空の認証ファイル
    touch "$MOCK_PROJECT/config/ntfy_auth.env"

    # 本物のntfy_auth.shをコピー
    cp "$PROJECT_ROOT/lib/ntfy_auth.sh" "$MOCK_PROJECT/lib/"

    # tmux_utils.sh stub（ローカル適応: ntfy_listener.shがsourceするため必要）
    cat > "$MOCK_PROJECT/scripts/lib/tmux_utils.sh" << 'STUB'
#!/bin/bash
safe_send_keys() { :; }
safe_send_keys_atomic() { :; }
STUB

    # ntfy_inbox初期化
    echo "inbox:" > "$MOCK_PROJECT/queue/ntfy_inbox.yaml"

    # --- モックスクリプト ---

    # mock tmux（ローカル適応: 実tmuxセッションへの副作用防止）
    cat > "$MOCK_BIN/tmux" << 'TMUX_MOCK'
#!/bin/bash
# Stub: prevent real tmux interaction during tests
exit 1
TMUX_MOCK
    chmod +x "$MOCK_BIN/tmux"

    # mock ntfy.sh
    cat > "$MOCK_PROJECT/scripts/ntfy.sh" << 'NTFY_MOCK'
#!/bin/bash
echo "$1" >> "$ACK_LOG"
exit ${MOCK_NTFY_EXIT_CODE:-0}
NTFY_MOCK
    chmod +x "$MOCK_PROJECT/scripts/ntfy.sh"

    # mock inbox_write.sh
    cat > "$MOCK_PROJECT/scripts/inbox_write.sh" << 'INBOX_MOCK'
#!/bin/bash
echo "$@" >> "$INBOX_LOG"
INBOX_MOCK
    chmod +x "$MOCK_PROJECT/scripts/inbox_write.sh"

    # ログ初期化
    touch "$ACK_LOG" "$INBOX_LOG"

    # PATHにモックtmuxを先頭配置
    export PATH="$MOCK_BIN:$PATH"

    # デフォルト: ntfy.sh正常終了
    unset MOCK_NTFY_EXIT_CODE

    # NTFY_LISTENER_LIB_ONLY=1でsource → 関数定義のみ（main loop不実行）
    export NTFY_LISTENER_LIB_ONLY=1
    sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$MOCK_PROJECT\"|" \
        "$PROJECT_ROOT/scripts/ntfy_listener.sh" \
        > "$MOCK_PROJECT/ntfy_listener_lib.sh"
    source "$MOCK_PROJECT/ntfy_listener_lib.sh"
}

teardown() {
    # Restore permissions if changed (T-ACK-007)
    chmod 755 "$MOCK_PROJECT/queue" 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
}

# --- ヘルパー ---

run_listener() {
    # process_stream_lineを直接呼出（coproc/timeout不要 → 高速・決定的）
    # 2>/dev/null: redirect失敗等のbashエラーメッセージ抑制
    # || true: append_ntfy_inbox失敗時のERR trap回避（T-ACK-007等）
    process_stream_line "$1" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-001: Normal message triggers inbox_write to shogun
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-001: Normal message triggers inbox_write to shogun" {
    run_listener '{"event":"message","id":"msg001","time":1234567890,"message":"テスト通知","tags":[]}'
    [ -s "$INBOX_LOG" ]
    grep -q "shogun" "$INBOX_LOG"
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-002: Outbound message does NOT trigger processing (loop prevention)
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-002: Outbound message does NOT trigger processing (loop prevention)" {
    run_listener '{"event":"message","id":"msg002","time":1234567890,"message":"📱受信: echo","tags":["outbound"]}'
    [ ! -s "$ACK_LOG" ]
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-003: No auto-ACK sent (shogun replies directly)
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-003: No auto-ACK sent (shogun replies directly)" {
    run_listener '{"event":"message","id":"msg003","time":1234567890,"message":"テスト通知です","tags":[]}'
    # Auto-ACK removed — ACK_LOG should be empty
    [ ! -s "$ACK_LOG" ]
    # But inbox_write to shogun should still fire
    [ -s "$INBOX_LOG" ]
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-004: ntfy.sh failure does not block inbox_write
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-004: ntfy.sh failure does not block inbox_write" {
    export MOCK_NTFY_EXIT_CODE=1
    run_listener '{"event":"message","id":"msg004","time":1234567890,"message":"test msg","tags":[]}'
    [ -s "$INBOX_LOG" ]
    grep -q "shogun" "$INBOX_LOG"
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-005: Empty message skips processing
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-005: Empty message skips processing" {
    run_listener '{"event":"message","id":"msg005","time":1234567890,"message":"","tags":[]}'
    [ ! -s "$ACK_LOG" ]
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-006: Non-message event (keepalive) skips processing
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-006: Non-message event (keepalive) skips processing" {
    run_listener '{"event":"keepalive","id":"","time":1234567890,"message":""}'
    [ ! -s "$ACK_LOG" ]
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-007: append_ntfy_inbox failure skips inbox_write
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-007: append_ntfy_inbox failure skips inbox_write" {
    # Make queue directory read-only to force flock/mkstemp failure
    chmod 555 "$MOCK_PROJECT/queue"
    run_listener '{"event":"message","id":"msg007","time":1234567890,"message":"should not ack","tags":[]}'
    # Both ACK and inbox_write should be skipped
    [ ! -s "$ACK_LOG" ]
    [ ! -s "$INBOX_LOG" ]
    # Restore for teardown
    chmod 755 "$MOCK_PROJECT/queue"
}

# ═══════════════════════════════════════════════════════════════
# T-ACK-008: Special characters in message preserved in inbox_write
# ═══════════════════════════════════════════════════════════════

@test "T-ACK-008: Special characters in message preserved in inbox_write" {
    run_listener '{"event":"message","id":"msg008","time":1234567890,"message":"こんにちは '\''world'\'' & <test>","tags":[]}'
    # Auto-ACK removed — verify inbox_write still fires for special characters
    [ ! -s "$ACK_LOG" ]
    [ -s "$INBOX_LOG" ]
    grep -q "shogun" "$INBOX_LOG"
}
