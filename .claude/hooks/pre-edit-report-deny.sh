#!/usr/bin/env bash
# pre-edit-report-deny.sh — PreToolUse hook
# queue/reports/*_report_*.yaml へのEdit/Write tool直接書込みをDENY。
# report_field_set.sh経由(Bash tool)は対象外（Bash toolはマッチしない）。
#
# GP-047: PostToolUse WARN(GP-032/041/043-046)→PreToolUse DENY昇格。
# 根拠: PostToolUse WARNINGを忍者が無視 → WA率低下が頭打ち。
# deepdive Phase 4: 「WARNINGは強制ではない。自動化×強制が唯一の解」
#
# 昇格元: post-edit-report-guard.sh (cmd_1265, Mode: WARN)
# 本hookはDENY(BLOCK)モード。PostToolUseのWARN hookは併存（検出ログ用）。

set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Edit/Write or not a report file
[[ "$payload" != *'"Edit"'* && "$payload" != *'"Write"'* ]] && exit 0
[[ "$payload" != *'queue/reports/'* ]] && exit 0
[[ "$payload" != *'_report_'* ]] && exit 0

# Extract file_path with jq for accurate check
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // empty' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# Pattern: queue/reports/*_report_*.yaml
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: 報告YAMLへの直接Edit/Write禁止。\\n対象: %s\\nWHY: report_field_set.sh経由でのみ更新可。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh %s <dot.notation.key> <value>\\n例: bash scripts/report_field_set.sh %s result.summary 検証完了\\n例: bash scripts/report_field_set.sh %s binary_checks.AC1 [check: 確認内容, result: yes]\\n例: bash scripts/report_field_set.sh %s verdict PASS"}}\n' "$file_path" "$file_path" "$file_path" "$file_path" "$file_path"
    exit 1
fi

exit 0
