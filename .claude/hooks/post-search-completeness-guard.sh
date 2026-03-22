#!/usr/bin/env bash
# post-search-completeness-guard.sh
# PostToolUse hook for Grep|Glob
# Purpose: 検索結果の網羅性仮定を防止する
# Created: 2026-03-23 (deepdive Phase 10+ 自走)
# Root cause: 1つの検索手法で結果が出た瞬間に「全て見つけた」と確定する早すぎる確定(premature closure)
# Lesson: L-SearchCompletenessGuard

# Only show reminder if results were found (no point warning on empty results)
# The tool_output is passed via stdin or environment — check TOOL_OUTPUT if available
# Simple approach: always show the reminder on search tool use
echo "⚠ この検索結果は網羅的ではない可能性がある。別の手法でも確認したか？（Grep→Glob / Glob→Grep / lord_conversation確認）"
