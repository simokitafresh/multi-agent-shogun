#!/usr/bin/env bash
# gate_dm_signal_production_smoke.sh — dm-signal deploy後の本番到達性ゲート
#
# Usage:
#   bash scripts/gates/gate_dm_signal_production_smoke.sh <cmd_id> \
#     --origin-sha <sha> --live-sha <sha>
#
# Exit 0: origin/live一致かつ主要APIが全て2xx
# Exit 1: deploy未到達、origin/live不一致、またはAPIエラー
#
# Production values are resolved by the caller/Render API.  The explicit
# SHA arguments make the check deterministic and keep unit fixtures offline.
# Contract: this gate is invoked through executable-path checks and must stay 100755.
set -euo pipefail

CMD_ID="${1:-}"
shift || true
ORIGIN_SHA="${DM_SIGNAL_SMOKE_ORIGIN_SHA:-}"
LIVE_SHA="${DM_SIGNAL_SMOKE_LIVE_SHA:-}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --origin-sha)
            ORIGIN_SHA="${2:-}"
            shift 2
            ;;
        --live-sha)
            LIVE_SHA="${2:-}"
            shift 2
            ;;
        *)
            echo "BLOCK: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$CMD_ID" ]; then
    echo "BLOCK: cmd_id is required" >&2
    exit 1
fi

is_sha() {
    [[ "${1:-}" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

if ! is_sha "$ORIGIN_SHA" || ! is_sha "$LIVE_SHA"; then
    echo "BLOCK: deploy_unreached origin_sha=${ORIGIN_SHA:-missing} live_sha=${LIVE_SHA:-missing}"
    exit 1
fi

if [ "${ORIGIN_SHA,,}" != "${LIVE_SHA,,}" ]; then
    echo "BLOCK: deploy_unreached origin_sha=${ORIGIN_SHA} live_sha=${LIVE_SHA}"
    exit 1
fi

API_BASE="${DM_SIGNAL_SMOKE_API_BASE:-https://dm-signal-backend.onrender.com}"
ENDPOINTS_RAW="${DM_SIGNAL_SMOKE_ENDPOINTS:-/healthz /api/signals}"
CURL_BIN="${DM_SIGNAL_SMOKE_CURL_BIN:-curl}"
CONNECT_TIMEOUT="${DM_SIGNAL_SMOKE_CONNECT_TIMEOUT:-10}"
MAX_TIME="${DM_SIGNAL_SMOKE_MAX_TIME:-30}"
AUTH_HEADER="${DM_SIGNAL_SMOKE_AUTH_HEADER:-}"
if [ -z "$AUTH_HEADER" ] && [ -n "${DM_SIGNAL_SMOKE_VIEWER_TOKEN:-}" ]; then
    AUTH_HEADER="Authorization: Bearer ${DM_SIGNAL_SMOKE_VIEWER_TOKEN}"
fi
STATUS_MAP="${DM_SIGNAL_SMOKE_HTTP_STATUS_MAP:-}"

MAP_STATUS=""
MAP_BODY_B64=""
RESPONSE_BODY_FILE=""

response_from_map() {
    local endpoint="$1" item key value
    MAP_STATUS=""
    MAP_BODY_B64=""
    [ -n "$STATUS_MAP" ] || return 1
    IFS=',' read -r -a items <<< "$STATUS_MAP"
    for item in "${items[@]}"; do
        key="${item%%=*}"
        value="${item#*=}"
        if [ "$key" = "$endpoint" ]; then
            MAP_STATUS="${value%%|*}"
            if [[ "$value" == *"|"* ]]; then
                MAP_BODY_B64="${value#*|}"
            fi
            return 0
        fi
    done
    return 1
}

fetch_response() {
    local endpoint="$1" url status curl_rc
    url="$endpoint"
    if [[ "$url" != http://* && "$url" != https://* ]]; then
        url="${API_BASE%/}/${url#/}"
    fi
    RESPONSE_BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/dm-signal-smoke.XXXXXX")"
    if response_from_map "$endpoint"; then
        RESPONSE_STATUS="$MAP_STATUS"
        if [ -n "$MAP_BODY_B64" ]; then
            if ! printf '%s' "$MAP_BODY_B64" | base64 --decode >"$RESPONSE_BODY_FILE" 2>/dev/null; then
                RESPONSE_STATUS="invalid_map_body"
            fi
        fi
        return 0
    fi

    local -a curl_args=(-sS --compressed -o "$RESPONSE_BODY_FILE" -w '%{http_code}'
        --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" "$url")
    if [ -n "$AUTH_HEADER" ]; then
        curl_args=(-H "$AUTH_HEADER" "${curl_args[@]}")
    fi
    status=""
    curl_rc=0
    status=$("$CURL_BIN" "${curl_args[@]}" 2>/dev/null) || curl_rc=$?
    if [ "$curl_rc" -ne 0 ]; then
        RESPONSE_STATUS="curl_error:$curl_rc"
        return 0
    fi
    RESPONSE_STATUS="$status"
}

validate_auth_header() {
    [[ "${1:-}" =~ ^[Aa]uthorization:[[:space:]]+[Bb]earer[[:space:]]+[^[:space:]]+$ ]]
}

validate_payload() {
    local endpoint="$1" body_file="$2"
    python3 - "$endpoint" "$body_file" <<'PY'
import json
import sys

endpoint, body_path = sys.argv[1:]

def invalid(reason):
    print(reason)
    raise SystemExit(1)

try:
    with open(body_path, encoding="utf-8") as handle:
        raw_payload = handle.read()
except OSError:
    invalid("invalid_json_payload")

if not raw_payload.strip():
    invalid("empty_required_payload")

try:
    payload = json.loads(raw_payload)
except json.JSONDecodeError:
    invalid("invalid_json_payload")

if not isinstance(payload, dict) or not payload:
    invalid("empty_required_payload")

if endpoint == "/healthz":
    if payload.get("status") != "ok":
        invalid("health_status_not_ok")
elif endpoint == "/api/signals":
    data = payload.get("data")
    if payload.get("success") is not True or not isinstance(data, dict):
        invalid("signals_success_data_missing")
    if not isinstance(data.get("as_of"), str) or not data["as_of"]:
        invalid("signals_as_of_missing")
    if not isinstance(data.get("server_date"), str) or not data["server_date"]:
        invalid("signals_server_date_missing")
    if not isinstance(data.get("portfolios"), list):
        invalid("signals_portfolios_missing")
PY
}

echo "DM-Signal production smoke: cmd=${CMD_ID} origin_sha=${ORIGIN_SHA} live_sha=${LIVE_SHA}"
read -r -a ENDPOINTS <<< "$ENDPOINTS_RAW"
if [ "${#ENDPOINTS[@]}" -eq 0 ]; then
    echo "BLOCK: no smoke endpoints configured"
    exit 1
fi

failed=0
for endpoint in "${ENDPOINTS[@]}"; do
    if [[ "$endpoint" == /api/* ]] && [ -z "$AUTH_HEADER" ]; then
        echo "endpoint=${endpoint} http_status=credential_missing result=BLOCK reason=credential_missing"
        failed=1
        continue
    fi
    if [[ "$endpoint" == /api/* ]] && ! validate_auth_header "$AUTH_HEADER"; then
        echo "endpoint=${endpoint} http_status=credential_invalid result=BLOCK reason=credential_invalid"
        failed=1
        continue
    fi

    fetch_response "$endpoint"
    status="$RESPONSE_STATUS"
    if [[ "$status" =~ ^2[0-9][0-9]$ ]] && validate_payload "$endpoint" "$RESPONSE_BODY_FILE"; then
        echo "endpoint=${endpoint} http_status=${status} result=PASS payload=valid"
    else
        payload_reason=""
        if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
            payload_reason="$(validate_payload "$endpoint" "$RESPONSE_BODY_FILE" 2>/dev/null || true)"
        fi
        echo "endpoint=${endpoint} http_status=${status:-missing} result=BLOCK${payload_reason:+ reason=${payload_reason}}"
        failed=1
    fi
    rm -f "$RESPONSE_BODY_FILE"
done

if [ "$failed" -ne 0 ]; then
    echo "BLOCK: production_api_smoke_failed"
    exit 1
fi

echo "PASS: production_api_smoke origin_live_match=1 endpoints=${#ENDPOINTS[@]}"
