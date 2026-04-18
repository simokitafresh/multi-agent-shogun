#!/usr/bin/env bash
# Combined Write/Edit PreToolUse guard: config-guard + read-tracker + report-deny + workaround-deny
# cmd_1661: 4 hooks → 1 script. Eliminates 3 bash startup costs (~60ms each).
set -eu

payload="$(</dev/stdin)"
case "$payload" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac

# Fast-path: only process Write/Edit
case "$payload" in
    *'"Write"'*|*'"Edit"'*) ;;
    *) exit 0 ;;
esac

emit_deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}

# Single jq call to extract tool_name and file_path
_parsed="$(printf '%s' "$payload" | jq -r '[(.tool_name // .toolName // ""), ((.tool_input // .toolInput // {}) | .file_path // .filePath // .path // "")] | @tsv' 2>/dev/null)" || exit 0
tool_name="${_parsed%%	*}"
file_path="${_parsed#*	}"

[[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]] && exit 0
[[ -z "$file_path" ]] && exit 0

# === Guard 1: config-guard (protected config files) ===
case "${file_path##*/}" in
    pyproject.toml|.eslintrc|.eslintrc.*|eslint.config*|biome.json|.prettierrc|.prettierrc.*|tsconfig.json|.ruff.toml|setup.cfg)
        emit_deny "ERROR: ${file_path##*/} is a protected config file.\\nWHY: Linter/formatter configs must not be modified to suppress violations.\\nFIX: Fix the code that triggered the violation, not the linter config."
        exit 1
        ;;
esac

# === Guard 2: read-tracker (Write/Edit must be preceded by Read) ===
# queue/tasks/*.yaml → unconditional deny
case "$file_path" in
    */queue/tasks/*.yaml)
        emit_deny "queue/tasks/*.yamlはWrite/Editで直接書くな。状態更新→bash scripts/lib/yaml_field_set.sh queue/tasks/{name}.yaml task {field} {value}。新規配備→deploy_task.sh。"
        exit 1
        ;;
    */queue/reports/*.yaml)
        emit_deny "queue/reports/*.yamlはWrite/Editで直接書くな。report_field_set.shを使え。"
        exit 1
        ;;
esac

# Check read log for existing files
if [ -f "$file_path" ]; then
    agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo 'unknown')"
    [[ -z "$agent_id" ]] && agent_id="unknown"
    LOG_FILE="/tmp/claude_read_log_${agent_id}.txt"
    if ! { [ -f "$LOG_FILE" ] && grep -qFx "$file_path" "$LOG_FILE" 2>/dev/null; }; then
        emit_deny "このファイルはまだReadされていません。先にReadツールで読んでからWrite/Editしてください。"
        exit 1
    fi
fi

# === Guard 3: report-deny (Edit/Write to report YAML) ===
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    emit_deny "BLOCKED: 報告YAMLへの直接Edit/Write禁止。\\n対象: $file_path\\nWHY: report_field_set.sh経由でのみ更新可。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh $file_path <dot.notation.key> <value>\\n例: bash scripts/report_field_set.sh $file_path result.summary 検証完了\\n例: bash scripts/report_field_set.sh $file_path binary_checks.AC1 [check: 確認内容, result: yes]\\n例: bash scripts/report_field_set.sh $file_path verdict PASS"
    exit 1
fi

# === Guard 4: workaround-deny (Edit/Write to karo_workarounds.yaml) ===
if [[ "$file_path" == *'logs/karo_workarounds.yaml' ]]; then
    emit_deny "BLOCKED: karo_workarounds.yamlへの直接Edit/Write禁止。\\nWHY: karo_workaround_log.sh経由でのみ記録可。ALERTメカニズム(3件同一カテゴリでntfy通知)が発火するために必須。\\nWA記録: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> <修正内容> <根本原因>"
    exit 1
fi

# === Guard 5: lessons.yaml tags直接Edit禁止 (LK052: 同期不整合防止) ===
if [[ "$tool_name" == "Edit" && "$file_path" == *'/lessons.yaml' ]]; then
    old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // ""' 2>/dev/null)" || true
    if [[ "$old_string" == *'tags:'* ]]; then
        emit_deny "BLOCKED: lessons.yamlのtags直接Edit禁止。\\nWHY: lessons.md←→lessons.yaml同期不整合が発生する(LK052実証済み)。\\nFIX: bash scripts/lesson_write.sh <project_id> --retag <lesson_id> --new-tags \\\"tag1,tag2\\\""
        exit 1
    fi
fi

exit 0
