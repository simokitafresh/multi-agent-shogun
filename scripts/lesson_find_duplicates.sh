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

_lfd_self="${BASH_SOURCE[0]}"; [[ "$_lfd_self" != /* ]] && _lfd_self="$PWD/$_lfd_self"
SCRIPT_DIR="${_lfd_self%/scripts/lesson_find_duplicates.sh}"

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
import yaml, sys, multiprocessing
from difflib import SequenceMatcher
from collections import Counter

_CLoader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

lessons_file = sys.argv[1]
threshold = 0.5

with open(lessons_file, encoding="utf-8") as f:
    data = yaml.load(f, Loader=_CLoader)

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

# Pre-compute text strings and metadata
texts = []
titles = []
ids = []
for lesson in active:
    t = (lesson.get("title") or "")
    s = (lesson.get("summary") or "")
    texts.append(str(t) + " " + str(s))
    titles.append(str(t)[:60])
    ids.append(lesson.get("id", "?"))

n = len(active)

# Pre-compute character frequency Counters and lengths (avoid per-pair dict rebuild)
counters = [Counter(t) for t in texts]
lens = [len(t) for t in texts]

# Worker function: compare one row i against all j > i
# Uses Counter-based quick_ratio pre-filter (same formula as SM.quick_ratio)
# then falls back to SM.ratio() only for candidates
def _compare_row(i):
    sm = SequenceMatcher()
    results = []
    thr = threshold
    ca, la = counters[i], lens[i]
    sm.set_seq1(texts[i])
    for j in range(i + 1, n):
        cb, lb = counters[j], lens[j]
        # Counter-based quick_ratio: same formula as SM, skips set_seq2 overhead
        common = sum(min(v, cb.get(k, 0)) for k, v in ca.items())
        if 2.0 * common / (la + lb) >= thr:
            sm.set_seq2(texts[j])
            ratio = sm.ratio()
            if ratio >= thr:
                results.append((ratio, ids[i], titles[i], ids[j], titles[j]))
    return results

# perf: candidate density (quick_ratio hits) varies a lot by row range, so a static
# equal-pair-count split starves fast workers while one worker lags (measured 2.3-3.9s
# spread across 8 equal-pair-count chunks on infra/914 lessons). Submitting one row per
# task lets the pool's task queue rebalance dynamically as workers free up.
num_procs = min(multiprocessing.cpu_count(), 8)

# Parallel execution via fork (globals shared copy-on-write)
with multiprocessing.Pool(processes=num_procs) as pool:
    results_list = pool.map(_compare_row, range(n), chunksize=4)

pairs = [r for sub in results_list for r in sub]

if not pairs:
    print("No similar pairs found (threshold >= 0.5).", file=sys.stderr)
    sys.exit(0)

# Sort by similarity descending
pairs.sort(key=lambda x: -x[0])

print(f"Found {len(pairs)} similar pair(s):\n", file=sys.stderr)
for ratio, id_a, title_a, id_b, title_b in pairs:
    print(f'\u985e\u4f3c\u5ea6: {ratio:.2f} | {id_a} "{title_a}" | {id_b} "{title_b}"')
PYEOF
