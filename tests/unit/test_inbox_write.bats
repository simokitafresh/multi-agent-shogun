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

    mkdir -p "$GIT_TEMPLATE_DIR/scripts/lib" "$GIT_TEMPLATE_DIR/scripts/gates" "$GIT_TEMPLATE_DIR/queue/tasks" "$GIT_TEMPLATE_DIR/queue/reports" "$GIT_TEMPLATE_DIR/src"
    # 選択的コピー: inbox_write.shが使う4ファイルのみ (NTFS→tmpfs コスト削減)
    for _lib_f in agent_config.sh field_get.sh cli_lookup.sh gunshi_notify.sh; do
        cp "$PROJECT_ROOT/scripts/lib/$_lib_f" "$GIT_TEMPLATE_DIR/scripts/lib/$_lib_f"
    done

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
    # another_file.sh を事前コミット: T-017がgit add+commitをスキップできる
    echo '#!/bin/bash' > "$GIT_TEMPLATE_DIR/src/another_file.sh"
    git -C "$GIT_TEMPLATE_DIR" add -A
    git -C "$GIT_TEMPLATE_DIR" commit -q -m "initial"

    # T-008用フィクスチャ: 既読60件 (python3不要)
    # printf -- で先頭の"-"がオプションと解釈されるのを防ぐ
    {
        printf 'messages:\n'
        for _i in $(seq 0 59); do
            printf -- "- content: '既読メッセージ %d'\n  from: 'test_sender'\n  id: 'msg_old_%03d'\n  read: true\n  timestamp: '2026-01-01T%02d:00:00'\n  type: 'test_type'\n" "$_i" "$_i" "$_i"
        done
    } > "$GIT_TEMPLATE_DIR/inbox_overflow_all_read.yaml"

    # T-009用フィクスチャ: 未読20件 + 既読40件 (python3不要)
    {
        printf 'messages:\n'
        for _i in $(seq 0 19); do
            printf -- "- content: '未読メッセージ %d'\n  from: 'test_sender'\n  id: 'msg_unread_%03d'\n  read: false\n  timestamp: '2026-01-01T%02d:00:00'\n  type: 'test_type'\n" "$_i" "$_i" "$_i"
        done
        for _i in $(seq 0 39); do
            printf -- "- content: '既読メッセージ %d'\n  from: 'test_sender'\n  id: 'msg_read_%03d'\n  read: true\n  timestamp: '2026-01-01T%02d:00:00'\n  type: 'test_type'\n" "$_i" "$_i" "$_i"
        done
    } > "$GIT_TEMPLATE_DIR/inbox_overflow_mixed.yaml"
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

    # grep検証 (python3不要)
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 1 ]]
    grep -q "^- content: 'テストメッセージ'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'shogun'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -qE "^  id: 'msg_" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  type: 'cmd_new'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  read: false" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  timestamp: " "$TEST_INBOX_DIR/test_agent.yaml"
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

    # grep検証 (python3不要)
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 2 ]]
    # 順序検証: メッセージ1が先頭
    _l1=$(grep -n "^- content: 'メッセージ1'" "$TEST_INBOX_DIR/test_agent.yaml" | cut -d: -f1)
    _l2=$(grep -n "^- content: 'メッセージ2'" "$TEST_INBOX_DIR/test_agent.yaml" | cut -d: -f1)
    [[ "$_l1" -lt "$_l2" ]]
}

# =============================================================================
# T-005: メッセージID一意性
# =============================================================================

@test "T-005: message ID uniqueness → 2 rapid writes produce different IDs" {
    setup_basic_test_env
    # 2回連続書き込み
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージA"
    bash "$TEST_INBOX_WRITE" "test_agent" "メッセージB"

    # grep検証 (python3不要): IDが2つあり、ユニークであること
    [[ "$(grep -c "^  id: " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 2 ]]
    [[ "$(grep "^  id: " "$TEST_INBOX_DIR/test_agent.yaml" | sort -u | wc -l)" -eq 2 ]]
}

# =============================================================================
# T-006: デフォルト値 — type未指定でwake_up
# =============================================================================

@test "T-006: type/from default values → type=wake_up, from=unknown when not specified" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "デフォルトテスト"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^  type: 'wake_up'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'unknown'" "$TEST_INBOX_DIR/test_agent.yaml"
}

# =============================================================================
# T-007: カスタムtype/from指定
# =============================================================================

@test "T-007: custom type/from → 4th and 5th args set type and from correctly" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "カスタムメッセージ" "custom_type" "custom_sender"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^  type: 'custom_type'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'custom_sender'" "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "T-007a: action argument provided → action field is persisted in YAML" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "アクション付き" "custom_type" "custom_sender" "notify_karo"
    [ "$status" -eq 0 ]

    # grep検証 (python3不要)
    grep -q "^- action: 'notify_karo'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  type: 'custom_type'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'custom_sender'" "$TEST_INBOX_DIR/test_agent.yaml"
}

@test "T-007b: action omitted → backward compatible write with WARN and no action field" {
    setup_basic_test_env
    run bash "$TEST_INBOX_WRITE" "test_agent" "アクションなし" "custom_type" "custom_sender"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: action omitted"* ]]

    # grep検証 (python3不要): actionフィールドが存在しないこと
    ! grep -qE "^[-]? action: " "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  type: 'custom_type'" "$TEST_INBOX_DIR/test_agent.yaml"
    grep -q "^  from: 'custom_sender'" "$TEST_INBOX_DIR/test_agent.yaml"
}

# =============================================================================
# T-008: Overflow Protection — 50件超で古い既読を削除
# =============================================================================

@test "T-008: overflow protection at 50 messages → oldest read messages removed" {
    setup_basic_test_env
    # 既読60件フィクスチャをコピー (python3不要)
    mkdir -p "$TEST_INBOX_DIR"
    cp "$GIT_TEMPLATE_DIR/inbox_overflow_all_read.yaml" "$TEST_INBOX_DIR/test_agent.yaml"

    # 新規メッセージ1件書き込み
    run bash "$TEST_INBOX_WRITE" "test_agent" "新規メッセージ"
    [ "$status" -eq 0 ]

    # grep検証: 50件以下 + 新規メッセージ存在 (python3不要)
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -le 50 ]]
    grep -q "新規メッセージ" "$TEST_INBOX_DIR/test_agent.yaml"
}

# =============================================================================
# T-009: Overflow Protection — 未読メッセージは削除されない
# =============================================================================

@test "T-009: overflow preserves unread → unread messages are NOT removed even when over 50" {
    setup_basic_test_env
    # 未読20件+既読40件フィクスチャをコピー (python3不要)
    mkdir -p "$TEST_INBOX_DIR"
    cp "$GIT_TEMPLATE_DIR/inbox_overflow_mixed.yaml" "$TEST_INBOX_DIR/test_agent.yaml"

    # 新規メッセージ1件書き込み（未読20→21件になる）
    run bash "$TEST_INBOX_WRITE" "test_agent" "新規未読"
    [ "$status" -eq 0 ]

    # grep検証: 未読21件が保持される (python3不要)
    # overflow保護は既読のみ削除するため、未読21件(元20+新1)が全て残る
    [[ "$(grep -c "^  read: false" "$TEST_INBOX_DIR/test_agent.yaml")" -eq 21 ]]
}

@test "mv failure during overflow rewrite is retried and preserves message" {
    setup_basic_test_env
    mkdir -p "$TEST_INBOX_DIR" "$TEST_TMPDIR/bin"
    cp "$GIT_TEMPLATE_DIR/inbox_overflow_all_read.yaml" "$TEST_INBOX_DIR/test_agent.yaml"

    cat > "$TEST_TMPDIR/bin/mv" <<'SCRIPT_EOF'
#!/bin/bash
dest="${@: -1}"
if [[ "$dest" == *"/queue/inbox/test_agent.yaml" && ! -f "${FAKE_MV_STATE}" ]]; then
    touch "${FAKE_MV_STATE}"
    exit 1
fi
exec /usr/bin/mv "$@"
SCRIPT_EOF
    chmod +x "$TEST_TMPDIR/bin/mv"

    export FAKE_MV_STATE="$TEST_TMPDIR/mv_failed_once"
    export PATH="$TEST_TMPDIR/bin:$PATH"
    export INBOX_WRITE_MV_RETRIES=2
    export INBOX_WRITE_MV_RETRY_SLEEP=0.01

    run bash "$TEST_INBOX_WRITE" "test_agent" "mv retry message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: mv failed"* ]]
    grep -q "mv retry message" "$TEST_INBOX_DIR/test_agent.yaml"
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 31 ]]
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

    for attempt in 1 2 3; do
        rm -f "$TEST_INBOX_DIR/test_agent.yaml"

        # 8個の並行書き込みプロセスを起動
        for i in {1..8}; do
            "$TEST_TMPDIR/parallel_write.sh" "$TEST_INBOX_WRITE" "test_agent" "$i" &
        done

        # 全プロセスの完了を待つ
        wait

        # grep検証: 8件 + ユニークID (python3不要)
        if [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 8 ]] \
           && [[ "$(grep "^  id: " "$TEST_INBOX_DIR/test_agent.yaml" | sort -u | wc -l)" -eq 8 ]]; then
            return 0
        fi
    done

    return 1
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

    # grep検証 (python3不要): 1件のメッセージ
    [[ "$(grep -c "^- " "$TEST_INBOX_DIR/test_agent.yaml")" -eq 1 ]]
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

    # another_file.shはテンプレートで既にコミット済み: git add+commit不要
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

    # grep検証 (python3不要)
    [ -f "$TEST_TMPDIR/queue/inbox/gunshi.yaml" ]
    [[ "$(grep -c "^- " "$TEST_TMPDIR/queue/inbox/gunshi.yaml")" -eq 1 ]]
    grep -q "^  type: 'report_review'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "^  from: 'karo'" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "cmd_test_001" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"
    grep -q "testninja" "$TEST_TMPDIR/queue/inbox/gunshi.yaml"

    [ -f "$TEST_TMPDIR/queue/gates/cmd_test_001/gunshi_report_review_notify_testninja.done" ]
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
        # sedでstatus更新 (python3不要): task YAMLは"  status: assigned"の1フィールドのみ
        sed -i 's/  status: assigned/  status: acknowledged/' "$TEST_TASK_FILE"
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

    # grep検証 (python3不要)
    grep -q "  status: acknowledged" "$TEST_TMPDIR/queue/tasks/testninja.yaml"
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
    [[ "$output" == *"review_gate.done created/updated: cmd_karo_auto_review_gate"* ]]
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
    # GIT_TEMPLATE_DIR (tmpfs) から コピー: NTFS→tmpfs を回避 (~105ms削減)
    cp -a "$GIT_TEMPLATE_DIR/scripts/lib" "$TEST_TMPDIR/scripts/lib"
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

    # grep検証 (python3不要)
    grep -q "^  type: 'review_result'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    for _ninja in ninja_a ninja_b; do
        [[ "$(grep -c "^- " "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml")" -eq 1 ]]
        grep -q "^  from: 'gunshi'" "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml"
        grep -q "^  type: 'task_supplement'" "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml"
        grep -q "軍師レビュー補足: verdict: FAIL cmd_999 要確認" "$TEST_TMPDIR/queue/inbox/${_ninja}.yaml"
    done
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_c.yaml" ]
}

@test "task_supplement: not forwarded again to avoid recursive fanout" {
    rm -rf "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/queue/tasks"
    # GIT_TEMPLATE_DIR (tmpfs) から コピー: NTFS→tmpfs を回避 (~105ms削減)
    cp -a "$GIT_TEMPLATE_DIR/scripts/lib" "$TEST_TMPDIR/scripts/lib"
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

    # grep検証 (python3不要)
    grep -q "^  type: 'task_supplement'" "$TEST_TMPDIR/queue/inbox/karo.yaml"
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_a.yaml" ]
    [ ! -f "$TEST_TMPDIR/queue/inbox/ninja_b.yaml" ]
}

@test "report_received: report moved to archive (no symlink) → archive fallback succeeds" {
    setup_git_test_env

    # archive_completed.sh移動後にsymlink作成失敗したケースをシミュレート:
    # queue/reports/からqueue/archive/reports/へ移動(シムリンク無し)
    mkdir -p "$TEST_TMPDIR/queue/archive/reports"
    mv "$TEST_TMPDIR/queue/reports/testninja_report_cmd_test_001.yaml" \
       "$TEST_TMPDIR/queue/archive/reports/testninja_report_cmd_test_001_20260425.yaml"

    run _run_inbox_write karo "報告完了" report_received testninja
    [ "$status" -eq 0 ]
    [[ "$output" == *"archive fallback"* ]]
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
