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
    echo "SKIP: gunshi_review_log.yaml not found"
    exit 0
fi

MISSING=$(python3 -c "
import re

with open('$LOG_FILE') as f:
    content = f.read()

blocks = re.split(r'\n(?=- (?:id|cmd_id): )', content)
recent = []
for block in blocks:
    is_review = ('review_type: draft' in block or 'review_type: report' in block
                 or 'type: draft' in block or 'type: report' in block)
    if not is_review:
        continue
    id_match = re.search(r'(?:id|cmd_id): (\S+)', block)
    entry_id = id_match.group(1) if id_match else '?'
    has_obs = 'observations:' in block
    recent.append((entry_id, has_obs))

# Check last 10 draft/report entries
for entry_id, has_obs in recent[-10:]:
    if not has_obs:
        print(entry_id)
" 2>/dev/null)

if [ -z "$MISSING" ]; then
    echo "PASS: 直近draft/reportレビュー全てにobservations確認"
    exit 0
else
    COUNT=$(echo "$MISSING" | wc -l)
    echo "WARN: ${COUNT}件のdraft/reportレビューにobservationsなし:"
    echo "$MISSING" | while read -r id; do echo "  - $id"; done
    exit 1
fi
