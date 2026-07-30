#!/usr/bin/env bats
# test_necessity: DNS/timeout/5xx到達性失敗時、DB fallbackがfreshならALERT:行を出さずexit 2(WARN)、
# staleはexit 1(ALERT)+stale文言、判定不能はexit 1(ALERT)+通信障害文言を返す不変量を守る(GA-416)。

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  GATE="$ROOT/scripts/gates/gate_p_average_freshness.sh"
  ENV_FILE="$BATS_TEST_TMPDIR/backend.env"
  printf 'ADMIN_USER=fixture_user\nADMIN_PASS=fixture_pass\n' > "$ENV_FILE"

  FAKE_CURL="$BATS_TEST_TMPDIR/fake_curl.sh"
  cat > "$FAKE_CURL" <<'SH'
#!/usr/bin/env bash
echo "${FAKE_CURL_HTTP_CODE:-000} ${FAKE_CURL_ELAPSED:-0.001}"
exit "${FAKE_CURL_EXIT:-0}"
SH
  chmod +x "$FAKE_CURL"

  CACHE_FILE="$BATS_TEST_TMPDIR/cache.txt"
}

run_gate() {
  run env \
    P_AVERAGE_ENV_FILE="$ENV_FILE" \
    P_AVERAGE_CURL_BIN="$FAKE_CURL" \
    P_AVERAGE_CACHE_FILE="$CACHE_FILE" \
    FAKE_CURL_EXIT="$1" \
    FAKE_CURL_HTTP_CODE="$2" \
    P_AVERAGE_DB_FALLBACK_RESULT="$3" \
    bash "$GATE"
}

@test "DNS failure with fresh DB fallback exits WARN and emits no ALERT: line" {
  run_gate 6 000 "$(printf 'OK\t2026-07-25T00:00:00+00:00\t5\tportfolio_count=10, benchmark_count=10')"
  [ "$status" -eq 2 ]
  [[ "$output" != *"ALERT:"* ]]
  [[ "$output" == *"p̄バッチ未実行/staleではない"* ]]
}

@test "DNS failure with stale DB fallback exits ALERT with stale wording" {
  run_gate 6 000 "$(printf 'OK\t2026-06-01T00:00:00+00:00\t40\tportfolio_count=10, benchmark_count=10')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: p̄バッチ未実行(stale)"* ]]
}

@test "DNS failure with undeterminable DB fallback exits ALERT with communication-failure wording" {
  run_gate 6 000 "ERROR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: p̄鮮度判定不能(通信障害)"* ]]
  [[ "$output" != *"p̄バッチ未実行(stale)"* ]]
}

@test "timeout (curl_exit=28) with fresh DB fallback exits WARN and emits no ALERT: line" {
  run_gate 28 000 "$(printf 'OK\t2026-07-25T00:00:00+00:00\t5\tportfolio_count=10, benchmark_count=10')"
  [ "$status" -eq 2 ]
  [[ "$output" != *"ALERT:"* ]]
}

@test "5xx server error (curl_exit=22) with fresh DB fallback exits WARN and emits no ALERT: line" {
  run_gate 22 503 "$(printf 'OK\t2026-07-25T00:00:00+00:00\t5\tportfolio_count=10, benchmark_count=10')"
  [ "$status" -eq 2 ]
  [[ "$output" != *"ALERT:"* ]]
}

@test "auth failure (401) still ALERTs immediately without reaching DB fallback" {
  run_gate 22 401 ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: p̄鮮度: API認証失敗"* ]]
  [[ "$output" != *"db_fallback:"* ]]
}
