#!/usr/bin/env bash
# Stop Hook: Check for lint violations in changed files before agent stops.
# Loop prevention: file-based failure hash comparison (cmd_972 pattern).
# Design: Same failure repeated = agent can't fix → allow stop + escalate to karo.
#         New/different failure = block stop, prompt fix.
set -euo pipefail

_stop_lint_self="${BASH_SOURCE[0]}"
[[ "$_stop_lint_self" != /* ]] && _stop_lint_self="$PWD/$_stop_lint_self"
SHOGUN_ROOT="${_stop_lint_self%/.claude/hooks/stop-lint-gate.sh}"
unset _stop_lint_self

# --- Collect lint-target changed files (staged files only) ---
# cmd_2076: git ls-files -m (unstaged scan) を廃止。staged-only に変更。
# 理由: git ls-files -m は /mnt/c/ 上で全tracked fileのmtime照合のため870ms-1.5s費やす。
#       staged files = コミット直前でlint違反を最重要チェックするタイミング。
#       unstaged違反はpre-commit hookでも検出される。
# 前回(cmd_2053)との差分: shebangではなくgit操作アルゴリズム変更。
collect_changed_files() {
    local cache_key="${SHOGUN_ROOT//[!A-Za-z0-9_]/_}"
    local cache_file="${STOP_LINT_CACHE_FILE:-/tmp/stop_lint_gate_staged_${cache_key}}"
    local index_file="$SHOGUN_ROOT/.git/index"
    local index_sig=""
    local cache_header=""
    local cached_file
    local expected_header=""
    local staged_files

    if [ -f "$index_file" ]; then
        index_sig="$(stat -c '%Y:%s' "$index_file" 2>/dev/null || true)"
        expected_header="${SHOGUN_ROOT}|${index_sig}"
        if [ -n "$index_sig" ] && [ -f "$cache_file" ]; then
            IFS= read -r cache_header < "$cache_file" || true
            if [ "$cache_header" = "$expected_header" ]; then
                {
                    IFS= read -r _ || true
                    while IFS= read -r cached_file; do
                        printf '%s\n' "$cached_file"
                    done
                } < "$cache_file"
                return 0
            fi
        fi
    fi

    staged_files="$(git -C "$SHOGUN_ROOT" diff-index --cached --name-only --diff-filter=ACMRTUXB HEAD -- 2>/dev/null || true)"

    staged_files="$(printf '%s\n' "$staged_files" | awk 'NF && /\.(sh|bash|py|ts|tsx|js|jsx)$/ && !seen[$0]++')"

    if [ -n "$index_sig" ]; then
        {
            printf '%s\n' "$expected_header"
            [ -z "$staged_files" ] || printf '%s\n' "$staged_files"
        } > "${cache_file}.$$" 2>/dev/null && mv "${cache_file}.$$" "$cache_file" 2>/dev/null || rm -f "${cache_file}.$$" 2>/dev/null
    fi

    [ -z "$staged_files" ] || printf '%s\n' "$staged_files"
}

mapfile -t changed_files < <(collect_changed_files)
if [ "${#changed_files[@]}" -eq 0 ]; then
    exit 0
fi

# --- Skip for non-tmux or shogun/karo/gunshi ---
if [ -z "${TMUX_PANE:-}" ]; then
    exit 0
fi
AGENT_ID="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
[ -z "$AGENT_ID" ] && AGENT_ID="${MOCK_AGENT_ID:-}"
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "shogun" ] || [ "$AGENT_ID" = "karo" ] || [ "$AGENT_ID" = "gunshi" ]; then
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
cd "$SHOGUN_ROOT"

# ShellCheck for .sh files (-S warning: info/style除外。既存警告での偽ブロック防止)
if [ "${#sh_files[@]}" -gt 0 ] && command -v shellcheck >/dev/null 2>&1; then
    sc_out=""
    if ! sc_out="$(shellcheck -S warning "${sh_files[@]}" 2>&1)"; then
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
        if ! ruff_out="$("$ruff_cmd" check --quiet --select E,W,F "${py_files[@]}" 2>&1)"; then
            if [ -n "$ruff_out" ]; then
                violations="${violations}--- ruff ---"$'\n'"${ruff_out}"$'\n'
            fi
        fi
    fi
fi

# Biome for .ts/.tsx/.js/.jsx files
if [ "${#ts_js_files[@]}" -gt 0 ] && command -v npx >/dev/null 2>&1; then
    biome_out=""
    if ! biome_out="$(npx --yes biome check "${ts_js_files[@]}" 2>/dev/null)"; then
        :
    fi
    if [ -n "$biome_out" ]; then
        violations="${violations}--- biome ---"$'\n'"${biome_out}"$'\n'
    fi
fi

# --- No violations: clean exit ---
if [ -z "$violations" ]; then
    rm -f "${STOP_LINT_HASH_FILE:-/tmp/stop_hook_${AGENT_ID}_lint_fail_hash}" 2>/dev/null
    exit 0
fi

# --- Violations found: compare with previous failure (loop prevention) ---
fail_hash_file="${STOP_LINT_HASH_FILE:-/tmp/stop_hook_${AGENT_ID}_lint_fail_hash}"
current_hash="$(printf '%s' "$violations" | md5sum | cut -d' ' -f1)"

if [ -f "$fail_hash_file" ]; then
    prev_hash="$(< "$fail_hash_file")"
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
