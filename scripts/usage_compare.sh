#!/usr/bin/env bash
# Compare Usage API utilization between primary and secondary Claude accounts.
set -euo pipefail

PRIMARY_DIR="${PRIMARY_DIR:-$HOME/.claude}"
SECONDARY_DIR="${SECONDARY_DIR:-$HOME/.claude-secondary}"
USAGE_API_URL="${USAGE_API_URL:-https://api.anthropic.com/v1/organizations/usage}"
USAGE_API_FALLBACK_URL="${USAGE_API_FALLBACK_URL:-https://api.anthropic.com/api/oauth/usage}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-5}"
DRY_RUN="${DRY_RUN:-0}"

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $cmd" >&2
        exit 1
    fi
}

find_credentials_file() {
    local account_dir="$1"
    local candidate
    for candidate in "credentials.json" ".credentials.json"; do
        if [[ -f "$account_dir/$candidate" ]]; then
            printf '%s\n' "$account_dir/$candidate"
            return 0
        fi
    done
    return 1
}

extract_access_token() {
    local credentials_file="$1"
    python3 - "$credentials_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)

token = None
if isinstance(data, dict):
    token = data.get("accessToken")
    oauth = data.get("claudeAiOauth")
    if not token and isinstance(oauth, dict):
        token = oauth.get("accessToken")

if not isinstance(token, str) or not token:
    sys.exit(1)

print(token)
PY
}

mock_usage_json() {
    local account="$1"
    if [[ "$account" == "Primary" ]]; then
        cat <<'JSON'
{"five_hour":{"utilization":42.3},"seven_day":{"utilization":55.1},"seven_day_sonnet":{"utilization":30.2}}
JSON
    else
        cat <<'JSON'
{"five_hour":{"utilization":15.7},"seven_day":{"utilization":23.4},"seven_day_sonnet":{"utilization":12.8}}
JSON
    fi
}

call_usage_api() {
    local token="$1"
    local url="$2"
    local output_file="$3"
    local include_beta_header="$4"
    local http_code
    local -a headers

    headers=(
        -H "Authorization: Bearer $token"
        -H "Accept: application/json"
    )
    if [[ "$include_beta_header" == "1" ]]; then
        headers+=(-H "anthropic-beta: oauth-2025-04-20")
    fi

    if ! http_code="$(curl -sS --max-time "$CURL_TIMEOUT" --connect-timeout "$CURL_CONNECT_TIMEOUT" \
        "${headers[@]}" -o "$output_file" -w "%{http_code}" "$url")"; then
        return $?
    fi

    printf '%s\n' "$http_code"
}

fetch_usage() {
    local account="$1"
    local account_dir="$2"
    local output_file="$3"
    local error_file="$4"

    : > "$error_file"

    if [[ "$DRY_RUN" == "1" ]]; then
        mock_usage_json "$account" > "$output_file"
        return 0
    fi

    local credentials_file
    if ! credentials_file="$(find_credentials_file "$account_dir")"; then
        printf 'ERROR [%s]: credentials file not found in %s (checked credentials.json/.credentials.json)\n' \
            "$account" "$account_dir" > "$error_file"
        return 1
    fi

    local token
    if ! token="$(extract_access_token "$credentials_file")"; then
        printf 'ERROR [%s]: access token missing/invalid in %s (authentication may be expired)\n' \
            "$account" "$credentials_file" > "$error_file"
        return 1
    fi

    local primary_code
    if ! primary_code="$(call_usage_api "$token" "$USAGE_API_URL" "$output_file" "0")"; then
        local curl_rc="$?"
        if [[ "$curl_rc" -eq 28 ]]; then
            printf 'ERROR [%s]: request timed out after %ss (WSL2 requires timeout >= 10s)\n' \
                "$account" "$CURL_TIMEOUT" > "$error_file"
        else
            printf 'ERROR [%s]: Usage API request failed (curl exit %s)\n' "$account" "$curl_rc" > "$error_file"
        fi
        return 1
    fi

    if [[ "$primary_code" == "200" ]]; then
        return 0
    fi

    local fallback_code
    if ! fallback_code="$(call_usage_api "$token" "$USAGE_API_FALLBACK_URL" "$output_file" "1")"; then
        local fallback_rc="$?"
        if [[ "$primary_code" == "401" || "$primary_code" == "403" ]]; then
            printf 'ERROR [%s]: authentication failed (HTTP %s). Re-login required.\n' \
                "$account" "$primary_code" > "$error_file"
        elif [[ "$fallback_rc" -eq 28 ]]; then
            printf 'ERROR [%s]: fallback request timed out after %ss\n' "$account" "$CURL_TIMEOUT" > "$error_file"
        else
            printf 'ERROR [%s]: API failure (primary HTTP %s, fallback curl exit %s)\n' \
                "$account" "$primary_code" "$fallback_rc" > "$error_file"
        fi
        return 1
    fi

    if [[ "$fallback_code" == "200" ]]; then
        return 0
    fi

    if [[ "$primary_code" == "401" || "$primary_code" == "403" || "$fallback_code" == "401" || "$fallback_code" == "403" ]]; then
        printf 'ERROR [%s]: authentication failed (primary HTTP %s, fallback HTTP %s)\n' \
            "$account" "$primary_code" "$fallback_code" > "$error_file"
    else
        printf 'ERROR [%s]: API failure (primary HTTP %s, fallback HTTP %s)\n' \
            "$account" "$primary_code" "$fallback_code" > "$error_file"
    fi
    return 1
}

print_table() {
    local primary_file="$1"
    local secondary_file="$2"

    python3 - "$primary_file" "$secondary_file" <<'PY'
import json
import sys

BUCKETS = ["five_hour", "seven_day", "seven_day_sonnet"]
LABELS = ["5h usage", "7d usage", "7d sonnet"]

def load_buckets(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return ["N/A"] * len(BUCKETS)
    results = []
    for bucket in BUCKETS:
        node = data.get(bucket) if isinstance(data, dict) else None
        value = None
        if isinstance(node, dict):
            value = node.get("utilization")
        elif isinstance(node, (int, float, str)):
            value = node
        try:
            value_f = float(value)
        except (TypeError, ValueError):
            results.append("N/A")
            continue
        if value_f <= 1.0:
            value_f *= 100.0
        results.append(f"{value_f:.1f}%")
    return results

primary = load_buckets(sys.argv[1])
secondary = load_buckets(sys.argv[2])

print("=== Claude Usage Compare ===")
print(f"{'Bucket':<14} | {'Primary':<8} | {'Secondary':<9}")
print("-" * 42)
for label, p, s in zip(LABELS, primary, secondary):
    print(f"{label:<14} | {p:>8} | {s:>9}")
PY
}

main() {
    require_command curl
    require_command python3

    primary_json="$(mktemp)"
    secondary_json="$(mktemp)"
    primary_err="$(mktemp)"
    secondary_err="$(mktemp)"

    trap 'rm -f "${primary_json:-}" "${secondary_json:-}" "${primary_err:-}" "${secondary_err:-}"' EXIT

    fetch_usage "Primary" "$PRIMARY_DIR" "$primary_json" "$primary_err" &
    local pid_primary="$!"
    fetch_usage "Secondary" "$SECONDARY_DIR" "$secondary_json" "$secondary_err" &
    local pid_secondary="$!"

    local rc_primary=0
    local rc_secondary=0
    wait "$pid_primary" || rc_primary="$?"
    wait "$pid_secondary" || rc_secondary="$?"

    if [[ "$rc_primary" -ne 0 || "$rc_secondary" -ne 0 ]]; then
        if [[ "$rc_primary" -ne 0 ]]; then
            cat "$primary_err" >&2
        fi
        if [[ "$rc_secondary" -ne 0 ]]; then
            cat "$secondary_err" >&2
        fi
        exit 1
    fi

    print_table "$primary_json" "$secondary_json"
}

main "$@"
