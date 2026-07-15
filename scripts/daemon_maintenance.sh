#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/daemon_maintenance_lock.sh"

usage() { echo "Usage: bash scripts/daemon_maintenance.sh {set|unset|status}" >&2; }

case "${1:-}" in
    set)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        operator="${AGENT_ID:-${TMUX_PANE:+$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)}}"
        operator="${operator:-unknown}"
        set_maintenance "$operator"
        echo "maintenance set: operator=$operator ttl=${DAEMON_MAINTENANCE_TTL_SECONDS}s"
        ;;
    unset)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        unset_maintenance
        echo "maintenance unset"
        ;;
    status)
        [[ $# -eq 1 ]] || { usage; exit 2; }
        if is_maintenance_active; then
            echo "maintenance active: operator=$MAINTENANCE_OPERATOR started_at=$MAINTENANCE_STARTED_AT"
            exit 0
        else
            rc=$?
        fi
        if (( rc == 2 )); then
            echo "maintenance invalid: corrupt marker" >&2
            exit 2
        fi
        echo "maintenance inactive"
        exit 1
        ;;
    *) usage; exit 2 ;;
esac
