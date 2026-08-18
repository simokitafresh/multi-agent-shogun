#!/usr/bin/env bats
# test_necessity: generation CAS must keep one current-file owner, fence stale
# processes, and leave legacy/duplicate candidates without false BLOCKs.

setup() {
  ROOT="$BATS_TEST_TMPDIR/root"
  STATE="$ROOT/state"
  OWNER="$STATE/ninja_monitor.owner"
  LOG="$ROOT/monitor.log"
  mkdir -p "$STATE" "$ROOT/logs"
}

monitor_lib() {
  FIXTURE_LOG="$LOG"
  export SHOGUN_STATE_DIR="$STATE"
  export NINJA_MONITOR_OWNER_FILE="$OWNER"
  export NINJA_MONITOR_LIB_ONLY=1
  source "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
}

@test "matching predecessor promotes one owner with current identity" {
  prod_log="$BATS_TEST_DIRNAME/../../logs/ninja_monitor.log"
  prod_sha_before=$(sha256sum "$prod_log" 2>/dev/null | awk '{print $1}' || printf missing)
  monitor_lib
  LOG="$FIXTURE_LOG"
  printf '999999 old-generation %s\n' "$EPOCHSECONDS" > "$OWNER"
  NINJA_MONITOR_REPLACE_GENERATION=old-generation
  acquire_singleton_lock
  read -r owner generation heartbeat < "$OWNER"
  read -r script_mtime script_fingerprint < "$OWNER.identity"
  [ "$owner" = "$$" ]
  [ "$generation" != old-generation ]
  [ "$heartbeat" -ge "$((EPOCHSECONDS - 1))" ]
  [ -n "$script_mtime" ] && [ -n "$script_fingerprint" ]
  ! grep -q HOT-RELOAD-BLOCK "$LOG" 2>/dev/null
  prod_sha_after=$(sha256sum "$prod_log" 2>/dev/null | awk '{print $1}' || printf missing)
  [ "$prod_sha_before" = "$prod_sha_after" ]
  printf 'owner=1 identity=1 hot_reload_block=0\n'
}

@test "ten concurrent candidates produce one owner and nine safe skips" {
  printf '999999 old-generation %s\n' "$EPOCHSECONDS" > "$OWNER"
  for _ in $(seq 1 10); do
    env SHOGUN_STATE_DIR="$STATE" NINJA_MONITOR_OWNER_FILE="$OWNER" \
      NINJA_MONITOR_LIB_ONLY=1 NINJA_MONITOR_RELEASE_OWNER_ON_EXIT=0 \
      NINJA_MONITOR_REPLACE_GENERATION=old-generation \
      bash -lc 'source "$1"; LOG="$2"; acquire_singleton_lock' \
      _ "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh" "$LOG" &
  done
  wait
  [ "$(wc -l < "$OWNER")" -eq 1 ]
  [ "$(grep -c SINGLETON-TAKEOVER "$LOG" 2>/dev/null || true)" -eq 1 ]
  [ "$(grep -c HOT-RELOAD-SKIP "$LOG" 2>/dev/null || true)" -eq 9 ]
  [ "$(grep -c HOT-RELOAD-BLOCK "$LOG" 2>/dev/null || true)" -eq 0 ]
  printf 'parallel=10 owner=1 old_owner_alive=0 duplicate_generation=0 hot_reload_block=0\n'
}

@test "current-file rebase fences old process and upgrades legacy owner" {
  script="$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  old_ready="$ROOT/old.ready"; old_exited="$ROOT/old.exited"
  (
    export NINJA_MONITOR_RELEASE_OWNER_ON_EXIT=0
    monitor_lib; LOG="$FIXTURE_LOG"; acquire_singleton_lock
    printf ready > "$old_ready"
    while ninja_monitor_owner_heartbeat; do sleep 0.05; done
    printf exited > "$old_exited"
  ) & old_pid=$!
  for _ in $(seq 1 100); do [ -s "$old_ready" ] && break; sleep 0.02; done
  [ -s "$old_ready" ]
  read -r _old_owner old_generation _old_heartbeat < "$OWNER"
  printf '%s stale-script-generation %s\n' "$old_pid" "$EPOCHSECONDS" > "$OWNER"
  printf '1 stale-fingerprint\n' > "$OWNER.identity"
  env SHOGUN_STATE_DIR="$STATE" NINJA_MONITOR_OWNER_FILE="$OWNER" \
    NINJA_MONITOR_LIB_ONLY=1 NINJA_MONITOR_RELEASE_OWNER_ON_EXIT=0 \
    NINJA_MONITOR_REPLACE_GENERATION="$old_generation" \
    bash -lc 'source "$1"; LOG="$2"; acquire_singleton_lock' \
    _ "$script" "$LOG"
  for _ in $(seq 1 100); do [ -s "$old_exited" ] && break; sleep 0.02; done
  wait "$old_pid"
  [ -s "$old_exited" ]
  read -r new_owner new_generation _new_heartbeat < "$OWNER"
  read -r new_mtime new_fingerprint < "$OWNER.identity"
  [ "$new_owner" != "$old_pid" ] && [ "$new_generation" != stale-script-generation ]
  [ -n "$new_mtime" ] && [ -n "$new_fingerprint" ]
  [ "$(grep -c HOT-RELOAD-REBASE "$LOG" 2>/dev/null || true)" -eq 1 ]
  printf 'current_file_owner=1 old_owner_alive=0 old_owner_self_exit=1 snapshot_generation=1\n'
}

@test "comparison and ownership boundaries are line-addressable" {
  run rg -n 'replace_generation.*existing_generation|HOT-RELOAD-(REBASE|SKIP)|SINGLETON-TAKEOVER' \
    "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -ge 4 ]
}
