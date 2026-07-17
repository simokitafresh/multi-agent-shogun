#!/usr/bin/env python3
"""Frozen contracts shared by campaign-lane residual shards."""
from __future__ import annotations

import hashlib
import json
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


def contract_fingerprint() -> str:
    payload = {"adapter": ADAPTER_SCHEMA, "outcome": OUTCOME_SCHEMA, "version": 1}
    return hashlib.sha256(canonical_json(payload).encode()).hexdigest()

