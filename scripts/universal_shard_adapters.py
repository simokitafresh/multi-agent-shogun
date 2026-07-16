#!/usr/bin/env python3
"""Manifest adapters for the role-neutral universal shard core."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time
import fcntl

ROOT = Path(__file__).resolve().parents[1]
CORE_PATH = ROOT / "scripts" / "universal_shard.py"


def _load_core():
    spec = importlib.util.spec_from_file_location("universal_shard", CORE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def available_workers(item_count, requested=None, heavy=False):
    detected = os.cpu_count() or 1
    limit = requested if requested is not None else detected
    count = min(item_count, detected, limit)
    if count < 2:
        raise ValueError("N<2: adapter requires at least two items and workers")
    rows = [{"id": f"local-{i}", "idle": True, "capabilities": ["local"]}
            for i in range(count)]
    if heavy:
        rows[0]["capabilities"].append("heavy")
    return rows


HEAVY_TESTS = {"test_cmd_complete_gate_small_consolidated.bats", "test_cmd_quality_memory_db.bats",
               "test_cmd_save_diagnosis_quality.bats", "test_cmd_save_warn_logging.bats",
               "test_insight_write.bats", "test_session_state_hooks.bats", "test_three_layer_preflight.bats",
               "test_gunshi_log_append_obs.bats", "test_ninja_monitor_stall.bats", "test_hook_dispatchers.bats",
               "test_statusline.bats", "test_sqlite3_cli_removal.bats", "test_small_workflow_consolidated.bats",
               "test_skill_recommend_metrics.bats"}


def timing_weights(path):
    ledger = Path(path)
    if not ledger.is_file(): return {}
    rows = ledger.read_text(errors="replace").splitlines()[1:]
    parsed = [line.split("\t") for line in rows]
    valid = [r for r in parsed if len(r) == 14 and r[8] == "pass" and r[10] == "0"]
    if not valid: return {}
    groups = {}
    for row in valid: groups.setdefault(row[0], []).append(row)
    # File ledger batches are published only after a completed suite and under
    # one lock, so the newest measured_at cohort is complete.  Choosing the
    # largest cohort instead resurrects an older all-mode run after the suite
    # grows and feeds stale, inflated weights into the new planner.
    complete_floor = max(len(rows) for rows in groups.values()) * .9
    complete = [rows for rows in groups.values() if len(rows) >= complete_floor]
    chosen = max(complete, key=lambda rows: rows[0][12])
    return {str(Path(r[5]).resolve()): float(r[7]) for r in chosen}


def _items(paths, source_fingerprint="", weights=None, kind="research"):
    weights = weights or {}
    result = []
    for raw in paths:
        path = Path(raw).resolve()
        if not path.exists():
            raise ValueError(f"adapter item does not exist: {path}")
        stat = path.stat()
        result.append({"id": hashlib.sha256(str(path).encode()).hexdigest()[:16],
                       "path": str(path), "weight": max(.001, weights.get(str(path), stat.st_size)),
                       "capability": "heavy" if kind == "test" and path.name in HEAVY_TESTS else "local",
                       "source_fingerprint": source_fingerprint})
    return result


def manifest(kind, paths, state_dir, workers=None, command=None,
             source_fingerprint="", timeout=900, timing_ledger=None):
    weights = timing_weights(timing_ledger) if timing_ledger else {}
    items = _items(paths, source_fingerprint, weights, kind)
    worker_rows = available_workers(len(items), workers, any(x["capability"] == "heavy" for x in items))
    if kind == "test":
        command = (f"timeout --foreground --kill-after=10s {int(timeout)}s "
                   f"env SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_JOBS=1 BATS_CACHE=0 "
                   f"bash {shlex.quote(str(ROOT / 'scripts/run_tests.sh'))} file {{item_path}}")
    elif kind == "research":
        command = command or "sha256sum {item_path} > {output_dir}/result"
    elif kind == "transform":
        if not command:
            raise ValueError("transform adapter requires --command")
    else:
        raise ValueError(f"unknown adapter: {kind}")
    return {"adapter": kind, "max_workers": len(worker_rows),
            "state_dir": str(Path(state_dir).resolve()), "timeout": timeout,
            "command": command, "workers": worker_rows, "items": items}


def run_adapter(kind, paths, state_dir, workers=None, command=None,
                source_fingerprint="", timeout=900, timing_ledger=None):
    core = _load_core()
    data = manifest(kind, paths, state_dir, workers, command,
                    source_fingerprint, timeout, timing_ledger)
    started = time.monotonic()
    out = core.run(data)
    out["suite_wall_sec"] = round(time.monotonic() - started, 6)
    out["sum_file_sec"] = round(sum(x["elapsed_sec"] for x in out["results"]), 6)
    out["adapter"] = kind
    out["source_items"] = len(paths)
    return out


def record_suite(path, out, mode, fingerprint):
    ledger = Path(path); ledger.parent.mkdir(parents=True, exist_ok=True)
    header = "measured_at\tmode\tsuite_wall_sec\tsum_file_sec\titem_count\tstatus\tsource_fingerprint\n"
    with ledger.open("a+") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX); fh.seek(0, 2)
        if fh.tell() == 0: fh.write(header)
        status = "pass" if not any(out["counts"][x] for x in ("fail","skip","timeout","cancel")) else "fail"
        fh.write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\t{mode}\t{out['suite_wall_sec']:.3f}\t{out['sum_file_sec']:.3f}\t{out['actual']}\t{status}\t{fingerprint}\n")
        fh.flush(); os.fsync(fh.fileno()); fcntl.flock(fh, fcntl.LOCK_UN)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("test", "research", "transform"))
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--workers", type=int)
    parser.add_argument("--command")
    parser.add_argument("--source-fingerprint", default="")
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("--timing-ledger")
    parser.add_argument("--suite-ledger")
    args = parser.parse_args()
    try:
        out = run_adapter(args.kind, args.paths, args.state_dir, args.workers,
                          args.command, args.source_fingerprint, args.timeout, args.timing_ledger)
        if args.suite_ledger:
            record_suite(args.suite_ledger, out, args.kind, args.source_fingerprint)
        print(json.dumps(out, indent=2, sort_keys=True))
        return 0 if not any(out["counts"][x] for x in ("fail", "skip", "timeout", "cancel")) else 1
    except (ValueError, RuntimeError, KeyError) as exc:
        print(f"BLOCK: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
