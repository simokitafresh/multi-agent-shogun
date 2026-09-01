#!/usr/bin/env bats

# test_necessity: attached本番tmuxへの無許可send-keysを拒否し隔離sessionだけを許可する安全境界を永続的に守るcontract test。

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    fake_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  display-message)
    printf '%s\n' "${FAKE_TMUX_INFO:-/tmp/default|isolated|0|agents|%1}"
    ;;
  send-keys)
    printf '%s\n' "$*" >> "${FAKE_TMUX_SEND_LOG:?}"
    ;;
  *)
    :
    ;;
esac
SH
    chmod +x "$fake_bin/tmux"
    export PATH="$fake_bin:$PATH"
    export FAKE_TMUX_SEND_LOG="$BATS_TEST_TMPDIR/send.log"
}

@test "attached production shogun is blocked without explicit allow" {
    run env FAKE_TMUX_INFO='/tmp/default|shogun|1|agents|%1' \
        bash -c 'source "$1/scripts/lib/tmux_live_send_guard.sh"; tmux_live_send_keys shogun:agents.1 echo Enter' _ "$PROJECT_ROOT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"SHOGUN_ALLOW_LIVE_SENDKEYS=1"* ]]
    [ ! -e "$FAKE_TMUX_SEND_LOG" ]
}

@test "detached isolated session passes and sends to resolved target" {
    run bash -c 'source "$1/scripts/lib/tmux_live_send_guard.sh"; tmux_live_send_keys isolated:agents.1 echo Enter' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    grep -q -- 'send-keys -t isolated:agents.1 echo Enter' "$FAKE_TMUX_SEND_LOG"
}

@test "explicit allow passes only the attached production boundary" {
    run env FAKE_TMUX_INFO='/tmp/default|shogun|1|agents|%1' SHOGUN_ALLOW_LIVE_SENDKEYS=1 \
        bash -c 'source "$1/scripts/lib/tmux_live_send_guard.sh"; tmux_live_send_keys shogun:agents.1 echo Enter' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    grep -q -- 'send-keys -t shogun:agents.1 echo Enter' "$FAKE_TMUX_SEND_LOG"
}

@test "all reset send-keys calls have an immediately preceding shared guard and canonical departure owns layout" {
    reset="$PROJECT_ROOT/scripts/reset_layout.sh"
    sends="$(grep -cE '^[[:space:]]*tmux send-keys ' "$reset")"
    guards="$(grep -cE '^[[:space:]]*tmux_live_send_guard ' "$reset")"
    [ "$sends" -eq 6 ]
    [ "$guards" -eq "$sends" ]
    awk '
        /tmux send-keys / && previous !~ /tmux_live_send_guard / { exit 1 }
        { previous = $0 }
    ' "$reset"
    grep -q 'tmux_live_send_guard.sh' "$reset"
    grep -q 'select-layout -t "\$AGENTS_WINDOW_TARGET"' "$PROJECT_ROOT/shutsujin_departure.sh"
}
