#!/usr/bin/env python3
from collections import Counter
from pathlib import Path
import sys, yaml

REPO_ROOT = Path(__file__).resolve().parents[1]

def resource_exists(value):
    value = str(value)
    generated = value.startswith("generated:")
    if generated:
        value = value[len("generated:"):]
    if not value.startswith("project:"):
        return (REPO_ROOT / value).exists()
    project_ref = value[len("project:"):]
    project_id, sep, relative = project_ref.partition("/")
    if not sep or not relative:
        return False
    projects = yaml.safe_load((REPO_ROOT / "config/projects.yaml").read_text(encoding="utf-8")) or {}
    entries = projects.get("projects", projects)
    if isinstance(entries, list):
        entry = next((x for x in entries if isinstance(x, dict) and x.get("id") == project_id), {})
    else:
        entry = entries.get(project_id, {}) if isinstance(entries, dict) else {}
    base = entry.get("path") if isinstance(entry, dict) else None
    target = Path(base) / relative if base else None
    return bool(target and ((target.parent.exists() if generated else target.exists())))

path = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "config/campaign_lane_catalog.yaml"
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
            if not resource_exists(lane.get(key, "")): errors.append(f"lanes[{i}] ready missing {key}")
if errors:
    print("CATALOG_FAIL", *errors, sep="\n")
    raise SystemExit(1)
counts = Counter(x["readiness"] for x in lanes)
print(f"CATALOG_PASS lanes={len(lanes)} duplicates=0 ready={counts['ready']} partial={counts['partial']} blocked={counts['blocked']}")
