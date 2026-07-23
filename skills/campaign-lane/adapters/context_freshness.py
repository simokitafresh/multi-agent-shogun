"""A1 context-freshness adapter — selects stale context files for refresh.

test_necessity: context-freshness candidates are returned only when stale
is reproducible with CONTEXT_CACHE_BYPASS=1 and a unique source-commit/path
mapping exists; ambiguous mappings are blocked at the adapter boundary.
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

LANE_ID = "context-freshness"
EXPECTED_FINGERPRINT = "5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5"


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
    stale_entries: list[dict[str, Any]],
    source_sha: str,
) -> list[dict]:
    """Return adapter candidates for context-freshness refresh.

    Each entry must have: context_path, source_commit, stale_source_count.
    Entries with ambiguous source mapping (multiple commits) are blocked.
    Only entries where stale_source_count >= 1 are candidated.
    """
    verify_fingerprint()

    candidates = []
    for entry in stale_entries:
        ctx_path = entry.get("context_path", "")
        commits = entry.get("source_commits") or (
            [entry["source_commit"]] if entry.get("source_commit") else []
        )
        stale_count = entry.get("stale_source_count", 0)

        if len(commits) != 1:
            raise BlockedError(
                f"context_path {ctx_path}: ambiguous source mapping "
                f"({len(commits)} source commits); requires unique commit"
            )

        if not stale_count or stale_count < 1:
            # Clean — correct normal stop.
            continue

        candidate = {
            "lane_id": LANE_ID,
            "candidate_id": ctx_path,
            "objective": "minimize",
            "source_sha": source_sha,
            "quality": "pass",
            "reason_code": f"stale_source_count_{stale_count}",
        }
        candidates.append(normalize_candidate(candidate))

    return candidates


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="A1 context-freshness adapter")
    parser.add_argument("entries_json", help="Path to JSON file with stale entry list")
    parser.add_argument("source_sha", help="Fixed source SHA for this run")
    args = parser.parse_args(argv)
    try:
        entries = json.loads(Path(args.entries_json).read_text())
        results = select_candidates(entries, args.source_sha)
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
