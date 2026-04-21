#!/usr/bin/env bats
# test_inbox_write.bats — inbox_write.sh ユニットテスト
# T-001 ~ T-012: リグレッションテスト仕様書実装
# Git uncommitted check: report_received時のコミット漏れ検知
# cmd_1565: tests/版(T-001~T-012) + tests/unit/版(git uncommitted)を統合
#
# テスト構成:
#   T-001~T-002: 引数バリデーション
#   T-003~T-004: 正常書き込み（新規/追記）
#   T-005: メッセージID一意性
#   T-006~T-007: デフォルト値（type/from）
#   T-008~T-009: Overflow Protection（50件制限）
#   T-010: flock競合時のリトライ
#   T-011: 特殊文字のエスケープ処理
#   T-012: inbox初期化（ディレクトリ自動作成）
#   Git uncommitted check tests (report_received)

# --- セットアップ ---

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export INBOX_WRITE_SCRIPT="$PROJECT_ROOT/scripts/inbox_write.sh"
    export GIT_TEMPLATE_DIR
    GIT_TEMPLATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inbox_write_git_template.XXXXXX")"

    # スクリプト存在確認（前提条件）
    [ -f "$INBOX_WRITE_SCRIPT" ] || return 1

    # python3 + PyYAML存在確認
    python3 -c "import yaml" 2>/dev/null || return 1

    mkdir -p "$GIT_TEMPLATE_DIR/scripts" "$GIT_TEMPLATE_DIR/scripts/gates" "$GIT_TEMPLATE_DIR/queue/tasks" "$GIT_TEMPLATE_DIR/queue/reports" "$GIT_TEMPLATE_DIR/src"
    cp -r "$PROJECT_ROOT/scripts/lib" "$GIT_TEMPLATE_DIR/scripts/lib"

    git -C "$GIT_TEMPLATE_DIR" init -q
    git -C "$GIT_TEMPLATE_DIR" config user.name "test"
    git -C "$GIT_TEMPLATE_DIR" config user.email "test@test.com"

    cat > "$GIT_TEMPLATE_DIR/scripts/lib/agent_config.sh" << 'MOCK'
get_ninja_names() { echo "testninja"; }
get_allowed_targets() { echo "karo shogun testninja gunshi"; }
MOCK

    printf '#!/bin/bash\necho "NO-FIX-NEEDED"\n' > "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_autofix.sh"
    chmod +x "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_autofix.sh"
    printf '#!/bin/bash\necho "PASS: all checks passed"\n' > "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_format.sh"
    chmod +x "$GIT_TEMPLATE_DIR/scripts/gates/gate_report_format.sh"

    cat > "$GIT_TEMPLATE_DIR/queue/tasks/testninja.yaml" << 'YAML'
task:
  status: in_progress
  parent_cmd: cmd_test_001
  target_path: src/test_file.sh
  report_path: queue/reports/testninja_report_cmd_test_001.yaml
  report_filename: testninja_report_cmd_test_001.yaml
YAML

    cat > "$GIT_TEMPLATE_DIR/queue/reports/testninja_report_cmd_test_001.yaml" << 'YAML'
verdict: PASS
files_modified:
  - path: src/test_file.sh
    change: modified
binary_checks:
  AC1:
    - check: test check
      result: PASS
lesson_candidate:
  found: false
  no_lesson_reason: no lesson
result:
  summary: implementation complete
YAML

    echo '#!/bin/bash' > "$GIT_TEMPLATE_DIR/src/test_file.sh"
    git -C "$GIT_TEMPLATE_DIR" add -A
    git -C "$GIT_TEMPLATE_DIR" commit -q -m "initial"
}

teardown_file() {
    [ -n "${GIT_TEMPLATE_DIR:-}" ] && [ -d "$GIT_TEMPLATE_DIR" ] && rm -rf "$GIT_TEMPLATE_DIR"
}

init_test_env() {
    export TEST_TMPDIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$TEST_TMPDIR"
    export INBOX_WRITE_ROOT_OVERRIDE="$TEST_TMPDIR"
    export TEST_INBOX_WRITE="$PROJECT_ROOT/scripts/inbox_write.sh"
}

setup_basic_test_env() {
    export INBOX_WRITE_TEST=1
    export TEST_INBOX_DIR="$TEST_TMPDIR/queue/inbox"
    mkdir -p "$TEST_INBOX_DIR" "$TEST_TMPDIR/scripts"
    if [ ! -L "$TEST_TMPDIR/scripts/lib" ]; then
        ln -s "$PROJECT_ROOT/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    fi
}

setup() {
    init_test_env
}

# =============================================================================
# T-001: 引数バリデーション — target未指定でexit 1
# =============================================================================

@test "T-001: no arguments → exit 1 with Usage message" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# =============================================================================
# T-002: 引数バリデーション — content未指定でexit 1
# =============================================================================

@test "T-002: only target, no content → exit 1" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Usage" ]]
}

# =============================================================================
# T-003: 正常書き込み — 新規inboxファイル作成
# =============================================================================

@test "T-003: normal write to new inbox file → messages array with correct fields" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "テストメッセージ" "cmd_new" "shogun"
    [ "$status" -eq 0 ]

    # YAMLファイルが作成されていることを確認
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]

    # python3でYAML検証
    python3 <<EOF
import yaml, sys

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

# messages配列が存在し、1件あること
assert 'messages' in data, 'messages key not found'
assert len(data['messages']) == 1, f'Expected 1 message, got {len(data["messages"])}'

msg = data['messages'][0]

# 必須フィールドの存在確認
required_fields = ['id', 'from', 'timestamp', 'type', 'content', 'read']
for field in required_fields:
    assert field in msg, f'Field {field} not found in message'

# フィールド値の検証
assert msg['from'] == 'shogun', f'Expected from=shogun, got {msg["from"]}'
assert msg['type'] == 'cmd_new', f'Expected type=cmd_new, got {msg["type"]}'
assert msg['content'] == 'テストメッセージ', f'Expected content=テストメッセージ, got {msg["content"]}'
assert msg['read'] == False, f'Expected read=False, got {msg["read"]}'
assert msg['id'].startswith('msg_'), f'Message ID should start with msg_, got {msg["id"]}'

print('T-003: PASS')
EOF
}

# =============================================================================
# T-004: 正常書き込み — 既存inboxへの追記
# =============================================================================

@test "T-004: append to existing inbox → preserves existing messages, adds new one" {
    setup_basic_test_env
    # 1件目の書き込み
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージ1" "type1" "sender1"

    # 2件目の書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "メッセージ2" "type2" "sender2"
    [ "$status" -eq 0 ]

    # python3で検証
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

assert len(data['messages']) == 2, f'Expected 2 messages, got {len(data["messages"])}'

# 順序検証（1件目が先頭）
assert data['messages'][0]['content'] == 'メッセージ1', 'First message mismatch'
assert data['messages'][1]['content'] == 'メッセージ2', 'Second message mismatch'

print('T-004: PASS')
EOF
}

# =============================================================================
# T-005: メッセージID一意性
# =============================================================================

@test "T-005: message ID uniqueness → 2 rapid writes produce different IDs" {
    setup_basic_test_env
    # 2回連続書き込み
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージA"
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージB"

    # python3で検証
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

assert len(data['messages']) == 2, 'Expected 2 messages'

id1 = data['messages'][0]['id']
id2 = data['messages'][1]['id']

assert id1 != id2, f'Message IDs should be different: {id1} == {id2}'

print('T-005: PASS')
EOF
}

# =============================================================================
# T-006: デフォルト値 — type未指定でwake_up
# =============================================================================

@test "T-006: type/from default values → type=wake_up, from=unknown when not specified" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "デフォルトテスト"
    [ "$status" -eq 0 ]

    # python3で検証
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

msg = data['messages'][0]

assert msg['type'] == 'wake_up', f'Expected type=wake_up, got {msg["type"]}'
assert msg['from'] == 'unknown', f'Expected from=unknown, got {msg["from"]}'

print('T-006: PASS')
EOF
}

# =============================================================================
# T-007: カスタムtype/from指定
# =============================================================================

@test "T-007: custom type/from → 4th and 5th args set type and from correctly" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "カスタムメッセージ" "custom_type" "custom_sender"
    [ "$status" -eq 0 ]

    # python3で検証
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

msg = data['messages'][0]

assert msg['type'] == 'custom_type', f'Expected type=custom_type, got {msg["type"]}'
assert msg['from'] == 'custom_sender', f'Expected from=custom_sender, got {msg["from"]}'

print('T-007: PASS')
EOF
}

@test "T-007a: action argument provided → action field is persisted in YAML" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "アクション付き" "custom_type" "custom_sender" "notify_karo"
    [ "$status" -eq 0 ]

    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

msg = data['messages'][0]

assert msg['action'] == 'notify_karo', f'Expected action=notify_karo, got {msg.get("action")}'
assert msg['type'] == 'custom_type', f'Expected type=custom_type, got {msg["type"]}'
assert msg['from'] == 'custom_sender', f'Expected from=custom_sender, got {msg["from"]}'

print('T-007a: PASS')
EOF
}

@test "T-007b: action omitted → backward compatible write with WARN and no action field" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "アクションなし" "custom_type" "custom_sender"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: action omitted"* ]]

    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

msg = data['messages'][0]

assert 'action' not in msg, f'Action field should be omitted, got {msg}'
assert msg['type'] == 'custom_type', f'Expected type=custom_type, got {msg["type"]}'
assert msg['from'] == 'custom_sender', f'Expected from=custom_sender, got {msg["from"]}'

print('T-007b: PASS')
EOF
}

# =============================================================================
# T-008: Overflow Protection — 50件超で古い既読を削除
# =============================================================================

@test "T-008: overflow protection at 50 messages → oldest read messages removed" {
    setup_basic_test_env
    # 既読メッセージ60件を事前に作成
    python3 <<EOF
import yaml

messages = []
for i in range(60):
    messages.append({
        'id': f'msg_old_{i:03d}',
        'from': 'test_sender',
        'timestamp': f'2026-01-01T00:{i:02d}:00',
        'type': 'test_type',
        'content': f'既読メッセージ {i}',
        'read': True
    })

data = {'messages': messages}

with open('$TEST_INBOX_DIR/test_agent.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
EOF

    # 新規メッセージ1件書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "新規メッセージ"
    [ "$status" -eq 0 ]

    # 検証: 合計50件以下、新規メッセージは存在
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

assert len(data['messages']) <= 50, f'Expected <= 50 messages, got {len(data["messages"])}'

# 新規メッセージが含まれていることを確認
new_msg_found = any(msg['content'] == '新規メッセージ' for msg in data['messages'])
assert new_msg_found, 'New message not found after overflow protection'

print('T-008: PASS')
EOF
}

# =============================================================================
# T-009: Overflow Protection — 未読メッセージは削除されない
# =============================================================================

@test "T-009: overflow preserves unread → unread messages are NOT removed even when over 50" {
    setup_basic_test_env
    # 未読20件 + 既読40件を事前に作成
    python3 <<EOF
import yaml

messages = []

# 未読20件
for i in range(20):
    messages.append({
        'id': f'msg_unread_{i:03d}',
        'from': 'test_sender',
        'timestamp': f'2026-01-01T00:{i:02d}:00',
        'type': 'test_type',
        'content': f'未読メッセージ {i}',
        'read': False
    })

# 既読40件
for i in range(40):
    messages.append({
        'id': f'msg_read_{i:03d}',
        'from': 'test_sender',
        'timestamp': f'2026-01-01T01:{i:02d}:00',
        'type': 'test_type',
        'content': f'既読メッセージ {i}',
        'read': True
    })

data = {'messages': messages}

with open('$TEST_INBOX_DIR/test_agent.yaml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
EOF

    # 新規メッセージ1件書き込み（未読20→21件になる）
    run bash "$TEST_INBOX_WRITE" "test_agent" "新規未読"
    [ "$status" -eq 0 ]

    # 検証: 未読21件が全て保持される
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

unread_count = sum(1 for msg in data['messages'] if not msg.get('read', False))

assert unread_count == 21, f'Expected 21 unread messages, got {unread_count}'

# 元の未読メッセージが全て残っていることを確認
for i in range(20):
    found = any(msg['content'] == f'未読メッセージ {i}' for msg in data['messages'])
    assert found, f'Unread message {i} was removed'

print('T-009: PASS')
EOF
}

# =============================================================================
# T-010: flock競合時のリトライ（並行書き込みテスト）
# =============================================================================

@test "T-010: concurrent writes (flock test) → 8 parallel writes all succeed, no data loss" {
    setup_basic_test_env
    # 並行書き込み用のスクリプトを作成
    cat > "$TEST_TMPDIR/parallel_write.sh" <<'SCRIPT_EOF'
#!/bin/bash
INBOX_WRITE="$1"
AGENT="$2"
ID="$3"
bash "$INBOX_WRITE" "$AGENT" "並行メッセージ $ID" "concurrent" "writer_$ID" 2>/dev/null
SCRIPT_EOF
    chmod +x "$TEST_TMPDIR/parallel_write.sh"

    # 8個の並行書き込みプロセスを起動
    for i in {1..8}; do
        "$TEST_TMPDIR/parallel_write.sh" "$TEST_INBOX_WRITE" "test_agent" "$i" &
    done

    # 全プロセスの完了を待つ
    wait

    # 検証: 8件全てが書き込まれていること
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

assert len(data['messages']) == 8, f'Expected 8 messages, got {len(data["messages"])}'

# 全てのIDが異なることを確認
ids = [msg['id'] for msg in data['messages']]
assert len(ids) == len(set(ids)), 'Duplicate message IDs found'

print('T-010: PASS')
EOF
}

# =============================================================================
# T-011: 特殊文字のエスケープ処理
# =============================================================================

@test "T-011: special characters in content → YAML special chars handled safely" {
    setup_basic_test_env
    # YAML特殊文字を含むメッセージ
    SPECIAL_CONTENT="引用符: \"test\" と 'test'
改行を含む
コロン: key: value
ブレース: {key: value}
配列: [1, 2, 3]"

    run bash "$TEST_INBOX_WRITE" "test_agent" "$SPECIAL_CONTENT"
    [ "$status" -eq 0 ]

    # 検証: 特殊文字が正しく保存・復元されること
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

msg = data['messages'][0]

expected_content = '''引用符: "test" と 'test'
改行を含む
コロン: key: value
ブレース: {key: value}
配列: [1, 2, 3]'''

assert msg['content'] == expected_content, f'Content mismatch: {msg["content"]}'

print('T-011: PASS')
EOF
}

# =============================================================================
# T-012: inbox初期化 — ディレクトリ自動作成
# =============================================================================

@test "T-012: auto-create inbox directory → missing queue/inbox/ directory is created" {
    setup_basic_test_env
    # queue/inbox/ ディレクトリを削除
    rm -rf "$TEST_INBOX_DIR"

    # ディレクトリが存在しないことを確認
    [ ! -d "$TEST_INBOX_DIR" ]

    # メッセージ書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "自動作成テスト"
    [ "$status" -eq 0 ]

    # ディレクトリとファイルが作成されていることを確認
    [ -d "$TEST_INBOX_DIR" ]
    [ -f "$TEST_INBOX_DIR/test_agent.yaml" ]

    # 内容検証
    python3 <<EOF
import yaml

with open('$TEST_INBOX_DIR/test_agent.yaml') as f:
    data = yaml.safe_load(f)

assert len(data['messages']) == 1, 'Expected 1 message after auto-create'

print('T-012: PASS')
EOF
}

# ============================================================
# Git uncommitted check tests (merged from tests/unit/ cmd_cycle_001)
# ============================================================

# Helper: set up git repo + mocks for report_received tests
setup_git_test_env() {
    # report_received requires NINJA_NAMES from agent_config.sh
    # Unset INBOX_WRITE_TEST so the script sources agent_config.sh
    unset INBOX_WRITE_TEST

    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/reports" "$TEST_TMPDIR/src" "$TEST_TMPDIR/.git"
    cp -a "$GIT_TEMPLATE_DIR/." "$TEST_TMPDIR/"
}

# Wrapper to capture stderr in bats output
_run_inbox_write() {
    bash "$TEST_INBOX_WRITE" "$@" 2>&1
}

_wait_for_file() {
    local path="$1"
    local _attempt
    for _attempt in {1..100}; do
        [ -f "$path" ] && return 0
        sleep 0.02
    done
    return 1
}

@test "report_received: uncommitted changes in files_modified → BLOCKED" {
    setup_git_test_env

    # Modify file WITHOUT committing
    echo 'echo "modified"' >> "$TEST_TMPDIR/src/test_file.sh"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 1 ]
    [[ "$output" == *"git_uncommitted_gate"* ]]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "report_received: all files committed → no BLOCK" {
    setup_git_test_env

    # All files committed — clean working tree
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]

    # Verify message was delivered to inbox
    [ -f "$TEST_TMPDIR/queue/inbox/karo.yaml" ]
}

@test "report_received: only files_modified checked, not whole repo" {
    setup_git_test_env

    # Add another tracked file and commit
    echo '#!/bin/bash' > "$TEST_TMPDIR/src/another_file.sh"
    git -C "$TEST_TMPDIR" add -A
    git -C "$TEST_TMPDIR" commit -q -m "add another file"

    # Modify another_file.sh (NOT in files_modified) without committing
    echo 'echo modified' >> "$TEST_TMPDIR/src/another_file.sh"

    # src/test_file.sh is clean, src/another_file.sh is dirty but not in check scope
    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
}

@test "report_received: auto-sends report_review to gunshi" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"
    echo 'status: completed' >> "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"gunshi_notify: SENT"* ]]

    python3 <<EOF
import yaml

with open('$TEST_TMPDIR/queue/inbox/gunshi.yaml') as f:
    data = yaml.safe_load(f)

assert len(data['messages']) == 1
msg = data['messages'][0]
assert msg['type'] == 'report_review'
assert msg['from'] == 'karo'
assert 'cmd_test_001' in msg['content']
assert 'testninja' in msg['content']
EOF

    [ -f "$TEST_TMPDIR/queue/gates/cmd_test_001/gunshi_notify_testninja.done" ]
}

@test "task_assigned: codex ninja delivery verification retries up to 2 times" {
    setup_basic_test_env
    mkdir -p "$TEST_TMPDIR/config" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/bin"

    cat > "$TEST_TMPDIR/config/settings.yaml" <<'YAML'
cli:
  default: claude
  agents:
    testninja:
      type: codex
YAML

    cat > "$TEST_TMPDIR/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: assigned
YAML

    export CLI_ADAPTER_SETTINGS="$TEST_TMPDIR/config/settings.yaml"
    export TMUX_LOG="$TEST_TMPDIR/tmux.log"
    export TMUX_SEND_COUNT_FILE="$TEST_TMPDIR/tmux_send_count"
    export TEST_TASK_FILE="$TEST_TMPDIR/queue/tasks/testninja.yaml"

    cat > "$TEST_TMPDIR/bin/tmux" <<'EOF'
#!/bin/bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes)
    echo "shogun:agents.3 testninja"
    ;;
  send-keys)
    if [[ "$*" == *" Enter"* ]]; then
      count=0
      [ -f "$TMUX_SEND_COUNT_FILE" ] && count=$(cat "$TMUX_SEND_COUNT_FILE")
      count=$((count + 1))
      echo "$count" > "$TMUX_SEND_COUNT_FILE"
      if [ "$count" -ge 2 ]; then
        python3 - "$TEST_TASK_FILE" <<'PYEOF'
import sys, yaml
path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f) or {}
data.setdefault('task', {})['status'] = 'acknowledged'
with open(path, 'w') as f:
    yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
PYEOF
      fi
    fi
    ;;
esac
exit 0
EOF
    chmod +x "$TEST_TMPDIR/bin/tmux"

    PATH="$TEST_TMPDIR/bin:$PATH" INBOX_CODEX_VERIFY_WAIT_SEC=0 run bash "$TEST_INBOX_WRITE" "testninja" "タスクを読め" "task_assigned" "karo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified after retry 2/2"* ]]

    grep -q "set-buffer -b nudge_testninja" "$TMUX_LOG"
    [ "$(cat "$TMUX_SEND_COUNT_FILE")" -eq 2 ]

    python3 <<EOF
import yaml
with open('$TEST_TMPDIR/queue/tasks/testninja.yaml') as f:
    data = yaml.safe_load(f)
assert data['task']['status'] == 'acknowledged'
EOF
}

@test "report_review_result: LGTM updates placeholder and starts cmd_complete_gate in background" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"

    cat > "$TEST_TMPDIR/scripts/cmd_complete_gate.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$INBOX_WRITE_BG_LOG"
EOF
    chmod +x "$TEST_TMPDIR/scripts/cmd_complete_gate.sh"
    export INBOX_WRITE_BG_LOG="$TEST_TMPDIR/cmd_complete_gate.log"

    cat > "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done" <<'EOF'
timestamp: 2026-04-21T13:00:00
source: deploy_preflight
note: placeholder
EOF

    run _run_inbox_write karo "cmd_karo_auto_review_gate testninja報告レビュー。verdict: LGTM。" report_review_result gunshi
    [ "$status" -eq 0 ]
    [[ "$output" == *"review_gate.done updated: cmd_karo_auto_review_gate"* ]]
    [[ "$output" == *"cmd_complete_gate.sh started in background for cmd_karo_auto_review_gate"* ]]

    _wait_for_file "$INBOX_WRITE_BG_LOG"
    grep -q '^cmd_karo_auto_review_gate$' "$INBOX_WRITE_BG_LOG"
    grep -q '^source: gunshi_review$' "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done"
    grep -q '^result: LGTM$' "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done"
}

@test "report_review_result: FAIL does not update placeholder or run cmd_complete_gate" {
    setup_git_test_env
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate"
    ln -sf "$PROJECT_ROOT/scripts/inbox_write.sh" "$TEST_TMPDIR/scripts/inbox_write.sh"

    cat > "$TEST_TMPDIR/scripts/cmd_complete_gate.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$INBOX_WRITE_BG_LOG"
EOF
    chmod +x "$TEST_TMPDIR/scripts/cmd_complete_gate.sh"
    export INBOX_WRITE_BG_LOG="$TEST_TMPDIR/cmd_complete_gate.log"

    cat > "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done" <<'EOF'
timestamp: 2026-04-21T13:00:00
source: deploy_preflight
note: placeholder
EOF

    run _run_inbox_write karo "cmd_karo_auto_review_gate testninja報告レビュー。verdict: FAIL。" report_review_result gunshi
    [ "$status" -eq 0 ]
    [[ "$output" != *"review_gate.done updated"* ]]
    [[ "$output" != *"cmd_complete_gate.sh started in background"* ]]

    grep -q '^source: deploy_preflight$' "$TEST_TMPDIR/queue/gates/cmd_karo_auto_review_gate/review_gate.done"
    [ ! -f "$INBOX_WRITE_BG_LOG" ]
}

@test "review_result: forwarded to active ninjas only as task_supplement" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks"
    cp -a "$PROJECT_ROOT/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
get_ninja_names() { echo "ninja_a ninja_b ninja_c"; }
get_allowed_targets() { echo "karo shogun gunshi ninja_a ninja_b ninja_c"; }
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_a.yaml" <<'YAML'
task:
  status: assigned
YAML

    cat > "$TEST_TMPDIR/queue/tasks/ninja_b.yaml" <<'YAML'
task:
  status: in_progress
YAML

    cat > "$TEST_TMPDIR/queue/tasks/ninja_c.yaml" <<'YAML'
task:
  status: idle
YAML

    run _run_inbox_write karo "verdict: FAIL cmd_999 要確認" review_result gunshi
    [ "$status" -eq 0 ]

    python3 <<EOF
import os
import yaml

root = "$TEST_TMPDIR/queue/inbox"

with open(os.path.join(root, "karo.yaml")) as f:
    karo = yaml.safe_load(f)
assert karo["messages"][0]["type"] == "review_result"

for ninja in ("ninja_a", "ninja_b"):
    with open(os.path.join(root, f"{ninja}.yaml")) as f:
        data = yaml.safe_load(f)
    assert len(data["messages"]) == 1, f"{ninja} should have exactly one forwarded message"
    msg = data["messages"][0]
    assert msg["from"] == "gunshi", f"{ninja} sender mismatch"
    assert msg["type"] == "task_supplement", f"{ninja} type mismatch"
    assert msg["content"] == "Gunshi review supplement: verdict: FAIL cmd_999 要確認", f"{ninja} content mismatch"

assert not os.path.exists(os.path.join(root, "ninja_c.yaml")), "idle ninja should not receive forwarded message"
EOF
}

@test "task_supplement: not forwarded again to avoid recursive fanout" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks"
    cp -a "$PROJECT_ROOT/scripts/lib" "$TEST_TMPDIR/scripts/lib"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
get_ninja_names() { echo "ninja_a ninja_b"; }
get_allowed_targets() { echo "karo shogun gunshi ninja_a ninja_b"; }
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_a.yaml" <<'YAML'
task:
  status: in_progress
YAML

    run _run_inbox_write karo "軍師レビュー補足: 既存補足" task_supplement gunshi
    [ "$status" -eq 0 ]

    python3 <<EOF
import os
import yaml

root = "$TEST_TMPDIR/queue/inbox"

with open(os.path.join(root, "karo.yaml")) as f:
    karo = yaml.safe_load(f)
assert karo["messages"][0]["type"] == "task_supplement"

assert not os.path.exists(os.path.join(root, "ninja_a.yaml")), "task_supplement should not be forwarded"
assert not os.path.exists(os.path.join(root, "ninja_b.yaml")), "task_supplement should not be forwarded"
EOF
}

@test "filesystem fast-path: known ninja target succeeds without sourcing agent_config" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/queue/tasks" "$TEST_TMPDIR/queue/inbox"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
echo "agent_config should not be sourced on filesystem fast-path" >&2
return 99
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_fast.yaml" <<'YAML'
task:
  status: assigned
YAML

    run _run_inbox_write ninja_fast "fast path ok" wake_up karo
    [ "$status" -eq 0 ]
    [[ "$output" != *"agent_config should not be sourced"* ]]
    [ -f "$TEST_TMPDIR/queue/inbox/ninja_fast.yaml" ]
}

@test "filesystem fast-path: ninja sender to shogun is blocked without agent_config" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts/lib" "$TEST_TMPDIR/queue/tasks"
    unset INBOX_WRITE_TEST

    cat > "$TEST_TMPDIR/scripts/lib/agent_config.sh" <<'MOCK'
echo "agent_config should not be sourced on filesystem fast-path" >&2
return 99
MOCK

    cat > "$TEST_TMPDIR/queue/tasks/ninja_fast.yaml" <<'YAML'
task:
  status: in_progress
YAML

    run _run_inbox_write shogun "relay forbidden" wake_up ninja_fast
    [ "$status" -eq 1 ]
    [[ "$output" == *"Ninja cannot send inbox to shogun directly"* ]]
    [[ "$output" != *"agent_config should not be sourced"* ]]
}
