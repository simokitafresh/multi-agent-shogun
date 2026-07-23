"""T1 pytest-live adapter — selects slow pytest nodes for speed improvement.

test_necessity: pytest-live candidates are selected only when the node shows
measurable timing regression against the p50/p95 baseline and the expectation
contract is not relaxed; adversarial rounds (FAIL/SKIP/degradation) must not
be adopted, and the same nodeid must not appear in two consecutive rounds.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

_SKILL_ROOT = Path(__file__).resolve().parent.parent
if str(_SKILL_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILL_ROOT))

from scripts.contracts import contract_fingerprint  # noqa: E402
from scripts.adapter_sdk import normalize_candidate  # noqa: E402

LANE_ID = "pytest-live"
EXPECTED_FINGERPRINT = "5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5"

# Maximum consecutive rounds for a single nodeid.
_MAX_SAME_NODE_ROUNDS = 1


class FingerprintError(ValueError):
    pass


class BlockedError(ValueError):
    pass


def verify_fingerprint() -> None:
    actual = contract_fingerprint()
    if actual != EXPECTED_FINGERPRINT:
        raise FingerprintError(
            f"contract fingerprint mismatch: expected {EXPECTED_FINGERPRINT} got {actual}"
        )


def select_candidates(
    nodes: list[dict[str, Any]],
    source_sha: str,
    previous_nodeids: list[str] | None = None,
) -> list[dict]:
    """Return adapter candidates for pytest live-chain speed improvement.

    Each node must have: nodeid, p50_ms, p95_ms, baseline_p50_ms, baseline_p95_ms.
    Nodes with FAIL or SKIP status produce quality=fail (adversarial round marker).
    Nodes where the expectation was manually relaxed (expectation_relaxed=True) are
    blocked — relaxing a threshold is not an improvement.
    Nodes that appeared in the previous round are skipped (different nodeid required).
    Nodes at or below baseline on both p50 and p95 are skipped (no regression to fix).
    Remaining nodes with p50 or p95 above baseline are slow candidates for optimisation.
    """
    verify_fingerprint()

    prev = set(previous_nodeids or [])
    candidates = []

    for node in nodes:
        nodeid = node.get("nodeid", "")
        status = node.get("status", "pass")
        p50 = node.get("p50_ms")
        p95 = node.get("p95_ms")
        base_p50 = node.get("baseline_p50_ms")
        base_p95 = node.get("baseline_p95_ms")
        expectation_relaxed = node.get("expectation_relaxed", False)

        if status in ("fail", "skip", "error"):
            candidate = {
                "lane_id": LANE_ID,
                "candidate_id": nodeid,
                "objective": "minimize",
                "source_sha": source_sha,
                "quality": "fail",
                "reason_code": f"adversarial_round_{status}",
            }
            candidates.append(normalize_candidate(candidate))
            continue

        if expectation_relaxed:
            raise BlockedError(
                f"nodeid {nodeid}: expectation was manually relaxed; "
                "raising the baseline is not an optimisation"
            )

        if nodeid in prev:
            # Same nodeid as previous round — require different nodeid across rounds.
            continue

        if None in (p50, p95, base_p50, base_p95):
            candidate = {
                "lane_id": LANE_ID,
                "candidate_id": nodeid,
                "objective": "minimize",
                "source_sha": source_sha,
                "quality": "measurement_missing",
                "reason_code": "baseline_unavailable",
            }
            candidates.append(normalize_candidate(candidate))
            continue

        if p50 <= base_p50 and p95 <= base_p95:
            # Already at or below baseline on both axes — correct normal stop.
            continue

        candidate = {
            "lane_id": LANE_ID,
            "candidate_id": nodeid,
            "objective": "minimize",
            "source_sha": source_sha,
            "quality": "pass",
            "reason_code": "p50_or_p95_above_baseline",
        }
        candidates.append(normalize_candidate(candidate))

    return candidates


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="T1 pytest-live adapter")
    parser.add_argument("nodes_json", help="Path to JSON file with pytest node list")
    parser.add_argument("source_sha", help="Fixed source SHA for this run")
    parser.add_argument("--previous-nodeids", default="", help="Comma-separated previous round nodeids")
    args = parser.parse_args(argv)
    try:
        nodes = json.loads(Path(args.nodes_json).read_text())
        prev = [n for n in args.previous_nodeids.split(",") if n]
        results = select_candidates(nodes, args.source_sha, prev)
        print(json.dumps(results, ensure_ascii=False))
        return 0
    except (FingerprintError, BlockedError) as exc:
        print(json.dumps({"status": "BLOCK", "reason": str(exc)}))
        return 2
    except Exception as exc:  # pylint: disable=broad-except
        print(json.dumps({"status": "BLOCK", "reason": f"unexpected: {exc}"}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
