#!/usr/bin/env bash

DAEMON_MAINTENANCE_MARKER="${DAEMON_MAINTENANCE_MARKER:-/tmp/daemon_maintenance.lock}"
DAEMON_MAINTENANCE_TTL_SECONDS="${DAEMON_MAINTENANCE_TTL_SECONDS:-3600}"

daemon_maintenance_read() {
    [[ -f "$DAEMON_MAINTENANCE_MARKER" ]] || return 1
    MAINTENANCE_STARTED_AT="$(sed -n 's/^started_at=//p' "$DAEMON_MAINTENANCE_MARKER" | head -1)"
    MAINTENANCE_OPERATOR="$(sed -n 's/^operator=//p' "$DAEMON_MAINTENANCE_MARKER" | head -1)"
    [[ "$MAINTENANCE_STARTED_AT" =~ ^[0-9]+$ ]] || return 2
}

is_maintenance_active() {
    local now age
    daemon_maintenance_read || return $?
    now="${DAEMON_MAINTENANCE_NOW:-$(date +%s)}"
    [[ "$now" =~ ^[0-9]+$ ]] || return 2
    age=$((now - MAINTENANCE_STARTED_AT))
    if (( age < 0 || age >= DAEMON_MAINTENANCE_TTL_SECONDS )); then
        rm -f -- "$DAEMON_MAINTENANCE_MARKER"
        return 1
    fi
    return 0
}

set_maintenance() {
    local operator="${1:-unknown}" now tmp
    now="${DAEMON_MAINTENANCE_NOW:-$(date +%s)}"
    tmp="${DAEMON_MAINTENANCE_MARKER}.tmp.$$"
    umask 077
    printf 'started_at=%s\noperator=%s\n' "$now" "$operator" > "$tmp"
    mv -f -- "$tmp" "$DAEMON_MAINTENANCE_MARKER"
}

unset_maintenance() { rm -f -- "$DAEMON_MAINTENANCE_MARKER"; }
