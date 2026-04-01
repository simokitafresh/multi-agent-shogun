#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Bash tool or no --no-verify/-n keyword
[[ "$payload" != *'"Bash"'* ]] && exit 0
[[ "$payload" != *'--no-verify'* && "$payload" != *'"-n"'* ]] && exit 0

# Extract command with jq for accurate check
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -z "$command" ]] && exit 0

# Check: git commit --no-verify or -n
if [[ "$command" =~ git[[:space:]]+commit[[:space:]] ]]; then
    if [[ "$command" == *'--no-verify'* || "$command" =~ [[:space:]]-n([[:space:]]|$) ]]; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: git commit --no-verify is forbidden. Fix hooks, do not bypass them."}}\n'
        exit 1
    fi
fi

exit 0
