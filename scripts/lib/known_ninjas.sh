#!/usr/bin/env bash
# Shared canonical ninja names for WA logging and data-quality gates.

KNOWN_NINJAS=(hayate kagemaru hanzo saizo kotaro tobisaru unknown)
KNOWN_NINJAS_CSV="$(IFS=,; echo "${KNOWN_NINJAS[*]}")"

is_known_ninja() {
    local candidate="${1:-}"
    local known
    for known in "${KNOWN_NINJAS[@]}"; do
        [[ "$candidate" == "$known" ]] && return 0
    done
    return 1
}

known_ninjas_display() {
    local IFS=/
    echo "${KNOWN_NINJAS[*]}"
}
