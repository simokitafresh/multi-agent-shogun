"""Acceptance-criteria identity normalization shared by deploy and gates."""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Any


def criterion_ids(task: Mapping[str, Any]) -> list[str]:
    raw = task.get("acceptance_criteria") or []
    ids: list[str] = []
    if isinstance(raw, Mapping):
        for position, (key, value) in enumerate(raw.items(), 1):
            ac_id = str(key).strip() or f"AC{position}"
            if isinstance(value, Mapping):
                ac_id = str(value.get("id") or ac_id).strip()
            ids.append(ac_id)
    elif isinstance(raw, list):
        for position, value in enumerate(raw, 1):
            ac_id = f"AC{position}"
            if isinstance(value, Mapping):
                ac_id = str(value.get("id") or ac_id).strip()
                legacy = str(value.get("ac") or "").strip()
                if re.match(r"^AC[\w-]+\s*:", legacy):
                    ac_id = legacy.split(":", 1)[0].strip()
            ids.append(ac_id)
    return ids


def assigned_tokens(task: Mapping[str, Any]) -> list[str]:
    raw = task.get("assigned_acs") or task.get("ac_assigned") or []
    if isinstance(raw, str):
        return [
            token
            for token in re.split(r"[\s,|]+", raw.strip().strip("[]"))
            if token
        ]
    if isinstance(raw, list):
        return [str(token).strip() for token in raw if str(token).strip()]
    return []


def canonical_assigned_ids(task: Mapping[str, Any]) -> set[str]:
    """Map legacy positional AC1/AC2 aliases onto explicit IDs such as R1/R2."""
    ids = criterion_ids(task)
    exact = set(ids)
    result: set[str] = set()
    for token in assigned_tokens(task):
        if token in exact:
            result.add(token)
            continue
        match = re.fullmatch(r"AC([1-9][0-9]*)", token, re.IGNORECASE)
        if match:
            index = int(match.group(1)) - 1
            if index < len(ids):
                result.add(ids[index])
    return result
