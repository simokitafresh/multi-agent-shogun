#!/usr/bin/env bash
# =============================================================================
# mcas_common.sh — Shared token extraction (from MCAS common.sh)
#
# Usage: source "${SCRIPT_DIR}/lib/mcas_common.sh"
# =============================================================================

mcas_get_token() {
    local dir="$1"
    local cred_file="${dir}/.credentials.json"

    if [[ ! -f "$cred_file" ]]; then
        echo >&2 "[usage] credentials not found: ${cred_file}"
        return 1
    fi

    if [[ ! -r "$cred_file" ]]; then
        echo >&2 "[usage] credentials not readable: ${cred_file}"
        return 1
    fi

    local token
    # New format first (claudeAiOauth), then legacy fallback
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$cred_file" 2>/dev/null) || true

    if [[ -z "$token" ]]; then
        token=$(jq -r '.accessToken // empty' "$cred_file" 2>/dev/null) || true
    fi

    if [[ -z "$token" ]]; then
        echo >&2 "[usage] accessToken not found in: ${cred_file}"
        return 1
    fi

    echo "$token"
}
