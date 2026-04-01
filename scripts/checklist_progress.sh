#!/bin/bash
# checklist_progress.sh — 段取りリストの進捗サマリー出力
# Usage: bash scripts/checklist_progress.sh <checklist_file>
#
# 段取りリストを読み込み、完了数/全数/完了率+担当別進捗を1行サマリーで出力。
# 例: "48/137 (35%) | hanzo:12 saizo:8 kotaro:10"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHECKLIST_FILE="$1"

if [ -z "$CHECKLIST_FILE" ]; then
    echo "Usage: checklist_progress.sh <checklist_file>" >&2
    exit 1
fi

# Resolve relative paths from project root
case "$CHECKLIST_FILE" in
    /*) ;;
    *) CHECKLIST_FILE="$SCRIPT_DIR/$CHECKLIST_FILE" ;;
esac

if [ ! -f "$CHECKLIST_FILE" ]; then
    echo "FATAL: checklist_progress: file not found: $CHECKLIST_FILE" >&2
    exit 1
fi

CHECKLIST_PATH="$CHECKLIST_FILE" python3 -c "
import os, re, sys
from collections import OrderedDict

checklist_path = os.environ['CHECKLIST_PATH']

with open(checklist_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

done_count = 0
total_count = 0
ninja_counts = OrderedDict()

def is_separator(s):
    return bool(re.match(r'^\|[-:\s|]+\$', s)) and '---' in s

def flush_table(rows):
    if not rows:
        return 0, 0, OrderedDict()
    is_checklist = False
    done = 0
    nc = OrderedDict()
    for row_text in rows:
        cells = row_text.split('|')
        row_done = False
        if '\u2705' in row_text:
            row_done = True
            is_checklist = True
        for c in cells[1:]:
            cu = c.strip().upper()
            if re.search(r'\bPASS\b', cu) or cu in ('DONE', 'O', 'OK'):
                row_done = True
                is_checklist = True
            elif re.search(r'\bFAIL\b', cu) or cu in ('NG', 'TODO', 'PENDING', 'SKIP'):
                is_checklist = True
        if row_done:
            done += 1
            if len(cells) >= 9:
                cell_ninja = cells[7].strip()
                if cell_ninja:
                    nc[cell_ninja] = nc.get(cell_ninja, 0) + 1
    if is_checklist:
        return done, len(rows), nc
    return 0, 0, OrderedDict()

in_table = False
table_rows = []

for line in lines:
    stripped = line.strip()

    if is_separator(stripped):
        if table_rows:
            d, t, nc = flush_table(table_rows)
            done_count += d
            total_count += t
            for n, c in nc.items():
                ninja_counts[n] = ninja_counts.get(n, 0) + c
        in_table = True
        table_rows = []
        continue

    if in_table:
        if stripped.startswith('|') and stripped.endswith('|'):
            table_rows.append(stripped)
            continue
        else:
            d, t, nc = flush_table(table_rows)
            done_count += d
            total_count += t
            for n, c in nc.items():
                ninja_counts[n] = ninja_counts.get(n, 0) + c
            in_table = False
            table_rows = []

    # Format 2: Markdown checkbox (- [ ] not done, - [x] done)
    cm = re.match(r'^-\s+\[([ xX])\]', stripped)
    if cm:
        total_count += 1
        if cm.group(1) in ('x', 'X'):
            done_count += 1

if table_rows:
    d, t, nc = flush_table(table_rows)
    done_count += d
    total_count += t
    for n, c in nc.items():
        ninja_counts[n] = ninja_counts.get(n, 0) + c

pct = int(done_count * 100 / total_count) if total_count > 0 else 0

parts = [f'{done_count}/{total_count} ({pct}%)']
if ninja_counts:
    ninja_str = ' '.join(f'{name}:{count}' for name, count in ninja_counts.items())
    parts.append(ninja_str)

print(' | '.join(parts))
"
