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

@test "cdp_measure: CDP preflight auto-starts browser when port is not responding" {
    grep -q 'auto-starting (port ${CDP_PORT})' "$SCRIPT"
    grep -q 'PYTHONPATH="${AUTO_OPS_ROOT}:${PYTHONPATH:-}" python3' "$SCRIPT"
    grep -q 'from cdp import cdp_helper' "$SCRIPT"
    grep -q 'cdp_helper.preflight_cdp_flow(port=port, browser="auto", launch_timeout=30)' "$SCRIPT"
    grep -q 'CDP_CHECK="python-preflight-ok"' "$SCRIPT"
}

@test "cdp_measure: perf_measure runs with auto-ops on PYTHONPATH" {
    grep -q 'AUTO_OPS_ROOT="/mnt/c/Python_app/auto-ops"' "$SCRIPT"
    grep -q 'PYTHONPATH="${AUTO_OPS_ROOT}:${PYTHONPATH:-}" "${MEASURE_CMD\[@\]}"' "$SCRIPT"
}

@test "cdp_measure: auth preflight reports failures instead of set-e silent exit" {
    grep -q '^set +e$' "$SCRIPT"
    grep -Fq 'AUTH_RC=$?' "$SCRIPT"
    grep -q 'if \[\[ "$AUTH_RC" -ne 0 || "$AUTH_CHECK" != "OK" \]\]' "$SCRIPT"
    grep -q "data.get('passwords', \\[\\])" "$SCRIPT"
}
