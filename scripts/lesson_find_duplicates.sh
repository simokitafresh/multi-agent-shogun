#!/bin/bash
# lesson_find_duplicates.sh — 教訓の類似ペア検出ツール
# Usage: bash scripts/lesson_find_duplicates.sh <project>
# Output: 類似度: 0.78 | L006 "title1" | L033 "title2"
#
# - projects/{project}/lessons.yaml の全教訓ペアの類似度を計算
# - difflib.SequenceMatcher使用
# - title+summaryの結合文字列で比較
# - 閾値0.5以上のペアをリスト出力（統合候補の提案）
# - status: draft/deprecated のエントリは比較対象から除外

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT="${1:-}"

if [ -z "$PROJECT" ]; then
    echo "Usage: lesson_find_duplicates.sh <project>" >&2
    echo "例: bash scripts/lesson_find_duplicates.sh infra" >&2
    exit 1
fi

LESSONS_FILE="$SCRIPT_DIR/projects/$PROJECT/lessons.yaml"

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: lessons.yaml not found: $LESSONS_FILE" >&2
    exit 1
fi

python3 - "$LESSONS_FILE" << 'PYEOF'
import yaml, sys
from difflib import SequenceMatcher

lessons_file = sys.argv[1]
threshold = 0.5

with open(lessons_file, encoding="utf-8") as f:
    data = yaml.safe_load(f)

lessons = data.get("lessons", []) if data else []
if not lessons:
    print("No lessons found.", file=sys.stderr)
    sys.exit(0)

# Filter: exclude draft and deprecated
active = []
skipped_deprecated = 0
skipped_draft = 0
for lesson in lessons:
    status = str(lesson.get("status", "confirmed")).lower()
    if status == "deprecated":
        skipped_deprecated += 1
        continue
    if status == "draft":
        skipped_draft += 1
        continue
    active.append(lesson)

print(f"Active lessons: {len(active)}, Deprecated: {skipped_deprecated}, Draft: {skipped_draft}", file=sys.stderr)

if len(active) < 2:
    print("Not enough active lessons to compare.", file=sys.stderr)
    sys.exit(0)

# Pre-compute text strings (avoid re-computation in O(n^2) inner loop)
texts = []
titles = []
for lesson in active:
    t = (lesson.get("title") or "")
    s = (lesson.get("summary") or "")
    texts.append(str(t) + " " + str(s))
    titles.append(str(t)[:60])

# Compare all pairs (quick_ratio pre-filter: O(n+m) upper bound skips expensive O(n*m) ratio)
pairs = []
sm = SequenceMatcher()
for i in range(len(active)):
    sm.set_seq1(texts[i])
    for j in range(i + 1, len(active)):
        sm.set_seq2(texts[j])
        if sm.quick_ratio() >= threshold:
            ratio = sm.ratio()
            if ratio >= threshold:
                pairs.append((ratio, active[i].get("id", "?"), titles[i], active[j].get("id", "?"), titles[j]))

if not pairs:
    print("No similar pairs found (threshold >= 0.5).", file=sys.stderr)
    sys.exit(0)

# Sort by similarity descending
pairs.sort(key=lambda x: -x[0])

print(f"Found {len(pairs)} similar pair(s):\n", file=sys.stderr)
for ratio, id_a, title_a, id_b, title_b in pairs:
    print(f'\u985e\u4f3c\u5ea6: {ratio:.2f} | {id_a} "{title_a}" | {id_b} "{title_b}"')
PYEOF
