#!/usr/bin/env bash
# PreToolUse hook: deny Bash redirect/tee to report YAML files.
# Reports must be written via scripts/report_field_set.sh (flock排他制御付き).
# cmd_1294(Write/Edit DENY)の防御ギャップ補完。
set -euo pipefail

emit_deny() {
    local reason="$1"
    jq -cn --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
}

payload="$(cat)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$tool_name" != "Bash" ]]; then
    exit 0
fi

command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
if [ -z "$command" ]; then
    exit 0
fi

# Allow report_field_set.sh (the approved tool for report writing)
if [[ "$command" =~ report_field_set\.sh ]]; then
    exit 0
fi

# Detect redirect (>, >>) or tee targeting report YAML files
redirect_pattern='>+[[:space:]]*[^ ]*queue/reports/[^ ]*\.yaml'
tee_pattern='tee[[:space:]].*queue/reports/[^ ]*\.yaml'

# Detect python3 open() targeting report YAML files (GP-039)
python3_pattern='python3.*open.*queue/reports/.*\.yaml'

if [[ "$command" =~ $redirect_pattern ]] || [[ "$command" =~ $tee_pattern ]]; then
    emit_deny "報告YAMLへのBashリダイレクト(>/>>/ tee)は禁止。report_field_set.sh経由で書き込みせよ。Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>"
fi

if [[ "$command" =~ $python3_pattern ]]; then
    emit_deny "報告YAMLへのpython3 open()直接書込みは禁止。report_field_set.sh経由で書き込みせよ。Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>"
fi

exit 0
