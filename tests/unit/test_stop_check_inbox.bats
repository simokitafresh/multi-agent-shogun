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

    export PATH="$TEST_BIN:$PATH"
    export TMUX_PANE="%1"
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

@test "T-SCI-014: shogun turn shows brainwash audit prompt" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次データを確認して次に進む"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"洗脳8パターン自問"* ]]
    [[ "$output" != *"WARN: 洗脳検出"* ]]
}

@test "T-SCI-015: shogun brainwash phrase warns with pattern number without blocking" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"この穴は低優先なので次セッションで対応する"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 洗脳検出 #5 先送り"* ]]
}

@test "T-SCI-017: shogun startup defer warning counts unresolved unique keys" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    mkdir -p "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/logs/shogun_startup_alert_history.tsv" <<'EOF'
2026-06-13T01:00:00+09:00	先送り判断: 穴A が3セッション連続
2026-06-13T01:00:00+09:00	先送り判断: 穴A が3セッション連続
2026-06-13T01:00:00+09:00	先送り判断: 穴B が3セッション連続
EOF

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次データを確認して進む"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"現在未解消2件"* ]]
    [[ "$output" != *"現在未解消3件"* ]]
}

@test "T-SCI-018: shogun startup defer warning clears after OK" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    mkdir -p "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/logs/shogun_startup_alert_history.tsv" <<'EOF'
2026-06-13T01:00:00+09:00	先送り判断: 穴A が3セッション連続
2026-06-13T01:05:00+09:00	__OK__
EOF

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次データを確認して進む"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"startup先送りBLOCK"* ]]
}

@test "T-SCI-F009-001: shogun lord delegation pattern blocks with F009 (cmd_3251 AC3-B)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"殿に手動でcommitしていただけますか"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "block"' >/dev/null
    [[ "$output" == *"F009"* ]]
}

@test "T-SCI-F009-002: polite operation request blocks with F009 (cmd_3251 AC3-B)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"貼り付けてください"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "block"' >/dev/null
    [[ "$output" == *"F009"* ]]
}

@test "T-SCI-F009-003: non-lord context does not trigger F009 (cmd_3251 AC3-B)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"忍者が手動でテスト実行する必要がある"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"F009"* ]]
}

@test "T-SCI-F009-004: lord delegation with お願い blocks (cmd_3251 AC3-B)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"殿にお願いしたい操作がある"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "block"' >/dev/null
    [[ "$output" == *"F009"* ]]
}

@test "T-SCI-F009-005: commitハッシュ言及+遠距離して の報告文はFP扱いしない (2026-06-10実測FP回帰)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"殿、報告する。軍師がgate自体のバグ3件をD0修正済み(commit 0d7f29701)。利他WARNのawk境界未リセットなどの偽陽性を排除。将軍が本日修正した形骸化問題と同根のものを軍師も独立に是正しており、三者の掃除が噛み合った。"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"F009"* ]]
}

@test "T-SCI-F009-006: 近接した操作依頼は引き続きblockする (有界化後の真陽性維持)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"殿、お手数だがgit pushを実行してくれ"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.decision == "block"' >/dev/null
    [[ "$output" == *"F009"* ]]
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

@test "T-SCI-016: unread summary cache invalidates when inbox changes" {
    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg1
    from: karo
    type: task_assigned
    content: 初回タスクを確認せよ
    read: false
EOF

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"初回タスクを確認せよ"* ]]

    sleep 1
    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg2
    from: karo
    type: task_assigned
    content: 更新後タスクを確認せよ
    read: false
EOF

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"更新後タスクを確認せよ"* ]]
    [[ "$output" != *"初回タスクを確認せよ"* ]]
}

@test "T-SCI-006: no unread exits cleanly" {
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

@test "T-SCI-010: karo sees pending work when inbox is empty but ninja status=done" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML
    # shogun_to_karo not needed for this test
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"次アクションあり"* ]]
    [[ "$output" == *"hayate"* ]]
    [[ "$output" == *"done"* ]]
}

@test "T-SCI-011: karo no pending work when all ninjas idle" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: idle
  parent_cmd: cmd_9999
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"次アクションあり"* ]]
}

@test "T-SCI-012: ninja with status=done exits cleanly without block" {
    export TMUX_AGENT_ID="hayate"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    # Codex互換: blockせずidle flag設定のみで正常終了(b95db54c)
    [[ "$output" != *"BLOCK"* ]]
}

@test "T-SCI-013: ninja with status=in_progress sees no wait instruction" {
    export TMUX_AGENT_ID="hayate"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: cmd_9999
YAML

    run_hook '{"stop_hook_active":false}'
    [ "$status" -eq 0 ]
    [[ "$output" != *"Wait for next task"* ]]
}

@test "T-SCI-019: shogun brainwash detection creates Q6 flag for next-turn WARN (LS065)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    local _q6_flag="$SHOGUN_STATE_DIR/shogun_q6_brainwash_shogun"

    # 1st turn: brainwash detected → flag created, no LS065 WARN yet
    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"この穴は低優先なので後回しにする"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 洗脳検出 #5 先送り"* ]]
    [ -f "$_q6_flag" ]

    # 2nd turn: no new brainwash, karo_yaml not updated → LS065 WARN継続
    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次データを確認して進む"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: LS065 Q6洗脳検出済み"* ]]
    [[ "$output" == *"cmd起票未完了"* ]]
    [ -f "$_q6_flag" ]
}

@test "T-SCI-020: shogun Q6 flag clears after karo yaml is updated (cmd issued) (LS065)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    # 1st turn: create Q6 flag
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"この穴は低優先なので後回しにする"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    local _q6_flag="$SHOGUN_STATE_DIR/shogun_q6_brainwash_shogun"
    [ -f "$_q6_flag" ]

    # Simulate cmd issued: update karo_yaml after flag creation
    sleep 1
    printf 'commands:\ncmd_9999:\n  status: delegated\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    # 2nd turn: karo_yaml newer than flag → flag cleared, no LS065 WARN
    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次データを確認して進む"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"LS065"* ]]
    [ ! -f "$_q6_flag" ]
}

@test "T-SCI-021: shogun no brainwash means no Q6 flag created (LS065)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    local _q6_flag="$SHOGUN_STATE_DIR/shogun_q6_brainwash_shogun"
    rm -f "$_q6_flag"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次データを確認してから判断する"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"LS065"* ]]
    [ ! -f "$_q6_flag" ]
}
