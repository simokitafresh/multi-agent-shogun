#!/bin/bash
# gate_gunshi_observations.sh — draft/reportレビューのobservations必須チェック
# @source: selfdriven_20260329_2230 (SG2-5深さ測定→observations0.8%→必須化)
# 知性の外部化: レビュー深さを意志に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_gunshi_observations.sh
# Exit: 0=PASS, 1=WARN(欠落あり)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/gunshi_review_log.yaml"

if [ ! -f "$LOG_FILE" ]; then
    echo "ALERT: gunshi_review_log.yaml not found — レビューログ不在は異常"
    exit 1
fi

MISSING=$(awk '
BEGIN { total = 0; cur_id = "?"; in_review = 0; has_obs = 0 }
/^- (id|cmd_id):/ {
    if (in_review) {
        total++
        ids[total] = cur_id
        obs[total] = has_obs
    }
    in_review = 0; has_obs = 0
    match($0, /[[:space:]]([^[:space:]]+)$/, a)
    cur_id = (RLENGTH > 0) ? a[1] : "?"
    next
}
/(review_type|type):[[:space:]]*(draft|report)/ { in_review = 1 }
/observations:/ { has_obs = 1 }
END {
    if (in_review) { total++; ids[total] = cur_id; obs[total] = has_obs }
    start = (total > 10) ? total - 9 : 1
    for (i = start; i <= total; i++) {
        if (!obs[i]) print ids[i]
    }
}
' "$LOG_FILE" 2>/dev/null)

if [ -z "$MISSING" ]; then
    echo "PASS: 直近draft/reportレビュー全てにobservations確認"
    exit 0
else
    COUNT=$(echo "$MISSING" | wc -l)
    echo "WARN: ${COUNT}件のdraft/reportレビューにobservationsなし:"
    echo "$MISSING" | while read -r id; do echo "  - $id"; done
    exit 1
fi
