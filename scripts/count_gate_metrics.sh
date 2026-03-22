#!/bin/bash
# count_gate_metrics.sh — gate_metrics.logの集計表示（各cmdの最新状態ベース）
# Usage: bash scripts/count_gate_metrics.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gate_metrics.log"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

if [ ! -f "$LOG_FILE" ]; then
    echo "gate metrics log not found: $LOG_FILE"
    exit 0
fi

# 履歴累積ではなく「cmdごとの最新1件」を対象にする
awk -F'\t' '
    NF >= 4 {
        cmd = $2
        last_status[cmd] = $3
        last_reason[cmd] = $4
    }
    END {
        for (cmd in last_status) {
            printf "%s\t%s\t%s\n", cmd, last_status[cmd], last_reason[cmd]
        }
    }
' "$LOG_FILE" > "$TMP_FILE"

total_count=$(wc -l < "$TMP_FILE")
clear_count=$(awk -F'\t' '$2=="CLEAR" { c++ } END { print c+0 }' "$TMP_FILE")
block_count=$(awk -F'\t' '$2=="BLOCK" { c++ } END { print c+0 }' "$TMP_FILE")

if [ "$total_count" -gt 0 ]; then
    block_rate=$(awk -v block="$block_count" -v total="$total_count" 'BEGIN { printf "%.2f", (block / total) * 100 }')
else
    block_rate="0.00"
fi

echo "対象(cmd最新状態): ${total_count}件"
echo "CLEAR: ${clear_count}件"
echo "BLOCK: ${block_count}件"
echo "BLOCK率: ${block_rate}%"
echo ""
echo "BLOCK理由内訳:"

if [ "$block_count" -eq 0 ]; then
    echo "  (none)"
    exit 0
fi

awk -F'\t' '$2=="BLOCK" { reason[$3]++ } END { for (r in reason) printf "%d\t%s\n", reason[r], r }' "$TMP_FILE" \
    | sort -rn \
    | while IFS=$'\t' read -r count reason; do
        echo "  ${reason}: ${count}件"
    done
