#!/usr/bin/env bats
# test_log_terminal.bats — log_terminal_input.sh / log_terminal_response.sh 単体テスト
# cmd_558: ターミナル会話ログのフック動作テスト
#
# テスト構成:
#   T-TL-001: スラッシュコマンドがフィルタされること
#   T-TL-002: nudge(inbox*)がフィルタされること
#   T-TL-003: 正常入力がlord_conversation.yamlに記録されること
#   T-TL-004: 500文字切り詰めが動作すること（response側）
#
# モック方針:
#   スクリプトはSCRIPT_DIR(=$0のdirname/..)からLORD_CONVERSATIONパスを計算する。
#   テスト用のディレクトリ構造を作り、スクリプトをsymlink配置することで
#   SCRIPT_DIRをテンポラリパスにリダイレクトし、本番ファイルへの書込みを回避。

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export INPUT_SCRIPT="$PROJECT_ROOT/scripts/log_terminal_input.sh"
    export RESPONSE_SCRIPT="$PROJECT_ROOT/scripts/log_terminal_response.sh"
    export LORD_CONV_LIB="$PROJECT_ROOT/lib/lord_conversation.sh"
    [ -f "$INPUT_SCRIPT" ] || return 1
    [ -f "$RESPONSE_SCRIPT" ] || return 1
    [ -f "$LORD_CONV_LIB" ] || return 1
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/log_terminal_test.XXXXXX")"

    # SCRIPT_DIRリダイレクト用のディレクトリ構造を作成
    # スクリプトは dirname($0)/.. を SCRIPT_DIR とするので、
    # $TEST_TMPDIR/scripts/ にsymlink配置 → SCRIPT_DIR=$TEST_TMPDIR
    mkdir -p "$TEST_TMPDIR/scripts"
    mkdir -p "$TEST_TMPDIR/lib"
    mkdir -p "$TEST_TMPDIR/queue"
    ln -s "$INPUT_SCRIPT" "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    ln -s "$RESPONSE_SCRIPT" "$TEST_TMPDIR/scripts/log_terminal_response.sh"
    ln -s "$LORD_CONV_LIB" "$TEST_TMPDIR/lib/lord_conversation.sh"

    # テスト用のLORD_CONVERSATIONパス（スクリプトが自動設定するパス）
    export TEST_LORD_CONV="$TEST_TMPDIR/queue/lord_conversation.yaml"

    # tmuxスタブ: agent_id=shogunを返す
    export MOCK_BIN="$TEST_TMPDIR/mock_bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
# tmux display-message -t PANE -p '#{@agent_id}' → shogun
if [[ "$*" == *"display-message"* ]]; then
    echo "shogun"
    exit 0
fi
# tmux capture-pane → テスト用レスポンスを返す
if [[ "$*" == *"capture-pane"* ]]; then
    echo "${MOCK_CAPTURE_OUTPUT:-}"
    exit 0
fi
exit 0
STUB
    chmod +x "$MOCK_BIN/tmux"

    export TMUX_PANE="%0"
    export PATH="$MOCK_BIN:$PATH"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# --- T-TL-001: スラッシュコマンドがフィルタされること ---

@test "T-TL-001: slash commands are filtered out by log_terminal_input.sh" {
    export CLAUDE_USER_PROMPT="/clear"
    run bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    [ "$status" -eq 0 ]
    # ファイルが作成されないこと（フィルタされた）
    [ ! -f "$TEST_LORD_CONV" ]
}

# --- T-TL-002: nudge(inbox*)がフィルタされること ---

@test "T-TL-002: inbox nudge messages are filtered out by log_terminal_input.sh" {
    export CLAUDE_USER_PROMPT="inbox3"
    run bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_LORD_CONV" ]
}

# --- T-TL-003: 正常入力がlord_conversation.yamlに記録されること ---

@test "T-TL-003: normal input is recorded in lord_conversation.yaml" {
    export CLAUDE_USER_PROMPT="dm-signalの進捗を教えてくれ"
    run bash "$TEST_TMPDIR/scripts/log_terminal_input.sh"
    [ "$status" -eq 0 ]

    [ -f "$TEST_LORD_CONV" ]
    local content
    content=$(cat "$TEST_LORD_CONV")

    echo "$content" | grep -q "direction: inbound"
    echo "$content" | grep -q "channel: terminal"
    echo "$content" | grep -q "dm-signal"
}

# --- T-TL-004: 500文字切り詰めが動作すること（response側） ---

@test "T-TL-004: response is truncated at 500 characters" {
    # 600文字の応答をモック（tmux capture-pane出力）
    local long_response
    long_response="$(python3 -c "print('A' * 600)")"
    export MOCK_CAPTURE_OUTPUT="$long_response"

    run bash "$TEST_TMPDIR/scripts/log_terminal_response.sh"
    [ "$status" -eq 0 ]

    [ -f "$TEST_LORD_CONV" ]

    # 記録されたメッセージが500文字以下であること
    local msg_len
    msg_len=$(python3 - <<PY
import yaml
with open("$TEST_LORD_CONV") as f:
    data = yaml.safe_load(f) or {}
entries = data.get("entries", [])
if entries:
    print(len(entries[-1].get("message", "")))
else:
    print(0)
PY
)
    [ "$msg_len" -le 500 ]
    [ "$msg_len" -gt 0 ]
}
