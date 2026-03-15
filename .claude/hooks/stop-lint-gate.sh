#!/usr/bin/env bash
# Stop Hook: Check for lint violations in changed files before agent stops.
# Loop prevention: file-based failure hash comparison (cmd_972 pattern).
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

SHOGUN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Collect changed files (staged + unstaged) ---
changed_files="$(cd "$SHOGUN_ROOT" && git diff --name-only --cached 2>/dev/null; cd "$SHOGUN_ROOT" && git diff --name-only 2>/dev/null)"
if [ -z "$changed_files" ]; then
    exit 0
fi

# --- Separate files by type ---
sh_files=""
py_files=""
ts_js_files=""

while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        *.sh|*.bash) sh_files="$sh_files $f" ;;
        *.py)        py_files="$py_files $f" ;;
        *.ts|*.tsx|*.js|*.jsx) ts_js_files="$ts_js_files $f" ;;
    esac
done <<< "$changed_files"

# --- Run lint checks ---
violations=""

# ShellCheck for .sh files
if [ -n "$sh_files" ] && command -v shellcheck >/dev/null 2>&1; then
    for f in $sh_files; do
        full_path="$SHOGUN_ROOT/$f"
        [ -f "$full_path" ] || continue
        sc_out="$(shellcheck "$full_path" 2>&1)" || true
        if [ -n "$sc_out" ]; then
            violations="${violations}--- shellcheck: $f ---\n${sc_out}\n"
        fi
    done
fi

# Ruff for .py files
if [ -n "$py_files" ]; then
    ruff_cmd=""
    if [ -x "$SHOGUN_ROOT/.venv/bin/ruff" ]; then
        ruff_cmd="$SHOGUN_ROOT/.venv/bin/ruff"
    elif [ -x "$SHOGUN_ROOT/.venv/Scripts/ruff.exe" ]; then
        ruff_cmd="$SHOGUN_ROOT/.venv/Scripts/ruff.exe"
    elif command -v ruff >/dev/null 2>&1; then
        ruff_cmd="ruff"
    fi
    if [ -n "$ruff_cmd" ]; then
        for f in $py_files; do
            full_path="$SHOGUN_ROOT/$f"
            [ -f "$full_path" ] || continue
            ruff_out="$("$ruff_cmd" check --select E,W,F "$full_path" 2>/dev/null)" || true
            if [ -n "$ruff_out" ]; then
                violations="${violations}--- ruff: $f ---\n${ruff_out}\n"
            fi
        done
    fi
fi

# Biome for .ts/.tsx/.js/.jsx files
if [ -n "$ts_js_files" ] && command -v npx >/dev/null 2>&1; then
    for f in $ts_js_files; do
        full_path="$SHOGUN_ROOT/$f"
        [ -f "$full_path" ] || continue
        biome_out="$(npx --yes biome check "$full_path" 2>/dev/null)" || true
        if [ -n "$biome_out" ]; then
            violations="${violations}--- biome: $f ---\n${biome_out}\n"
        fi
    done
fi

# --- No violations: clean exit ---
if [ -z "$violations" ]; then
    rm -f "/tmp/stop_hook_${AGENT_ID}_lint_fail_hash" 2>/dev/null
    exit 0
fi

# --- Violations found: compare with previous failure (loop prevention) ---
fail_hash_file="/tmp/stop_hook_${AGENT_ID}_lint_fail_hash"
current_hash="$(printf '%s' "$violations" | md5sum | cut -d' ' -f1)"

if [ -f "$fail_hash_file" ]; then
    prev_hash="$(cat "$fail_hash_file" 2>/dev/null || true)"
    if [ "$current_hash" = "$prev_hash" ]; then
        # Same failure repeated — agent cannot fix this. Allow stop but escalate.
        rm -f "$fail_hash_file" 2>/dev/null
        if [ -x "${SHOGUN_ROOT}/scripts/inbox_write.sh" ]; then
            bash "${SHOGUN_ROOT}/scripts/inbox_write.sh" karo \
                "${AGENT_ID}: Stop Hook lint違反同一繰り返し。修正不能と判断しstop許可。要対応。" \
                error_report "$AGENT_ID" 2>/dev/null || true
        fi
        cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "WARNING: Lint violations still present (same failure repeated). Stop allowed but escalated to karo.\nWHY: Same lint violations occurred twice — agent cannot resolve autonomously.\nACTION: karo has been notified. Lint fix will be handled in a follow-up task."
  }
}
HOOK_JSON
        exit 0
    fi
fi

# --- New or different failure: save hash and block stop ---
printf '%s' "$current_hash" > "$fail_hash_file"

# Prepare violations for JSON (escape special chars)
violations_escaped="$(printf '%b' "$violations" | head -100 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' '|' | sed 's/|/\\n/g')"

cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "ERROR: Lint violations found in changed files. You MUST fix them before completing.\nWHY: F006 — lint違反を無視してstopするな。\nFIX: 1) Read violations below. 2) Fix each violation. 3) Try completing again.\n\n${violations_escaped}"
  }
}
HOOK_JSON
exit 1
