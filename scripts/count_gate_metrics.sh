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

# 履歴累積ではなく「cmdごとの最新1件」を対象にし、BLOCK理由は複合理由を分解して集計する
# awk単一パスで集計・比率計算・ソート済み表示を完結させる
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
                if (part != "") reason_count[part]++
            }
        }

        block_rate = (total > 0) ? sprintf("%.2f", (block / total) * 100) : "0.00"

        printf "対象(cmd最新状態): %d件\n", total+0
        printf "CLEAR: %d件\n", clear+0
        printf "BLOCK: %d件\n", block+0
        printf "BLOCK率: %s%%\n\n", block_rate
        print "BLOCK理由内訳:"

        if (block+0 == 0) {
            print "  (none)"
        } else {
            n = 0
            for (reason in reason_count) {
                counts[n] = reason_count[reason]
                reasons[n] = reason
                n++
            }
            for (i = 0; i < n-1; i++) {
                for (j = i+1; j < n; j++) {
                    if (counts[j] > counts[i]) {
                        tmp_c = counts[i]; counts[i] = counts[j]; counts[j] = tmp_c
                        tmp_r = reasons[i]; reasons[i] = reasons[j]; reasons[j] = tmp_r
                    }
                }
            }
            for (i = 0; i < n; i++) {
                printf "  %s: %d件\n", reasons[i], counts[i]
            }
        }
    }
' "$LOG_FILE"
