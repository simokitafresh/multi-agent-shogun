#!/usr/bin/env bash
# gate_clear_terminal_notify.sh — durable-worker entry point for the terminal
# shogun/karo GATE CLEAR notifications (send_clear_notifications_once).
# Usage: bash scripts/gate_clear_terminal_notify.sh <cmd_id> <phase> <log_dir> <archive_auto_handled>
#
# cmd_karo_hotfix_t3s40_post_source_v6: cmd_complete_gate.sh's terminal
# call site launches this via `nohup setsid` so the notification survives
# termination of the launching process group (tmux respawn-pane -k etc.) —
# the same reason semantic_causal_post_clear.sh is launched this way
# elsewhere in cmd_complete_gate.sh. send_clear_notifications_once itself
# stays defined once in scripts/lib/gate_clear_notify.sh (sourced here and
# by cmd_complete_gate.sh) so the 3 synchronous emergency-override call
# sites still in cmd_complete_gate.sh and this durable path never drift.

set -uo pipefail

CMD_ID="${1:?Usage: gate_clear_terminal_notify.sh <cmd_id> <phase> <log_dir> <archive_auto_handled>}"
PHASE="${2:-GATE CLEAR}"
LOG_DIR="${3:?Usage: gate_clear_terminal_notify.sh <cmd_id> <phase> <log_dir> <archive_auto_handled>}"
ARCHIVE_AUTO_HANDLED="${4:-0}"

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# shellcheck source=scripts/lib/gate_clear_notify.sh
source "$SCRIPT_DIR/scripts/lib/gate_clear_notify.sh"

send_clear_notifications_once "$CMD_ID" "$PHASE"
