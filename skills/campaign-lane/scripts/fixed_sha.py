#!/usr/bin/env python3
"""Fail-closed fixed-SHA checkpoint contract."""
from __future__ import annotations

import re


class CheckpointError(ValueError):
    pass


def checkpoint(candidate_sha: str, observed: dict) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", candidate_sha):
        raise CheckpointError("candidate SHA must be full lowercase SHA")
    required = ["head_sha", "dirty", "target_fail", "target_skip", "full_fail", "full_skip", "ci_head_sha", "ci_run_id", "ci_conclusion", "required_jobs"]
    missing = [key for key in required if key not in observed]
    if missing:
        raise CheckpointError(f"missing checkpoint evidence: {','.join(missing)}")
    if observed["dirty"] is not False:
        raise CheckpointError("dirty worktree")
    if observed["head_sha"] != candidate_sha:
        raise CheckpointError("wrong checkout SHA")
    if any(observed[key] != 0 for key in ("target_fail", "target_skip", "full_fail", "full_skip")):
        raise CheckpointError("tests require FAIL0 SKIP0")
    if observed["ci_head_sha"] != candidate_sha:
        raise CheckpointError("CI headSha mismatch")
    if observed["ci_conclusion"] != "success" or not observed["required_jobs"] or any(job.get("conclusion") != "success" for job in observed["required_jobs"]):
        raise CheckpointError("required CI is not GREEN")
    return {"status": "ready", "fixed_sha": candidate_sha, "target_result": "PASS", "full_result": "PASS", "skip_count": 0, "ci_run_id": observed["ci_run_id"], "ci_conclusion": "success"}

