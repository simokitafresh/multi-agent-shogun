"""Tests for A2 insight-queue campaign adapter.

test_necessity: insight-queue auto-selection is limited to fix_known and
mechanical duplicate/superseded/already_fixed actions; design decisions,
production judgments, and human-value insights are blocked at the adapter.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_SKILL = _ROOT / "skills/campaign-lane"
if str(_SKILL) not in sys.path:
    sys.path.insert(0, str(_SKILL))

from adapters.insight_queue import (  # noqa: E402
    BlockedError,
    FingerprintError,
    select_candidates,
    verify_fingerprint,
    EXPECTED_FINGERPRINT,
)

SHA = "c" * 40


def insight(insight_id: str = "INS-001", action: str = "fix_known", priority: int = 5) -> dict:
    return {"insight_id": insight_id, "action": action, "priority": priority}


def test_fingerprint_matches_s0c():
    verify_fingerprint()


def test_fingerprint_mismatch_raises(monkeypatch):
    import adapters.insight_queue as mod

    monkeypatch.setattr(mod, "EXPECTED_FINGERPRINT", "0" * 64)
    with pytest.raises(FingerprintError):
        select_candidates([insight()], SHA)


def test_selects_fix_known():
    results = select_candidates([insight(action="fix_known")], SHA)
    assert len(results) == 1
    assert results[0]["reason_code"] == "auto_action_fix_known"
    assert results[0]["quality"] == "pass"


def test_selects_duplicate():
    results = select_candidates([insight(action="duplicate")], SHA)
    assert results[0]["reason_code"] == "auto_action_duplicate"


def test_selects_superseded():
    results = select_candidates([insight(action="superseded")], SHA)
    assert results[0]["reason_code"] == "auto_action_superseded"


def test_selects_already_fixed():
    results = select_candidates([insight(action="already_fixed")], SHA)
    assert results[0]["reason_code"] == "auto_action_already_fixed"


def test_blocks_design_decision():
    with pytest.raises(BlockedError, match="design_decision"):
        select_candidates([insight(action="design_decision")], SHA)


def test_blocks_production_decision():
    with pytest.raises(BlockedError, match="production_decision"):
        select_candidates([insight(action="production_decision")], SHA)


def test_blocks_value_judgment():
    with pytest.raises(BlockedError, match="value_judgment"):
        select_candidates([insight(action="value_judgment")], SHA)


def test_blocks_unknown_action():
    with pytest.raises(BlockedError, match="auto-select allowlist"):
        select_candidates([insight(action="unknown_action")], SHA)


def test_priority_order_preserved():
    insights = [
        insight("A", priority=1),
        insight("B", priority=10),
        insight("C", priority=5),
    ]
    results = select_candidates(insights, SHA)
    assert [r["candidate_id"] for r in results] == ["B", "C", "A"]


def test_empty_returns_empty():
    assert select_candidates([], SHA) == []


def test_contract_fingerprint_in_output():
    results = select_candidates([insight()], SHA)
    assert results[0]["contract_fingerprint"] == EXPECTED_FINGERPRINT
