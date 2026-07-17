#!/usr/bin/env python3
"""Deterministic validation/normalization for campaign adapters."""
from __future__ import annotations

from .contracts import ADAPTER_SCHEMA, canonical_json, contract_fingerprint


class AdapterContractError(ValueError):
    pass


def normalize_candidate(candidate: dict) -> dict:
    missing = [key for key in ADAPTER_SCHEMA["required"] if candidate.get(key) in (None, "")]
    if missing:
        raise AdapterContractError(f"missing adapter fields: {','.join(missing)}")
    if candidate["objective"] not in ADAPTER_SCHEMA["objective"]:
        raise AdapterContractError("invalid objective")
    if candidate["quality"] not in {"pass", "fail", "measurement_missing"}:
        raise AdapterContractError("invalid quality")
    normalized = dict(candidate)
    normalized["contract_fingerprint"] = contract_fingerprint()
    return normalized


def serialize_candidate(candidate: dict) -> str:
    return canonical_json(normalize_candidate(candidate))

