#!/usr/bin/env bats
# test_necessity: a SessionStart hook running without TMUX_PANE (a child
# `claude -p`, a daemon-spawned CLI) must NOT resolve its agent from the tmux
# active pane and must therefore never rewrite another agent's deepdive
# session marker. Invariant guards 2026-09-01 15:19 (marker of shogun rewritten
# by a foreign process -> 16/16 receipts expired -> false stop-hook BLOCK).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts/hooks" "$T/scripts/lib" "$T/logs/deepdive_replay" "$T/queue" "$T/config"
  cp "$ROOT/scripts/hooks/session_start_inject.sh" "$T/scripts/hooks/"
  cp -r "$ROOT/scripts/lib/." "$T/scripts/lib/" 2>/dev/null || true
  # fake tmux: any -p query without -t returns "shogun" (the active pane);
  # with -t it returns the pane's own id.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/tmux" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" -t "* ]]; then echo "gunshi"; else echo "shogun"; fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
}

@test "startup without TMUX_PANE does not touch any deepdive session marker" {
  run env -u TMUX_PANE -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" >/dev/null 2>&1; ls "$1/logs/deepdive_replay"' _ "$T"
  [ "$status" -eq 0 ]
  [[ "$output" != *"shogun.session"* ]]
  [[ "$output" != *".session"* ]]
}

@test "startup with TMUX_PANE resolves the pane's own agent and writes only that marker" {
  run env -u AGENT_ID TMUX=/tmp/tmux-1000/default,1,0 TMUX_PANE=%9 PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
      bash -c 'printf "{\"source\":\"startup\"}" | bash "$1/scripts/hooks/session_start_inject.sh" >/dev/null 2>&1; ls "$1/logs/deepdive_replay"' _ "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gunshi.session"* ]]
  [[ "$output" != *"shogun.session"* ]]
}
