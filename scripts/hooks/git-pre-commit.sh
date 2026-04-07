#!/usr/bin/env bash
# pre-commit hook with failure recording (cmd_1117)
#
# Non-zero exitで logs/hook_failures.yaml に自動記録。
# 記録部分は || true で防御（記録エラーでhookの動作を阻害しない）。

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
_STDERR_FILE="/tmp/_hook_stderr_precommit_$$"

# --- Failure recording trap (cmd_1117) ---
# shellcheck disable=SC2317  # Called indirectly via trap EXIT below
_record_hook_failure() {
    local exit_code=$1
    if [ "$exit_code" -ne 0 ]; then
        (
            ninja_name=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")
            stderr_summary=""
            [ -s "$_STDERR_FILE" ] && stderr_summary=$(head -c 200 "$_STDERR_FILE" 2>/dev/null | tr '\n' ' ' | tr '"' "'")
            mkdir -p "$REPO_ROOT/logs"
            {
                echo "- timestamp: $(date -Iseconds)"
                echo "  hook: pre-commit"
                echo "  ninja: $ninja_name"
                echo "  exit_code: $exit_code"
                echo "  detail: \"$stderr_summary\""
            } >> "$REPO_ROOT/logs/hook_failures.yaml"
        ) || true
    fi
    rm -f "$_STDERR_FILE" 2>/dev/null
}
_ec=0
# shellcheck disable=SC2154  # _ec is assigned in the trap string before use
trap '_ec=$?; _record_hook_failure "$_ec"; exit "$_ec"' EXIT

# Capture stderr for failure recording while still showing on terminal
exec 2> >(tee "$_STDERR_FILE" >&2)

# ============================================
# Pre-commit checks (add checks below this line)
# ============================================

# --- GP-136: yaml.dump in scripts static check ---
# yaml.dump/yaml.safe_dump on operational YAML causes data loss (cmd_1399).
# pre-bash hook catches Bash tool commands but NOT code inside script files.
# This check catches yaml.dump in newly added lines of staged files.
_yaml_dump_violations=""
while IFS= read -r file; do
    # Skip test files, the yaml-dump guard itself, and hook files (which reference yaml.dump by design)
    [[ "$file" == tests/* ]] && continue
    [[ "$file" == *yaml-dump-guard* ]] && continue
    [[ "$file" == scripts/hooks/* ]] && continue
    # Only check .sh and .py files
    [[ "$file" != *.sh && "$file" != *.py ]] && continue
    # Check added lines only (grandfather existing code)
    matches=$(git diff --cached -U0 -- "$file" | grep -n '^+' | grep -v '^+++ ' | grep -v '+[[:space:]]*#' | grep -E 'yaml\.(safe_)?dump' || true)
    if [[ -n "$matches" ]]; then
        _yaml_dump_violations+="  $file: $matches"$'\n'
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)

if [[ -n "$_yaml_dump_violations" ]]; then
    echo "BLOCKED: yaml.dump/yaml.safe_dump detected in staged files (GP-136)" >&2
    echo "Data loss risk on operational YAML. Use yaml_field_set.sh instead." >&2
    echo "$_yaml_dump_violations" >&2
    exit 1
fi

# --- CI: build_instructions.sh sync check (cmd_ci_precommit_build) ---
# Run only when instructions/*.md (excluding generated/) is staged.
_instructions_changed=false
while IFS= read -r _staged_file; do
    if [[ "$_staged_file" == instructions/*.md && "$_staged_file" != instructions/generated/* ]]; then
        _instructions_changed=true
        break
    fi
done < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)

if [[ "$_instructions_changed" == "true" ]]; then
    echo "instructions/*.md staged — checking generated/ sync..."
    if ! bash "$REPO_ROOT/scripts/build_instructions.sh" > /dev/null 2>&1; then
        echo "BLOCKED: build_instructions.sh failed" >&2
        exit 1
    fi
    if ! git diff --exit-code instructions/generated/ > /dev/null 2>&1; then
        echo "BLOCKED: Generated instructions out of sync." >&2
        echo "Run: bash scripts/build_instructions.sh && git add instructions/generated/" >&2
        exit 1
    fi
    echo "  OK: generated instructions in sync."
fi

exit 0
