#!/usr/bin/env python3
"""Validate the shared command/task execution-time contract."""

from __future__ import annotations

import argparse
import math
import re
import sys

import yaml


NULLISH_REASONS = {"none", "n/a", "na", "null", "unknown", "tbd", "fill_this"}
SPLIT_KEYS = {"boundary_ac_ids", "integration_tasks", "review_round_trips"}
SPLIT_ERROR = (
    "estimated_minutes exceeds the 10-minute target; split_decision must be a "
    "mapping with exactly boundary_ac_ids (non-empty list of unique ids that exist in "
    "this command/task's own acceptance_criteria), integration_tasks and "
    "review_round_trips (non-negative integers, not booleans, summing to at least 1); "
    "free-form split_decision_reason text is not accepted as a substitute"
)


def _entry(data: object, cmd_id: str) -> dict:
    if not isinstance(data, dict):
        raise ValueError("command/task YAML must be a mapping")
    if cmd_id:
        commands = data.get("commands", data)
        value = commands.get(cmd_id) if isinstance(commands, dict) else None
        if not isinstance(value, dict):
            raise ValueError(f"command {cmd_id!r} not found or not a mapping")
        return value
    value = data.get("task", data)
    if (
        value is data
        and "estimated_minutes" not in data
        and len(data) == 1
        and isinstance(next(iter(data.values())), dict)
    ):
        value = next(iter(data.values()))
    if not isinstance(value, dict):
        raise ValueError("task must be a mapping")
    return value


def _known_ac_ids(entry: dict) -> set[str]:
    acceptance_criteria = entry.get("acceptance_criteria")
    if isinstance(acceptance_criteria, list):
        return {
            item["id"].strip()
            for item in acceptance_criteria
            if isinstance(item, dict)
            and isinstance(item.get("id"), str)
            and item["id"].strip()
        }
    if isinstance(acceptance_criteria, dict):
        return {key.strip() for key in acceptance_criteria if isinstance(key, str) and key.strip()}
    return set()


def _nonnegative_int(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def validate(entry: dict, *, allow_missing_estimated: bool = False) -> str:
    estimated = entry.get("estimated_minutes")
    if allow_missing_estimated and estimated in (None, ""):
        return "PASS estimated_minutes=not_declared"
    if isinstance(estimated, bool):
        estimated = None
    try:
        estimated = float(estimated)
    except (TypeError, ValueError):
        estimated = None
    if estimated is None or not math.isfinite(estimated) or estimated <= 0:
        raise ValueError("estimated_minutes must be a positive number")
    if estimated <= 10:
        return f"PASS estimated_minutes={estimated:g}"

    if estimated <= 15:
        split = entry.get("split_decision")
        if not isinstance(split, dict) or set(split) != SPLIT_KEYS:
            raise ValueError(SPLIT_ERROR)
        boundary_ids = split.get("boundary_ac_ids")
        if (
            not isinstance(boundary_ids, list)
            or not boundary_ids
            or any(not isinstance(value, str) or not value.strip() for value in boundary_ids)
        ):
            raise ValueError(SPLIT_ERROR)
        normalized = [value.strip() for value in boundary_ids]
        known_ids = _known_ac_ids(entry)
        if len(set(normalized)) != len(normalized) or not known_ids or any(
            value not in known_ids for value in normalized
        ):
            raise ValueError(SPLIT_ERROR)
        integration_tasks = _nonnegative_int(split.get("integration_tasks"))
        review_round_trips = _nonnegative_int(split.get("review_round_trips"))
        if (
            integration_tasks is None
            or review_round_trips is None
            or integration_tasks + review_round_trips < 1
        ):
            raise ValueError(SPLIT_ERROR)
        return (
            f"PASS natural-boundary exception estimated_minutes={estimated:g} "
            f"boundary_ac_ids={normalized} integration_tasks={integration_tasks} "
            f"review_round_trips={review_round_trips}"
        )

    env = entry.get("execution_env")
    env = env if isinstance(env, dict) else {}
    reason = str(env.get("long_runtime_reason") or "").strip()
    runtime = env.get("measured_runtime_sec")
    if isinstance(runtime, bool):
        runtime = None
    try:
        runtime = float(runtime)
    except (TypeError, ValueError):
        runtime = None
    if (
        not reason
        or reason.lower() in NULLISH_REASONS
        or runtime is None
        or not math.isfinite(runtime)
        or runtime <= 0
    ):
        raise ValueError(
            "estimated_minutes>15 requires execution_env mapping with concrete "
            "long_runtime_reason and positive measured_runtime_sec"
        )
    observed = _observation_window_hits(entry, reason)
    if observed:
        raise ValueError(OBSERVATION_WINDOW_ERROR + " hits=" + ", ".join(observed))
    return f"PASS long-runtime exception estimated_minutes={estimated:g} measured_runtime_sec={runtime:g}"


# 殿裁定 2026-08-29 00:49『1時間後に再確認を忍者に配備するのは配備スキルの品質バグ』:
# 観測窓(live 後 N 時間の本番観測/証明)を long-runtime 例外の理由にすると忍者が
# 3600 秒級の機械的待ちに人質化する(08-28/29 に 16 回)。観測は monitor の責務
# (production_proof)であり忍者 AC にも long_runtime_reason にも置けない。
OBSERVATION_WINDOW_ERROR = (
    "long-runtime exception cannot be justified by an observation window: "
    "move production observation/proof out of ninja acceptance_criteria into "
    "production_proof (monitor-owned); ninja tasks must not wait for live windows"
)
_OBSERVATION_WINDOW_RE = re.compile(
    r"(live\s*後|本番(で|の|を)?\s*(\d+\s*(h|時間|分|min)))"
    r"|((\d+\s*(h|時間|min|分)|1h|3600\s*(s|秒)?)\s*(の)?\s*(観測|窓|計測|待|proof|証明|監視))"
    r"|観測窓|観測し|観測する|live\s*\d+\s*(h|時間|s|秒|分)"
    r"|(gate_metrics|ninja_monitor\.log|monitor).{0,30}(で|から).{0,20}(証明|proof)",
    re.IGNORECASE,
)


def _observation_window_hits(entry: dict, reason: str) -> list[str]:
    texts: list[tuple[str, str]] = [("long_runtime_reason", reason)]
    acceptance_criteria = entry.get("acceptance_criteria")
    if isinstance(acceptance_criteria, list):
        for item in acceptance_criteria:
            if isinstance(item, dict):
                texts.append((str(item.get("id") or "AC?"), str(item.get("description") or "")))
            elif isinstance(item, str):
                texts.append(("AC?", item))
    elif isinstance(acceptance_criteria, dict):
        for key, value in acceptance_criteria.items():
            texts.append((str(key), str(value)))
    hits: list[str] = []
    for label, text in texts:
        if text and _OBSERVATION_WINDOW_RE.search(text):
            hits.append(label)
    return hits


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", nargs="?", default="-")
    parser.add_argument("--cmd-id", default="")
    parser.add_argument("--allow-missing-estimated", action="store_true")
    args = parser.parse_args()
    try:
        if args.path == "-":
            data = yaml.safe_load(sys.stdin) or {}
        else:
            with open(args.path, encoding="utf-8") as handle:
                data = yaml.safe_load(handle) or {}
        print(
            validate(
                _entry(data, args.cmd_id),
                allow_missing_estimated=args.allow_missing_estimated,
            )
        )
        return 0
    except (OSError, yaml.YAMLError, ValueError) as exc:
        print(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
