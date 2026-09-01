#!/usr/bin/env bats
# test_necessity: processes that are not a pane's CLI (the ninja_monitor daemon
# and the codd propagate child spawned by cmd_complete_gate) must not carry
# TMUX_PANE, otherwise their hooks resolve as the launching pane's agent.
# Invariant guards 2026-09-01 15:19/15:39 (TMUX_PANE=%0 inherited from the
# shogun pane -> headless claude --print resolved as shogun).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "ninja_monitor daemon path scrubs TMUX_PANE; library sourcing leaves it alone" {
  run env TMUX_PANE=%0 bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$1/scripts/ninja_monitor.sh"
    echo "lib=${TMUX_PANE:-unset}"
    ninja_monitor_scrub_pane_env
    echo "scrubbed=${TMUX_PANE:-unset}"
  ' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lib=%0"* ]]
  [[ "$output" == *"scrubbed=unset"* ]]
}

@test "cmd_complete_gate launches codd propagate without TMUX_PANE/TMUX" {
  run grep -nE 'env -u TMUX_PANE -u TMUX .*"\$codd_bin" propagate' "$ROOT/scripts/cmd_complete_gate.sh"
  [ "$status" -eq 0 ]
  # every propagate invocation is scrubbed (no bare call remains)
  run grep -nE '"\$codd_bin" propagate' "$ROOT/scripts/cmd_complete_gate.sh"
  bare="$(printf '%s\n' "$output" | grep -vc 'env -u TMUX_PANE' || true)"
  [ "$bare" -eq 0 ]
}

@test "shutsujin launches ninja_monitor without TMUX_PANE" {
  run grep -nE 'env -u TMUX_PANE nohup bash "\$SCRIPT_DIR/scripts/ninja_monitor.sh"' "$ROOT/shutsujin_departure.sh"
  [ "$status" -eq 0 ]
}
