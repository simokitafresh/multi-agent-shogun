#!/usr/bin/env bats
# test_stop_check_inbox.bats - cmd_648 stop hook behavior

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SOURCE_SCRIPT="$PROJECT_ROOT/scripts/hooks/stop_check_inbox.sh"
    [ -f "$SOURCE_SCRIPT" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    python3 -c "import yaml" >/dev/null 2>&1 || return 1

    # cmd_2111: 共有モックをsetup_fileで一度だけ作成(fixture共有。per-test cat+chmod廃止)
    export SHARED_BIN="$BATS_SUITE_TMPDIR/shared_bin"
    export SHARED_SCRIPTS="$BATS_SUITE_TMPDIR/shared_scripts"
    mkdir -p "$SHARED_BIN" "$SHARED_SCRIPTS"

    cat > "$SHARED_SCRIPTS/inbox_write.sh" <<'EOF'
#!/bin/bash
printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$INBOX_WRITE_LOG"
EOF
    chmod +x "$SHARED_SCRIPTS/inbox_write.sh"

    cat > "$SHARED_BIN/tmux" <<'EOF'
#!/bin/bash
if [[ "$1" == "display-message" ]]; then
    printf '%s\n' "${TMUX_AGENT_ID:-hayate}"
    exit 0
fi
printf '%s\n' "$*" >> "$TMUX_LOG"
exit 0
EOF
    chmod +x "$SHARED_BIN/tmux"

    # cmd_2111: タイムアウト比例ポーリング — 短時間(0.01s)は高速終了、長時間(1s)は変化検知で早期脱出
    cat > "$SHARED_BIN/inotifywait" <<'EOF'
#!/bin/bash
timeout_val=1
file_to_watch=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --timeout) timeout_val="$2"; shift 2 ;;
        -e) shift 2 ;;
        -*) shift ;;
        *) file_to_watch="$1"; shift ;;
    esac
done
if [ -n "$file_to_watch" ] && [ -f "$file_to_watch" ]; then
    init_size=$(wc -c < "$file_to_watch" 2>/dev/null || echo 0)
    polls=$(awk "BEGIN{n = int($timeout_val / 0.05); print (n < 1) ? 1 : n}")
    sleep_per=$(awk "BEGIN{printf \"%.4f\", $timeout_val / $polls}")
    for ((i=0; i<polls; i++)); do
        sleep "$sleep_per"
        cur_size=$(wc -c < "$file_to_watch" 2>/dev/null || echo 0)
        [ "$cur_size" != "$init_size" ] && exit 0
    done
else
    sleep "$timeout_val"
fi
exit 0
EOF
    chmod +x "$SHARED_BIN/inotifywait"
}

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/stop_check_inbox.XXXXXX")"
    export TEST_PROJECT="$TEST_ROOT/project"
    export TEST_BIN="$TEST_ROOT/bin"
    export TMUX_LOG="$TEST_ROOT/tmux.log"
    export INBOX_WRITE_LOG="$TEST_ROOT/inbox_write.log"
    export TMUX_AGENT_ID="hayate"
    export SHOGUN_STATE_DIR="$TEST_ROOT/state"
    export TEST_IDLE_FLAG="$SHOGUN_STATE_DIR/shogun_idle_${TMUX_AGENT_ID}"

    mkdir -p "$TEST_PROJECT/scripts/hooks" "$TEST_PROJECT/scripts" "$TEST_PROJECT/queue/inbox" "$TEST_BIN" "$SHOGUN_STATE_DIR"

    # cmd_2111: cp+chmod → ln -sf でサブプロセス削減(fixture共有)
    ln -sf "$SOURCE_SCRIPT" "$TEST_PROJECT/scripts/hooks/stop_check_inbox.sh"
    ln -sf "$SHARED_SCRIPTS/inbox_write.sh" "$TEST_PROJECT/scripts/inbox_write.sh"
    ln -sf "$SHARED_BIN/tmux" "$TEST_BIN/tmux"
    ln -sf "$SHARED_BIN/inotifywait" "$TEST_BIN/inotifywait"

    export PATH="$TEST_BIN:$PATH"
    export TMUX_PANE="%1"
    export STOP_HOOK_INOTIFY_TIMEOUT=0.01  # cmd_2111: 0.2→0.01。T-SCI-005は上書き
    rm -f "$TEST_IDLE_FLAG"
    : > "$TMUX_LOG"
    : > "$INBOX_WRITE_LOG"
}

teardown() {
    rm -f "${TEST_IDLE_FLAG:-}"
    [ -n "${TEST_ROOT:-}" ] && [ -d "$TEST_ROOT" ] && rm -rf "$TEST_ROOT"
}

run_hook() {
    local payload="$1"
    PAYLOAD="$payload" TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
}

@test "T-SCI-001: unread inbox keeps idle flag while blocking" {
    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg1
    from: karo
    type: task_assigned
    content: 新タスクを確認せよ
    read: false
EOF
    touch "$TEST_IDLE_FLAG"

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [ -f "$TEST_IDLE_FLAG" ]
    echo "$output" | jq -e '.decision == "block"' >/dev/null
}

@test "T-SCI-002: completion message triggers async report_completed notification" {
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"

    run_hook '{"stop_hook_active":false,"last_assistant_message":"任務完了でござる。報告YAMLを更新した"}'
    [ "$status" -eq 0 ]

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -s "$INBOX_WRITE_LOG" ]] && break
        sleep 0.02
    done

    grep -q '^karo|hayate、タスク完了|report_completed|hayate$' "$INBOX_WRITE_LOG"
}

@test "T-SCI-003: shogun skips karo notification but runs inbox check" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"task completed"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [ ! -s "$INBOX_WRITE_LOG" ]
}

@test "T-SCI-004: unread summary is embedded in block reason" {
    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg1
    from: karo
    type: task_assigned
    content: 新タスクAを開始せよ
    read: false
  - id: msg2
    from: shogun
    type: cmd_new
    content: 追加の指示を確認せよ
    read: false
EOF

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"inbox未読2件あり。内容:"* ]]
    [[ "$output" == *"[karo/task_assigned] 新タスクAを開始せよ"* ]]
    [[ "$output" == *"[shogun/cmd_new] 追加の指示を確認せよ"* ]]
}

@test "T-SCI-005: inotifywait blocks when message arrives during wait" {
    # T-SCI-005専用: initial check(WSL2高負荷時~200ms)完了後に確実に書き込むため延長
    export STOP_HOOK_INOTIFY_TIMEOUT=1
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"

    # バックグラウンドで0.5秒後に未読メッセージを書き込む
    # hookのinitial check完了後に書き込み、かつinotifywait timeout(1s)より前に到達
    (
        sleep 0.5
        cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'YAML'
messages:
  - id: msg_late
    from: karo
    type: task_assigned
    content: 待機中に届いたタスク
    read: false
YAML
    ) &
    local bg_pid=$!

    run_hook '{"stop_hook_active":false}'
    wait "$bg_pid" 2>/dev/null || true
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "block"' >/dev/null
    [[ "$output" == *"待機中に到着"* ]]
}

@test "T-SCI-006: no unread after inotifywait timeout exits cleanly" {
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [ -f "$TEST_IDLE_FLAG" ]
    # block出力がないことを確認
    if [[ -n "$output" ]]; then
        ! echo "$output" | jq -e '.decision == "block"' >/dev/null 2>&1 || false
    fi
}

@test "T-SCI-008: conclusion type triggers cross-check warning" {
    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg1
    from: shogun
    type: bulletin_notify
    content: 修正不要。計測結果を確認した
    read: false
EOF

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"★結論を含む通知あり。自分の証拠と突合せよ。矛盾があれば問い返せ。撤回は突合後。"* ]]
}

@test "T-SCI-009: non-conclusion type does not trigger cross-check warning" {
    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg1
    from: karo
    type: task_assigned
    content: タスクYAMLを読んで作業開始せよ
    read: false
EOF

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [[ "$output" != *"★結論を含む通知あり"* ]]
}

@test "T-SCI-007: error message triggers async error_report notification" {
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"

    run_hook '{"stop_hook_active":false,"last_assistant_message":"エラーのため中断する"}'
    [ "$status" -eq 0 ]

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -s "$INBOX_WRITE_LOG" ]] && break
        sleep 0.02
    done

    grep -q '^karo|hayate、エラー停止|error_report|hayate$' "$INBOX_WRITE_LOG"
}
