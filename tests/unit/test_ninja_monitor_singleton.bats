#!/usr/bin/env bats
# test_necessity: ninja_monitor must recover from a live-but-stalled generation without destructive process termination or duplicate healthy owners.

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$ROOT/logs" "$BATS_TEST_TMPDIR/state"
  export SHOGUN_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export NINJA_MONITOR_OWNER_FILE="$SHOGUN_STATE_DIR/ninja_monitor.owner"
  export LOG="$ROOT/logs/monitor.log"
  export SCRIPT_DIR="$BATS_TEST_DIRNAME/../.."
  export NINJA_MONITOR_HEARTBEAT_STALE_SECONDS=5
}

monitor_lib() {
  NINJA_MONITOR_LIB_ONLY=1 source "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  LOG="$ROOT/logs/monitor.log"
}

@test "live but stalled owner is atomically replaced without termination" {
  monitor_lib
  printf '%s old-generation %s\n' "$$" "$((EPOCHSECONDS - 30))" > "$NINJA_MONITOR_OWNER_FILE"
  printf '%s\n' "$$" > "$SHOGUN_STATE_DIR/ninja_monitor.pid"
  acquire_singleton_lock
  read -r owner generation heartbeat < "$NINJA_MONITOR_OWNER_FILE"
  [ "$owner" = "$$" ]
  [ "$generation" = "$NINJA_MONITOR_GENERATION" ]
  [ "$heartbeat" -ge "$((EPOCHSECONDS - 1))" ]
}

@test "healthy owner blocks a duplicate generation" {
  run env SHOGUN_STATE_DIR="$SHOGUN_STATE_DIR" \
    NINJA_MONITOR_OWNER_FILE="$NINJA_MONITOR_OWNER_FILE" \
    NINJA_MONITOR_HEARTBEAT_STALE_SECONDS=5 \
    bash -c 'NINJA_MONITOR_LIB_ONLY=1 source "$1"; LOG="$2"; printf "%s healthy %s\n" "$$" "$EPOCHSECONDS" > "$NINJA_MONITOR_OWNER_FILE"; acquire_singleton_lock; echo duplicate-ran' \
    _ "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh" "$LOG"
  [ "$status" -eq 0 ]
  [[ "$output" != *duplicate-ran* ]]
  grep -q 'SINGLETON-BLOCK: healthy owner' "$LOG"
}

@test "two stale contenders produce one owner and loser self-fences" {
  printf '999999 stale %s\n' "$((EPOCHSECONDS - 30))" > "$NINJA_MONITOR_OWNER_FILE"
  run env SHOGUN_STATE_DIR="$SHOGUN_STATE_DIR" \
    NINJA_MONITOR_OWNER_FILE="$NINJA_MONITOR_OWNER_FILE" \
    NINJA_MONITOR_HEARTBEAT_STALE_SECONDS=5 \
    NINJA_MONITOR_RELEASE_OWNER_ON_EXIT=0 \
    bash -c 'NINJA_MONITOR_LIB_ONLY=1 source "$1"; LOG="$2"; acquire_singleton_lock; printf "%s" "$NINJA_MONITOR_GENERATION"' \
    _ "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh" "$LOG"
  [ "$status" -eq 0 ]
  winner_generation="$output"
  read -r owner winner_generation heartbeat < "$NINJA_MONITOR_OWNER_FILE"
  printf '%s %s %s\n' "$$" "$winner_generation" "$EPOCHSECONDS" > "$NINJA_MONITOR_OWNER_FILE"
  run env SHOGUN_STATE_DIR="$SHOGUN_STATE_DIR" \
    NINJA_MONITOR_OWNER_FILE="$NINJA_MONITOR_OWNER_FILE" \
    NINJA_MONITOR_HEARTBEAT_STALE_SECONDS=5 \
    NINJA_MONITOR_LIVENESS_OVERRIDE_PID="$$" \
    bash -c 'NINJA_MONITOR_LIB_ONLY=1 source "$1"; LOG="$2"; acquire_singleton_lock; printf loser > "$3"' \
    _ "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh" "$LOG" "$BATS_TEST_TMPDIR/b"
  [ "$status" -eq 0 ]
  read -r owner generation heartbeat < "$NINJA_MONITOR_OWNER_FILE"
  [ "$generation" = "$winner_generation" ]
  [ ! -e "$BATS_TEST_TMPDIR/b" ]
}

@test "old generation self-fences and new generation keeps auto-clear lane available" {
  monitor_lib
  NINJA_MONITOR_GENERATION=old-generation
  printf '%s new-generation %s\n' "$$" "$EPOCHSECONDS" > "$NINJA_MONITOR_OWNER_FILE"
  before_auto_clear=0
  ninja_monitor_owner_heartbeat || before_auto_clear=$?
  [ "$before_auto_clear" -eq 1 ]
  NINJA_MONITOR_GENERATION=new-generation
  after_auto_clear=0
  ninja_monitor_owner_heartbeat || after_auto_clear=$?
  [ "$after_auto_clear" -eq 0 ]
}

@test "takeover implementation contains no destructive process termination" {
  run awk '/^acquire_singleton_lock\(\)/,/^_ninja_monitor_pid_is_live\(\)/' \
    "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  [ "$status" -eq 0 ]
  ! grep -Eq '(^|[;&|[:space:]])(pkill|killall|tmux[[:space:]]+kill|kill[[:space:]]+-[^0])' <<< "$output"
}
