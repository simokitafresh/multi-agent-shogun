#!/usr/bin/env bash
set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Bash tool
[[ "$payload" != *'"Bash"'* ]] && exit 0
# Fast-path (cheap substring pre-filter, not the final detector): skip only if
# neither "yaml" nor "dump" appear at all. cmd_karo_hotfix_lesson_impact_yaml_dump:
# aliased imports (`import yaml as yaml_module` -> `yaml_module.dump(...)`,
# `import yaml as _yaml_nm` -> `_yaml_nm.dump(...)`) do not contain the literal
# substring "yaml.dump", so a literal-substring fast-path silently let two real
# call sites through (scripts/lesson_impact_analysis.sh, scripts/semantic_index_update.sh).
[[ "$payload" != *'dump'* ]] && exit 0
[[ "$payload" != *'yaml'* && "$payload" != *'Yaml'* && "$payload" != *'YAML'* ]] && exit 0

# Extract command with jq
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -z "$command" ]] && exit 0

# Check all 3 conditions: python invocation + yaml(.alias)?.(safe_)?dump( + operational target
invokes_python=false
[[ "$command" == *'python3'* || "$command" == *'python '* || "$command" == *'python	'* || "$command" == *'python -'* ]] && invokes_python=true
[[ "$invokes_python" == "false" ]] && exit 0

# cmd_karo_hotfix_lesson_impact_yaml_dump: family regex (家老/軍師実測パターン)
# matches yaml.dump(/yaml.safe_dump( plus common alias forms (yaml_module.dump(,
# _yaml_nm.dump(). Deliberately anchored on the "yaml" token in the identifier
# so json.dump(/pickle.dump( etc. are not caught (no behavior-class change, only
# vocabulary widening for the same yaml.dump family this guard already targets).
has_yaml_dump=false
[[ "$command" =~ (yaml[a-zA-Z_]*|[a-zA-Z_]*yaml[a-zA-Z_]*)\.(safe_)?dump\( ]] && has_yaml_dump=true
[[ "$has_yaml_dump" == "false" ]] && exit 0

targets_operational=false
for pattern in "queue/" "tasks/" "shogun_to_karo" "karo_snapshot" "inbox/" "reports/" "logs/karo_workarounds"; do
    [[ "$command" == *"$pattern"* ]] && { targets_operational=true; break; }
done
[[ "$targets_operational" == "false" ]] && exit 0

# All 3 conditions met → DENY
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: yaml.dump on operational YAML is forbidden (data loss risk). Use: bash scripts/lib/yaml_field_set.sh <file> <block_id> <field> <value>"}}\n'
exit 1
