#!/usr/bin/env bash
# post-edit-report-guard.sh — PostToolUse hook
# queue/reports/*_report_*.yaml へのEdit tool直接書込みを検出しWARNING表示。
# report_field_set.sh経由(Bash tool)は対象外。
#
# Mode: WARN (初期)。安定後にBLOCK昇格（PreToolUse deny化）。
# cmd_1265
# GP-095: crash耐性 — PostToolUse hookは非ゼロ終了禁止

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Edit/Write or not a report file
[[ "$payload" != *'"Edit"'* && "$payload" != *'"Write"'* ]] && exit 0
[[ "$payload" != *'queue/reports/'* ]] && exit 0
[[ "$payload" != *'_report_'* ]] && exit 0

# Extract file_path with jq
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // empty' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# Pattern: queue/reports/*_report_*.yaml
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"WARNING: 報告YAMLへの直接Edit/Write検出。\\nWHY: 報告YAMLはreport_field_set.sh経由で更新せよ。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>"}}\n'
fi
exit 0
