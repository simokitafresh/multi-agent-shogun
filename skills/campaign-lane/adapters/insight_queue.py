"""A2 insight-queue adapter — auto-selects only deterministic insight actions.

test_necessity: insight-queue auto-selection is limited to fix_known and
mechanical duplicate/superseded/already_fixed actions; design decisions,
production judgments, and human-value insights are blocked at the adapter.
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

LANE_ID = "insight-queue"
EXPECTED_FINGERPRINT = "5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5"

# Actions that can be mechanically applied without human judgment.
_AUTO_ACTIONS = frozenset({"fix_known", "duplicate", "superseded", "already_fixed"})
# Actions that require human judgment — must be blocked.
_HUMAN_ACTIONS = frozenset({
    "design_decision", "production_decision", "value_judgment",
    "deprecate", "escalate", "review_required",
})


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
    insights: list[dict[str, Any]],
    source_sha: str,
) -> list[dict]:
    """Return adapter candidates from the insight queue.

    Each insight must have: insight_id, action, priority.
    Insights with human-judgment actions are blocked.
    Results are ordered by priority (highest first).
    """
    verify_fingerprint()

    sorted_insights = sorted(
        insights,
        key=lambda x: (-float(x.get("priority", 0)), x.get("insight_id", "")),
    )

    candidates = []
    for insight in sorted_insights:
        insight_id = insight.get("insight_id", "")
        action = insight.get("action", "")

        if action in _HUMAN_ACTIONS:
            raise BlockedError(
                f"insight {insight_id}: action '{action}' requires human judgment; "
                "must not be auto-selected"
            )

        if action not in _AUTO_ACTIONS:
            # Unknown action — fail-closed.
            raise BlockedError(
                f"insight {insight_id}: action '{action}' is not in the auto-select allowlist"
            )

        candidate = {
            "lane_id": LANE_ID,
            "candidate_id": insight_id,
            "objective": "minimize",
            "source_sha": source_sha,
            "quality": "pass",
            "reason_code": f"auto_action_{action}",
        }
        candidates.append(normalize_candidate(candidate))

    return candidates


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="A2 insight-queue adapter")
    parser.add_argument("insights_json", help="Path to JSON file with insight list")
    parser.add_argument("source_sha", help="Fixed source SHA for this run")
    args = parser.parse_args(argv)
    try:
        insights = json.loads(Path(args.insights_json).read_text())
        results = select_candidates(insights, args.source_sha)
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
