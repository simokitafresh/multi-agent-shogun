#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Source the pure detector once per Bats test process. Spawning env + bash for
  # every threshold case dominated this five-test file on WSL /mnt/c.
  source "$ROOT/scripts/lib/disk_space_watch.sh"
}

@test "shared detector is OK above warning threshold" {
  DISK_WATCH_AVAILABLE_KB=$((60*1024*1024)) DISK_WATCH_WARN_GB=50 DISK_WATCH_DANGER_GB=20 \
    run disk_space_watch_measure
  [ "$status" -eq 0 ]
  [[ "$output" == OK\|* ]]
}

@test "shared detector warns below warning threshold" {
  DISK_WATCH_AVAILABLE_KB=$((40*1024*1024)) DISK_WATCH_WARN_GB=50 DISK_WATCH_DANGER_GB=20 \
    run disk_space_watch_measure
  [ "$status" -eq 0 ]
  [[ "$output" == WARN\|* ]]
}

@test "shared detector blocks below danger threshold" {
  DISK_WATCH_AVAILABLE_KB=$((10*1024*1024)) DISK_WATCH_WARN_GB=50 DISK_WATCH_DANGER_GB=20 \
    run disk_space_watch_measure
  [ "$status" -eq 0 ]
  [[ "$output" == BLOCK\|* ]]
}

@test "both startup gates consume the shared detector and expose danger BLOCK" {
  local shogun karo
  shogun="$(<"$ROOT/scripts/gates/gate_shogun_startup.sh")"
  karo="$(<"$ROOT/scripts/gates/gate_karo_startup.sh")"
  [[ "$shogun" == *'source "$SCRIPT_DIR/scripts/lib/disk_space_watch.sh"'* ]]
  [[ "$karo" == *'source "$SCRIPT_DIR/scripts/lib/disk_space_watch.sh"'* ]]
  [[ "$shogun" == *'overall="BLOCK"'* ]]
  [[ "$karo" == *'overall="BLOCK"'* ]]
}

@test "monitor notification records a detector-compatible gate fire" {
  tmp="$(mktemp -d)"
  local line definition="" capture=false
  while IFS= read -r line; do
    if [[ "$line" == 'check_disk_space_watch() {' ]]; then
      capture=true
    fi
    if [[ "$capture" == true ]]; then
      definition+="$line"$'\n'
      [[ "$line" == '}' ]] && break
    fi
  done < "$ROOT/scripts/ninja_monitor.sh"
  [[ -n "$definition" ]]
  eval "$definition"
  STATE_DIR="$tmp"
  SCRIPT_DIR="$ROOT"
  # The detector and logger have direct coverage above/in their library tests.
  # Inject their deterministic results here so this orchestration test does not
  # repeatedly spawn awk/date/dirname/mkdir processes on /mnt/c.
  send_inbox_message() { :; }
  disk_space_watch_human_gb() { printf '10.0'; }
  disk_space_watch_log_fire() {
    printf '%s\n' '- ts: "fixture", file: "disk_space_watch:/mnt/c", gate: "disk_space_watch", result: BLOCK' > "$DISK_WATCH_GATE_FIRE_LOG"
  }
  log() { :; }
  mkdir() { :; }
  dirname() { printf '%s\n' "$tmp"; }
  DISK_WATCH_AVAILABLE_KB=$((10*1024*1024))
  DISK_WATCH_GATE_FIRE_LOG="$tmp/fire.yaml"
  DISK_WATCH_STATE_FILE="$tmp/state"
  run check_disk_space_watch
  [ "$status" -eq 0 ]
  [ -s "$DISK_WATCH_GATE_FIRE_LOG" ]
  [[ "$(<"$DISK_WATCH_GATE_FIRE_LOG")" == *'gate: "disk_space_watch", result: BLOCK'* ]]
}
