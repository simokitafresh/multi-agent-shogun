#!/usr/bin/env bash
# Stop Hook: Check for lint violations in changed files before agent stops.
# Loop prevention: file-based failure hash comparison (cmd_972 pattern).
# Design: Same failure repeated = agent can't fix → allow stop + escalate to karo.
#         New/different failure = block stop, prompt fix.
set -euo pipefail

# --- Skip for non-tmux or shogun/karo ---
if [ -z "${TMUX_PANE:-}" ]; then
    exit 0
fi
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "shogun" ] || [ "$AGENT_ID" = "karo" ] || [ "$AGENT_ID" = "gunshi" ]; then
    exit 0
fi

SHOGUN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Collect changed files (staged + unstaged tracked files only) ---
# `git diff --name-only` was the dominant cost on WSL2. Use lighter plumbing commands
# and dedupe the staged/unstaged union before dispatching the linters.
collect_changed_files() {
    local staged_files unstaged_files
    staged_files="$(cd "$SHOGUN_ROOT" && git diff-index --cached --name-only --diff-filter=ACMRTUXB HEAD -- 2>/dev/null || true)"
    unstaged_files="$(cd "$SHOGUN_ROOT" && git ls-files -m 2>/dev/null || true)"

    if [ -z "${staged_files}${unstaged_files}" ]; then
        return 0
    fi

    printf '%s\n%s\n' "$staged_files" "$unstaged_files" | awk 'NF && !seen[$0]++'
}

mapfile -t changed_files < <(collect_changed_files)
if [ "${#changed_files[@]}" -eq 0 ]; then
    exit 0
fi

# --- Separate files by type ---
sh_files=()
py_files=()
ts_js_files=()

for f in "${changed_files[@]}"; do
    [ -f "$SHOGUN_ROOT/$f" ] || continue
    case "$f" in
        *.sh|*.bash) sh_files+=("$f") ;;
        *.py) py_files+=("$f") ;;
        *.ts|*.tsx|*.js|*.jsx) ts_js_files+=("$f") ;;
    esac
done

# --- Run lint checks ---
violations=""

# ShellCheck for .sh files (-S warning: info/style除外。既存警告での偽ブロック防止)
if [ "${#sh_files[@]}" -gt 0 ] && command -v shellcheck >/dev/null 2>&1; then
    sc_out=""
    if ! sc_out="$(cd "$SHOGUN_ROOT" && shellcheck -S warning "${sh_files[@]}" 2>&1)"; then
        :
    fi
    if [ -n "$sc_out" ]; then
        violations="${violations}--- shellcheck ---"$'\n'"${sc_out}"$'\n'
    fi
fi

# Ruff for .py files
if [ "${#py_files[@]}" -gt 0 ]; then
    ruff_cmd=""
    if [ -x "$SHOGUN_ROOT/.venv/bin/ruff" ]; then
        ruff_cmd="$SHOGUN_ROOT/.venv/bin/ruff"
    elif [ -x "$SHOGUN_ROOT/.venv/Scripts/ruff.exe" ]; then
        ruff_cmd="$SHOGUN_ROOT/.venv/Scripts/ruff.exe"
    elif command -v ruff >/dev/null 2>&1; then
        ruff_cmd="ruff"
    fi
    if [ -n "$ruff_cmd" ]; then
        ruff_out=""
        if ! ruff_out="$(cd "$SHOGUN_ROOT" && "$ruff_cmd" check --quiet --select E,W,F "${py_files[@]}" 2>&1)"; then
            if [ -n "$ruff_out" ]; then
                violations="${violations}--- ruff ---"$'\n'"${ruff_out}"$'\n'
            fi
        fi
    fi
fi

# Biome for .ts/.tsx/.js/.jsx files
if [ "${#ts_js_files[@]}" -gt 0 ] && command -v npx >/dev/null 2>&1; then
    biome_out=""
    if ! biome_out="$(cd "$SHOGUN_ROOT" && npx --yes biome check "${ts_js_files[@]}" 2>/dev/null)"; then
        :
    fi
    if [ -n "$biome_out" ]; then
        violations="${violations}--- biome ---"$'\n'"${biome_out}"$'\n'
    fi
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
        # Same failure repeated — agent cannot fix this. Block + escalate to karo.
        # 消火禁止: auto-approveは問題を隠す。blockを維持し家老に対処を委ねる。
        rm -f "$fail_hash_file" 2>/dev/null
        if [ -x "${SHOGUN_ROOT}/scripts/inbox_write.sh" ]; then
            bash "${SHOGUN_ROOT}/scripts/inbox_write.sh" karo \
                "${AGENT_ID}: Stop Hook lint違反同一繰り返し。修正不能。タスク停止+lint修正cmdが必要。" \
                error_report "$AGENT_ID" 2>/dev/null || true
        fi
        violations_escaped2="$(printf '%s' "$violations" | head -50 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' '|' | sed 's/|/\\n/g')"
        cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "BLOCK: Same lint violations repeated. Agent cannot fix autonomously. Escalated to karo for task halt + lint fix cmd.\n\n${violations_escaped2}"
}
HOOK_JSON
        exit 0
    fi
fi

# --- New or different failure: save hash and block stop ---
printf '%s' "$current_hash" > "$fail_hash_file"

# Prepare violations for JSON (escape special chars)
violations_escaped="$(printf '%s' "$violations" | head -100 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' '|' | sed 's/|/\\n/g')"

cat <<HOOK_JSON
{
  "decision": "block",
  "reason": "ERROR: Lint violations found in changed files. You MUST fix them before completing.\nWHY: F006 — lint違反を無視してstopするな。\nFIX: 1) Read violations below. 2) Fix each violation. 3) Try completing again.\n\n${violations_escaped}"
}
HOOK_JSON
exit 0
