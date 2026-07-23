"""I1 inbox-drain adapter — selects the dominant latency phase for reduction.

test_necessity: inbox drain candidates are selected only when the dominant
drain phase is not review_wait_ms, and candidate data passes the S0c contract
fingerprint check; review_wait_ms-dominant episodes are blocked as a different
lane concern.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# Allow import from the skills/campaign-lane/scripts package regardless of cwd
_SKILL_ROOT = Path(__file__).resolve().parent.parent
if str(_SKILL_ROOT) not in sys.path:
    sys.path.insert(0, str(_SKILL_ROOT))

from scripts.contracts import contract_fingerprint  # noqa: E402
from scripts.adapter_sdk import normalize_candidate  # noqa: E402

LANE_ID = "inbox-drain"
EXPECTED_FINGERPRINT = "5e5cbdf07ee17a947ea7d3e14d489498d1c7dd3eee57e85323a10e689d735eb5"
# Dominant-phase keys that belong to a different lane (must not be auto-selected here).
_HUMAN_PHASES = {"review_wait_ms"}


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


def _dominant_phase(episode: dict) -> str | None:
    phase_keys = ["read_ms", "triage_ms", "ack_ms", "review_wait_ms"]
    # Only include keys that are explicitly present in the episode with a positive value.
    phases = {k: episode[k] for k in phase_keys if k in episode and isinstance(episode[k], (int, float)) and episode[k] > 0}
    if not phases:
        return None
    return max(phases, key=phases.__getitem__)


def select_candidates(
    episodes: list[dict[str, Any]],
    source_sha: str,
) -> list[dict]:
    """Return adapter candidates for inbox-drain optimisation.

    Episodes whose dominant phase is review_wait_ms are blocked (different lane).
    Episodes missing measurement data produce reason_code=measurement_missing.
    """
    verify_fingerprint()

    candidates = []
    for ep in episodes:
        ep_id = ep.get("episode_id") or ep.get("agent_id", "unknown")
        loss = ep.get("loss_count", 0)
        wrong_ack = ep.get("wrong_ack_count", 0)
        dup_exec = ep.get("duplicate_execution_count", 0)

        if loss or wrong_ack or dup_exec:
            # Quality contract: any of these must be 0.
            candidate = {
                "lane_id": LANE_ID,
                "candidate_id": ep_id,
                "objective": "minimize",
                "source_sha": source_sha,
                "quality": "fail",
                "reason_code": "quality_violation_loss_or_dup",
            }
            candidates.append(normalize_candidate(candidate))
            continue

        dominant = _dominant_phase(ep)
        if dominant is None:
            candidate = {
                "lane_id": LANE_ID,
                "candidate_id": ep_id,
                "objective": "minimize",
                "source_sha": source_sha,
                "quality": "measurement_missing",
                "reason_code": "no_phase_data",
            }
            candidates.append(normalize_candidate(candidate))
            continue

        if dominant in _HUMAN_PHASES:
            # BLOCK: dominant phase is review_wait_ms — belongs to a different lane.
            raise BlockedError(
                f"episode {ep_id}: dominant phase {dominant} is not auto-optimisable; "
                "route to responsibility-separation lane"
            )

        candidate = {
            "lane_id": LANE_ID,
            "candidate_id": ep_id,
            "objective": "minimize",
            "source_sha": source_sha,
            "quality": "pass",
            "reason_code": f"dominant_phase_{dominant}",
        }
        candidates.append(normalize_candidate(candidate))

    return candidates


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="I1 inbox-drain adapter")
    parser.add_argument("episodes_json", help="Path to JSON file with episode list")
    parser.add_argument("source_sha", help="Fixed source SHA for this run")
    args = parser.parse_args(argv)
    try:
        episodes = json.loads(Path(args.episodes_json).read_text())
        results = select_candidates(episodes, args.source_sha)
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
