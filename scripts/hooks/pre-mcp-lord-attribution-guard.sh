#!/usr/bin/env bash
# PreToolUse hook: MCP add_observations時の殿帰属キーワード照合ガード
#
# 根本原因: cmd_1871事故。将軍が研究出力(WFエンジン6目的)を「殿定義6バージョン体系」として
#           MCPに記録→後続cmdが42体universeで設計→OOM Kill。
#           一次情報源(projects/dm-signal.yaml modes定義=3目的)との照合をしなかった。
#
# 対策: mcp__memory__add_observations実行時、observation内容に殿帰属キーワード
#       (殿定義/殿裁定/殿指示/殿厳命/殿確認)を含む場合、
#       一次情報源の引用(file:行番号 or timestamp等)がなければBLOCKする。
#
# 判定ロジック:
#   - 殿帰属キーワードなし → PASS
#   - 殿帰属キーワードあり + 引用パターンあり → PASS
#   - 殿帰属キーワードあり + 引用パターンなし → BLOCK
set -euo pipefail

# --- 引用パターン(一次情報源の証拠) ---
# 出典:/source:/file:/L[数字]/timestamp: のいずれかがあればOK
CITATION_PATTERN='出典:|source:|file:|L[0-9][0-9]*[^0-9]|timestamp:|[0-9]{4}-[0-9]{2}-[0-9]{2}'

# --- 殿帰属キーワード ---
LORD_ATTR_PATTERN='殿定義|殿裁定|殿指示|殿厳命|殿確認'

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

# --- Read hook payload ---
payload="$(cat)"
if [ -z "${payload//[[:space:]]/}" ]; then
    exit 0
fi

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$tool_name" != "mcp__memory__add_observations" ]]; then
    exit 0
fi

# --- Extract observations contents ---
# observations は [{entityName: "...", contents: ["...", "..."]}] の配列
observations_json="$(printf '%s' "$payload" | jq -r '.tool_input.observations // empty' 2>/dev/null || true)"
if [ -z "$observations_json" ] || [ "$observations_json" = "null" ]; then
    exit 0
fi

# 全observationのcontentsを結合して1テキストにする
all_contents="$(printf '%s' "$observations_json" | jq -r '.[].contents[]?' 2>/dev/null || true)"
if [ -z "$all_contents" ]; then
    exit 0
fi

# --- 殿帰属キーワードチェック ---
if ! printf '%s' "$all_contents" | grep -qP "$LORD_ATTR_PATTERN" 2>/dev/null; then
    # 殿帰属キーワードなし → PASS
    exit 0
fi

# --- 引用パターンチェック ---
if printf '%s' "$all_contents" | grep -qP "$CITATION_PATTERN" 2>/dev/null; then
    # 引用あり → PASS
    exit 0
fi

# --- BLOCK: 殿帰属キーワードあり + 引用なし ---
emit_deny "BLOCK: 殿帰属の一次情報源を引用せよ（file:行番号 or timestamp）。[pre-mcp-lord-attribution-guard] 殿帰属キーワード(殿定義/殿裁定/殿指示/殿厳命/殿確認)検出。引用パターン(出典:/source:/file:/L数字/timestamp:)が見当たらない。"
exit 2
