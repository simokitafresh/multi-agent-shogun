"""Tests for A4 memory-candidates campaign adapter.

test_necessity: memory candidate auto-selection is limited to hash-identical
duplicates, known-conflict-key matches, and mechanical Obsidian link additions;
semantic promotion, preference judgments, and partial-layer completions are
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

from adapters.memory_candidates import (  # noqa: E402
    BlockedError,
    FingerprintError,
    select_candidates,
    verify_fingerprint,
    EXPECTED_FINGERPRINT,
)

SHA = "e" * 40


def item(item_id: str = "MEM-001", reason: str = "hash_identical_duplicate", layers_completed: int = 3) -> dict:
    return {"item_id": item_id, "reason": reason, "layers_completed": layers_completed}


def test_fingerprint_matches_s0c():
    verify_fingerprint()


def test_fingerprint_mismatch_raises(monkeypatch):
    import adapters.memory_candidates as mod

    monkeypatch.setattr(mod, "EXPECTED_FINGERPRINT", "0" * 64)
    with pytest.raises(FingerprintError):
        select_candidates([item()], SHA)


def test_selects_hash_identical_duplicate():
    results = select_candidates([item(reason="hash_identical_duplicate")], SHA)
    assert len(results) == 1
    assert results[0]["reason_code"] == "hash_identical_duplicate"
    assert results[0]["quality"] == "pass"


def test_selects_known_conflict_key():
    results = select_candidates([item(reason="known_conflict_key")], SHA)
    assert results[0]["reason_code"] == "known_conflict_key"


def test_selects_obsidian_link_missing():
    results = select_candidates([item(reason="obsidian_link_missing")], SHA)
    assert results[0]["reason_code"] == "obsidian_link_missing"


def test_blocks_semantic_promotion():
    with pytest.raises(BlockedError, match="semantic_promotion"):
        select_candidates([item(reason="semantic_promotion")], SHA)


def test_blocks_preference_judgment():
    with pytest.raises(BlockedError, match="preference_judgment"):
        select_candidates([item(reason="preference_judgment")], SHA)


def test_blocks_value_assessment():
    with pytest.raises(BlockedError, match="value_assessment"):
        select_candidates([item(reason="value_assessment")], SHA)


def test_blocks_unknown_reason():
    with pytest.raises(BlockedError, match="auto-select allowlist"):
        select_candidates([item(reason="arbitrary")], SHA)


def test_partial_layer_success_is_quality_fail():
    for layers in (1, 2):
        results = select_candidates([item(layers_completed=layers)], SHA)
        assert results[0]["quality"] == "fail"
        assert f"partial_layer_success_{layers}_of_3" in results[0]["reason_code"]


def test_full_three_layers_is_pass():
    results = select_candidates([item(layers_completed=3)], SHA)
    assert results[0]["quality"] == "pass"


def test_empty_returns_empty():
    assert select_candidates([], SHA) == []


def test_contract_fingerprint_in_output():
    results = select_candidates([item()], SHA)
    assert results[0]["contract_fingerprint"] == EXPECTED_FINGERPRINT
