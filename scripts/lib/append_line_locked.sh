#!/usr/bin/env bash
# append_line_locked.sh — flock-protected single-line append, plus a small
# helper that mirrors a stderr capture file into the shared gate stderr log.
#
# cmd_karo_hotfix_t3s40_post_source_v6: extracted (moved, not duplicated) out
# of scripts/cmd_complete_gate.sh so a standalone durable-worker script
# (scripts/gate_clear_terminal_notify.sh) can source the exact same
# definition instead of re-implementing it. cmd_complete_gate.sh now sources
# this file at its original definition site; behavior is unchanged.

# Depends on lock_path() (scripts/lib/lock_path.sh). Source defensively so
# this file works whether or not the caller already sourced it.
if ! declare -F lock_path >/dev/null 2>&1; then
    _ALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck source=scripts/lib/lock_path.sh
    source "$_ALL_SCRIPT_DIR/lib/lock_path.sh"
    unset _ALL_SCRIPT_DIR
fi

append_line_locked() {
    local target_file="$1"
    local line="$2"
    local target_dir
    target_dir="$(dirname "$target_file")"
    mkdir -p "$target_dir" 2>/dev/null || true

    (
        flock -w 10 200 || exit 1
        printf '%s\n' "$line" >> "$target_file"
    ) 200>"$(lock_path "$target_file")"
}

log_gate_stderr_file() {
    local label="$1"
    local stderr_file="$2"
    local line

    [ -s "$stderr_file" ] || return 0
    while IFS= read -r line; do
        append_line_locked "$LOG_DIR/cmd_complete_gate_stderr.log" "$(date '+%Y-%m-%dT%H:%M:%S') [${CMD_ID}] ${label}: ${line}"
    done < "$stderr_file"
}
