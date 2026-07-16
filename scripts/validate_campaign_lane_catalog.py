#!/usr/bin/env python3
from collections import Counter
from pathlib import Path
import sys, yaml

path = Path(sys.argv[1] if len(sys.argv) > 1 else "config/campaign_lane_catalog.yaml")
data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
lanes = data.get("lanes") or []
required = {"lane_id", "name", "measurement_source", "writer", "adapter", "objective", "metric_key", "target_key", "priority", "quality_contract", "stop_conditions", "readiness", "blocker"}
errors = []
if len(lanes) < 12: errors.append(f"lane_count={len(lanes)} (<12)")
ids = [str(x.get("lane_id", "")) for x in lanes]
dups = sorted(k for k, v in Counter(ids).items() if v > 1)
if dups: errors.append(f"duplicate_lane_id={dups}")
for i, lane in enumerate(lanes):
    missing = sorted(required - set(lane))
    if missing: errors.append(f"lanes[{i}] missing={missing}")
    if lane.get("objective") not in {"minimize", "maximize", "target"}: errors.append(f"lanes[{i}] bad objective")
    if lane.get("readiness") not in {"ready", "partial", "blocked"}: errors.append(f"lanes[{i}] bad readiness")
    if not lane.get("stop_conditions"): errors.append(f"lanes[{i}] empty stop_conditions")
    if lane.get("readiness") == "ready":
        for key in ("measurement_source", "writer", "adapter"):
            if not Path(str(lane.get(key, ""))).exists(): errors.append(f"lanes[{i}] ready missing {key}")
if errors:
    print("CATALOG_FAIL", *errors, sep="\n")
    raise SystemExit(1)
counts = Counter(x["readiness"] for x in lanes)
print(f"CATALOG_PASS lanes={len(lanes)} duplicates=0 ready={counts['ready']} partial={counts['partial']} blocked={counts['blocked']}")
