#!/usr/bin/env python3
"""Deterministic campaign state controller; execution belongs to shard-work."""
from __future__ import annotations

import argparse
import fcntl
import json
import math
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import yaml


class ContractError(ValueError):
    pass


def load_catalog(path: str) -> dict:
    data = yaml.safe_load(Path(path).read_text()) or {}
    if data.get("objective") not in {"minimize", "maximize", "target"}:
        raise ContractError("objective must be minimize|maximize|target")
    if data.get("objective") == "target" and not isinstance(data.get("target"), (int, float)):
        raise ContractError("target objective requires numeric target")
    if data.get("min_rounds", 2) != 2 or data.get("max_rounds", 3) != 3:
        raise ContractError("round contract is min_rounds=2,max_rounds=3")
    if not isinstance(data.get("budget"), (int, float)) or data["budget"] <= 0:
        raise ContractError("budget must be positive numeric")
    candidates = data.get("candidates") or []
    workers = data.get("workers") or []
    if len({x.get("id") for x in candidates}) != len(candidates):
        raise ContractError("duplicate target")
    if len({x.get("id") for x in workers}) != len(workers):
        raise ContractError("duplicate worker")
    for item in candidates:
        if not item.get("id") or not isinstance(item.get("cost"), (int, float)) or item["cost"] < 0:
            raise ContractError("candidate requires id and nonnegative numeric cost")
        if not item.get("independent", False):
            raise ContractError("dependent candidate BLOCK")
        if not item.get("capability"):
            raise ContractError("candidate capability required")
    return data


def load_measurements(path: str) -> list[dict]:
    p = Path(path)
    if not p.exists():
        return []
    rows = []
    for line_no, line in enumerate(p.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ContractError(f"invalid measurement line {line_no}: {exc}") from exc
        if not row.get("target") or not isinstance(row.get("round"), int):
            raise ContractError(f"measurement line {line_no} missing target/round")
        rows.append(row)
    return rows


def parse_time(value: str) -> datetime:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            raise ContractError("measurement timestamp requires timezone")
        return value
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, TypeError, ValueError) as exc:
        raise ContractError("measurement timestamp must be ISO-8601") from exc
    if parsed.tzinfo is None:
        raise ContractError("measurement timestamp requires timezone")
    return parsed


def reject_stale(catalog: dict, rows: list[dict]) -> None:
    boundary = catalog.get("measurement_not_before")
    if not boundary:
        return
    minimum = parse_time(boundary)
    for row in rows:
        if not row.get("measured_at") or parse_time(row["measured_at"]) < minimum:
            raise ContractError(f"stale measurement: {row.get('target')}")


def accepted(rows: list[dict]) -> list[dict]:
    return [r for r in rows if r.get("status") == "success" and r.get("quality") != "fail" and isinstance(r.get("value"), (int, float))]


def best_value(catalog: dict, rows: list[dict]):
    values = [r["value"] for r in accepted(rows)]
    if not values:
        return None
    if catalog["objective"] == "maximize":
        return max(values)
    if catalog["objective"] == "minimize":
        return min(values)
    target = catalog["target"]
    return min(values, key=lambda value: (abs(value - target), value))


def improves(catalog: dict, value: float, best) -> bool:
    if best is None:
        return True
    if catalog["objective"] == "minimize":
        return value < best
    if catalog["objective"] == "maximize":
        return value > best
    return abs(value - catalog["target"]) < abs(best - catalog["target"])


def state(catalog: dict, rows: list[dict]) -> dict:
    good = accepted(rows)
    best = best_value(catalog, rows)
    rounds = max((r["round"] for r in rows), default=0)
    spent = sum(float(r.get("cost", 0)) for r in rows if r.get("status") != "in_flight")
    terminal = None
    if catalog["objective"] == "target" and best is not None and best == catalog["target"]:
        terminal = "TARGET_REACHED"
    elif spent >= catalog["budget"]:
        terminal = "BUDGET_EXHAUSTED"
    elif rounds >= 3:
        terminal = "MAX_ROUNDS"
    elif rounds >= 2 and good and not any(r.get("improved", improves(catalog, r["value"], None)) for r in good if r["round"] == rounds):
        terminal = "SATURATED"
    return {"best_so_far": best, "rounds": rounds, "spent": spent, "terminal": terminal}


def select(catalog: dict, rows: list[dict]) -> dict:
    reject_stale(catalog, rows)
    if catalog.get("environment") == "production" and catalog.get("sealed") is True:
        return {"status": "BLOCK", "reason": "production SEALED"}
    if catalog.get("evaluation") == "subjective":
        return {"status": "BLOCK", "reason": "subjective evaluation"}
    current = state(catalog, rows)
    if current["terminal"]:
        return {"status": "STOP", **current}
    next_round = current["rounds"] + 1
    attempted = {(r["target"], r["round"]) for r in rows}
    inflight = {(r["target"], r["round"]) for r in rows if r.get("status") == "in_flight"}
    remaining_budget = catalog["budget"] - current["spent"]
    candidates = [c for c in catalog["candidates"] if (c["id"], next_round) not in attempted and (c["id"], next_round) not in inflight and c["cost"] <= remaining_budget]
    workers = [w for w in catalog.get("workers", []) if w.get("idle")]
    eligible = []
    used_workers = []
    for candidate in candidates:
        worker = next((w for w in workers if w["id"] not in used_workers and candidate["capability"] in w.get("capabilities", [])), None)
        if worker:
            eligible.append(candidate)
            used_workers.append(worker["id"])
    if len(eligible) < 2 or len(used_workers) < 2:
        return {"status": "BLOCK", "reason": "fewer than two eligible independent candidates/workers"}
    n = min(len(eligible), len(used_workers))
    items = eligible[:n]
    return {"status": "HANDOFF", "round": next_round, "best_so_far": current["best_so_far"], "handoff": {"skill": "shard-work", "n": n, "items": items, "workers": used_workers[:n]}}


def record(path: str, row: dict, catalog: dict, rows: list[dict]) -> dict:
    if row.get("status") not in {"success", "quality_fail", "in_flight", "failed"}:
        raise ContractError("invalid result status")
    if row.get("status") == "success" and not isinstance(row.get("value"), (int, float)):
        raise ContractError("success requires numeric value")
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.seek(0)
        locked_rows = []
        for line in handle:
            if line.strip():
                locked_rows.append(json.loads(line))
        key = (row.get("target"), row.get("round"))
        if key in {(r.get("target"), r.get("round")) for r in locked_rows}:
            raise ContractError("duplicate or same-round in-flight target")
        reject_stale(catalog, [row])
        row["quality"] = "fail" if row["status"] == "quality_fail" else row.get("quality", "pass")
        row["improved"] = row["status"] == "success" and row["quality"] != "fail" and improves(catalog, row["value"], best_value(catalog, locked_rows))
        handle.seek(0, os.SEEK_END)
        handle.write(json.dumps(row, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
        fcntl.flock(handle, fcntl.LOCK_UN)
    return row


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["validate", "select", "record", "status"])
    parser.add_argument("catalog")
    parser.add_argument("measurements")
    parser.add_argument("--result")
    args = parser.parse_args()
    try:
        catalog = load_catalog(args.catalog)
        rows = load_measurements(args.measurements)
        if args.action == "validate":
            output = {"status": "PASS", "measurements": len(rows)}
        elif args.action == "select":
            output = select(catalog, rows)
        elif args.action == "status":
            output = state(catalog, rows)
        else:
            if not args.result:
                raise ContractError("record requires --result JSON")
            output = record(args.measurements, json.loads(args.result), catalog, rows)
        print(json.dumps(output, sort_keys=True))
        return 0 if output.get("status") != "BLOCK" else 2
    except (ContractError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "BLOCK", "reason": str(exc)}, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
