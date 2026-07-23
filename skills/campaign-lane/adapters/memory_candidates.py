"""A4 memory-candidates adapter — selects mechanically resolvable memory items.

test_necessity: memory candidate auto-selection is limited to hash-identical
duplicates, known-conflict-key matches, and mechanical Obsidian link additions;
semantic promotion, preference judgments, and partial-layer completions are
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

LANE_ID = "memory-candidates"
EXPECTED_FINGERPRINT = "5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5"

_AUTO_REASONS = frozenset({
    "hash_identical_duplicate",
    "known_conflict_key",
    "obsidian_link_missing",
})
_HUMAN_REASONS = frozenset({
    "semantic_promotion",
    "preference_judgment",
    "value_assessment",
    "subjective_merge",
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
    memory_items: list[dict[str, Any]],
    source_sha: str,
) -> list[dict]:
    """Return adapter candidates from memory item backlog.

    Each item must have: item_id, reason, layers_completed (int 0-3).
    Partial layer completion (layers_completed < 3) → quality=fail (rollback needed).
    Human-judgment reasons are blocked.
    """
    verify_fingerprint()

    candidates = []
    for item in memory_items:
        item_id = item.get("item_id", "")
        reason = item.get("reason", "")
        layers = item.get("layers_completed", 0)

        if reason in _HUMAN_REASONS:
            raise BlockedError(
                f"memory item {item_id}: reason '{reason}' requires human judgment; "
                "semantic promotion and preference judgments are not auto-selected"
            )

        if reason not in _AUTO_REASONS:
            raise BlockedError(
                f"memory item {item_id}: reason '{reason}' is not in auto-select allowlist"
            )

        # Partial layer success must not be treated as complete.
        if isinstance(layers, int) and 0 < layers < 3:
            candidate = {
                "lane_id": LANE_ID,
                "candidate_id": item_id,
                "objective": "minimize",
                "source_sha": source_sha,
                "quality": "fail",
                "reason_code": f"partial_layer_success_{layers}_of_3",
            }
            candidates.append(normalize_candidate(candidate))
            continue

        candidate = {
            "lane_id": LANE_ID,
            "candidate_id": item_id,
            "objective": "minimize",
            "source_sha": source_sha,
            "quality": "pass",
            "reason_code": reason,
        }
        candidates.append(normalize_candidate(candidate))

    return candidates


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="A4 memory-candidates adapter")
    parser.add_argument("items_json", help="Path to JSON file with memory item list")
    parser.add_argument("source_sha", help="Fixed source SHA for this run")
    args = parser.parse_args(argv)
    try:
        items = json.loads(Path(args.items_json).read_text())
        results = select_candidates(items, args.source_sha)
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
