#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "shared detector is OK above warning threshold" {
  run env DISK_WATCH_AVAILABLE_KB=$((60*1024*1024)) DISK_WATCH_WARN_GB=50 DISK_WATCH_DANGER_GB=20 \
    bash -c 'source "$1/scripts/lib/disk_space_watch.sh"; disk_space_watch_measure' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == OK\|* ]]
}

@test "shared detector warns below warning threshold" {
  run env DISK_WATCH_AVAILABLE_KB=$((40*1024*1024)) DISK_WATCH_WARN_GB=50 DISK_WATCH_DANGER_GB=20 \
    bash -c 'source "$1/scripts/lib/disk_space_watch.sh"; disk_space_watch_measure' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == WARN\|* ]]
}

@test "shared detector blocks below danger threshold" {
  run env DISK_WATCH_AVAILABLE_KB=$((10*1024*1024)) DISK_WATCH_WARN_GB=50 DISK_WATCH_DANGER_GB=20 \
    bash -c 'source "$1/scripts/lib/disk_space_watch.sh"; disk_space_watch_measure' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == BLOCK\|* ]]
}

@test "both startup gates consume the shared detector and expose danger BLOCK" {
  run rg -n 'source .*disk_space_watch.sh|overall="BLOCK"' "$ROOT/scripts/gates/gate_shogun_startup.sh" "$ROOT/scripts/gates/gate_karo_startup.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | rg -c 'source .*disk_space_watch.sh')" -eq 2 ]
  [ "$(printf '%s\n' "$output" | rg -c 'overall="BLOCK"')" -ge 2 ]
}

@test "monitor notification records a detector-compatible gate fire" {
  tmp="$(mktemp -d)"
  run env NINJA_MONITOR_LIB_ONLY=1 SHOGUN_STATE_DIR="$tmp" DISK_WATCH_AVAILABLE_KB=$((10*1024*1024)) \
    DISK_WATCH_GATE_FIRE_LOG="$tmp/fire.yaml" DISK_WATCH_STATE_FILE="$tmp/state" \
    bash -c 'source "$1/scripts/ninja_monitor.sh"; send_inbox_message(){ printf "%s" "$2" > /dev/null; }; check_disk_space_watch; test -s "$DISK_WATCH_GATE_FIRE_LOG"; rg -q '\''gate: "disk_space_watch".*result: BLOCK'\'' "$DISK_WATCH_GATE_FIRE_LOG"' _ "$ROOT"
  [ "$status" -eq 0 ]
}
