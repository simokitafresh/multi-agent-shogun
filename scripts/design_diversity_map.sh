#!/usr/bin/env bash
# design_diversity_map.sh — 設計多様性地図 MAP-Elites (LayerX記事 #5)
# Usage: bash scripts/design_diversity_map.sh
# Origin: [[self_improving_agent_local_optima]] MAP-Elites設計多様性地図
#
# 軸1: scope_mode (FULL/PATCH/SCOUT/karo_direct)
# 軸2: cmd規模 (AC数 0-1/2-3/4+)
# 軸3: project (dm-signal/infra/other)
# 各マスにBLOCK率と探索回数を表示。空マス=未探索領域。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KARO_YAML="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
QUALITY_LOG="$SCRIPT_DIR/logs/cmd_design_quality.yaml"

python3 - "$KARO_YAML" "$QUALITY_LOG" <<'PY'
import sys, yaml, re
from collections import defaultdict

karo_path, quality_path = sys.argv[1], sys.argv[2]

# Load shogun_to_karo for scope_mode and AC count
def load_karo(path):
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
        return data.get("commands", {}) if isinstance(data, dict) else {}
    except Exception:
        return {}

# Load cmd_design_quality for gate results
def load_quality(path):
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
        return data.get("entries", []) if isinstance(data, dict) else []
    except Exception:
        return []

cmds = load_karo(karo_path)
quality_entries = load_quality(quality_path)

# Build quality lookup: cmd_id → latest gate_result
quality_map = {}
for e in quality_entries:
    cid = e.get("cmd_id", "")
    quality_map[cid] = e  # last wins (latest timestamp)

# Classify scope_mode
def get_scope(cmd_data, cmd_id):
    sm = cmd_data.get("scope_mode", "")
    if sm:
        return sm.upper()
    if "recon" in cmd_id:
        return "SCOUT"
    if "hotfix" in cmd_id:
        return "PATCH"
    if cmd_id.startswith("cmd_karo_"):
        return "KARO_DIRECT"
    return "FULL"

# Count ACs
def count_acs(cmd_data):
    ac = cmd_data.get("acceptance_criteria", {})
    if isinstance(ac, dict):
        return len(ac)
    if isinstance(ac, list):
        return len(ac)
    return 0

# AC size bucket
def ac_bucket(n):
    if n <= 1:
        return "0-1"
    if n <= 3:
        return "2-3"
    return "4+"

# Project bucket
def pj_bucket(cmd_data):
    p = cmd_data.get("project", "")
    if p in ("dm-signal",):
        return "dm-signal"
    if p in ("infra",):
        return "infra"
    if p:
        return p
    return "other"

# Build diversity map
# Key: (scope, ac_size, project)
diversity = defaultdict(lambda: {"total": 0, "block": 0, "pass": 0, "clear": 0, "warn": 0, "cmds": []})

for cmd_id, cmd_data in cmds.items():
    if not isinstance(cmd_data, dict):
        continue
    scope = get_scope(cmd_data, cmd_id)
    ac_n = count_acs(cmd_data)
    ac_sz = ac_bucket(ac_n)
    pj = pj_bucket(cmd_data)

    cell = diversity[(scope, ac_sz, pj)]
    cell["total"] += 1
    cell["cmds"].append(cmd_id)

    # Match with quality data
    q = quality_map.get(cmd_id, {})
    result = q.get("gate_result", "")
    if result == "BLOCK":
        cell["block"] += 1
    elif result == "PASS":
        cell["pass"] += 1
    elif result == "CLEAR":
        cell["clear"] += 1
    elif result == "WARN":
        cell["warn"] += 1

# Output as MAP-Elites grid
scopes = sorted(set(k[0] for k in diversity))
ac_sizes = ["0-1", "2-3", "4+"]
projects = sorted(set(k[2] for k in diversity))

print(f"=== Design Diversity Map (MAP-Elites) — {len(cmds)} cmds ===")
print()

for pj in projects:
    print(f"  [{pj}]")
    # Header
    header = f"    {'scope':<14}"
    for ac in ac_sizes:
        header += f" {'AC:'+ac:>12}"
    print(header)
    print(f"    {'-'*14}" + "".join(f" {'-'*12}" for _ in ac_sizes))

    for scope in scopes:
        row = f"    {scope:<14}"
        for ac in ac_sizes:
            cell = diversity.get((scope, ac, pj))
            if cell and cell["total"] > 0:
                blk = cell["block"]
                tot = cell["total"]
                pct = (blk / tot * 100) if tot > 0 else 0
                row += f" {tot:>3}cmd/{pct:>4.0f}%B"
            else:
                row += f"     {'---':>7} "
        print(row)
    print()

# Identify unexplored cells
print("  === 未探索領域 (探索0件) ===")
unexplored = []
for pj in projects:
    for scope in scopes:
        for ac in ac_sizes:
            if (scope, ac, pj) not in diversity:
                unexplored.append(f"    {pj}/{scope}/AC:{ac}")

if unexplored:
    for u in unexplored:
        print(u)
else:
    print("    全領域探索済み")

# Identify high-BLOCK cells (>25% and n>=3)
print()
print("  === 高BLOCK率領域 (>25%, n>=3) ===")
high_block = []
for key, cell in diversity.items():
    if cell["total"] >= 3:
        pct = cell["block"] / cell["total"] * 100
        if pct > 25:
            high_block.append((key, pct, cell["block"], cell["total"]))

if high_block:
    for key, pct, bc, tot in sorted(high_block, key=lambda x: -x[1]):
        scope, ac, pj = key
        print(f"    {pj}/{scope}/AC:{ac}: {pct:.0f}% ({bc}/{tot})")
else:
    print("    なし")
print()
PY
