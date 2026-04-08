#!/usr/bin/env bash
# should_dream.sh — dream実行条件チェック
# 条件: 前回dreamから24h以上経過
# Exit 0 = ready, Exit 1 = not ready
set -euo pipefail

LAST_DREAM_FILE="$HOME/.claude/skills/dream/.last-dream"
THRESHOLD=$((24 * 60 * 60))  # 24 hours in seconds

if [[ ! -f "$LAST_DREAM_FILE" ]]; then
    echo "DREAM: 初回実行。Ready."
    exit 0
fi

LAST_TS=$(cat "$LAST_DREAM_FILE")
LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
ELAPSED=$(( NOW_EPOCH - LAST_EPOCH ))

if [[ $ELAPSED -ge $THRESHOLD ]]; then
    HOURS=$(( ELAPSED / 3600 ))
    echo "DREAM: 前回から${HOURS}h経過 (>24h)。Ready."
    exit 0
else
    REMAINING_H=$(( (THRESHOLD - ELAPSED) / 3600 ))
    REMAINING_M=$(( ((THRESHOLD - ELAPSED) % 3600) / 60 ))
    echo "DREAM: 次回まで${REMAINING_H}h${REMAINING_M}m。Not ready."
    exit 1
fi
