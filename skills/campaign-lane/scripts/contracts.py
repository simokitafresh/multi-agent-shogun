#!/usr/bin/env python3
"""Frozen contracts shared by campaign-lane residual shards."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


OUTCOME_SCHEMA = {
    "required": ["lane_id", "candidate_id", "round", "selected_at", "baseline", "after", "objective", "quality", "decision", "reason_code", "fixed_sha", "ci_run_id"],
    "decision": ["accepted", "rejected", "rolled_back", "blocked"],
    "key": ["lane_id", "candidate_id", "round"],
}
ADAPTER_SCHEMA = {
    "required": ["lane_id", "candidate_id", "objective", "source_sha", "quality", "reason_code"],
    "objective": ["minimize", "maximize", "target"],
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def _file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contract_fingerprint() -> str:
    scripts = Path(__file__).resolve().parent
    payload = {
        "adapter": ADAPTER_SCHEMA,
        "outcome": OUTCOME_SCHEMA,
        "version": 1,
        "helper_sha": _file_sha256(scripts / "outcome_ledger.py"),
        "sdk_sha": _file_sha256(scripts / "adapter_sdk.py"),
    }
    return hashlib.sha256(canonical_json(payload).encode()).hexdigest()
