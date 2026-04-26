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

@test "cdp_measure: CDP auth uses cdp_cli.sh auth with admin verification" {
    grep -q 'CDP_CLI="/mnt/c/Python_app/auto-ops/scripts/cdp/cdp_cli.sh"' "$SCRIPT"
    grep -q 'bash "$CDP_CLI" auth --env "$ENV_FILE" --port "$CDP_PORT"' "$SCRIPT"
    grep -q 'admin_authenticated' "$SCRIPT"
}

@test "cdp_measure: perf_measure runs with auto-ops on PYTHONPATH" {
    grep -q 'AUTO_OPS_ROOT="/mnt/c/Python_app/auto-ops"' "$SCRIPT"
    grep -q 'PYTHONPATH="${AUTO_OPS_ROOT}:${PYTHONPATH:-}" "${MEASURE_CMD\[@\]}"' "$SCRIPT"
}

@test "cdp_measure: auth preflight reports failures instead of set-e silent exit" {
    grep -q '^set +e$' "$SCRIPT"
    grep -Fq 'AUTH_RC=$?' "$SCRIPT"
    grep -q 'if \[\[ "$AUTH_RC" -ne 0 \]\]' "$SCRIPT"
    grep -q 'ADMIN_AUTH' "$SCRIPT"
}
