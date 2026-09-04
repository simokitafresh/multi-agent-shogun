#!/usr/bin/env bats
# test_necessity: GA-577再発防止。一過性の通信障害(DNS/timeout/5xx)は1回だけ短い待機を
# 挟んで再試行し、2回目で成功すれば通常のOK/WARN/ALERT判定へ復帰する(exit_code=0でALERT:を
# 出さない)不変量を守る。非一過性の失敗(認証エラー)は再試行せず即ALERTする不変量、
# および再試行が2回までに限定される(無限リトライしない)不変量も併せて守る。

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  GATE="$ROOT/scripts/gates/gate_p_average_freshness.sh"
  ENV_FILE="$BATS_TEST_TMPDIR/backend.env"
  printf 'ADMIN_USER=fixture_user\nADMIN_PASS=fixture_pass\n' > "$ENV_FILE"
  CACHE_FILE="$BATS_TEST_TMPDIR/cache.txt"
  COUNT_FILE="$BATS_TEST_TMPDIR/call_count"

  RECENT_CALC_AT="$(date -u -d '-3 days' +%Y-%m-%dT%H:%M:%SZ)"

  # 呼出し回数に応じて挙動を変える擬似curl。
  # 1回目: FAKE_CURL_EXIT_1 / FAKE_CURL_HTTP_CODE_1 を返す
  # 2回目以降: FAKE_CURL_EXIT_2 / FAKE_CURL_HTTP_CODE_2 を返し、-o先へFAKE_CURL_BODY_2を書く(指定時)
  FAKE_CURL="$BATS_TEST_TMPDIR/fake_curl_retry.sh"
  cat > "$FAKE_CURL" <<'SH'
#!/usr/bin/env bash
count=0
[ -f "$FAKE_CURL_COUNT_FILE" ] && count="$(cat "$FAKE_CURL_COUNT_FILE")"
count=$((count + 1))
printf '%s' "$count" > "$FAKE_CURL_COUNT_FILE"

out_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out_file="$arg"; fi
  prev="$arg"
done

if [ "$count" -eq 1 ]; then
  echo "${FAKE_CURL_HTTP_CODE_1:-000} 0.001"
  exit "${FAKE_CURL_EXIT_1:-6}"
else
  if [ -n "$out_file" ] && [ -n "${FAKE_CURL_BODY_2:-}" ]; then
    printf '%s' "$FAKE_CURL_BODY_2" > "$out_file"
  fi
  echo "${FAKE_CURL_HTTP_CODE_2:-200} 0.002"
  exit "${FAKE_CURL_EXIT_2:-0}"
fi
SH
  chmod +x "$FAKE_CURL"
}

run_gate_retry() {
  run env \
    P_AVERAGE_ENV_FILE="$ENV_FILE" \
    P_AVERAGE_CURL_BIN="$FAKE_CURL" \
    P_AVERAGE_CACHE_FILE="$CACHE_FILE" \
    P_AVERAGE_API_RETRY_SLEEP_SECONDS=0 \
    FAKE_CURL_COUNT_FILE="$COUNT_FILE" \
    FAKE_CURL_EXIT_1="$1" \
    FAKE_CURL_HTTP_CODE_1="$2" \
    FAKE_CURL_EXIT_2="$3" \
    FAKE_CURL_HTTP_CODE_2="$4" \
    FAKE_CURL_BODY_2="$5" \
    bash "$GATE"
}

@test "DNS failure then recovery on retry exits OK with no ALERT: line" {
  body="{\"data\": {\"calculated_at\": \"${RECENT_CALC_AT}\"}}"
  run_gate_retry 6 000 0 200 "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK:"* ]]
  [[ "$output" != *"ALERT:"* ]]
  [ "$(cat "$COUNT_FILE")" -eq 2 ]
}

@test "timeout then recovery on retry exits OK with no ALERT: line" {
  body="{\"data\": {\"calculated_at\": \"${RECENT_CALC_AT}\"}}"
  run_gate_retry 28 000 0 200 "$body"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK:"* ]]
  [ "$(cat "$COUNT_FILE")" -eq 2 ]
}

@test "auth failure (401) does not retry: only 1 call attempted" {
  run_gate_retry 22 401 0 200 ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: p̄鮮度: API認証失敗"* ]]
  [ "$(cat "$COUNT_FILE")" -eq 1 ]
}

@test "DNS failure persists across retry: falls back to existing DB-fallback ALERT and stops at 2 attempts" {
  run_gate_retry 6 000 6 000 ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: p̄鮮度判定不能(通信障害)"* ]]
  [ "$(cat "$COUNT_FILE")" -eq 2 ]
}
