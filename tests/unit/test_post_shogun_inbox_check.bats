#!/usr/bin/env bats

setup() {
    export PROJECT_ROOT HOOK TMP_DIR PANE CACHE NON_SHOGUN_CACHE INBOX LORD_CONV MARKER
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/post-shogun-inbox-check.sh"
    TMP_DIR="$(mktemp -d)"
    # Use TMP_DIR-derived unique suffix to avoid stale /tmp cache files from prior CI runs
    PANE="%psi_$(basename "$TMP_DIR")"
    CACHE="/tmp/shogun_aid_${PANE}"
    NON_SHOGUN_CACHE="/tmp/shogun_not_shogun_${PANE}"
    INBOX="$TMP_DIR/shogun.yaml"
    LORD_CONV="$TMP_DIR/lord_conversation.jsonl"
    MARKER="$TMP_DIR/recovery_complete"
    rm -f "$CACHE" "$NON_SHOGUN_CACHE"
    : > "$LORD_CONV"
    : > "$MARKER"
}

teardown() {
    rm -rf "$TMP_DIR"
    rm -f "$CACHE" "$NON_SHOGUN_CACHE"
}

@test "post shogun inbox check exits silently for cached non-shogun pane" {
    printf 'kagemaru\n' > "$CACHE"
    : > "$NON_SHOGUN_CACHE"
    printf 'messages:\n' > "$INBOX"

    run env TMUX_PANE="$PANE" \
        SHOGUN_INBOX_PATH="$INBOX" \
        SHOGUN_LORD_CONV_PATH="$LORD_CONV" \
        SHOGUN_RECOVERY_MARKER="$MARKER" \
        "$HOOK"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "post shogun inbox check reports unread inbox for cached shogun pane" {
    printf 'shogun\n' > "$CACHE"
    cat > "$INBOX" <<'YAML'
messages:
- id: msg_1
  read: false
- id: msg_2
  read: true
YAML

    run env TMUX_PANE="$PANE" \
        SHOGUN_INBOX_PATH="$INBOX" \
        SHOGUN_LORD_CONV_PATH="$LORD_CONV" \
        SHOGUN_RECOVERY_MARKER="$MARKER" \
        "$HOOK"

    [ "$status" -eq 0 ]
    [[ "$output" == *'"hookEventName":"PostToolUse"'* ]]
    [[ "$output" == *'INBOX 1件未読'* ]]
}
