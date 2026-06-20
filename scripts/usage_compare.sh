#!/usr/bin/env bash
# Compare Usage API utilization between primary and secondary Claude accounts.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/model_family.sh"
SEVEN_DAY_SECONDARY_KEY="seven_day_${MODEL_FAMILY_TOKEN_SONNET}"

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
    # WSL2最適化: python3(~34ms)→jq(~4ms)。fork 1回分削減。
    local token
    token="$(jq -r '(.accessToken // .claudeAiOauth.accessToken) // empty' "$credentials_file" 2>/dev/null)"
    if [[ -z "$token" || "$token" == "null" ]]; then
        return 1
    fi
    printf '%s\n' "$token"
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

    # WSL2最適化: python3(~34ms)→jq+awk pipeline(~8ms)。
    # jqで6値抽出(両ファイル1回)→awkでテーブル整形。
    jq -rn \
        --slurpfile p "$primary_file" \
        --slurpfile s "$secondary_file" \
        --arg secondary_key "$SEVEN_DAY_SECONDARY_KEY" \
        '($p[0].five_hour.utilization // "null"),
         ($p[0].seven_day.utilization // "null"),
         ($p[0][$secondary_key].utilization // "null"),
         ($s[0].five_hour.utilization // "null"),
         ($s[0].seven_day.utilization // "null"),
         ($s[0][$secondary_key].utilization // "null")' 2>/dev/null \
    | awk '
        { vals[NR] = $0 }
        END {
            labels[1]="5h usage"; labels[2]="7d usage"; labels[3]="7d secondary"
            printf "=== Claude Usage Compare ===\n"
            printf "%-14s | %-8s | %-9s\n", "Bucket", "Primary", "Secondary"
            printf "------------------------------------------\n"
            for (i=1; i<=3; i++) {
                p=vals[i]; s=vals[i+3]
                pfmt=(p=="null")?"N/A":sprintf("%.1f%%",(p+0<=1.0?p*100:p+0))
                sfmt=(s=="null")?"N/A":sprintf("%.1f%%",(s+0<=1.0?s*100:s+0))
                printf "%-14s | %8s | %9s\n", labels[i], pfmt, sfmt
            }
        }'
}

main() {
    require_command curl
    require_command jq

    # WSL2最適化: $(mktemp)×4のsubshell fork(~8ms×4=~32ms)を排除。
    # $$+RANDOMで一意性保証。/tmpはtmpfsなので書き込み高速。
    local _uc_base="/tmp/uc_${$}_${RANDOM}"
    local primary_json="${_uc_base}_pj.json"
    local secondary_json="${_uc_base}_sj.json"
    local primary_err="${_uc_base}_pe"
    local secondary_err="${_uc_base}_se"

    # shellcheck disable=SC2064  # ダブルクォートで即時展開: EXIT時にlocal変数スコープが切れるため
    trap "rm -f '${_uc_base}_pj.json' '${_uc_base}_sj.json' '${_uc_base}_pe' '${_uc_base}_se'" EXIT

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
