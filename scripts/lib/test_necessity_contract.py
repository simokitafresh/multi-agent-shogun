#!/usr/bin/env python3
"""Canonical persistent-test necessity contract.

Deployment, report review, and the commit boundary must classify the same
declaration identically.  Callers supply the actual new-test paths; this module
owns normalization and validation only.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any


def normalize_entries(
    raw: Any, candidate_paths: Sequence[str]
) -> list[dict[str, Any]]:
    candidates = [str(path).strip() for path in candidate_paths if str(path).strip()]
    if isinstance(raw, list):
        return [dict(entry) for entry in raw if isinstance(entry, Mapping)]
    if isinstance(raw, Mapping) and len(candidates) == 1:
        entry = dict(raw)
        entry.setdefault("path", candidates[0])
        return [entry]
    return []


def validate_entries(
    raw: Any, candidate_paths: Sequence[str]
) -> tuple[set[str], list[str]]:
    candidates = {str(path).strip() for path in candidate_paths if str(path).strip()}
    entries = normalize_entries(raw, sorted(candidates))
    by_path = {
        str(entry.get("path", "")).strip(): entry
        for entry in entries
        if str(entry.get("path", "")).strip()
    }
    errors: list[str] = []

    for path, entry in by_path.items():
        if path not in candidates:
            errors.append(f"test_necessity path is not an actual new test: {path}")
            continue
        target = str(entry.get("defense_target", "")).strip()
        evidence = str(entry.get("overlap_evidence", "")).strip()
        if not target or "\n" in target:
            errors.append(f"{path}: defense_target must be one non-empty line")
        if not evidence or "\n" in evidence:
            errors.append(f"{path}: overlap_evidence must be one non-empty line")

        overlap = entry.get("overlaps_existing")
        regression = str(entry.get("regression_justification", "")).strip()
        if overlap is True:
            if not regression or "\n" in regression or len(regression) < 12:
                errors.append(
                    f"{path}: overlaps_existing=true requires one-line "
                    "regression_justification"
                )
        elif overlap is not False:
            errors.append(f"{path}: overlaps_existing must be false or justified true")

        for key in ("fixture_self_reference", "deprecated_mechanism"):
            if entry.get(key) is not False:
                errors.append(f"{path}: {key} must be false")

    return set(by_path) & candidates, errors
