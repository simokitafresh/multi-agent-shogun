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

@test "cdp_measure: CDP login uses UI operation not API injection" {
    grep -q 'CDP Admin Login (UI)' "$SCRIPT"
    grep -q 'type_ref' "$SCRIPT"
    grep -q 'click_ref' "$SCRIPT"
    grep -q 'snapshot_items' "$SCRIPT"
    ! grep -q 'cdp_cli.sh auth' "$SCRIPT"
}

@test "cdp_measure: perf_measure runs with auto-ops on PYTHONPATH" {
    grep -q 'AUTO_OPS_ROOT="/mnt/c/Python_app/auto-ops"' "$SCRIPT"
    grep -q 'PYTHONPATH="${AUTO_OPS_ROOT}:${PYTHONPATH:-}" "${MEASURE_CMD\[@\]}"' "$SCRIPT"
}

@test "cdp_measure: login failure exits with clear message and cleanup runs on exit" {
    grep -q 'LOGIN_RC' "$SCRIPT"
    grep -q 'trap _cdp_cleanup EXIT' "$SCRIPT"
    grep -q 'cleanup_chrome' "$SCRIPT"
}
