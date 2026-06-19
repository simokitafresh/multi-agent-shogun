#!/usr/bin/env bats

setup() {
  export PROJECT_ROOT
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export TEST_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TEST_BIN"

  cat > "$TEST_BIN/curl" <<'SH'
#!/bin/bash
echo 200
SH
  chmod +x "$TEST_BIN/curl"

  export PATH="$TEST_BIN:$PATH"
  export NTFY_SYNC=1
  export NTFY_MIN_INTERVAL_SECONDS=0
  export NTFY_STATE_DIR="$BATS_TEST_TMPDIR/ntfy_state"
}

@test "ntfy.sh reports tmux permission denial separately from outside tmux" {
  cat > "$TEST_BIN/tmux" <<'SH'
#!/bin/bash
echo "error connecting to /tmp/tmux-1000/default (Operation not permitted)" >&2
exit 1
SH
  chmod +x "$TEST_BIN/tmux"

  export TMUX="/tmp/tmux-1000/default,1248,0"
  export TMUX_PANE="%1"

  run bash "$PROJECT_ROOT/scripts/ntfy.sh" "test permission warning"

  [ "$status" -eq 0 ]
  [[ "$output" == *"tmux permission denied"* ]]
  [[ "$output" != *"outside tmux?"* ]]
}

@test "ntfy.sh still reports outside tmux when no tmux environment exists" {
  cat > "$TEST_BIN/tmux" <<'SH'
#!/bin/bash
echo "no server running" >&2
exit 1
SH
  chmod +x "$TEST_BIN/tmux"

  unset TMUX
  unset TMUX_PANE

  run bash "$PROJECT_ROOT/scripts/ntfy.sh" "test outside tmux warning"

  [ "$status" -eq 0 ]
  [[ "$output" == *"outside tmux"* ]]
  [[ "$output" != *"tmux permission denied"* ]]
}
