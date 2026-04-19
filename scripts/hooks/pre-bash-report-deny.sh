#!/usr/bin/env bash
# @source: cmd_1298 (Bash redirect/teeによるreport YAML直接書込み防止hook)
# PreToolUse hook: deny Bash redirect/tee to report YAML files.
# Reports must be written via scripts/report_field_set.sh (flock排他制御付き).
# cmd_1294(Write/Edit DENY)の防御ギャップ補完。
set -euo pipefail

payload="$(cat)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Bash or no report path
[[ "$payload" != *'"Bash"'* ]] && exit 0
[[ "$payload" != *'queue/reports/'* ]] && exit 0

# Extract command with single jq call
command="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -z "$command" ]] && exit 0

# Allow report_field_set.sh (the approved tool for report writing)
[[ "$command" == *'report_field_set.sh'* ]] && exit 0

# Detect redirect (>, >>) or tee targeting report YAML files
redirect_pattern='>+[[:space:]]*[^ ]*queue/reports/[^ ]*\.yaml'
tee_pattern='tee[[:space:]].*queue/reports/[^ ]*\.yaml'
python3_pattern='python3.*open.*queue/reports/.*\.yaml'

emit_deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}

if [[ "$command" =~ $redirect_pattern ]] || [[ "$command" =~ $tee_pattern ]]; then
    emit_deny "報告YAMLへのBashリダイレクト(>/>>/ tee)は禁止。report_field_set.sh経由で書き込みせよ。"
    exit 1
fi

if [[ "$command" =~ $python3_pattern ]]; then
    emit_deny "報告YAMLへのpython3 open()直接書込みは禁止。report_field_set.sh経由で書き込みせよ。"
    exit 1
fi

exit 0
