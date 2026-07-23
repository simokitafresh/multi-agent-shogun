"""A3 lesson-backlog adapter — selects mechanically resolvable lesson entries.

test_necessity: lesson-backlog auto-selection is limited to origin-missing,
exact-duplicate, superseded_by-confirmed, and mechanical-merge entries;
content correctness, permanent-rule changes, and deprecation decisions are
blocked at the adapter boundary.
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

LANE_ID = "lesson-backlog"
EXPECTED_FINGERPRINT = "5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5"

_AUTO_REASONS = frozenset({
    "origin_missing",
    "exact_duplicate",
    "superseded_by_confirmed",
    "mechanical_merge",
})
_HUMAN_REASONS = frozenset({
    "content_correctness",
    "permanent_rule",
    "deprecation",
    "value_judgment",
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
    lessons: list[dict[str, Any]],
    source_sha: str,
) -> list[dict]:
    """Return adapter candidates from the lesson backlog.

    Each lesson must have: lesson_id, reason.
    Candidates are selected for mechanical resolution only.
    Human-judgment reasons are blocked.
    After processing, draft_count must decrease and causal links must be preserved
    (verified by caller — this adapter only selects; it does not mutate).
    """
    verify_fingerprint()

    candidates = []
    for lesson in lessons:
        lesson_id = lesson.get("lesson_id", "")
        reason = lesson.get("reason", "")

        if reason in _HUMAN_REASONS:
            raise BlockedError(
                f"lesson {lesson_id}: reason '{reason}' requires human judgment; "
                "content correctness, permanent rules, and deprecation are not auto-selected"
            )

        if reason not in _AUTO_REASONS:
            raise BlockedError(
                f"lesson {lesson_id}: reason '{reason}' is not in auto-select allowlist"
            )

        candidate = {
            "lane_id": LANE_ID,
            "candidate_id": lesson_id,
            "objective": "minimize",
            "source_sha": source_sha,
            "quality": "pass",
            "reason_code": reason,
        }
        candidates.append(normalize_candidate(candidate))

    return candidates


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="A3 lesson-backlog adapter")
    parser.add_argument("lessons_json", help="Path to JSON file with lesson list")
    parser.add_argument("source_sha", help="Fixed source SHA for this run")
    args = parser.parse_args(argv)
    try:
        lessons = json.loads(Path(args.lessons_json).read_text())
        results = select_candidates(lessons, args.source_sha)
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
