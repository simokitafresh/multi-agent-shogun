#!/usr/bin/env bash
# pre-edit-workaround-deny.sh — PreToolUse hook
# logs/karo_workarounds.yaml へのEdit/Write tool直接書込みをDENY。
# karo_workaround_log.sh経由(Bash tool)は対象外（Bash toolはマッチしない）。
#
# GP-055: 教訓→gate昇格パイプラインの強制。
# 根拠: karo_workaround_log.shに3件ALERTメカニズムが実装済みだが、
# 家老がEdit toolで直接編集→ALERTが一度も発火しなかった（deepdive 2026-03-24発見）。
# count_category_entries()バグ修正と併せて、script使用を強制する。

set -eu

payload="$(cat 2>/dev/null || true)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0

# Fast-path: skip if not Edit/Write or not workaround file
[[ "$payload" != *'"Edit"'* && "$payload" != *'"Write"'* ]] && exit 0
[[ "$payload" != *'karo_workarounds.yaml'* ]] && exit 0

# Extract file_path with jq
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // empty' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# Pattern: logs/karo_workarounds.yaml
if [[ "$file_path" == *'logs/karo_workarounds.yaml' ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: karo_workarounds.yamlへの直接Edit/Write禁止。\\nWHY: karo_workaround_log.sh経由でのみ記録可。ALERTメカニズム(3件同一カテゴリでntfy通知)が発火するために必須。\\nWA記録: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> <修正内容> <根本原因>"}}\n'
    exit 1
fi

exit 0
