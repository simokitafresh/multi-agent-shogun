#!/bin/bash
# count_gate_metrics.sh — gate_metrics.logの集計表示（各cmdの最新状態ベース）
# Usage: bash scripts/count_gate_metrics.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/logs/gate_metrics.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "gate metrics log not found: $LOG_FILE"
    exit 0
fi

total_count=0
clear_count=0
block_count=0
reason_rows=()

# 履歴累積ではなく「cmdごとの最新1件」を対象にし、BLOCK理由は複合理由を分解して集計する
while IFS=$'\t' read -r row_type col2 col3 col4; do
    case "$row_type" in
        SUMMARY)
            total_count="$col2"
            clear_count="$col3"
            block_count="$col4"
            ;;
        REASON)
            reason_rows+=("${col2}"$'\t'"${col3}")
            ;;
    esac
done < <(
    awk -F'\t' '
        function trim(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
        }
        NF >= 4 {
            cmd = $2
            last_status[cmd] = $3
            last_reason[cmd] = $4
        }
        END {
            for (cmd in last_status) {
                total++
                if (last_status[cmd] == "CLEAR") {
                    clear++
                    continue
                }
                if (last_status[cmd] != "BLOCK") {
                    continue
                }

                block++
                reason_text = last_reason[cmd]
                if (reason_text == "") {
                    reason_count["(empty)"]++
                    continue
                }

                split(reason_text, parts, /\|/)
                for (i = 1; i <= length(parts); i++) {
                    part = trim(parts[i])
                    if (part != "") {
                        reason_count[part]++
                    }
                }
            }

            printf "SUMMARY\t%d\t%d\t%d\n", total+0, clear+0, block+0
            for (reason in reason_count) {
                printf "REASON\t%d\t%s\n", reason_count[reason], reason
            }
        }
    ' "$LOG_FILE"
)

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

printf '%s\n' "${reason_rows[@]}" \
    | sort -rn \
    | while IFS=$'\t' read -r count reason; do
        echo "  ${reason}: ${count}件"
    done
