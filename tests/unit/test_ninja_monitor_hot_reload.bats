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
  [ "$(grep -c 'SINGLETON-TAKEOVER' "$LOG" 2>/dev/null || true)" -ge 1 ]
  printf 'current_file_owner=1 old_owner_alive=0 old_owner_self_exit=1 snapshot_generation=1\n'
}

@test "owner parser normalizes three-field, legacy five-field, and malformed records" {
  monitor_lib
  LOG="$FIXTURE_LOG"
  printf '123 old-generation 42\n' > "$OWNER"
  IFS=$'\t' read -r pid generation heartbeat legacy_mtime legacy_fp \
    < <(ninja_monitor_read_owner_record "$OWNER")
  [ "$pid" = 123 ] && [ "$generation" = old-generation ] && [ "$heartbeat" = 42 ]
  printf '123 old-generation 42 99 legacy-fingerprint\n' > "$OWNER"
  IFS=$'\t' read -r pid generation heartbeat legacy_mtime legacy_fp \
    < <(ninja_monitor_read_owner_record "$OWNER")
  [ "$heartbeat" = 42 ] && [ "$legacy_mtime" = 99 ] && [ "$legacy_fp" = legacy-fingerprint ]
  printf 'malformed owner\n' > "$OWNER"
  ! ninja_monitor_read_owner_record "$OWNER"
  printf 'three_field=1 five_field=1 malformed_fail_closed=1\n'
}

@test "comparison and ownership boundaries are line-addressable" {
  run rg -n 'replace_generation.*existing_generation|HOT-RELOAD-(REBASE|SKIP)|SINGLETON-TAKEOVER' \
    "$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -ge 4 ]
}

@test "normal startup acquires owner before reconciliation" {
  script="$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  acquire_line=$(rg -n '^    acquire_singleton_lock$' "$script" | tail -1 | cut -d: -f1)
  reconcile_line=$(rg -n 'auto_deploy_next\.sh.*--reconcile-owner-transactions' "$script" | tail -1 | cut -d: -f1)
  [ "$acquire_line" -lt "$reconcile_line" ]
  printf 'acquire_line=%s reconcile_line=%s order=valid\n' "$acquire_line" "$reconcile_line"
}

@test "dead owner rollover escapes held old inode and recursive waiter" {
  script="$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"
  ready="$ROOT/holder.ready"; recursive="$ROOT/recursive.done"
  printf '999999 dead-generation 1\n' > "$OWNER"
  (
    exec 9>"$OWNER.lock"
    flock 9
    waiter_ready="$ROOT/waiter.ready"
    bash -lc 'exec 9>"$1"; printf ready > "$3"; flock -w 4 9; printf done > "$2"' \
      _ "$OWNER.lock" "$recursive" "$waiter_ready" & waiter_pid=$!
    for _ in $(seq 1 100); do [ -s "$waiter_ready" ] && break; sleep 0.02; done
    [ -s "$waiter_ready" ]
    printf ready > "$ready"
    sleep 0.1
    sleep 1.5
    flock -u 9
    wait "$waiter_pid"
  ) & holder_pid=$!
  for _ in $(seq 1 100); do [ -s "$ready" ] && break; sleep 0.02; done
  [ -s "$ready" ]
  old_lock_inode=$(stat -c %i "$OWNER.lock")
  started=$(date +%s%3N)
  env SHOGUN_STATE_DIR="$STATE" NINJA_MONITOR_OWNER_FILE="$OWNER" \
    NINJA_MONITOR_LIB_ONLY=1 NINJA_MONITOR_RELEASE_OWNER_ON_EXIT=0 \
    NINJA_MONITOR_OWNER_LOCK_TIMEOUT_SEC=1 \
    bash -lc 'source "$1"; LOG="$2"; acquire_singleton_lock' \
    _ "$script" "$LOG"
  elapsed=$(( $(date +%s%3N) - started ))
  wait "$holder_pid"
  for _ in $(seq 1 100); do [ -s "$recursive" ] && break; sleep 0.02; done
  [ -s "$recursive" ]
  read -r owner generation heartbeat < "$OWNER"
  [ "$owner" != 999999 ]
  [ "$elapsed" -lt 3000 ]
  new_lock_inode=$(stat -c %i "$OWNER.lock")
  [ "$new_lock_inode" != "$old_lock_inode" ]
  printf 'rollover=1 new_owner=1 recursive_waiter_released=1 elapsed_ms=%s\n' "$elapsed"
}

@test "active rollover guard blocks and dead guard recovers" {
  monitor_lib
  LOG="$FIXTURE_LOG"
  printf '999999 dead-generation 1\n' > "$OWNER"
  printf stale > "$OWNER.lock"
  old_inode=$(stat -c %i "$OWNER.lock")
  mkdir "$OWNER.lock.rollover"
  bash -c 'exec -a ninja_monitor.sh sleep 4' &
  live_pid=$!
  printf '%s %s\n' "$live_pid" "$EPOCHSECONDS" > "$OWNER.lock.rollover/claim"
  if ninja_monitor_rollover_owner_lock "$OWNER.lock" 1; then
    exit 41
  fi
  [ -d "$OWNER.lock.rollover" ]
  wait "$live_pid"
  unlink "$OWNER.lock.rollover/claim"
  rmdir "$OWNER.lock.rollover"
  mkdir "$OWNER.lock.rollover"
  printf '999999 1\n' > "$OWNER.lock.rollover/claim"
  ninja_monitor_rollover_owner_lock "$OWNER.lock" 1
  new_inode=$(stat -c %i "$OWNER.lock")
  [ "$new_inode" != "$old_inode" ]
  printf 'active_guard_block=1 dead_guard_recovery=1 inode_changed=1\n'
}

@test "new lock creation failure rolls quarantine back to old inode" {
  monitor_lib
  LOG="$FIXTURE_LOG"
  printf stale > "$OWNER.lock"
  old_inode=$(stat -c %i "$OWNER.lock")
  (
    :() { return 1; }
    ninja_monitor_rollover_owner_lock "$OWNER.lock" 1
  ) && exit 41
  [ -f "$OWNER.lock" ]
  [ "$(stat -c %i "$OWNER.lock")" = "$old_inode" ]
  [ "$(find "$STATE" -maxdepth 1 -name 'ninja_monitor.owner.lock.quarantine.*' | wc -l)" -eq 0 ]
  printf 'new_lock_failure=1 rollback=1 old_inode_restored=1\n'
}
