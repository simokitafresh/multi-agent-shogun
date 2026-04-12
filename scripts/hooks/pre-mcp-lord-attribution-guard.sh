#!/usr/bin/env bash
# PreToolUse hook: MCP add_observations時の殿帰属キーワード照合ガード + 設計情報仕分けガード
#
# 根本原因: cmd_1871事故。将軍が研究出力(WFエンジン6目的)を「殿定義6バージョン体系」として
#           MCPに記録→後続cmdが42体universeで設計→OOM Kill。
#           一次情報源(projects/dm-signal.yaml modes定義=3目的)との照合をしなかった。
#
# 対策1 (cmd_1874): 殿帰属キーワード検出 → 引用なしでBLOCK
# 対策2 (cmd_1875): 設計情報パターン検出 → WARN「projects/*.yamlに書くべきか確認せよ」
#
# 設計情報 = 数値・定義・パラメータ・体数・目的関数・スキーマ・UUID等の具体値
#           → projects/*.yaml（受動的知識/全員が読める）に書くべき。
#             MCPに入れると将軍にしか見えず、家老・軍師・忍者が検証できない。
# 好み/哲学 = 原則・方針・思想・哲学・判断基準 → MCPが適切
#
# 判定ロジック(Check1: 殿帰属):
#   - 殿帰属キーワードなし → PASS
#   - 殿帰属キーワードあり + 引用パターンあり → PASS
#   - 殿帰属キーワードあり + 引用パターンなし → BLOCK
#
# 判定ロジック(Check2: 設計情報 — WARNのみ、BLOCKなし):
#   - 設計情報パターンなし → PASS
#   - 設計情報パターンあり → WARN(exit 0。参照値は哲学寄りの場合もあるためBLOCKしない)
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

# --- Check2: 設計情報パターン（WARN only、BLOCKなし） ---
# 数値+単位: [0-9]+体, [0-9]+目的, N=[0-9]
# 定義キーワード: 目的関数, パラメータ, スキーマ, UUID, pipeline_config
# 構造定義: ×[0-9], =[0-9], モード=
DESIGN_PATTERN='[0-9]+体|[0-9]+目的|N=[0-9]|目的関数|パラメータ|スキーマ|UUID|pipeline_config|×[0-9]|=[0-9]|モード='
if printf '%s' "$all_contents" | grep -qP "$DESIGN_PATTERN" 2>/dev/null; then
    echo "WARN [pre-mcp-lord-attribution-guard]: 設計情報パターン検出。projects/*.yamlに書くべきか確認せよ。" \
         "（数値/定義キーワードあり: 体数/目的数/パラメータ等）MCPに設計情報を入れると将軍以外が検証不可。" >&2
fi
# Check2はWARNのみ。処理継続。

# --- Check1: 殿帰属キーワードチェック ---
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
