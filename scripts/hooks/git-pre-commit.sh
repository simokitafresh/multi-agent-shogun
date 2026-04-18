#!/usr/bin/env bash
# pre-commit hook with failure recording (cmd_1117)
#
# Non-zero exitで logs/hook_failures.yaml に自動記録。
# 記録部分は || true で防御（記録エラーでhookの動作を阻害しない）。

_git_pre_commit_self="${BASH_SOURCE[0]:-$0}"
[[ "$_git_pre_commit_self" != /* ]] && _git_pre_commit_self="$PWD/$_git_pre_commit_self"
REPO_ROOT="${_git_pre_commit_self%/scripts/hooks/git-pre-commit.sh}"
unset _git_pre_commit_self
_STDERR_FILE="/tmp/_hook_stderr_precommit_$$"

list_staged_files() {
    git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
}

is_yaml_dump_scan_target() {
    local file="${1:-}"
    [[ -n "$file" ]] || return 1
    [[ "$file" == tests/* ]] && return 1
    [[ "$file" == *yaml-dump-guard* ]] && return 1
    [[ "$file" == scripts/hooks/* ]] && return 1
    [[ "$file" == *.sh || "$file" == *.py ]]
}

collect_yaml_dump_violations() {
    local current_file="" current_matches="" violations="" line added_line

    flush_current_matches() {
        if [[ -n "$current_matches" ]] && [[ -n "$current_file" ]]; then
            violations+=$(printf '  %s: %s\n' "$current_file" "$(printf '%s' "$current_matches" | paste -sd ' ' -)")
        fi
        current_matches=""
    }

    while IFS= read -r line; do
        case "$line" in
            "+++ b/"*)
                flush_current_matches
                current_file="${line#+++ b/}"
                if ! is_yaml_dump_scan_target "$current_file"; then
                    current_file=""
                fi
                ;;
            "+"*)
                [[ "$line" == "+++"* ]] && continue
                [[ -n "$current_file" ]] || continue
                added_line="${line#+}"
                [[ "$added_line" =~ ^[[:space:]]*# ]] && continue
                if [[ "$added_line" == *"yaml.dump"* || "$added_line" == *"yaml.safe_dump"* ]]; then
                    current_matches+="${line}"$'\n'
                fi
                ;;
        esac
    done < <(git diff --cached --unified=0 --no-color --diff-filter=ACMR 2>/dev/null)

    flush_current_matches
    printf '%s' "$violations"
}

main() {
    local _yaml_dump_violations="" _instructions_changed=false _has_yaml_dump_scan_target=false
    local _staged_file

    while IFS= read -r _staged_file; do
        [[ -n "$_staged_file" ]] || continue
        if is_yaml_dump_scan_target "$_staged_file"; then
            _has_yaml_dump_scan_target=true
        fi
        if [[ "$_staged_file" == instructions/*.md && "$_staged_file" != instructions/generated/* ]]; then
            _instructions_changed=true
        fi
    done < <(list_staged_files)

    if [[ "$_has_yaml_dump_scan_target" == "true" ]]; then
        _yaml_dump_violations="$(collect_yaml_dump_violations)"
    fi

    if [[ -n "$_yaml_dump_violations" ]]; then
        echo "BLOCKED: yaml.dump/yaml.safe_dump detected in staged files (GP-136)" >&2
        echo "Data loss risk on operational YAML. Use yaml_field_set.sh instead." >&2
        echo "$_yaml_dump_violations" >&2
        exit 1
    fi

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
}

# --- Failure recording trap (cmd_1117) ---
# shellcheck disable=SC2317  # Called indirectly via trap EXIT below
_record_hook_failure() {
    local exit_code=$1
    if [ "$exit_code" -ne 0 ]; then
        (
            ninja_name=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")
            stderr_summary=""
            [ -s "$_STDERR_FILE" ] && stderr_summary=$(head -c 200 "$_STDERR_FILE" 2>/dev/null | tr '\n' ' ' | tr '"' "'")
            printf -v _hook_failure_ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
            if [[ "$_hook_failure_ts" =~ ^(.+)([+-][0-9]{2})([0-9]{2})$ ]]; then
                _hook_failure_ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
            fi
            mkdir -p "$REPO_ROOT/logs"
            {
                echo "- timestamp: ${_hook_failure_ts}"
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

main
