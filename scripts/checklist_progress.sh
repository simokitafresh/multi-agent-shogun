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

for line in lines:
    stripped = line.strip()
    # Format 1: Pipe-delimited table rows (| 1 | ... | status | ... | ninja | ... |)
    m = re.match(r'^\|\s*(\d+)\s*\|', stripped)
    if m:
        cells = stripped.split('|')
        if len(cells) >= 9:
            total_count += 1
            cell_status = cells[5].strip()
            cell_ninja = cells[7].strip()
            if cell_status in ('done', 'DONE', 'PASS', 'pass', 'o', 'OK', 'ok'):
                done_count += 1
                if cell_ninja:
                    ninja_counts[cell_ninja] = ninja_counts.get(cell_ninja, 0) + 1
        continue
    # Format 2: Markdown checkbox (- [ ] not done, - [x] done)
    cm = re.match(r'^-\s+\[([ xX])\]', stripped)
    if cm:
        total_count += 1
        if cm.group(1) in ('x', 'X'):
            done_count += 1

pct = int(done_count * 100 / total_count) if total_count > 0 else 0

parts = [f'{done_count}/{total_count} ({pct}%)']
if ninja_counts:
    ninja_str = ' '.join(f'{name}:{count}' for name, count in ninja_counts.items())
    parts.append(ninja_str)

print(' | '.join(parts))
"
