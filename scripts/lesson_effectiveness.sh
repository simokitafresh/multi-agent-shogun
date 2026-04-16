#!/usr/bin/env bash
# ============================================================
# lesson_effectiveness.sh
# 教訓別効果メトリクス集計スクリプト
#
# Usage:
#   bash scripts/lesson_effectiveness.sh
#   bash scripts/lesson_effectiveness.sh --project infra
#
# データソース:
#   1. logs/gate_metrics.log — injected_lessons列(8列目)からinject_count
#   2. queue/reports/*_report_*.yaml — lessons_useful/lesson_referenced
#   3. (将来) preventable_by from report YAMLs
#
# 出力: TSV (lesson_id, inject_count, useful_count, preventable_count, effectiveness)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE_METRICS_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"

# Parse --project option
PROJECT_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_FILTER="${2:-}"; shift 2 ;;
        --help) echo "Usage: $0 [--project <project>]"; exit 0 ;;
        *) shift ;;
    esac
done

# === 高速化: python3 一括処理 (bash while-loop×501ファイル廃止) ===
python3 - "$GATE_METRICS_LOG" "$REPORTS_DIR" "$PROJECT_FILTER" <<'PYTHON'
import sys
import os
import glob
import re

gate_metrics_log = sys.argv[1]
reports_dir = sys.argv[2]
project_filter = sys.argv[3]

inject_count = {}
useful_count = {}
preventable_count = {}
all_lessons = set()

# --- 1. gate_metrics.log: injected_lessons (8th column, 0-indexed: col 7) ---
if os.path.isfile(gate_metrics_log):
    with open(gate_metrics_log, errors='replace') as f:
        for line in f:
            cols = line.rstrip('\n').split('\t')
            if len(cols) >= 8:
                injected = cols[7]
                if injected and injected != 'none':
                    for lid in injected.split(','):
                        lid = lid.strip()
                        if lid and re.match(r'^L\d+', lid):
                            inject_count[lid] = inject_count.get(lid, 0) + 1
                            all_lessons.add(lid)

# --- 2. Report YAMLs: lessons_useful / lesson_referenced / preventable_by ---
_RE_ID = re.compile(r'^\s*-\s+id:\s*(L\d+)')
_RE_FLAT = re.compile(r'^\s*-\s+(L\d+)\s*$')
_RE_USEFUL = re.compile(r'\buseful:\s*(true|false)')
_RE_PREVENTABLE = re.compile(r'^\s+-\s+(L\d+)')
_RE_SECTION_START = re.compile(r'^(lessons_useful|lesson_referenced):')
_RE_PREVENTABLE_SECTION = re.compile(r'^\s*preventable_by:')
_RE_TOPLEVEL = re.compile(r'^[a-zA-Z_]')
_RE_DASH_PREFIX = re.compile(r'^\s*-')

def parse_report(lines, project_filter):
    """Parse a single report's lines. Returns (useful_list, preventable_list)."""
    if project_filter:
        # Quick project check: scan for 'project:' at top level
        proj = ''
        for l in lines:
            if l.startswith('project:'):
                proj = l.split(':', 1)[1].strip().strip("'\"")
                break
        if proj != project_filter:
            return [], []

    useful_lids = []
    preventable_lids = []

    i = 0
    n = len(lines)
    while i < n:
        stripped = lines[i].rstrip()

        # lessons_useful / lesson_referenced section
        if _RE_SECTION_START.match(stripped):
            if '[]' in stripped or 'false' in stripped:
                i += 1
                continue
            i += 1
            current_lid = None
            current_useful = None
            while i < n:
                l = lines[i].rstrip()
                # Section ends at next top-level key (letter/underscore at col 0)
                if l and _RE_TOPLEVEL.match(l):
                    if current_lid and current_useful == 'true':
                        useful_lids.append(current_lid)
                    current_lid = None  # Prevent double-flush in post-loop code
                    break
                # New list item: "- id: LXXX"
                m = _RE_ID.match(l)
                if m:
                    if current_lid and current_useful == 'true':
                        useful_lids.append(current_lid)
                    current_lid = m.group(1)
                    current_useful = None
                else:
                    # Legacy flat: "- LXXX"
                    m2 = _RE_FLAT.match(l)
                    if m2:
                        if current_lid and current_useful == 'true':
                            useful_lids.append(current_lid)
                        current_lid = m2.group(1)
                        current_useful = 'true'
                    else:
                        # useful: true/false
                        m3 = _RE_USEFUL.search(l)
                        if m3:
                            current_useful = m3.group(1)
                i += 1
            # Flush at EOF / section end
            if current_lid and current_useful == 'true':
                useful_lids.append(current_lid)
            continue

        # preventable_by section
        if _RE_PREVENTABLE_SECTION.match(stripped):
            if '[]' in stripped:
                i += 1
                continue
            i += 1
            while i < n:
                l = lines[i].rstrip()
                m = _RE_PREVENTABLE.match(l)
                if m:
                    preventable_lids.append(m.group(1))
                elif not _RE_DASH_PREFIX.match(l):
                    # Section ends when line doesn't start with optional-spaces then dash
                    break
                i += 1
            continue

        i += 1

    return useful_lids, preventable_lids


pattern = os.path.join(reports_dir, '*_report_*.yaml')
report_paths = glob.glob(pattern)

def read_and_parse(report_path):
    try:
        with open(report_path, errors='replace') as f:
            lines = f.readlines()
        return parse_report(lines, project_filter)
    except OSError:
        return [], []

# ThreadPoolExecutor: WSL2の501ファイルI/Oを並列化(1.0s→0.3s)
import concurrent.futures
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
    for ul, pl in executor.map(read_and_parse, report_paths):
        for lid in ul:
            useful_count[lid] = useful_count.get(lid, 0) + 1
            all_lessons.add(lid)
        for lid in pl:
            preventable_count[lid] = preventable_count.get(lid, 0) + 1
            all_lessons.add(lid)

# --- Output ---
print("lesson_id\tinject_count\tuseful_count\tpreventable_count\teffectiveness")

if not all_lessons:
    sys.exit(0)

rows = []
for lid in all_lessons:
    ic = inject_count.get(lid, 0)
    uc = useful_count.get(lid, 0)
    pc = preventable_count.get(lid, 0)
    eff = f"{uc / ic * 100:.1f}%" if ic > 0 else "N/A"
    rows.append((lid, ic, uc, pc, eff))

# Sort by inject_count desc (same as original: sort -t$'\t' -k2 -rn)
rows.sort(key=lambda x: x[1], reverse=True)
for lid, ic, uc, pc, eff in rows:
    print(f"{lid}\t{ic}\t{uc}\t{pc}\t{eff}")
PYTHON
