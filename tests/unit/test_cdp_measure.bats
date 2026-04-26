#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/scripts/cdp/cdp_measure.sh"
}

@test "cdp_measure: frontend preflight follows redirects and has hard timeout" {
    grep -q 'FRONTEND_HEALTH_URL="${FRONTEND_HEALTH_URL:-${FRONTEND_URL}/}"' "$SCRIPT"
    grep -q 'curl -sS -L -o /dev/null -w' "$SCRIPT"
    grep -q -- '--connect-timeout 10 --max-time 30 "$FRONTEND_HEALTH_URL"' "$SCRIPT"
}

@test "cdp_measure: CDP connects to existing Chrome session (no API auth)" {
    grep -q 'CDP_PORT="${CDP_PORT:-9222}"' "$SCRIPT"
    grep -q 'curl -fsS --connect-timeout 5 --max-time 10 "http://localhost:${CDP_PORT}/json/version"' "$SCRIPT"
    ! grep -q 'cdp_cli.sh auth' "$SCRIPT"
}

@test "cdp_measure: perf_measure runs with auto-ops on PYTHONPATH" {
    grep -q 'AUTO_OPS_ROOT="/mnt/c/Python_app/auto-ops"' "$SCRIPT"
    grep -q 'PYTHONPATH="${AUTO_OPS_ROOT}:${PYTHONPATH:-}" "${MEASURE_CMD\[@\]}"' "$SCRIPT"
}

@test "cdp_measure: CDP failure exits with clear message" {
    grep -q 'FAIL (port ${CDP_PORT} not responding)' "$SCRIPT"
    grep -q 'CDPモードで起動していない' "$SCRIPT"
}
