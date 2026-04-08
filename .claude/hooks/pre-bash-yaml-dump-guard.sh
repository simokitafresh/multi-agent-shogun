#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Bash tool
[[ "$payload" != *'"Bash"'* ]] && exit 0
# Fast-path: skip if no yaml.dump keyword
[[ "$payload" != *'yaml.dump'* && "$payload" != *'yaml.safe_dump'* ]] && exit 0

# Extract command with jq
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -z "$command" ]] && exit 0

# Check all 3 conditions: python invocation + yaml.dump + operational target
invokes_python=false
[[ "$command" == *'python3'* || "$command" == *'python '* || "$command" == *'python	'* || "$command" == *'python -'* ]] && invokes_python=true
[[ "$invokes_python" == "false" ]] && exit 0

has_yaml_dump=false
[[ "$command" == *'yaml.dump'* || "$command" == *'yaml.safe_dump'* ]] && has_yaml_dump=true
[[ "$has_yaml_dump" == "false" ]] && exit 0

targets_operational=false
for pattern in "queue/" "tasks/" "shogun_to_karo" "karo_snapshot" "inbox/" "reports/" "logs/karo_workarounds"; do
    [[ "$command" == *"$pattern"* ]] && { targets_operational=true; break; }
done
[[ "$targets_operational" == "false" ]] && exit 0

# All 3 conditions met → DENY
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: yaml.dump on operational YAML is forbidden (data loss risk). Use: bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>"}}\n'
exit 1
