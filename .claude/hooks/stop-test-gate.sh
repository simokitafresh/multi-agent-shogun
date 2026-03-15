#!/usr/bin/env bash
# Stop Hook: Run bats tests before ninja stops. If tests fail, inject context to prompt fix.
# - Only runs for ninjas (not shogun/karo)
# - Counter-based loop guard: after MAX_FAILURES consecutive failures, skip to prevent infinite loop
set -eu

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAX_FAILURES=2

# --- Skip for non-tmux or shogun/karo ---
if [ -z "${TMUX_PANE:-}" ]; then
    exit 0
fi
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "shogun" ] || [ "$AGENT_ID" = "karo" ]; then
    exit 0
fi

# --- Counter-based loop prevention ---
COUNTER_FILE="/tmp/stop_hook_failures_${AGENT_ID}"
fail_count=0
if [ -f "$COUNTER_FILE" ]; then
    fail_count=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    # Expire counter after 300s (stale from previous task)
    counter_age=$(( $(date +%s) - $(stat -c %Y "$COUNTER_FILE" 2>/dev/null || echo 0) ))
    if [ "$counter_age" -gt 300 ]; then
        fail_count=0
        rm -f "$COUNTER_FILE"
    fi
fi
if [ "$fail_count" -ge "$MAX_FAILURES" ]; then
    rm -f "$COUNTER_FILE"
    exit 0
fi

# --- Skip if no bats test files ---
test_dir="${PROJECT_ROOT}/tests/unit"
if [ ! -d "$test_dir" ]; then
    exit 0
fi

bats_files=()
while IFS= read -r -d '' f; do
    bats_files+=("$f")
done < <(find "$test_dir" -name '*.bats' -print0 2>/dev/null)

if [ ${#bats_files[@]} -eq 0 ]; then
    exit 0
fi

# --- Find bats ---
if ! command -v bats >/dev/null 2>&1; then
    exit 0
fi

# --- Run bats ---
output=""
exit_code=0
output=$(bats "${bats_files[@]}" 2>&1) || exit_code=$?

if [ "$exit_code" -eq 0 ]; then
    rm -f "$COUNTER_FILE"
    exit 0
fi

# --- Increment failure counter ---
echo $(( fail_count + 1 )) > "$COUNTER_FILE"

# --- Emit additionalContext on failure ---
remaining=$(( MAX_FAILURES - fail_count - 1 ))
cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "ERROR: bats tests failed (exit code ${exit_code}). You MUST fix failing tests before completing.\nWHY: SKIP=FAIL rule (CLAUDE.md). All tests must pass.\nFIX: 1) Read the test output below. 2) Fix the failing test or source script. 3) Re-run bats to confirm. 4) Try completing again.\nRetries remaining: ${remaining}\n\n--- bats output ---\n${output}\n--- end ---"
  }
}
HOOK_JSON
exit 1
