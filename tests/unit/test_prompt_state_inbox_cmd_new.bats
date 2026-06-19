#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/prompt_state.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/hooks" "$TEST_TMPDIR/queue/inbox"
    cp "$PROJECT_ROOT/scripts/hooks/prompt_state_inject.sh" "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh"
    chmod +x "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh"
    cat > "$TEST_TMPDIR/queue/inbox/karo.yaml" <<'EOF'
messages:
- content: "cmd_3457を書いた。配備せよ。"
  type: cmd_new
  read: false
  id: msg_cmd_3457
- content: "FYI"
  type: bulletin_notify
  read: false
  id: msg_fyi
EOF
}

teardown() {
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "karo unread cmd_new is injected as deployment-omission warning" {
    run env PROMPT_STATE_AGENT_ID=karo bash "$TEST_TMPDIR/scripts/hooks/prompt_state_inject.sh" <<'JSON'
{"prompt":"status"}
JSON
    [ "$status" -eq 0 ]
    [[ "$output" == *"inbox_unread: 2"* ]]
    [[ "$output" == *"KARO CMD_NEW 1件未処理"* ]]
    [[ "$output" == *"msg_cmd_3457"* ]]
    [[ "$output" == *"配備漏れ直結"* ]]
}
