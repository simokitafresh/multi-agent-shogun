"""Tests for I1 inbox-drain campaign adapter.

test_necessity: inbox drain candidates are selected only when the dominant
drain phase is not review_wait_ms, and candidate data passes the S0c contract
fingerprint check; review_wait_ms-dominant episodes are blocked as a different
lane concern.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_SKILL = _ROOT / "skills/campaign-lane"
if str(_SKILL) not in sys.path:
    sys.path.insert(0, str(_SKILL))

from adapters.inbox_drain import (  # noqa: E402
    BlockedError,
    FingerprintError,
    select_candidates,
    verify_fingerprint,
    EXPECTED_FINGERPRINT,
)
from scripts.contracts import contract_fingerprint  # noqa: E402

SHA = "a" * 40


def ep(episode_id: str = "ep1", **overrides) -> dict:
    base = {
        "episode_id": episode_id,
        "read_ms": 100,
        "triage_ms": 50,
        "ack_ms": 200,
        "review_wait_ms": 10,
        "loss_count": 0,
        "wrong_ack_count": 0,
        "duplicate_execution_count": 0,
    }
    base.update(overrides)
    return base


def test_fingerprint_matches_s0c():
    assert contract_fingerprint() == EXPECTED_FINGERPRINT
    verify_fingerprint()  # must not raise


def test_fingerprint_mismatch_raises(monkeypatch):
    import adapters.inbox_drain as mod

    monkeypatch.setattr(mod, "EXPECTED_FINGERPRINT", "0" * 64)
    with pytest.raises(FingerprintError):
        select_candidates([ep()], SHA)


def test_selects_ack_dominant_episode():
    results = select_candidates([ep(ack_ms=500, read_ms=10, triage_ms=10, review_wait_ms=5)], SHA)
    assert len(results) == 1
    assert results[0]["reason_code"] == "dominant_phase_ack_ms"
    assert results[0]["quality"] == "pass"
    assert results[0]["lane_id"] == "inbox-drain"


def test_blocks_review_wait_dominant():
    episode = ep(review_wait_ms=1000, read_ms=10, triage_ms=10, ack_ms=10)
    with pytest.raises(BlockedError, match="review_wait_ms"):
        select_candidates([episode], SHA)


def test_quality_fail_on_loss():
    results = select_candidates([ep(loss_count=1)], SHA)
    assert results[0]["quality"] == "fail"
    assert "loss_or_dup" in results[0]["reason_code"]


def test_quality_fail_on_wrong_ack():
    results = select_candidates([ep(wrong_ack_count=2)], SHA)
    assert results[0]["quality"] == "fail"


def test_quality_fail_on_duplicate_execution():
    results = select_candidates([ep(duplicate_execution_count=1)], SHA)
    assert results[0]["quality"] == "fail"


def test_measurement_missing_when_no_phase_data():
    episode = {"episode_id": "ep_empty", "loss_count": 0, "wrong_ack_count": 0, "duplicate_execution_count": 0}
    results = select_candidates([episode], SHA)
    assert results[0]["quality"] == "measurement_missing"
    assert results[0]["reason_code"] == "no_phase_data"


def test_empty_episodes_returns_empty():
    assert select_candidates([], SHA) == []


def test_contract_fingerprint_in_output():
    results = select_candidates([ep()], SHA)
    assert results[0]["contract_fingerprint"] == EXPECTED_FINGERPRINT


def test_multiple_episodes_mixed():
    episodes = [
        ep("a", ack_ms=300, read_ms=10, triage_ms=10, review_wait_ms=5),
        ep("b", loss_count=1),
    ]
    results = select_candidates(episodes, SHA)
    assert len(results) == 2
    ids = {r["candidate_id"] for r in results}
    assert "a" in ids and "b" in ids
