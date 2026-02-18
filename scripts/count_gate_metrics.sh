#!/bin/bash
# count_gate_metrics.sh — gate_metrics.logの集計表示
# Usage: bash scripts/count_gate_metrics.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gate_metrics.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "gate metrics log not found: $LOG_FILE"
    exit 0
fi

total_count=$(wc -l < "$LOG_FILE")
clear_count=$(awk -F'\t' '$3=="CLEAR" { c++ } END { print c+0 }' "$LOG_FILE")
block_count=$(awk -F'\t' '$3=="BLOCK" { c++ } END { print c+0 }' "$LOG_FILE")

if [ "$total_count" -gt 0 ]; then
    block_rate=$(awk -v block="$block_count" -v total="$total_count" 'BEGIN { printf "%.2f", (block / total) * 100 }')
else
    block_rate="0.00"
fi

echo "合計: ${total_count}件"
echo "CLEAR: ${clear_count}件"
echo "BLOCK: ${block_count}件"
echo "BLOCK率: ${block_rate}%"
echo ""
echo "BLOCK理由内訳:"

if [ "$block_count" -eq 0 ]; then
    echo "  (none)"
    exit 0
fi

awk -F'\t' '$3=="BLOCK" { reason[$4]++ } END { for (r in reason) printf "%d\t%s\n", reason[r], r }' "$LOG_FILE" \
    | sort -rn \
    | while IFS=$'\t' read -r count reason; do
        echo "  ${reason}: ${count}件"
    done
