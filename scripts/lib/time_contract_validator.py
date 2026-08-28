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


# 殿裁定 2026-08-29 01:25『配備スキル=忍者への指示や AC の構築・内容が我らのスタイルにフィットしているかも含まれる』
# 今日の家老 task 3 本で AC 二値性 4/6 行欠落・速度へのつながり 3/3 欠落を実測。家老の判断でなく入口で強制する。
# 対象=task YAML(task_type を持つ entry)のみ。偵察系(recon/scout/recon2)は AC の二値・報告禁止を免除(finding が成果)。
STYLE_SPEED_LINK_ERROR = (
    "task YAML requires speed_link (1 line: which mechanical wait this unit removes, e.g. "
    "'speed_link: fin_c の bats 再走 2-5 分/件を 0') — 殿裁定 2026-08-26 速度4則(3)"
)
STYLE_BINARY_AC_ERROR = "acceptance_criteria must be binary (each description carries a verifiable token such as 0件/=/以下/以上/PASS/FAIL0/一致/実在/BLOCK): "
STYLE_REPORT_ONLY_AC_ERROR = "acceptance_criteria must not end at reporting/measuring only (『報告する/再測定する/差異を報告』は成果ではない=洗脳#6); write the binary outcome the report must show: "
_BINARY_TOKEN_RE = re.compile(
    r"(0\s*(件|行|本|回|個)|[0-9]+\s*(件|行|本|回|個|秒|ms|分|%)\s*(以下|以上|未満|超)?|=|一致|不一致|同一|実在|存在|PASS|FAIL\s*0|FAIL0|SKIP\s*0|SKIP0|BLOCK|CLEAR|idle|0\s*で|ゼロ|全件|100%|≤|≥|<|>)",
    re.IGNORECASE,
)
_REPORT_ONLY_RE = re.compile(r"(報告する|報告せよ|再測定し|計測し|差異を報告|を記録する|一覧化する|洗い出す|調査する)\s*$")
_RECON_TYPES = {"recon", "scout", "recon2", "investigation", "survey"}
# 自動生成 lane(reflux=exact / ci_fix)は speed_link を持たない(機械起票)。人(家老)が起票する型だけ必須。
_SPEED_LINK_TYPES = {"hotfix", "karo_hotfix", "impl", "implement", "full", "normal", "fix", "enhance", "refactor"}


def _style_hits(entry: dict) -> list[str]:
    if "task_type" not in entry:
        return []
    task_type = str(entry.get("task_type") or "").strip().lower()
    hits: list[str] = []
    speed = str(entry.get("speed_link") or "").strip()
    if task_type in _SPEED_LINK_TYPES and (not speed or speed.lower() in NULLISH_REASONS):
        hits.append(STYLE_SPEED_LINK_ERROR)
    if task_type in _RECON_TYPES:
        return hits
    acs = entry.get("acceptance_criteria")
    items: list[tuple[str, str]] = []
    if isinstance(acs, list):
        for item in acs:
            if isinstance(item, dict):
                items.append((str(item.get("id") or "AC?"), str(item.get("description") or "")))
            elif isinstance(item, str):
                items.append(("AC?", item))
    elif isinstance(acs, dict):
        items = [(str(k), str(v)) for k, v in acs.items()]
    non_binary = [label for label, text in items if text and not _BINARY_TOKEN_RE.search(text)]
    if non_binary:
        hits.append(STYLE_BINARY_AC_ERROR + ", ".join(non_binary))
    report_only = [label for label, text in items if text and _REPORT_ONLY_RE.search(text.strip()) and not re.search(r"(0\s*(件|行)|PASS|FAIL\s*0|一致|=)", text)]
    if report_only:
        hits.append(STYLE_REPORT_ONLY_AC_ERROR + ", ".join(report_only))
    return hits


def validate(entry: dict, *, allow_missing_estimated: bool = False) -> str:
    style = _style_hits(entry)
    if style:
        raise ValueError("STYLE: " + " | ".join(style))
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
