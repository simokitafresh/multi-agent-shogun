#!/usr/bin/env bats

# test_necessity: 非同期workerがcaller PGIDを継承するとheavy laneを永続BLOCKするため、dispatch境界を契約化する。

setup() {
  TEST_ROOT="$(mktemp -d)"
  mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/lib" "$TEST_ROOT/config" "$TEST_ROOT/logs" "$TEST_ROOT/bin" "$TEST_ROOT/queue"
  cp "$BATS_TEST_DIRNAME/../../scripts/ntfy.sh" "$TEST_ROOT/scripts/ntfy.sh"
  cp "$BATS_TEST_DIRNAME/../../scripts/ntfy_action.sh" "$TEST_ROOT/scripts/ntfy_action.sh"
  cp "$BATS_TEST_DIRNAME/../../scripts/x_ops/x_token_refresh.py" "$TEST_ROOT/x_token_refresh.py"
  cp "$BATS_TEST_DIRNAME/../../lib/ntfy_auth.sh" "$TEST_ROOT/lib/ntfy_auth.sh"
  cp "$BATS_TEST_DIRNAME/../../lib/lord_conversation.sh" "$TEST_ROOT/lib/lord_conversation.sh"
  printf 'ntfy_topic: test-topic\n' > "$TEST_ROOT/config/settings.yaml"
  : > "$TEST_ROOT/config/ntfy_auth.env"
  MARKER="$TEST_ROOT/marker"
  cat > "$TEST_ROOT/bin/curl" <<'SH'
#!/bin/bash
printf '%s %s %s\n' "$PPID" "$(ps -o sid= -p $$ | tr -d ' ')" "$(ps -o pgid= -p $$ | tr -d ' ')" >> "$MARKER"
printf '%s\n' "$*" >> "${ACTION_REQUEST:-/dev/null}"
printf '200'
SH
  chmod +x "$TEST_ROOT/bin/curl"
  export MARKER PATH="$TEST_ROOT/bin:$PATH" NTFY_ENDPOINT=http://127.0.0.1/mock
  export NTFY_MIN_INTERVAL_SECONDS=0 NTFY_STATE_DIR="$TEST_ROOT/state" TMUX='' TMUX_PANE=''
  export NTFY_ASYNC_STDERR="$TEST_ROOT/worker.err"
  export NTFY_ASYNC_EVIDENCE_FILE="$TEST_ROOT/worker.evidence"
  export ACTION_REQUEST="$TEST_ROOT/action.request"
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

@test "default dispatch returns only after caller process group is empty" {
  caller_pgid="$(ps -o pgid= -p $$ | tr -d ' ')"
  bash "$TEST_ROOT/scripts/ntfy.sh" boundary-message
  dispatch_status=$?
  [ "$dispatch_status" -eq 0 ]
  read -r worker_pid worker_sid worker_pgid < "$NTFY_ASYNC_EVIDENCE_FILE"
  WORKER_PID="$worker_pid"
  [ "$worker_sid" = "$worker_pgid" ]
  [ "$worker_pgid" != "$caller_pgid" ]
  [ "$(ps -p "$worker_pid" -o pgid= | tr -d ' ')" = "$worker_pgid" ]
  wait_for_lines 1 || { cat "$NTFY_ASYNC_STDERR" >&2; return 1; }
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

# test_necessity: action-required transport must have a distinct topic,
# high priority, fixed prefix, and synchronous failure visibility while the
# existing ntfy.sh one-argument/info transport remains unchanged.
@test "action transport fixes topic priority prefix and fails closed" {
  run bash "$TEST_ROOT/scripts/ntfy_action.sh" "殿裁定を確認"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MARKER")" -eq 1 ]
  grep -qF 'https://ntfy.sh/shogun-simokitafresh-action?priority=high' "$ACTION_REQUEST"
  grep -qF '【要操作】殿裁定を確認' "$ACTION_REQUEST"

  run bash "$TEST_ROOT/scripts/ntfy_action.sh" "短時間の二通目"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MARKER")" -eq 2 ]

  cat > "$TEST_ROOT/bin/curl" <<'SH'
#!/bin/bash
printf '429'
SH
  chmod +x "$TEST_ROOT/bin/curl"
  run bash "$TEST_ROOT/scripts/ntfy_action.sh" "429失敗確認"
  [ "$status" -ne 0 ]
}

# test_necessity: refresh-token failure must produce a fresh PKCE
# authorization URL through the action channel without exposing credentials.
@test "refresh failure sends reauthorization URL through action channel" {
  cat > "$TEST_ROOT/x_api.env" <<'EOF'
X_CLIENT_ID=test-client-id
X_CLIENT_SECRET=test-client-secret
X_REDIRECT_URI=http://127.0.0.1:8585/callback
EOF
  cat > "$TEST_ROOT/reauth_action.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$REAUTH_CAPTURE"
SH
  chmod +x "$TEST_ROOT/reauth_action.sh"
  export REAUTH_CAPTURE="$TEST_ROOT/reauth.message"
  run env X_TOKEN_ACTION_NTFY_SCRIPT="$TEST_ROOT/reauth_action.sh" \
    X_PKCE_VERIFIER_FILE="$TEST_ROOT/verifier" X_PKCE_STATE_FILE="$TEST_ROOT/state" \
    python3 "$TEST_ROOT/x_token_refresh.py" "$TEST_ROOT/x_api.env"
  [ "$status" -eq 2 ]
  grep -qF 'X再認可URLを開いてAuthorize appを押してください。' "$REAUTH_CAPTURE"
  grep -qF 'https://x.com/i/oauth2/authorize?' "$REAUTH_CAPTURE"
  grep -qF 'code_challenge_method=S256' "$REAUTH_CAPTURE"
  [[ "$output" != *"test-client-secret"* ]]
}
