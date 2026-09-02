#!/usr/bin/env bash

# Return success when legacy publication must defer to the single publisher.
# Callers may pass their repository root; otherwise use the caller's existing
# root variable so sourced scripts retain their canonical path resolution.
publisher_single_enabled() {
    local _publisher_root="${1:-${REPO_ROOT:-${ROOT:-${SCRIPT_DIR:-}}}}"
    [[ "${PUBLISHER_SINGLE:-0}" = 1 ]] || {
        [[ -n "$_publisher_root" && -f "$_publisher_root/queue/flags/publisher_single" ]]
    }
}
