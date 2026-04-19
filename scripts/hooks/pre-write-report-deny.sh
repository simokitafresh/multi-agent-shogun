#!/usr/bin/env bash
# @source: cmd_1294 (報告YAML直接Write/Edit拒否hook)
# PreToolUse hook: deny direct Write/Edit to report YAML files.
# Reports must be written via scripts/report_field_set.sh (flock排他制御付き).
# report_field_set.shはBash経由で実行されるためこのhookは発火しない。
# 環境変数REPORT_FIELD_SET_ACTIVE=1でのバイパスも防御的に実装。
set -euo pipefail

emit_deny() {
    local reason="$1"
    # printf builtin avoids jq subprocess for JSON generation
    local escaped="${reason//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$escaped"
}

# Read stdin without forking cat subprocess
IFS='' read -r -d '' payload || true
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

# Extract tool_name using bash regex (avoids jq subprocess)
tool_name=""
if [[ "$payload" =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    tool_name="${BASH_REMATCH[1]}"
fi
if [[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]]; then
    exit 0
fi

# Extract file_path using bash regex (avoids jq subprocess)
file_path=""
if [[ "$payload" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    file_path="${BASH_REMATCH[1]}"
fi
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
