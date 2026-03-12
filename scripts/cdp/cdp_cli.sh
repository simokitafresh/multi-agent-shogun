#!/usr/bin/env bash
# cdp_cli.sh — Thin CLI wrapper for CDP persistent daemon (cdp_server.py)
# Reads port+token from /tmp/cdp-server.json, auto-starts server if needed.
set -euo pipefail

readonly SERVER_INFO="/tmp/cdp-server.json"
readonly SERVER_SCRIPT="$(cd "$(dirname "$0")" && pwd)/cdp_server.py"
readonly STARTUP_TIMEOUT=10
readonly REQUEST_TIMEOUT=5

# ── Helpers ──────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

# Read port and token from server info file
read_server_info() {
    if [[ ! -f "$SERVER_INFO" ]]; then
        return 1
    fi
    PORT=$(python3 -c "import json,sys; d=json.load(open('$SERVER_INFO')); print(d['port'])" 2>/dev/null) || return 1
    TOKEN=$(python3 -c "import json,sys; d=json.load(open('$SERVER_INFO')); print(d['token'])" 2>/dev/null) || return 1
}

# Check if server is responding
server_alive() {
    local port="${1:-$PORT}"
    local token="${2:-$TOKEN}"
    curl -sf -m "$REQUEST_TIMEOUT" \
        -H "Authorization: Bearer $token" \
        "http://localhost:${port}/healthz" >/dev/null 2>&1
}

# Start the server if not running
ensure_server() {
    if read_server_info && server_alive; then
        return 0
    fi

    # Server not running — start it
    if [[ ! -f "$SERVER_SCRIPT" ]]; then
        die "Server script not found: $SERVER_SCRIPT"
    fi

    python3 "$SERVER_SCRIPT" &
    local pid=$!

    # Wait for server to become ready
    local elapsed=0
    while (( elapsed < STARTUP_TIMEOUT )); do
        sleep 1
        elapsed=$((elapsed + 1))
        if read_server_info && server_alive; then
            return 0
        fi
        # Check if process died
        if ! kill -0 "$pid" 2>/dev/null; then
            die "Server process exited unexpectedly"
        fi
    done

    die "Server not responding after ${STARTUP_TIMEOUT}s"
}

# Send a POST request to the server
post_json() {
    local endpoint="$1"
    local body="$2"
    local response
    response=$(curl -sf -m "$REQUEST_TIMEOUT" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "http://localhost:${PORT}${endpoint}" 2>&1) || {
        local rc=$?
        if [[ "$response" == *"401"* ]] || [[ "$response" == *"Unauthorized"* ]]; then
            die "Token mismatch"
        fi
        die "Server not responding (curl exit $rc)"
    }
    echo "$response"
}

# ── Subcommands ──────────────────────────────────────────

cmd_healthz() {
    ensure_server
    local response
    response=$(curl -sf -m "$REQUEST_TIMEOUT" \
        -H "Authorization: Bearer $TOKEN" \
        "http://localhost:${PORT}/healthz" 2>&1) || die "Server not responding"
    echo "$response"
}

cmd_navigate() {
    local url="${1:?Usage: cdp_cli.sh navigate <url>}"
    ensure_server
    post_json "/cdp/command" "$(printf '{"method":"Page.navigate","params":{"url":"%s"}}' "$url")"
}

cmd_screenshot() {
    local path="${1:?Usage: cdp_cli.sh screenshot <path>}"
    ensure_server
    local response
    response=$(post_json "/cdp/command" '{"method":"Page.captureScreenshot","params":{"format":"png"}}')
    # Extract base64 data and decode to file
    echo "$response" | python3 -c "
import json, base64, sys
data = json.load(sys.stdin)
result = data.get('result', data)
b64 = result.get('data', '')
if not b64:
    print('ERROR: No screenshot data in response', file=sys.stderr)
    sys.exit(1)
with open('$path', 'wb') as f:
    f.write(base64.b64decode(b64))
print('$path')
"
}

cmd_snapshot() {
    ensure_server
    post_json "/ax/snapshot" '{}'
}

cmd_click() {
    local ref="${1:?Usage: cdp_cli.sh click <@ref>}"
    # Strip leading @ if present
    ref="${ref#@}"
    ensure_server
    post_json "/ref/resolve" "$(printf '{"ref":"%s","action":"click"}' "$ref")"
}

cmd_eval() {
    local expression="${1:?Usage: cdp_cli.sh eval <expression>}"
    ensure_server
    # Use python to safely JSON-encode the expression
    local body
    body=$(python3 -c "
import json, sys
expr = sys.argv[1]
print(json.dumps({'method': 'Runtime.evaluate', 'params': {'expression': expr, 'returnByValue': True}}))
" "$expression")
    post_json "/cdp/command" "$body"
}

cmd_stop() {
    if ! read_server_info; then
        echo "Server not running (no info file)"
        return 0
    fi
    if server_alive; then
        # Read PID from server info if available, otherwise find by port
        local pid
        pid=$(python3 -c "import json; d=json.load(open('$SERVER_INFO')); print(d.get('pid',''))" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "Server stopped (PID $pid)"
        else
            # Fallback: find process by port
            pid=$(lsof -ti :"$PORT" 2>/dev/null | head -1) || true
            if [[ -n "$pid" ]]; then
                kill "$pid"
                echo "Server stopped (PID $pid)"
            else
                echo "Could not find server process"
            fi
        fi
    else
        echo "Server not running"
    fi
    rm -f "$SERVER_INFO"
}

# ── Usage ────────────────────────────────────────────────

usage() {
    cat <<'USAGE'
Usage: cdp_cli.sh <command> [args...]

Commands:
  navigate <url>         Navigate to URL
  screenshot <path>      Capture screenshot and save to file
  snapshot               Get accessibility tree (@ref annotated)
  click <@ref>           Click element by ref (e.g., @e1 or e1)
  eval <expression>      Evaluate JavaScript expression
  healthz                Check server health
  stop                   Stop the daemon server
USAGE
    exit 1
}

# ── Main ─────────────────────────────────────────────────

if (( $# < 1 )); then
    usage
fi

command="$1"
shift

case "$command" in
    navigate)    cmd_navigate "$@" ;;
    screenshot)  cmd_screenshot "$@" ;;
    snapshot)    cmd_snapshot "$@" ;;
    click)       cmd_click "$@" ;;
    eval)        cmd_eval "$@" ;;
    healthz)    cmd_healthz "$@" ;;
    stop)        cmd_stop "$@" ;;
    *)           die "Unknown command: $command"; usage ;;
esac
