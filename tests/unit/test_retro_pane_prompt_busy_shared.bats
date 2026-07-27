#!/usr/bin/env bats
# test_necessity: retro_pane_prompt's default idle check (no RETRO_PANE_IDLE_CHECK override)
# must reuse the shared lib/agent_state.sh check_agent_busy classifier and fail-closed
# on busy/unknown, so Codex "Working..." panes never receive a paste even when the
# legacy @agent_state tmux option says idle (cmd_karo_hotfix_retro_prompt_legacy_busy_singleflight_20260727 AC2).

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMPD="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TMPD"
}

_fake_tmux_busy() {
    cat > "$TMPD/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message)
    case "$*" in
      *pane_dead*) echo 0 ;;
      *pane_id*) echo "%1" ;;
      *@agent_state*) echo idle ;;
      *) echo "" ;;
    esac ;;
  capture-pane) echo "Working on something..." ;;
esac
EOF
    chmod +x "$TMPD/tmux"
}

_fake_tmux_idle() {
    cat > "$TMPD/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message)
    case "$*" in
      *pane_dead*) echo 0 ;;
      *pane_id*) echo "%1" ;;
      *@agent_state*) echo idle ;;
      *) echo "" ;;
    esac ;;
  capture-pane) echo "some-prompt> " ;;
esac
EOF
    chmod +x "$TMPD/tmux"
}

@test "active Codex(Working, stale @agent_state=idle) is fail-closed rejected" {
    _fake_tmux_busy
    run bash -c '
export PATH="'"$TMPD"':$PATH"
source "'"$ROOT"'/scripts/lib/retro_pane_prompt.sh"
retro_pane_prompt_idle "fixture:agents.1" "kagemaru"
'
    [ "$status" -ne 0 ]
}

@test "true idle pane is accepted" {
    _fake_tmux_idle
    run bash -c '
export PATH="'"$TMPD"':$PATH"
source "'"$ROOT"'/scripts/lib/retro_pane_prompt.sh"
retro_pane_prompt_idle "fixture:agents.1" "kagemaru"
'
    [ "$status" -eq 0 ]
}
