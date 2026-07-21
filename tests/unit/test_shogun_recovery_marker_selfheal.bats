#!/usr/bin/env bats
# test_necessity: startup timeout後だけ完了markerを自己回復し、証跡なし・期限切れ・非将軍ではRECOVERY INCOMPLETEを隠さない境界契約。

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$ROOT/scripts/hooks/prompt_state_inject.sh"
  TEST_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$TEST_ROOT/logs"
}

load_refresh() {
  eval "$(sed -n '/^refresh_shogun_recovery_marker()/,/^}/p' "$SCRIPT")"
}

@test "fresh startup attempt self-heals a missing completion marker" {
  load_refresh
  export agent_id=shogun SCRIPT_DIR="$TEST_ROOT"
  touch "$TEST_ROOT/logs/shogun_recovery_attempted"
  refresh_shogun_recovery_marker
  [ -f "$TEST_ROOT/logs/shogun_recovery_complete" ]
}

@test "missing startup evidence stays fail-closed" {
  load_refresh
  export agent_id=shogun SCRIPT_DIR="$TEST_ROOT"
  refresh_shogun_recovery_marker
  [ ! -e "$TEST_ROOT/logs/shogun_recovery_complete" ]
}

@test "existing completion marker is refreshed" {
  load_refresh
  export agent_id=shogun SCRIPT_DIR="$TEST_ROOT" PROMPT_STATE_NOW_EPOCH=2000000000
  touch -d @1000000000 "$TEST_ROOT/logs/shogun_recovery_complete"
  refresh_shogun_recovery_marker
  [ "$(stat -c %Y "$TEST_ROOT/logs/shogun_recovery_complete")" -gt 1000000000 ]
}

@test "non-shogun does not self-heal" {
  load_refresh
  export agent_id=hanzo SCRIPT_DIR="$TEST_ROOT"
  touch "$TEST_ROOT/logs/shogun_recovery_attempted"
  refresh_shogun_recovery_marker
  [ ! -e "$TEST_ROOT/logs/shogun_recovery_complete" ]
}

@test "attempt older than 480 minutes stays fail-closed" {
  load_refresh
  export agent_id=shogun SCRIPT_DIR="$TEST_ROOT" PROMPT_STATE_NOW_EPOCH=2000000000
  touch -d @1999971199 "$TEST_ROOT/logs/shogun_recovery_attempted"
  refresh_shogun_recovery_marker
  [ ! -e "$TEST_ROOT/logs/shogun_recovery_complete" ]
}
