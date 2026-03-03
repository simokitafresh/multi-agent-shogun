#!/usr/bin/env bash
# =============================================================================
# usage_monitor_codex.sh — Codex usage monitor for tmux status bar
#
# Extracts usage-like data from Codex TUI output in a target pane.
# Output format (compatible with usage_status.sh parser):
#   D%\tD_reset\tW%\tW_reset
#
# Notes:
# - Codex has no public non-interactive usage endpoint in this environment.
# - This script parses latest `/status`-style lines from pane history when present.
# - If 5h/weekly lines are missing, it falls back to context usage for D% and ERR for W%.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_PANE="${TARGET_PANE:-shogun:main}"
SCAN_LINES="${SCAN_LINES:-500}"

show_help() {
    cat <<'HELP'
usage_monitor_codex.sh — Codex usage monitor

Usage:
  ./usage_monitor_codex.sh --status

Output:
  D%\tD_reset\tW%\tW_reset
HELP
    exit 0
}

get_status_from_pane() {
    tmux capture-pane -t "$TARGET_PANE" -p -S "-${SCAN_LINES}" 2>/dev/null || true
}

monitor_status() {
    local pane_text
    pane_text="$(get_status_from_pane)"

    if [[ -z "$pane_text" ]]; then
        printf 'ERR\t--\tERR\t--\n'
        return
    fi

    PANE_TEXT="$pane_text" python3 - <<'PY'
import os
import re
import sys

text = os.environ.get("PANE_TEXT", "").splitlines()

main_5h_left = None
main_5h_reset = "--"
main_w_left = None
main_w_reset = "--"

spark_section = False
pending = None  # "5h" | "w" | None

# Always available in Codex footer when visible:
# "... 26% left · 74% used"
ctx_used = None
ctx_re = re.compile(r'(\d+)% left\s*[·|]\s*(\d+)% used')

for line in text:
    line = line.strip()
    m_ctx = ctx_re.search(line)
    if m_ctx:
        try:
            ctx_used = int(m_ctx.group(2))
        except Exception:
            pass

    # New /status block starts here; reset Spark discriminator.
    if "Context window:" in line:
        spark_section = False
        pending = None

    if "GPT-5.3-Codex-Spark limit:" in line:
        spark_section = True
        pending = None
        continue

    # Main limits: parse only before Spark section.
    if not spark_section and "5h limit:" in line:
        m = re.search(r'(\d+)% left', line)
        if m:
            main_5h_left = int(m.group(1))
            pending = "5h"
        continue

    if not spark_section and "Weekly limit:" in line:
        m = re.search(r'(\d+)% left', line)
        if m:
            main_w_left = int(m.group(1))
            pending = "w"
        continue

    if pending and "resets" in line:
        # Keep short reset text, e.g. "18:58" or "13:58 on 10 Mar"
        m = re.search(r'resets\s+(.+?)(?:\)|$)', line)
        if m:
            reset_val = m.group(1).strip()
            if pending == "5h":
                main_5h_reset = reset_val
            elif pending == "w":
                main_w_reset = reset_val
        pending = None

day_used = None
week_used = None

if main_5h_left is not None:
    day_used = max(0, min(100, 100 - main_5h_left))
elif ctx_used is not None:
    # Fallback: session context usage as day-like signal.
    day_used = max(0, min(100, ctx_used))
    main_5h_reset = "ctx"

if main_w_left is not None:
    week_used = max(0, min(100, 100 - main_w_left))

d_out = "ERR" if day_used is None else str(day_used)
w_out = "ERR" if week_used is None else str(week_used)

print(f"{d_out}\t{main_5h_reset}\t{w_out}\t{main_w_reset}")
PY
}

case "${1:---status}" in
    --status) monitor_status ;;
    --help|-h) show_help ;;
    *) echo "Unknown option: $1" >&2; show_help ;;
esac
