#!/usr/bin/env bash
# PreToolUse hook: deny direct Write/Edit to report YAML files.
# Reports must be written via scripts/report_field_set.sh (flock排他制御付き).
# report_field_set.shはBash経由で実行されるためこのhookは発火しない。
# 環境変数REPORT_FIELD_SET_ACTIVE=1でのバイパスも防御的に実装。
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
if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]]; then
    exit 0
fi

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "$file_path" ]; then
    exit 0
fi

# Check if file matches report YAML pattern: queue/reports/*_report*.yaml
if [[ "$file_path" =~ queue/reports/.*_report.*\.yaml$ ]]; then
    # Allow if called via report_field_set.sh (defensive bypass)
    if [ "${REPORT_FIELD_SET_ACTIVE:-}" = "1" ]; then
        exit 0
    fi
    emit_deny "報告YAMLへの直接Write/Editは禁止。report_field_set.sh経由で書き込みせよ。Usage: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>"
fi

exit 0
