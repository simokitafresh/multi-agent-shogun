"""Tests for T1 pytest-live campaign adapter.

test_necessity: pytest-live candidates are selected only when the node shows
measurable timing regression against the p50/p95 baseline and the expectation
contract is not relaxed; adversarial rounds (FAIL/SKIP/degradation) must not
be adopted, and the same nodeid must not appear in two consecutive rounds.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_SKILL = _ROOT / "skills/campaign-lane"
if str(_SKILL) not in sys.path:
    sys.path.insert(0, str(_SKILL))

from adapters.pytest_live import (  # noqa: E402
    BlockedError,
    FingerprintError,
    select_candidates,
    verify_fingerprint,
    EXPECTED_FINGERPRINT,
)

SHA = "f" * 40


def node(
    nodeid: str = "tests/test_foo.py::test_bar",
    status: str = "pass",
    p50_ms: float = 200.0,
    p95_ms: float = 300.0,
    baseline_p50_ms: float = 100.0,
    baseline_p95_ms: float = 250.0,
) -> dict:
    return {
        "nodeid": nodeid,
        "status": status,
        "p50_ms": p50_ms,
        "p95_ms": p95_ms,
        "baseline_p50_ms": baseline_p50_ms,
        "baseline_p95_ms": baseline_p95_ms,
    }


def test_fingerprint_matches_s0c():
    verify_fingerprint()


def test_fingerprint_mismatch_raises(monkeypatch):
    import adapters.pytest_live as mod

    monkeypatch.setattr(mod, "EXPECTED_FINGERPRINT", "0" * 64)
    with pytest.raises(FingerprintError):
        select_candidates([node()], SHA)


def test_selects_slow_node_above_baseline():
    # p50=200 > baseline_p50=100, p95=300 > baseline_p95=250 → slow node, select.
    results = select_candidates([node()], SHA)
    assert len(results) == 1
    assert results[0]["reason_code"] == "p50_or_p95_above_baseline"
    assert results[0]["quality"] == "pass"


def test_skips_node_at_or_below_baseline():
    # p50=90 <= baseline 100, p95=230 <= baseline 250 — no regression, correct stop.
    results = select_candidates(
        [node(p50_ms=90.0, p95_ms=230.0, baseline_p50_ms=100.0, baseline_p95_ms=250.0)],
        SHA,
    )
    assert results == []


def test_blocks_expectation_relaxed_flag():
    # expectation_relaxed=True — raising the baseline is not an optimisation.
    n = {
        "nodeid": "tests/test_foo.py::test_bar",
        "status": "pass",
        "p50_ms": 200.0,
        "p95_ms": 300.0,
        "baseline_p50_ms": 100.0,
        "baseline_p95_ms": 250.0,
        "expectation_relaxed": True,
    }
    with pytest.raises(BlockedError, match="expectation was manually relaxed"):
        select_candidates([n], SHA)


def test_fail_status_produces_quality_fail():
    results = select_candidates([node(status="fail")], SHA)
    assert results[0]["quality"] == "fail"
    assert "adversarial_round_fail" in results[0]["reason_code"]


def test_skip_status_produces_quality_fail():
    results = select_candidates([node(status="skip")], SHA)
    assert results[0]["quality"] == "fail"


def test_skips_previous_round_nodeid():
    results = select_candidates(
        [node("tests/test_foo.py::test_bar")],
        SHA,
        previous_nodeids=["tests/test_foo.py::test_bar"],
    )
    assert results == []


def test_different_nodeid_from_previous_is_selected():
    results = select_candidates(
        [node("tests/test_foo.py::test_baz")],
        SHA,
        previous_nodeids=["tests/test_foo.py::test_bar"],
    )
    assert len(results) == 1
    assert results[0]["reason_code"] == "p50_or_p95_above_baseline"


def test_measurement_missing_when_no_baseline():
    n = {"nodeid": "tests/test_x.py::test_y", "status": "pass", "p50_ms": 100.0, "p95_ms": 200.0}
    results = select_candidates([n], SHA)
    assert results[0]["quality"] == "measurement_missing"


def test_empty_returns_empty():
    assert select_candidates([], SHA) == []


def test_contract_fingerprint_in_output():
    results = select_candidates([node()], SHA)
    assert results[0]["contract_fingerprint"] == EXPECTED_FINGERPRINT
