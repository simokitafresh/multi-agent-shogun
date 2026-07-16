#!/usr/bin/env python3
"""Generate a role-neutral shard manifest from a cmd/task contract.

The entrance is deliberately data-only: callers provide the task YAML and this
module derives items and currently idle workers without role/CLI/model policy.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import yaml


NULLISH = {"", "none", "n/a", "na", "null", "unknown", "tbd", "fill_this"}


def unwrap(data, block_id=""):
    if block_id:
        commands = data.get("commands", data) if isinstance(data, dict) else {}
        data = commands.get(block_id)
    elif isinstance(data, dict):
        data = data.get("task", data)
        if isinstance(data, dict) and len(data) == 1:
            only = next(iter(data.values()))
            if isinstance(only, dict):
                data = only
    if not isinstance(data, dict):
        raise ValueError("task/cmd contract must be a mapping")
    return data


def ac_rows(task):
    raw = task.get("acceptance_criteria") or []
    if isinstance(raw, dict):
        return [{"id": str(k), "description": str(v)} for k, v in raw.items()]
    return [x for x in raw if isinstance(x, dict)] if isinstance(raw, list) else []


def derive_items(task):
    explicit = task.get("work_items")
    if isinstance(explicit, list) and len(explicit) >= 2:
        rows = explicit
    else:
        parallel = task.get("parallel_ok")
        parallel = parallel if isinstance(parallel, list) else []
        wanted = {str(x).strip() for x in parallel if str(x).strip()}
        rows = [x for x in ac_rows(task) if str(x.get("id", "")).strip() in wanted]
    items = []
    for pos, row in enumerate(rows):
        if isinstance(row, str):
            iid, description = row.strip(), row.strip()
        else:
            iid = str(row.get("id") or f"item-{pos + 1}").strip()
            description = str(row.get("description") or row.get("command") or iid).strip()
        if iid:
            items.append({"id": iid, "weight": 1, "capability": "task",
                          "description": description})
    return items


def serial_evidence(task):
    raw = task.get("serial_dependency_evidence")
    if not isinstance(raw, str) or raw.strip().lower() in NULLISH:
        return ""
    return raw.strip()


def idle_workers(tasks_dir):
    workers = []
    for path in sorted(Path(tasks_dir).glob("*.yaml")):
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            task = data.get("task", data) if isinstance(data, dict) else {}
            status = str(task.get("status", "idle")).strip().lower()
        except (OSError, yaml.YAMLError):
            continue
        if status in {"idle", "done", "completed"}:
            workers.append({"id": path.stem, "idle": True, "capabilities": ["task"]})
    return workers


def build(task, workers, source_id):
    estimated = task.get("estimated_minutes")
    try:
        estimated = float(estimated)
    except (TypeError, ValueError):
        estimated = 0
    if not math.isfinite(estimated) or estimated < 30:
        return {"status": "not_required", "estimated_minutes": estimated}
    items = derive_items(task)
    evidence = serial_evidence(task)
    if evidence:
        return {"status": "serial", "serial_dependency_evidence": evidence,
                "estimated_minutes": estimated}
    if len(items) < 2:
        raise ValueError("30-minute single task requires >=2 work_items/parallel_ok boundaries or explicit serial_dependency_evidence")
    if len(workers) < 2:
        return {"status": "deferred", "reason": "eligible_workers<2; silent single-worker fallback forbidden",
                "eligible_workers": len(workers), "item_count": len(items)}
    selected = workers[:min(len(items), len(workers))]
    key = hashlib.sha256(source_id.encode()).hexdigest()[:16]
    return {"status": "manifest", "source_id": source_id, "max_workers": len(selected),
            "state_dir": f"queue/shard_state/{key}", "command": "true",
            "items": items, "workers": selected}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--block-id", default="")
    ap.add_argument("--tasks-dir", default="queue/tasks")
    ap.add_argument("--output")
    ap.add_argument("--idle-workers", type=int)
    args = ap.parse_args()
    try:
        data = yaml.safe_load(Path(args.source).read_text(encoding="utf-8")) or {}
        task = unwrap(data, args.block_id)
        if args.idle_workers is None:
            workers = idle_workers(args.tasks_dir)
        else:
            workers = [{"id": f"worker-{i + 1}", "idle": True, "capabilities": ["task"]}
                       for i in range(args.idle_workers)]
        source_id = args.block_id or str(task.get("task_id") or Path(args.source).stem)
        result = build(task, workers, source_id)
        if args.output and result["status"] == "manifest":
            out = Path(args.output)
            out.parent.mkdir(parents=True, exist_ok=True)
            tmp = out.with_suffix(out.suffix + ".tmp")
            tmp.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            tmp.replace(out)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, yaml.YAMLError, ValueError) as exc:
        print(f"BLOCK: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
