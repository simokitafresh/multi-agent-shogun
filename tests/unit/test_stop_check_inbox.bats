#!/usr/bin/env bats
# test_necessity: Lord delegation pattern blocks with F009, and delegated cmd IDs require exact parent_cmd equality; violation is BLOCK.
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

write_successful_preflight_evidence() {
    local dir="$TEST_ROOT/preaction_memory"
    mkdir -p "$dir"
    printf '%s\n' '{"agent_id":"shogun","pane_id":"%1","prompt_hash":"hash","nonce":"nonce","issued_at":"2099-01-01T00:00:00+09:00","memory_db":"0","semantic":"0","obsidian":"0","status":"success"}' > "$dir/evidence_shogun__1.json"
    export THREE_LAYER_PREACTION_EVIDENCE_DIR="$dir"
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

@test "T-SCI-001: unread inbox clears idle flag while blocking" {
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
    [ ! -f "$TEST_IDLE_FLAG" ]
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

@test "T-SCI-F009-007: shogun completion report context does not trigger F009" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"殿05:02指示を受け、家老へ依頼済み。依頼直後に修正を確認し、次の一手としてcommit整理を推薦する。"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"F009"* ]]
}

@test "T-SCI-F009-008: explicit request to karo does not trigger F009" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"家老へCLIをrespawnしてください。"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"F009"* ]]
}

@test "T-SCI-F009-009: detector BLOCK reason mention does not retrigger F009" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"F009のBLOCK理由は、殿にcommitやpushを依頼するな、自分で実行せよという防御である。"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh" 2>/dev/null
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"F009"* ]]
}

@test "T-SCI-F009-010: direct lord CLI operation request remains blocked" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"殿、CLIをrespawnしてください"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
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

    cat > "$TEST_PROJECT/queue/inbox/hayate.yaml" <<'EOF'
messages:
  - id: msg2
    from: karo
    type: task_assigned
    content: 更新後タスクを確認せよ
    read: false
EOF
    # Cache invalidation is an mtime contract; advance it deterministically without a wall-clock sleep.
    touch -d "@$(($(stat -c %Y "$SHOGUN_STATE_DIR/shogun_stop_check_inbox_summary_hayate") + 1))" \
        "$TEST_PROJECT/queue/inbox/hayate.yaml"

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

# cmd_karo_impl_b37_error_report_false_fire_20260726 (B37): 契約を反転した。
# 旧T-SCI-007は「発言がERROR_PATTERNにマッチしたら error_report を送る」を固定していたが、
# その経路は「エラーが起きた」と「エラーについて語った」を区別できず 2026-07-26 に3件誤発火した。
# 実停止は ninja_monitor のSTALL検知(active task + idle pane)が一次情報で拾い、
# error_report の正当な発火元は .claude/hooks/stop-lint-gate.sh(実状態で判定)のみである。
@test "T-SCI-007: error mention in speech never triggers error_report (B37 陰性対照)" {
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"

    run_hook '{"stop_hook_active":false,"last_assistant_message":"エラーのため中断する"}'
    [ "$status" -eq 0 ]

    sleep 0.3
    ! grep -q 'error_report' "$INBOX_WRITE_LOG"
}

# 本日の誤発火3件と同型の実データ: 忍者がエラーについて報告・議論しているだけの発言。
@test "T-SCI-007b: real false-fire texts do not notify karo at all (B37 陰性対照)" {
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/hayate.yaml"

    run_hook '{"stop_hook_active":false,"last_assistant_message":"pre-commitがaffected_tests rc=1でBLOCK。失敗3件は当方のdiff起因でない既存REDであり、隔離treeで同じ行で同じFAILを確認した。作業は中断せず継続する。"}'
    [ "$status" -eq 0 ]

    sleep 0.3
    ! grep -q 'error_report' "$INBOX_WRITE_LOG"

    run_hook '{"stop_hook_active":false,"last_assistant_message":"commitがfailed. stopせずに原因を調べる: error handling path was aborted in the fixture, not in production."}'
    [ "$status" -eq 0 ]

    sleep 0.3
    ! grep -q 'error_report' "$INBOX_WRITE_LOG"
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

@test "T-SCI-011B: karo does not treat cmd_4131 or xcmd_41 parent_cmd as cmd_41 deployment" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: cmd_4131
YAML
    cat > "$TEST_PROJECT/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  status: in_progress
  parent_cmd: xcmd_41
YAML
    cat > "$TEST_PROJECT/queue/shogun_to_karo.yaml" <<'YAML'
commands:
  cmd_41:
    status: delegated
YAML
    # idle忍者1名以上のfixture — L596 grep '|idle|' karo_snapshot.txtが0を返すとdelegated alertがスキップされるため必須
    # fix: cmd_karo_ci_fix_sci011b_snapshot_20260724 (CI run 30067518341)
    cat > "$TEST_PROJECT/queue/karo_snapshot.txt" <<'SNAPSHOT'
ninja|saizo|cmd_test|idle|infra|CTX:0%|M:So|SRC:2026-07-24T00:00:00|TASK:idle|RUNTIME:idle
SNAPSHOT

    PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd_41 status=delegated"* ]]
    [[ "$output" == *"忍者配備を進めよ"* ]]
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
    printf 'commands:\ncmd_9999:\n  status: delegated\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    # The hook compares integer mtimes. Set the command queue one second past the flag directly.
    touch -d "@$(($(stat -c %Y "$SHOGUN_STATE_DIR/shogun_q6_brainwash_shogun") + 1))" \
        "$TEST_PROJECT/queue/shogun_to_karo.yaml"

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

@test "T-SCI-022: shogun quantity expression triggers AC1 WARN (cmd_3420 AC1)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"FoFが21件登録されている"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 数量表現"* ]]
}

@test "T-SCI-023: shogun partial count assertion triggers AC2 WARN (cmd_3420 AC2)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"21体のうち2体を確認した結果問題なしと判断した"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 部分データから全体断定パターン"* ]]
}

@test "T-SCI-024: numeric Write without memory search warns (cmd_3522 AC2-a)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    local transcript="$TEST_ROOT/transcript.jsonl"
    cat > "$transcript" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_write","name":"Write","input":{"file_path":"/tmp/article.md","content":"GS全量探索は7,521,549パターンである。"}}],"stop_reason":"tool_use"}}
EOF

    PAYLOAD="$(python3 - <<PY
import json
print(json.dumps({"stop_hook_active": False, "last_assistant_message": "記事を更新した", "transcript_path": "$transcript"}))
PY
)" TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 数値を含むWrite/gh gist edit出力"* ]]
}

@test "T-SCI-025: numeric Write after memory_db_query passes (cmd_3522 AC2-b)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    local transcript="$TEST_ROOT/transcript.jsonl"
    cat > "$transcript" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mem","name":"Bash","input":{"command":"bash scripts/memory_db_query.sh --search GS全量探索"}}],"stop_reason":"tool_use"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_write","name":"Write","input":{"file_path":"/tmp/article.md","content":"GS全量探索は7,521,549パターンである。"}}],"stop_reason":"tool_use"}}
EOF

    PAYLOAD="$(python3 - <<PY
import json
print(json.dumps({"stop_hook_active": False, "last_assistant_message": "記事を更新した", "transcript_path": "$transcript"}))
PY
)" TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: 数値を含むWrite/gh gist edit出力"* ]]
}

@test "T-SCI-026: non-numeric Write passes without memory search (cmd_3522 AC2-c)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    local transcript="$TEST_ROOT/transcript.jsonl"
    cat > "$transcript" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_write","name":"Write","input":{"file_path":"/tmp/article.md","content":"GS全量探索の概要を整理した。"}}],"stop_reason":"tool_use"}}
EOF

    PAYLOAD="$(python3 - <<PY
import json
print(json.dumps({"stop_hook_active": False, "last_assistant_message": "記事を更新した", "transcript_path": "$transcript"}))
PY
)" TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: 数値を含むWrite/gh gist edit出力"* ]]
}

@test "T-SCI-027: numeric gh gist edit without memory search warns (cmd_3522 AC1)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    local transcript="$TEST_ROOT/transcript.jsonl"
    cat > "$transcript" <<'EOF'
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_gist","name":"Bash","input":{"command":"gh gist edit abc123 --filename article.md /tmp/article.md"}}],"stop_reason":"tool_use"}}
{"type":"user","tool_result":{"tool_use_id":"toolu_gist","content":"Updated gist article.md with GS全量探索7,521,549パターン"}}
EOF

    PAYLOAD="$(python3 - <<PY
import json
print(json.dumps({"stop_hook_active": False, "last_assistant_message": "Gistを更新した", "transcript_path": "$transcript"}))
PY
)" TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 数値を含むWrite/gh gist edit出力"* ]]
}

@test "T-SCI-028: numeric tool flag without memory flag warns at Stop (cmd_3522 runtime path)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    : > "$SHOGUN_STATE_DIR/shogun_numeric_tool_output_shogun"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"記事を更新した"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 数値を含むWrite/gh gist edit出力フラグあり"* ]]
}

@test "T-SCI-029: numeric tool flag with memory flag passes at Stop (cmd_3522 runtime path)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    : > "$SHOGUN_STATE_DIR/shogun_numeric_tool_output_shogun"
    : > "$SHOGUN_STATE_DIR/shogun_memory_search_seen_shogun"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"記事を更新した"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: 数値を含むWrite/gh gist edit出力フラグあり"* ]]
}

@test "T-SCI-030: shogun Stop warns when verification action count is zero (cmd_3523 AC1)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"確認なしで応答する"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: 確認行為ゼロ"* ]]
}

@test "T-SCI-031: shogun Stop passes when verification action count is at least one (cmd_3523 AC1)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    printf '1\n' > "$SHOGUN_STATE_DIR/shogun_verification_action_count_shogun"

    PAYLOAD='{"stop_hook_active":false,"last_assistant_message":"一次確認後に応答する"}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="shogun"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN: 確認行為ゼロ"* ]]
    [ ! -f "$SHOGUN_STATE_DIR/shogun_verification_action_count_shogun" ]
}

@test "T-SCI-MEM-001: preflight evidence plus substantive response without MEM tag blocks" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    write_successful_preflight_evidence

    run_hook '{"stop_hook_active":false,"last_assistant_message":"過去の裁定を踏まえて設計理由を説明する"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"block"'* ]]
    [[ "$output" == *"[MEM:]引用タグがない"* ]]
}

@test "T-SCI-MEM-002: preflight evidence plus MEM citation passes" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    write_successful_preflight_evidence

    run_hook '{"stop_hook_active":false,"last_assistant_message":"過去の裁定を踏まえる。[MEM: semantic concept=three_layer_memory]"}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision":"block"'* ]]
}

@test "T-SCI-MEM-003: routine response without MEM tag passes even with preflight" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    write_successful_preflight_evidence

    run_hook '{"stop_hook_active":false,"last_assistant_message":"配備完了。新着を待つ。"}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision":"block"'* ]]
}

@test "T-SCI-MEM-004: substantive response without preflight evidence passes" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"
    export THREE_LAYER_PREACTION_EVIDENCE_DIR="$TEST_ROOT/no-evidence"

    run_hook '{"stop_hook_active":false,"last_assistant_message":"現在の設計理由を説明する"}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision":"block"'* ]]
}

@test "T-SCI-032: shogun brainwash #3 BLOCK on permission-seeking phrases (cmd_3996 bug fix)" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    # "殿のお許し" must trigger BLOCK
    run_hook '{"stop_hook_active":false,"last_assistant_message":"殿のお許しがあれば進める"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"block"'* ]]
    [[ "$output" == *"洗脳#3"* ]]
}

@test "T-SCI-033: shogun brainwash #3 BLOCK on judgment-deferral phrase" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    # "殿の判断を仰ぐ" must trigger BLOCK
    run_hook '{"stop_hook_active":false,"last_assistant_message":"殿の判断を仰ぐ"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"block"'* ]]
    [[ "$output" == *"洗脳#3"* ]]
}

@test "T-SCI-034: shogun brainwash #3 BLOCK on conditional deference" {
    export TMUX_AGENT_ID="shogun"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/shogun.yaml"

    # "意に沿わねば申されよ" must trigger BLOCK
    run_hook '{"stop_hook_active":false,"last_assistant_message":"意に沿わねば申されよ"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"block"'* ]]
    [[ "$output" == *"洗脳#3"* ]]
}

# cmd_4158: CI RED/GREEN境界テスト — stop_check_inbox.shのGATE催促抑制contract
@test "T-SCI-CI-RED-001: karo CI RED中はGATE催促の代わりにCI RED修正待ちを表示" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"
    mkdir -p "$TEST_PROJECT/logs"

    # CI RED状態をキャッシュファイルで注入
    _ci_cache="$TEST_ROOT/ci_state"
    printf 'failure:30000000000\n' > "$_ci_cache"

    CI_READINESS_CACHE="$_ci_cache" PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | CI_READINESS_CACHE="$CI_READINESS_CACHE" "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI RED修正待ち"* ]]
    [[ "$output" != *"報告レビュー/GATE処理を進めよ"* ]]
    # gate_fire_logにSUPPRESSED記録あり
    grep -q 'result: SUPPRESSED' "$TEST_PROJECT/logs/gate_fire_log.yaml"
    grep -q 'ci_red_gate_prompt_suppressed' "$TEST_PROJECT/logs/gate_fire_log.yaml"
}

# cmd_karo_impl_b38_ci_cache_staleness_20260726 (B38):
# 真因は「鮮度上限がない」ではなく「別種の値(最後に通知した状態)を現在状態として読んでいた」こと。
# ci_status_check.shは状態が変わらない限り書き直さないため、2行目の確認時刻でしか鮮度は判定できない。
# 是正の主対象は偽陽性(GREENなのにRED表示)であり、陰性側=古い値でRED表示しないことを本体として固定する。
@test "T-SCI-CI-STALE-001: 確認時刻がTTL超過のfailureキャッシュではCI RED表示をせず通常のGATE催促を出す" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    # 2行形式: 1行目=最後に通知した状態 / 2行目=最後に確認した時刻(2時間前=TTL 900秒超過)
    _ci_cache="$TEST_ROOT/ci_state"
    printf 'failure:30000000000\n%s\n' "$(( $(date +%s) - 7200 ))" > "$_ci_cache"

    CI_READINESS_CACHE="$_ci_cache" PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | CI_READINESS_CACHE="$CI_READINESS_CACHE" "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"CI RED修正待ち"* ]]
    [[ "$output" == *"報告レビュー/GATE処理を進めよ"* ]]
}

@test "T-SCI-CI-FRESH-001: 確認時刻がTTL内のfailureキャッシュでは従来通りCI RED修正待ちを表示する" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    _ci_cache="$TEST_ROOT/ci_state"
    printf 'failure:30000000000\n%s\n' "$(( $(date +%s) - 60 ))" > "$_ci_cache"

    CI_READINESS_CACHE="$_ci_cache" PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | CI_READINESS_CACHE="$CI_READINESS_CACHE" "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI RED修正待ち"* ]]
    [[ "$output" != *"報告レビュー/GATE処理を進めよ"* ]]
}

@test "T-SCI-CI-LEGACY-001: 旧1行形式のfailureキャッシュはmtimeが古ければCI RED表示をしない" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    _ci_cache="$TEST_ROOT/ci_state"
    printf 'failure:30000000000\n' > "$_ci_cache"
    touch -d '2 hours ago' "$_ci_cache"

    CI_READINESS_CACHE="$_ci_cache" PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | CI_READINESS_CACHE="$CI_READINESS_CACHE" "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" != *"CI RED修正待ち"* ]]
    [[ "$output" == *"報告レビュー/GATE処理を進めよ"* ]]
}

@test "T-SCI-CI-GREEN-001: karo CI GREEN時は従来のGATE催促を表示" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    # CI GREEN状態をキャッシュファイルで注入
    _ci_cache="$TEST_ROOT/ci_state"
    printf 'success:30000000001\n' > "$_ci_cache"

    CI_READINESS_CACHE="$_ci_cache" PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | CI_READINESS_CACHE="$CI_READINESS_CACHE" "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"報告レビュー/GATE処理を進めよ"* ]]
    [[ "$output" != *"CI RED修正待ち"* ]]
}

# cmd_4171: 承認記録済みタスクへの反復催促を状態表示へ切替える境界テスト
setup_review_approval_fixture_libs() {
    mkdir -p "$TEST_PROJECT/scripts/lib"
    ln -sf "$PROJECT_ROOT/scripts/lib/review_approval.sh" "$TEST_PROJECT/scripts/lib/review_approval.sh"
    ln -sf "$PROJECT_ROOT/scripts/lib/report_commit_identity.py" "$TEST_PROJECT/scripts/lib/report_commit_identity.py"
}

write_review_approval_report_fixture() {
    local cmd_id="$1" report_rel="$2"
    mkdir -p "$TEST_PROJECT/queue/reports"
    cat > "$TEST_PROJECT/$report_rel" <<YAML
parent_cmd: ${cmd_id}
task_type: full
worker_id: hayate
commit_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
status: completed
YAML
}

write_review_approval_records() {
    local cmd_id="$1" report_rel="$2" fp_key fp key dir
    fp_key=$(bash -c "
set -euo pipefail
source '$TEST_PROJECT/scripts/lib/review_approval.sh'
fp=\$(PROJECT_ROOT='$TEST_PROJECT' review_report_fingerprint '$TEST_PROJECT/$report_rel')
key=\$(review_report_key '$report_rel')
printf '%s %s' \"\$fp\" \"\$key\"
")
    fp="${fp_key%% *}"
    key="${fp_key##* }"
    dir="$TEST_PROJECT/queue/gates/${cmd_id}/review_approvals/reports/${key}"
    mkdir -p "$dir"
    printf 'timestamp: %s\nrole: gunshi\nresult: LGTM\nfingerprint: %s\nreport: %s\ncorrection_scope: implementation\n' \
        "$(date -Iseconds)" "$fp" "$report_rel" > "$dir/gunshi.yaml"
    printf 'timestamp: %s\nrole: karo\nresult: ACCEPT\nfingerprint: %s\nreport: %s\ncorrection_scope: implementation\n' \
        "$(date -Iseconds)" "$fp" "$report_rel" > "$dir/karo.yaml"
}

@test "T-SCI-REVIEW-APPROVED-001: karo sees state display instead of催促 when review already approved (cmd_4171)" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
  report_path: queue/reports/hayate_report_cmd_9999.yaml
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    setup_review_approval_fixture_libs
    write_review_approval_report_fixture cmd_9999 queue/reports/hayate_report_cmd_9999.yaml
    write_review_approval_records cmd_9999 queue/reports/hayate_report_cmd_9999.yaml

    PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"承認済み・GATE自動処理待ち"* ]]
    [[ "$output" != *"報告レビュー/GATE処理を進めよ"* ]]
    grep -q 'result: SUPPRESSED' "$TEST_PROJECT/logs/gate_fire_log.yaml"
    grep -q 'review_approved_gate_prompt_suppressed' "$TEST_PROJECT/logs/gate_fire_log.yaml"
}

@test "T-SCI-REVIEW-APPROVED-002: karo still sees従来の催促 when review not yet approved (cmd_4171)" {
    export TMUX_AGENT_ID="karo"
    printf 'messages:\n' > "$TEST_PROJECT/queue/inbox/karo.yaml"
    mkdir -p "$TEST_PROJECT/queue/tasks" "$TEST_PROJECT/logs"
    cat > "$TEST_PROJECT/queue/tasks/hayate.yaml" <<'YAML'
task:
  status: done
  parent_cmd: cmd_9999
  report_path: queue/reports/hayate_report_cmd_9999.yaml
YAML
    printf 'commands:\n' > "$TEST_PROJECT/queue/shogun_to_karo.yaml"

    setup_review_approval_fixture_libs
    write_review_approval_report_fixture cmd_9999 queue/reports/hayate_report_cmd_9999.yaml
    # 承認記録(gunshi.yaml/karo.yaml)は書き込まない = 未承認状態

    PAYLOAD='{"stop_hook_active":false}' TEST_PROJECT_PATH="$TEST_PROJECT" run bash -c '
set -euo pipefail
TMUX_AGENT_ID="karo"
printf "%s" "$PAYLOAD" | "$TEST_PROJECT_PATH/scripts/hooks/stop_check_inbox.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"報告レビュー/GATE処理を進めよ"* ]]
    [[ "$output" != *"承認済み・GATE自動処理待ち"* ]]
}
