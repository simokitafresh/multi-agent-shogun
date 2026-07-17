from __future__ import annotations

import json
import multiprocessing
import subprocess
from pathlib import Path

import pytest

from scripts.adapter_sdk import serialize_candidate
from scripts.contracts import contract_fingerprint
from scripts.fixed_sha import CheckpointError, checkpoint
from scripts.materialize import MaterializeError, materialize
from scripts.outcome_ledger import OutcomeContractError, append_outcome


SHA = "a" * 40


def evidence(**changes):
    value = {"head_sha": SHA, "dirty": False, "target_fail": 0, "target_skip": 0, "full_fail": 0, "full_skip": 0, "ci_head_sha": SHA, "ci_run_id": 7, "ci_conclusion": "success", "required_jobs": [{"name": "test", "conclusion": "success"}]}
    value.update(changes)
    return value


@pytest.mark.parametrize("changes", [{"dirty": True}, {"head_sha": "b" * 40}, {"target_skip": 1}, {"ci_head_sha": "b" * 40}])
def test_fixed_sha_blocks_adversarial_evidence(changes):
    with pytest.raises(CheckpointError):
        checkpoint(SHA, evidence(**changes))


def test_fixed_sha_accepts_only_complete_green():
    assert checkpoint(SHA, evidence())["status"] == "ready"


def outcome(candidate):
    return {"lane_id": "lane", "candidate_id": candidate, "round": 1, "selected_at": "2026-07-17T00:00:00Z", "baseline": 2, "after": 1, "objective": "minimize", "quality": "pass", "decision": "accepted", "reason_code": "improved", "fixed_sha": SHA, "ci_run_id": 7}


def _append(path, candidate):
    append_outcome(path, outcome(candidate))


def test_outcome_duplicate_blocked(tmp_path):
    ledger = tmp_path / "outcomes.jsonl"
    append_outcome(ledger, outcome("same"))
    with pytest.raises(OutcomeContractError):
        append_outcome(ledger, outcome("same"))


def test_outcome_parallel_write_loss_zero(tmp_path):
    ledger = tmp_path / "outcomes.jsonl"
    processes = [multiprocessing.Process(target=_append, args=(ledger, str(index))) for index in range(16)]
    for process in processes: process.start()
    for process in processes: process.join()
    assert all(process.exitcode == 0 for process in processes)
    rows = [json.loads(line) for line in ledger.read_text().splitlines()]
    assert len(rows) == len({row["candidate_id"] for row in rows}) == 16


def test_adapter_schema_and_fingerprint_are_deterministic():
    candidate = {"lane_id": "x", "candidate_id": "y", "objective": "minimize", "source_sha": SHA, "quality": "pass", "reason_code": "ready"}
    assert serialize_candidate(candidate) == serialize_candidate(dict(reversed(list(candidate.items()))))
    assert len(contract_fingerprint()) == 64


def test_materialize_exact_sha_and_fail_closed(tmp_path):
    source = tmp_path / "source"
    source.mkdir()
    subprocess.run(["git", "init", "-q", str(source)], check=True)
    subprocess.run(["git", "-C", str(source), "config", "user.email", "test@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(source), "config", "user.name", "test"], check=True)
    (source / "tracked").write_text("ok")
    subprocess.run(["git", "-C", str(source), "add", "tracked"], check=True)
    subprocess.run(["git", "-C", str(source), "commit", "-qm", "fixture"], check=True)
    sha = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    result = materialize(source, tmp_path / "clone", sha)
    assert result == {"status": "success", "fixed_sha": sha, "dirty": 0}
    with pytest.raises(MaterializeError):
        materialize(source, tmp_path / "bad", "f" * 40)
