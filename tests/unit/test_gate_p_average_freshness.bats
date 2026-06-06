#!/usr/bin/env bats
# gate_p_average_freshness.sh regression tests

setup() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/gate_p_average_freshness.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts/gates" "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/bin"
    cp "$PROJECT_ROOT/scripts/gates/gate_p_average_freshness.sh" "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"
    chmod +x "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"
    cat > "$TEST_TMPDIR/scripts/ntfy.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_TMPDIR/ntfy.log"
SH
    chmod +x "$TEST_TMPDIR/scripts/ntfy.sh"
    cat > "$TEST_TMPDIR/backend.env" <<'EOF'
ADMIN_USER=test_user
ADMIN_PASS=test_pass
EOF
    export P_AVERAGE_ENV_FILE="$TEST_TMPDIR/backend.env"
    export P_AVERAGE_CACHE_FILE="$TEST_TMPDIR/p_average.cache"
    export P_AVERAGE_API_BASE="https://example.test"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
    unset P_AVERAGE_ENV_FILE P_AVERAGE_CACHE_FILE P_AVERAGE_API_BASE P_AVERAGE_CURL_BIN
}

write_fake_curl() {
    local exit_code="$1"
    local http_code="$2"
    local elapsed="$3"
    local body="$4"
    local stderr="${5:-}"
    cat > "$TEST_TMPDIR/bin/fake_curl" <<EOF
#!/usr/bin/env bash
out_file=""
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -o) out_file="\$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "\$out_file" ]; then
    printf '%s' '$body' > "\$out_file"
fi
if [ -n '$stderr' ]; then
    printf '%s\n' '$stderr' >&2
fi
printf '%s %s' '$http_code' '$elapsed'
exit $exit_code
EOF
    chmod +x "$TEST_TMPDIR/bin/fake_curl"
    export P_AVERAGE_CURL_BIN="$TEST_TMPDIR/bin/fake_curl"
}

@test "classifies HTTP 401 as API auth failure" {
    write_fake_curl 22 401 0.123 '{"detail":"Unauthorized"}'

    run bash "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"API認証失敗 (HTTP 401, curl_exit=22, elapsed=0.123s)"* ]]
    [[ "$output" == *"ADMIN_USER/ADMIN_PASS"* ]]
}

@test "classifies curl timeout separately from stale p-average" {
    write_fake_curl 28 000 15.001 ''

    run bash "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"APIタイムアウト (HTTP 000, curl_exit=28, elapsed=15.001s)"* ]]
    [[ "$output" == *"cold start/timeout"* ]]
}

@test "classifies curl exit 6 as DNS/API_BASE failure with next checks" {
    write_fake_curl 6 000 0.001 '' 'curl: (6) Could not resolve host: missing.example'

    run bash "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"API_BASE DNS解決失敗 (HTTP 000, curl_exit=6, elapsed=0.001s)"* ]]
    [[ "$output" == *"DNS/API_BASEを先に確認"* ]]
    [[ "$output" == *"サーバ到達性・cold sleep・バッチ鮮度はAPI到達後"* ]]
    [[ "$output" == *"getent hosts example.test"* ]]
    [[ "$output" == *"curl_error: curl: (6) Could not resolve host: missing.example"* ]]
}

@test "fresh p-average returns OK and writes cache" {
    local now_iso
    now_iso="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
    write_fake_curl 0 200 0.050 "{\"data\":{\"calculated_at\":\"${now_iso}\"}}"

    run env TZ=UTC bash "$TEST_TMPDIR/scripts/gates/gate_p_average_freshness.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: p̄ calculated_at within 30 days"* ]]
    grep -q 'exit_code=0' "$P_AVERAGE_CACHE_FILE"
}
