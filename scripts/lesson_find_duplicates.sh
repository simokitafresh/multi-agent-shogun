#!/bin/bash
# lesson_find_duplicates.sh — 教訓の類似ペア検出ツール
# Usage: bash scripts/lesson_find_duplicates.sh <project>
# Output: similarity: 0.72 | L006 vs L033 | タイトル1 | タイトル2
#
# - projects/{project}/lessons.yaml の全教訓ペアの類似度を計算
# - difflib.SequenceMatcher使用（lesson_write.shと同方式）
# - title+summaryの結合文字列で比較
# - 閾値0.5以上のペアをリスト出力（統合候補の提案）
# - status: deprecated のエントリは比較対象から除外

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

python3 -c "
import yaml, sys
from difflib import SequenceMatcher

lessons_file = '$LESSONS_FILE'
threshold = 0.5

with open(lessons_file) as f:
    data = yaml.safe_load(f)

lessons = data.get('lessons', []) if data else []
if not lessons:
    print('No lessons found.', file=sys.stderr)
    sys.exit(0)

# Filter: confirmed only (exclude deprecated + draft)
active = []
skipped_deprecated = 0
skipped_draft = 0
for lesson in lessons:
    status = str(lesson.get('status', 'confirmed')).lower()
    if status == 'deprecated':
        skipped_deprecated += 1
        continue
    if status != 'confirmed':
        skipped_draft += 1
        continue
    active.append(lesson)

print(f'Active lessons: {len(active)}, Deprecated: {skipped_deprecated}, Draft/other: {skipped_draft}', file=sys.stderr)

if len(active) < 2:
    print('Not enough active lessons to compare.', file=sys.stderr)
    sys.exit(0)

# Compare all pairs
pairs = []
for i in range(len(active)):
    for j in range(i + 1, len(active)):
        a = active[i]
        b = active[j]
        text_a = str(a.get('title', '')) + ' ' + str(a.get('summary', ''))
        text_b = str(b.get('title', '')) + ' ' + str(b.get('summary', ''))
        ratio = SequenceMatcher(None, text_a, text_b).ratio()
        if ratio >= threshold:
            pairs.append((ratio, a.get('id', '?'), b.get('id', '?'),
                          str(a.get('title', ''))[:60], str(b.get('title', ''))[:60]))

if not pairs:
    print('No similar pairs found (threshold >= 0.5).', file=sys.stderr)
    sys.exit(0)

# Sort by similarity descending
pairs.sort(key=lambda x: -x[0])

for ratio, id_a, id_b, title_a, title_b in pairs:
    print(f'Score: {ratio:.2f} | {id_a} vs {id_b}')
    print(f'  {id_a}: {title_a}')
    print(f'  {id_b}: {title_b}')
    print('  ---')
"
