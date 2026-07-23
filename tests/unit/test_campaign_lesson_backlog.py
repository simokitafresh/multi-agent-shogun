"""Tests for A3 lesson-backlog campaign adapter.

test_necessity: lesson-backlog auto-selection is limited to origin-missing,
exact-duplicate, superseded_by-confirmed, and mechanical-merge entries;
content correctness, permanent-rule changes, and deprecation decisions are
blocked at the adapter boundary.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_SKILL = _ROOT / "skills/campaign-lane"
if str(_SKILL) not in sys.path:
    sys.path.insert(0, str(_SKILL))

from adapters.lesson_backlog import (  # noqa: E402
    BlockedError,
    FingerprintError,
    select_candidates,
    verify_fingerprint,
    EXPECTED_FINGERPRINT,
)

SHA = "d" * 40


def lesson(lesson_id: str = "L001", reason: str = "origin_missing") -> dict:
    return {"lesson_id": lesson_id, "reason": reason}


def test_fingerprint_matches_s0c():
    verify_fingerprint()


def test_fingerprint_mismatch_raises(monkeypatch):
    import adapters.lesson_backlog as mod

    monkeypatch.setattr(mod, "EXPECTED_FINGERPRINT", "0" * 64)
    with pytest.raises(FingerprintError):
        select_candidates([lesson()], SHA)


def test_selects_origin_missing():
    results = select_candidates([lesson(reason="origin_missing")], SHA)
    assert len(results) == 1
    assert results[0]["reason_code"] == "origin_missing"
    assert results[0]["quality"] == "pass"


def test_selects_exact_duplicate():
    results = select_candidates([lesson(reason="exact_duplicate")], SHA)
    assert results[0]["reason_code"] == "exact_duplicate"


def test_selects_superseded_by_confirmed():
    results = select_candidates([lesson(reason="superseded_by_confirmed")], SHA)
    assert results[0]["reason_code"] == "superseded_by_confirmed"


def test_selects_mechanical_merge():
    results = select_candidates([lesson(reason="mechanical_merge")], SHA)
    assert results[0]["reason_code"] == "mechanical_merge"


def test_blocks_content_correctness():
    with pytest.raises(BlockedError, match="content_correctness"):
        select_candidates([lesson(reason="content_correctness")], SHA)


def test_blocks_permanent_rule():
    with pytest.raises(BlockedError, match="permanent_rule"):
        select_candidates([lesson(reason="permanent_rule")], SHA)


def test_blocks_deprecation():
    with pytest.raises(BlockedError, match="deprecation"):
        select_candidates([lesson(reason="deprecation")], SHA)


def test_blocks_unknown_reason():
    with pytest.raises(BlockedError, match="auto-select allowlist"):
        select_candidates([lesson(reason="custom_reason")], SHA)


def test_empty_returns_empty():
    assert select_candidates([], SHA) == []


def test_contract_fingerprint_in_output():
    results = select_candidates([lesson()], SHA)
    assert results[0]["contract_fingerprint"] == EXPECTED_FINGERPRINT


def test_multiple_lessons():
    lessons = [
        lesson("L001", "origin_missing"),
        lesson("L002", "exact_duplicate"),
        lesson("L003", "superseded_by_confirmed"),
    ]
    results = select_candidates(lessons, SHA)
    assert len(results) == 3
    ids = {r["candidate_id"] for r in results}
    assert ids == {"L001", "L002", "L003"}
