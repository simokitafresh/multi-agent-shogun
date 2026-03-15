#!/usr/bin/env bash
# Stop Hook: Run bats tests before ninja stops.
# Loop prevention: file-based failure hash comparison.
# Design: Same failure repeated = agent can't fix → allow stop + escalate to karo.
#         New/different failure = block stop, prompt fix.
set -eu

# --- Skip for non-tmux or shogun/karo ---
if [ -z "${TMUX_PANE:-}" ]; then
    exit 0
fi
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "shogun" ] || [ "$AGENT_ID" = "karo" ]; then
    exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
    # Tests passed — clean up any previous failure marker and allow stop
    rm -f "/tmp/stop_hook_${AGENT_ID}_fail_hash" 2>/dev/null
    exit 0
fi

# --- Tests failed: compare with previous failure ---
fail_hash_file="/tmp/stop_hook_${AGENT_ID}_fail_hash"
current_hash="$(printf '%s' "$output" | md5sum | cut -d' ' -f1)"

if [ -f "$fail_hash_file" ]; then
    prev_hash="$(cat "$fail_hash_file" 2>/dev/null || true)"
    if [ "$current_hash" = "$prev_hash" ]; then
        # Same failure repeated — agent cannot fix this.
        # Allow stop but escalate to karo.
        rm -f "$fail_hash_file" 2>/dev/null
        if [ -x "${PROJECT_ROOT}/scripts/inbox_write.sh" ]; then
            bash "${PROJECT_ROOT}/scripts/inbox_write.sh" karo \
                "${AGENT_ID}: Stop Hook batsテスト同一失敗繰り返し。修正不能と判断しstop許可。要対応。" \
                error_report "$AGENT_ID" 2>/dev/null || true
        fi
        # Emit warning but allow stop (exit 0)
        cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "WARNING: bats tests still failing (same failure repeated). Stop allowed but escalated to karo.\nWHY: Same test failure occurred twice — agent cannot resolve this autonomously.\nACTION: karo has been notified. Test fix will be handled in a follow-up task."
  }
}
HOOK_JSON
        exit 0
    fi
fi

# --- New or different failure: save hash and block stop ---
printf '%s' "$current_hash" > "$fail_hash_file"

cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "ERROR: bats tests failed (exit code ${exit_code}). You MUST fix failing tests before completing.\nWHY: SKIP=FAIL rule (CLAUDE.md). All tests must pass.\nFIX: 1) Read the test output below. 2) Fix the failing test or source script. 3) Try completing again.\n\n--- bats output ---\n${output}\n--- end ---"
  }
}
HOOK_JSON
exit 1
