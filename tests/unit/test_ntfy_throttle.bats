#!/usr/bin/env bats
# test_ntfy_throttle.bats — ntfy.sh global throttle/cooldown tests

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

setup() {
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/ntfy_throttle.XXXXXX")"
    export TEST_PROJECT="$TEST_TMPDIR/project"
    export CURL_LOG="$TEST_TMPDIR/curl.log"
    export NTFY_STATE_DIR="$TEST_TMPDIR/state"
    export NTFY_SYNC=1
    export PATH="$TEST_TMPDIR/bin:$PATH"

    mkdir -p "$TEST_PROJECT"/{config,lib,scripts,logs,queue} "$TEST_TMPDIR/bin" "$NTFY_STATE_DIR"
    cp "$PROJECT_ROOT/scripts/ntfy.sh" "$TEST_PROJECT/scripts/ntfy.sh"
    cp "$PROJECT_ROOT/lib/ntfy_auth.sh" "$TEST_PROJECT/lib/ntfy_auth.sh"

    cat > "$TEST_PROJECT/lib/lord_conversation.sh" <<'SH'
#!/usr/bin/env bash
append_lord_conversation() { return 0; }
SH
    cat > "$TEST_PROJECT/config/settings.yaml" <<'YAML'
ntfy_topic: "test-topic-12345"
YAML
    : > "$TEST_PROJECT/config/ntfy_auth.env"
    : > "$CURL_LOG"

    cat > "$TEST_TMPDIR/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '%s\n' "${MOCK_CURL_HTTP_CODE:-200}"
SH
    chmod +x "$TEST_PROJECT/scripts/ntfy.sh" "$TEST_TMPDIR/bin/curl"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "ntfy.sh skips sends within global 10s throttle window" {
    run bash "$TEST_PROJECT/scripts/ntfy.sh" "first"
    [ "$status" -eq 0 ]

    run bash "$TEST_PROJECT/scripts/ntfy.sh" "second"
    [ "$status" -eq 0 ]

    [ "$(wc -l < "$CURL_LOG" | tr -d ' ')" -eq 1 ]
    grep -q "SKIP throttle" "$TEST_PROJECT/logs/ntfy.log"
}

@test "ntfy.sh enters 60s cooldown after HTTP 429 and suppresses next send" {
    run env MOCK_CURL_HTTP_CODE=429 bash "$TEST_PROJECT/scripts/ntfy.sh" "rate limited"
    [ "$status" -eq 0 ]

    run env MOCK_CURL_HTTP_CODE=200 bash "$TEST_PROJECT/scripts/ntfy.sh" "suppressed"
    [ "$status" -eq 0 ]

    [ "$(wc -l < "$CURL_LOG" | tr -d ' ')" -eq 1 ]
    grep -q "COOLDOWN http=429" "$TEST_PROJECT/logs/ntfy.log"
    grep -q "SKIP cooldown_until" "$TEST_PROJECT/logs/ntfy.log"
}
