#!/usr/bin/env bash
# Render role-specific session_alerts files while preserving resolved alerts.

render_session_alerts_file() {
    local _sar_alerts_file="$1"
    local _sar_header="$2"
    local _sar_run_id="$3"
    shift 3

    local _sar_tmp
    _sar_tmp="$(mktemp "${_sar_alerts_file}.tmp.XXXXXX")" || return 1

    {
        printf '# %s — generated: %s\n' "$_sar_header" "$_sar_run_id"
        local _sar_alert _sar_status
        for _sar_alert in "$@"; do
            _sar_status="TODO"
            if [ -f "$_sar_alerts_file" ] && grep -Fxq "[DONE] ${_sar_alert}" "$_sar_alerts_file" 2>/dev/null; then
                _sar_status="DONE"
            fi
            printf '[%s] %s\n' "$_sar_status" "$_sar_alert"
        done
    } > "$_sar_tmp"

    mv "$_sar_tmp" "$_sar_alerts_file"
}
