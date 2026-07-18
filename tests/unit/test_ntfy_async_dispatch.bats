#!/usr/bin/env bats

# test_necessity: 非同期workerがcaller PGIDを継承するとheavy laneを永続BLOCKするため、dispatch境界を契約化する。

setup() {
  TEST_ROOT="$(mktemp -d)"
  mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/lib" "$TEST_ROOT/config" "$TEST_ROOT/logs" "$TEST_ROOT/bin"
  cp "$BATS_TEST_DIRNAME/../../scripts/ntfy.sh" "$TEST_ROOT/scripts/ntfy.sh"
  cp "$BATS_TEST_DIRNAME/../../lib/ntfy_auth.sh" "$TEST_ROOT/lib/ntfy_auth.sh"
  cp "$BATS_TEST_DIRNAME/../../lib/lord_conversation.sh" "$TEST_ROOT/lib/lord_conversation.sh"
  printf 'ntfy_topic: test-topic\n' > "$TEST_ROOT/config/settings.yaml"
  : > "$TEST_ROOT/config/ntfy_auth.env"
  MARKER="$TEST_ROOT/marker"
  cat > "$TEST_ROOT/bin/curl" <<'SH'
#!/bin/bash
printf '%s %s %s\n' "$PPID" "$(ps -o sid= -p $$ | tr -d ' ')" "$(ps -o pgid= -p $$ | tr -d ' ')" >> "$MARKER"
printf '200'
SH
  chmod +x "$TEST_ROOT/bin/curl"
  export MARKER PATH="$TEST_ROOT/bin:$PATH" NTFY_ENDPOINT=http://127.0.0.1/mock
  export NTFY_MIN_INTERVAL_SECONDS=0 NTFY_STATE_DIR="$TEST_ROOT/state" TMUX='' TMUX_PANE=''
  export NTFY_ASYNC_STDERR="$TEST_ROOT/worker.err"
}

teardown() {
  local attempt
  if [ -n "${WORKER_PID:-}" ]; then
    for attempt in $(seq 1 100); do
      [ -n "$(ps -p "$WORKER_PID" -o pid= 2>/dev/null)" ] || break
      sleep 0.02
    done
    [ -z "$(ps -p "$WORKER_PID" -o pid= 2>/dev/null)" ]
  fi
  rm -r "$TEST_ROOT"
}

wait_for_lines() {
  local expected="$1" attempt
  for attempt in $(seq 1 500); do
    [ "$(wc -l < "$MARKER" 2>/dev/null || true)" = "$expected" ] && return 0
    sleep 0.02
  done
  return 1
}

@test "default dispatch returns immediately and worker leaves caller process group" {
  caller_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  start_ms="$(date +%s%3N)"
  bash "$TEST_ROOT/scripts/ntfy.sh" async-message
  dispatch_status=$?
  elapsed_ms=$(( $(date +%s%3N) - start_ms ))
  [ "$dispatch_status" -eq 0 ]
  [ "$elapsed_ms" -lt 1000 ]
  wait_for_lines 1 || { cat "$NTFY_ASYNC_STDERR" >&2; return 1; }
  read -r _worker_pid worker_sid worker_pgid < "$MARKER"
  WORKER_PID="$_worker_pid"
  [ "$worker_sid" = "$worker_pgid" ]
  [ "$worker_pgid" != "$caller_pgid" ]
  [ "$(wc -l < "$MARKER")" -eq 1 ]
}

@test "sync mode executes exactly once without recursive dispatch" {
  run env NTFY_SYNC=1 bash "$TEST_ROOT/scripts/ntfy.sh" sync-message
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MARKER")" -eq 1 ]
}

@test "missing message exits one and starts no worker" {
  run bash "$TEST_ROOT/scripts/ntfy.sh"
  [ "$status" -eq 1 ]
  [ ! -e "$MARKER" ]
}
