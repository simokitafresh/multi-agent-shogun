#!/usr/bin/env bash
set -euo pipefail

_pane_trace_self="${BASH_SOURCE[0]}"
[[ "$_pane_trace_self" != /* ]] && _pane_trace_self="$PWD/$_pane_trace_self"
SCRIPT_DIR="${_pane_trace_self%/scripts/enable_pane_trace.sh}"
unset _pane_trace_self

pane_target="${1:-shogun:main}"
mode="${2:-on}"

log_dir="$SCRIPT_DIR/logs/pane_trace"
mkdir -p "$log_dir"

safe_target="${pane_target//[:.]/_}"
log_file="$log_dir/${safe_target}.log"
touch "$log_file"

if [[ "$mode" == "off" ]]; then
    tmux pipe-pane -t "$pane_target"
    echo "disabled $pane_target"
    exit 0
fi

logger_cmd="python3 '$SCRIPT_DIR/scripts/tmux_pipe_logger.py' '$pane_target' '$log_file'"
tmux pipe-pane -o -t "$pane_target" "$logger_cmd"
echo "$log_file"
