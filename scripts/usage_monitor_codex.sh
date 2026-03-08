#!/usr/bin/env bash
# =============================================================================
# usage_monitor_codex.sh — Codex usage monitor for tmux status bar
#
# Extracts usage-like data from Codex TUI output in a target pane.
# Output format (compatible with usage_status.sh parser):
#   D%\tD_reset\tW%\tW_reset
#
# Notes on percentage semantics:
# - For Codex, D/W are "left %" from /status limits (not "used %").
# - usage_status.sh formats Codex output as "% left".
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
    tmux capture-pane -t "$TARGET_PANE" -p -J -S "-${SCAN_LINES}" 2>/dev/null || true
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
ctx_left = None
ctx_re = re.compile(r'(\d+)% left\s*[·|]\s*(\d+)% used')
line_5h_re = re.compile(r'5h limit:\s*(?:\[[^\]]*\]\s*)?(\d+)% left(?:\s*\(resets\s*([^)]+)\))?', re.I)
line_w_re = re.compile(r'weekly limit:\s*(?:\[[^\]]*\]\s*)?(\d+)% left(?:\s*\(resets\s*([^)]+)\))?', re.I)

for line in text:
    line = line.strip()
    m_ctx = ctx_re.search(line)
    if m_ctx:
        try:
            ctx_left = int(m_ctx.group(1))
        except Exception:
            pass

    # New /status block starts here; reset Spark discriminator.
    if "Context window:" in line:
        spark_section = False
        pending = None

    if re.search(r'codex-spark limit:', line, re.I):
        spark_section = True
        pending = None
        continue

    # Main limits: parse only before Spark section.
    if not spark_section:
        m5 = line_5h_re.search(line)
        if m5:
            main_5h_left = int(m5.group(1))
            if m5.group(2):
                main_5h_reset = m5.group(2).strip()
                pending = None
            else:
                pending = "5h"
            continue

        mw = line_w_re.search(line)
        if mw:
            main_w_left = int(mw.group(1))
            if mw.group(2):
                main_w_reset = mw.group(2).strip()
                pending = None
            else:
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

day_left = None
week_left = None

if main_5h_left is not None:
    day_left = max(0, min(100, main_5h_left))
elif ctx_left is not None:
    # Fallback: session context left% as day-like signal.
    day_left = max(0, min(100, ctx_left))
    main_5h_reset = "ctx"

if main_w_left is not None:
    week_left = max(0, min(100, main_w_left))

d_out = "ERR" if day_left is None else str(day_left)
w_out = "ERR" if week_left is None else str(week_left)

print(f"{d_out}\t{main_5h_reset}\t{w_out}\t{main_w_reset}")
PY
}

case "${1:---status}" in
    --status) monitor_status ;;
    --help|-h) show_help ;;
    *) echo "Unknown option: $1" >&2; show_help ;;
esac
