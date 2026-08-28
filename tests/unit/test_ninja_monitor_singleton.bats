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

# test_necessity: accidental sourcing or unknown CLI arguments must fail closed
# before daemon initialization, while the explicit library contract stays usable.
@test "entrypoint rejects accidental source and unknown args without orphan monitor" {
  script="$BATS_TEST_DIRNAME/../../scripts/ninja_monitor.sh"

  run timeout 2 bash -c 'source "$1"' _ "$script"
  [ "$status" -eq 64 ]
  [[ "$output" == *"Usage: bash scripts/ninja_monitor.sh"* ]]

  run timeout 2 bash -c 'source "$1" --source-only' _ "$script"
  [ "$status" -eq 64 ]
  [[ "$output" == *"Usage: bash scripts/ninja_monitor.sh"* ]]

  run timeout 2 bash "$script" --unknown
  [ "$status" -eq 64 ]
  [[ "$output" == *"Usage: bash scripts/ninja_monitor.sh"* ]]

  run timeout 2 env NINJA_MONITOR_LIB_ONLY=1 bash -c \
    'source "$1"; declare -F acquire_singleton_lock >/dev/null' _ "$script"
  [ "$status" -eq 0 ]

  run pgrep -af '[s]cripts/ninja_monitor.sh'
  [[ "$output" != *"$BATS_TEST_TMPDIR"* ]]
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

# test_necessity: done fast-path must publish snapshot/autoclear state without
# waiting for a contended promotion ledger, while the detached writer persists it.
@test "done fast-path detaches promotion ledger writer without losing completion" {
  run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; STATE_DIR="$BATS_TEST_TMPDIR/state"
    LOG="$BATS_TEST_TMPDIR/monitor.log"; REFLUX_PROMOTION_LEDGER="$BATS_TEST_TMPDIR/promotion.tsv"
    mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/locks" "$STATE_DIR"
    printf "%s\tcmd_reflux_promotion_probe\tCLEAR\tfixture\n" "$(date -Iseconds)" >"$SCRIPT_DIR/logs/gate_metrics.log"
    task="$SCRIPT_DIR/queue/tasks/alpha.yaml"; report="$BATS_TEST_TMPDIR/completed.yaml"
    printf "task:\n  parent_cmd: cmd_reflux_promotion_probe\n  task_id: task_probe\n  status: done\n" >"$task"
    printf "parent_cmd: cmd_reflux_promotion_probe\ntask_id: task_probe\nstatus: completed\nverdict: PASS\nresult:\n  summary: 昇格候補 L999\nbinary_checks: {}\n" >"$report"
    find_matching_report_file() { printf "%s\n" "$report"; }
    write_karo_snapshot() { sleep 2; }
    refresh_karo_snapshot_task_assignment() { date +%s%3N >"$BATS_TEST_TMPDIR/snapshot_at"; }
    log() { :; }
    flock "$REFLUX_PROMOTION_LEDGER.lock" -c "sleep 2" & holder=$!
    sleep 0.1
    start=$(date +%s%3N)
    check_and_update_done_task alpha
    elapsed=$(( $(date +%s%3N) - start ))
    [ "$elapsed" -lt 1000 ]
    [ -s "$BATS_TEST_TMPDIR/snapshot_at" ]
    # A background child that inherits deploy_lock_fd makes autoclear/deploy
    # observe the task as busy even though the fast-path already returned.
    flock -n "$SCRIPT_DIR/queue/locks/deploy_ninja_alpha.lock" -c true
    wait "$holder"
    deadline=$(( EPOCHSECONDS + 5 ))
    until grep -q $'"'"'\tL999\t'"'"' "$REFLUX_PROMOTION_LEDGER" 2>/dev/null; do
      [ "$EPOCHSECONDS" -lt "$deadline" ] || exit 91
      sleep 0.1
    done
    printf "elapsed_ms=%s promotion_count=%s\n" "$elapsed" "$(grep -c $'"'"'\tL999\t'"'"' "$REFLUX_PROMOTION_LEDGER")"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"promotion_count=1"* ]]
}

# test_necessity: a terminal done task remains eligible for exactly one
# successful autoclear after the monitor fast-path publishes its state.
@test "done task reaches autoclear after fast-path without singleton regression" {
  run env PROJECT_ROOT="$BATS_TEST_DIRNAME/../.." bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; mkdir -p "$SCRIPT_DIR/queue/tasks"
    printf "task:\n  status: done\n" >"$SCRIPT_DIR/queue/tasks/alpha.yaml"
    PANE_TARGETS[alpha]=fixture-pane
    tmux() { [ "$1" = display-message ] && printf "alpha\n" || return 0; }
    cli_type() { printf "codex\n"; }
    get_context_pct() { printf "42\n"; }
    cli_profile_get() { [ "$2" = clear_debounce ] && printf "0\n" || printf "\n"; }
    can_send_clear_with_report_gate() { return 0; }
    safe_send_clear() { printf "%s|%s|%s\n" "$1" "$2" "$3" >>"$BATS_TEST_TMPDIR/clears"; }
    _handle_auto_clear alpha "$EPOCHSECONDS"
    [ "$(wc -l <"$BATS_TEST_TMPDIR/clears")" -eq 1 ]
    grep -Fx "fixture-pane|alpha|AUTO-CLEAR" "$BATS_TEST_TMPDIR/clears"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"fixture-pane|alpha|AUTO-CLEAR"* ]]
}
