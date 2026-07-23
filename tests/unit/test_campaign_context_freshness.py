"""Tests for A1 context-freshness campaign adapter.

test_necessity: context-freshness candidates are returned only when stale
is reproducible with CONTEXT_CACHE_BYPASS=1 and a unique source-commit/path
mapping exists; ambiguous mappings are blocked at the adapter boundary.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_SKILL = _ROOT / "skills/campaign-lane"
if str(_SKILL) not in sys.path:
    sys.path.insert(0, str(_SKILL))

from adapters.context_freshness import (  # noqa: E402
    BlockedError,
    FingerprintError,
    select_candidates,
    verify_fingerprint,
    EXPECTED_FINGERPRINT,
)

SHA = "b" * 40


def entry(context_path: str = "context/foo.md", source_commit: str = "abc123", stale_source_count: int = 1) -> dict:
    return {
        "context_path": context_path,
        "source_commit": source_commit,
        "stale_source_count": stale_source_count,
    }


def test_fingerprint_matches_s0c():
    verify_fingerprint()  # must not raise


def test_fingerprint_mismatch_raises(monkeypatch):
    import adapters.context_freshness as mod

    monkeypatch.setattr(mod, "EXPECTED_FINGERPRINT", "0" * 64)
    with pytest.raises(FingerprintError):
        select_candidates([entry()], SHA)


def test_selects_stale_entry():
    results = select_candidates([entry(stale_source_count=2)], SHA)
    assert len(results) == 1
    assert results[0]["candidate_id"] == "context/foo.md"
    assert results[0]["quality"] == "pass"
    assert results[0]["lane_id"] == "context-freshness"
    assert "stale_source_count_2" in results[0]["reason_code"]


def test_skips_fresh_entry():
    results = select_candidates([entry(stale_source_count=0)], SHA)
    assert results == []


def test_blocks_ambiguous_source_mapping():
    ambiguous = {
        "context_path": "context/bar.md",
        "source_commits": ["sha1", "sha2"],
        "stale_source_count": 3,
    }
    with pytest.raises(BlockedError, match="ambiguous source mapping"):
        select_candidates([ambiguous], SHA)


def test_blocks_empty_source_commits():
    no_commits = {
        "context_path": "context/baz.md",
        "source_commits": [],
        "stale_source_count": 1,
    }
    with pytest.raises(BlockedError):
        select_candidates([no_commits], SHA)


def test_empty_input_returns_empty():
    assert select_candidates([], SHA) == []


def test_contract_fingerprint_in_output():
    results = select_candidates([entry()], SHA)
    assert results[0]["contract_fingerprint"] == EXPECTED_FINGERPRINT


def test_mixed_fresh_and_stale():
    entries = [
        entry("context/a.md", stale_source_count=2),
        entry("context/b.md", stale_source_count=0),
        entry("context/c.md", stale_source_count=1),
    ]
    results = select_candidates(entries, SHA)
    assert len(results) == 2
    ids = {r["candidate_id"] for r in results}
    assert "context/a.md" in ids and "context/c.md" in ids
    assert "context/b.md" not in ids
