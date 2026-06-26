#!/usr/bin/env bash
# score_matrix.sh — PJ×cmd種類×gate_result Score Matrix (LayerX記事 #2)
# Usage: bash scripts/score_matrix.sh [--archive]
# Origin: [[self_improving_agent_local_optima]] GEPA Score Matrix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTIVE_LOG="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
ARCHIVE_LOG="$SCRIPT_DIR/logs/archive/cmd_design_quality.yaml"

USE_ARCHIVE=false
[[ "${1:-}" == "--archive" ]] && USE_ARCHIVE=true

python3 - "$ACTIVE_LOG" "$ARCHIVE_LOG" "$USE_ARCHIVE" <<'PY'
import sys, yaml, re
from collections import defaultdict

active_path, archive_path, use_archive = sys.argv[1], sys.argv[2], sys.argv[3] == "True"

def load_entries(path):
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
        return data.get("entries", []) if isinstance(data, dict) else []
    except Exception:
        return []

entries = load_entries(active_path)
if use_archive:
    entries = load_entries(archive_path) + entries

def classify_cmd_type(cmd_id):
    if not cmd_id:
        return "unknown"
    if "recon" in cmd_id:
        return "recon"
    if "hotfix" in cmd_id:
        return "hotfix"
    if cmd_id.startswith("cmd_karo_") and "recon" not in cmd_id and "hotfix" not in cmd_id:
        return "karo_direct"
    if re.match(r"^cmd_\d+$", cmd_id):
        return "shogun_cmd"
    return "other"

# Build Score Matrix: project × cmd_type × gate_result
matrix = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
totals_by_pj_type = defaultdict(lambda: defaultdict(int))

for e in entries:
    pj = e.get("project", "") or "unknown"
    cmd_type = classify_cmd_type(e.get("cmd_id", ""))
    result = e.get("gate_result", "unknown")
    matrix[pj][cmd_type][result] += 1
    totals_by_pj_type[pj][cmd_type] += 1

# Output
results_order = ["PASS", "WARN", "BLOCK", "CLEAR"]
all_types = sorted(set(t for pj in matrix for t in matrix[pj]))

print(f"=== Score Matrix (n={len(entries)}, archive={'ON' if use_archive else 'OFF'}) ===")
print()

for pj in sorted(matrix.keys()):
    print(f"  [{pj}]")
    # Header
    header = f"    {'cmd_type':<14}"
    for r in results_order:
        header += f" {r:>6}"
    header += f" {'TOTAL':>6}  {'BLOCK%':>6}"
    print(header)
    print(f"    {'-'*14}" + "".join(f" {'-'*6}" for _ in results_order) + f" {'-'*6}  {'-'*6}")

    for ct in all_types:
        if ct not in matrix[pj]:
            continue
        row = f"    {ct:<14}"
        total = totals_by_pj_type[pj][ct]
        block_count = matrix[pj][ct].get("BLOCK", 0)
        for r in results_order:
            count = matrix[pj][ct].get(r, 0)
            row += f" {count:>6}"
        block_pct = (block_count / total * 100) if total > 0 else 0
        row += f" {total:>6}  {block_pct:>5.1f}%"
        print(row)
    print()

# Summary: BLOCK hotspots (BLOCK% > 20%)
print("  === BLOCK Hotspots (>20%) ===")
hotspots = []
for pj in matrix:
    for ct in matrix[pj]:
        total = totals_by_pj_type[pj][ct]
        if total < 3:  # min sample
            continue
        block_count = matrix[pj][ct].get("BLOCK", 0)
        block_pct = block_count / total * 100
        if block_pct > 20:
            hotspots.append((pj, ct, block_pct, block_count, total))

if hotspots:
    for pj, ct, pct, bc, tot in sorted(hotspots, key=lambda x: -x[2]):
        print(f"    {pj}/{ct}: {pct:.1f}% ({bc}/{tot})")
else:
    print("    なし")
print()
PY
