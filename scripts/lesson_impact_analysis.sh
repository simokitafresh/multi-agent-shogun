#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_FILE="$SCRIPT_DIR/logs/lesson_impact.tsv"

python3 - "$DATA_FILE" "$@" <<'PY'
import csv
import glob
import os
import sys
from collections import Counter, defaultdict

try:
    import yaml
except Exception:
    yaml = None


def usage() -> None:
    print("Usage: bash scripts/lesson_impact_analysis.sh [--detail LESSON_ID]")


def parse_args(argv):
    if not argv:
        return None
    if len(argv) == 2 and argv[0] == "--detail":
        return argv[1]
    usage()
    sys.exit(1)


def to_bool(value: str) -> bool:
    return str(value).strip().lower() in {"yes", "true", "1", "y"}


def to_result(value: str) -> str:
    return str(value).strip().upper()


def pct(num: int, den: int) -> int:
    if den <= 0:
        return 0
    return int(round((num * 100.0) / den))


def safe_date(ts: str) -> str:
    ts = (ts or "").strip()
    if len(ts) >= 10:
        return ts[:10]
    return "unknown"


def load_rows(path: str):
    rows = []
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return rows

    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for raw in reader:
            lesson_id = (raw.get("lesson_id") or "").strip()
            action = (raw.get("action") or "").strip().lower()
            result = to_result(raw.get("result", ""))
            if not lesson_id or action not in {"injected", "withheld"}:
                continue
            if result == "PENDING":
                continue

            rows.append(
                {
                    "timestamp": raw.get("timestamp", ""),
                    "lesson_id": lesson_id,
                    "action": action,
                    "result": result,
                    "referenced": to_bool(raw.get("referenced", "")),
                    "task_type": (raw.get("task_type") or "").strip(),
                    "model": (raw.get("model") or "").strip(),
                }
            )
    return rows


def load_lesson_summaries(root: str):
    summaries = {}
    if yaml is None:
        return summaries

    for lesson_file in glob.glob(os.path.join(root, "projects", "*", "lessons.yaml")):
        try:
            with open(lesson_file, "r", encoding="utf-8") as f:
                data = yaml.safe_load(f) or {}
        except Exception:
            continue
        for lesson in data.get("lessons", []):
            lesson_id = str(lesson.get("id", "")).strip()
            if lesson_id and lesson_id not in summaries:
                summaries[lesson_id] = str(lesson.get("summary", "")).strip()
    return summaries


def build_stats(rows):
    stats = defaultdict(
        lambda: {
            "injected": 0,
            "withheld": 0,
            "inj_clear": 0,
            "inj_block": 0,
            "with_clear": 0,
            "with_block": 0,
            "referenced_count": 0,
            "ref_clear": 0,
            "ref_block": 0,
            "task_types": Counter(),
            "models": Counter(),
        }
    )

    for r in rows:
        sid = r["lesson_id"]
        st = stats[sid]
        action = r["action"]
        result = r["result"]

        if action == "injected":
            st["injected"] += 1
            if result == "CLEAR":
                st["inj_clear"] += 1
            elif result == "BLOCK":
                st["inj_block"] += 1

            if r["referenced"]:
                st["referenced_count"] += 1
                if result == "CLEAR":
                    st["ref_clear"] += 1
                elif result == "BLOCK":
                    st["ref_block"] += 1

            if r["task_type"]:
                st["task_types"][r["task_type"]] += 1
            if r["model"]:
                st["models"][r["model"]] += 1
        else:
            st["withheld"] += 1
            if result == "CLEAR":
                st["with_clear"] += 1
            elif result == "BLOCK":
                st["with_block"] += 1

    return stats


def rate_line(lesson_id: str, st: dict) -> str:
    inj = st["injected"]
    ref_rate = pct(st["referenced_count"], inj)
    clear_rate = pct(st["inj_clear"], inj)
    block_rate = pct(st["inj_block"], inj)
    return (
        f"  {lesson_id:<5} injected:{inj:<4} ref_rate:{ref_rate:>3}%  "
        f"CLEAR:{clear_rate:>3}%  BLOCK:{block_rate:>3}%"
    )


def ab_line(lesson_id: str, st: dict) -> str:
    inj_n = st["injected"]
    with_n = st["withheld"]
    inj_clear = pct(st["inj_clear"], inj_n)
    with_clear = pct(st["with_clear"], with_n)
    delta = inj_clear - with_clear
    if min(inj_n, with_n) >= 10 and abs(delta) >= 20:
        sig = "*"
    else:
        sig = "n/s"
    sign = "+" if delta >= 0 else ""
    return (
        f"  {lesson_id:<5} injected:{inj_n:<3} CLEAR:{inj_clear:>3}%  |  "
        f"withheld:{with_n:<3} CLEAR:{with_clear:>3}%  |  delta:{sign}{delta}%  sig:{sig}"
    )


def joined_counter(counter: Counter) -> str:
    if not counter:
        return "n/a"
    return " ".join(f"{k}={v}" for k, v in counter.most_common())


def print_summary(rows, stats):
    print("=== Lesson Impact Analysis ===")
    if rows:
        dates = sorted(safe_date(r["timestamp"]) for r in rows)
        print(f"Period: {dates[0]} ~ {dates[-1]}")
    else:
        print("Period: n/a")
    total_injected = sum(1 for r in rows if r["action"] == "injected")
    print(f"Total injections: {total_injected}")
    print(f"Unique lessons: {len(stats)}")
    print()

    print("Top 10 Most Injected:")
    top_injected = sorted(stats.items(), key=lambda kv: (-kv[1]["injected"], kv[0]))[:10]
    if top_injected and top_injected[0][1]["injected"] > 0:
        for lesson_id, st in top_injected:
            if st["injected"] <= 0:
                continue
            print(rate_line(lesson_id, st))
    else:
        print("  none")
    print()

    print("Low Reference Rate (noise candidates):")
    low_ref = [kv for kv in stats.items() if kv[1]["injected"] > 0]
    low_ref.sort(key=lambda kv: (pct(kv[1]["referenced_count"], kv[1]["injected"]), -kv[1]["injected"], kv[0]))
    if low_ref:
        for lesson_id, st in low_ref[:10]:
            print(rate_line(lesson_id, st))
    else:
        print("  none")
    print()

    print("High BLOCK Rate (harm candidates):")
    high_block = [kv for kv in stats.items() if kv[1]["injected"] > 0]
    high_block.sort(key=lambda kv: (-pct(kv[1]["inj_block"], kv[1]["injected"]), -kv[1]["injected"], kv[0]))
    if high_block:
        for lesson_id, st in high_block[:10]:
            print(rate_line(lesson_id, st))
    else:
        print("  none")
    print()

    print("Never Referenced:")
    never_ref = [kv for kv in stats.items() if kv[1]["injected"] > 0 and kv[1]["referenced_count"] == 0]
    never_ref.sort(key=lambda kv: (-kv[1]["injected"], kv[0]))
    if never_ref:
        for lesson_id, st in never_ref[:10]:
            print(f"  {lesson_id:<5} injected:{st['injected']:<4} ref_rate:  0%")
    else:
        print("  none")
    print()

    print("=== A/B Comparison (lessons with N>=5 in both groups) ===")
    ab_candidates = [kv for kv in stats.items() if kv[1]["injected"] >= 5 and kv[1]["withheld"] >= 5]
    ab_candidates.sort(
        key=lambda kv: (
            -(pct(kv[1]["inj_clear"], kv[1]["injected"]) - pct(kv[1]["with_clear"], kv[1]["withheld"])),
            kv[0],
        )
    )
    if ab_candidates:
        for lesson_id, st in ab_candidates:
            print(ab_line(lesson_id, st))
        print("sig: n/s=not significant, *=p<0.05 (heuristic)")
    else:
        print("  insufficient data for A/B comparison")


def print_detail(lesson_id: str, stats: dict, summaries: dict):
    st = stats.get(
        lesson_id,
        {
            "injected": 0,
            "withheld": 0,
            "inj_clear": 0,
            "inj_block": 0,
            "with_clear": 0,
            "with_block": 0,
            "referenced_count": 0,
            "ref_clear": 0,
            "ref_block": 0,
            "task_types": Counter(),
            "models": Counter(),
        },
    )

    print(f"=== {lesson_id} Detail ===")
    summary = summaries.get(lesson_id, "summary not found")
    print(f"Summary: {summary}")
    inj = st["injected"]
    print(f"Injected: {inj} times")
    print(f"Referenced: {st['referenced_count']} times ({pct(st['referenced_count'], inj)}%)")
    print(
        f"Results when injected: CLEAR {st['inj_clear']} ({pct(st['inj_clear'], inj)}%) / "
        f"BLOCK {st['inj_block']} ({pct(st['inj_block'], inj)}%)"
    )
    ref_n = st["referenced_count"]
    print(
        f"Results when referenced: CLEAR {st['ref_clear']} ({pct(st['ref_clear'], ref_n)}%) / "
        f"BLOCK {st['ref_block']} ({pct(st['ref_block'], ref_n)}%)"
    )
    print(f"Models: {joined_counter(st['models'])}")
    print(f"Task types: {joined_counter(st['task_types'])}")

    if st["injected"] >= 5 and st["withheld"] >= 5:
        print("A/B: " + ab_line(lesson_id, st).strip())
    else:
        print("A/B: insufficient data for A/B comparison")


def main():
    data_file = sys.argv[1]
    detail_lesson_id = parse_args(sys.argv[2:])
    rows = load_rows(data_file)
    stats = build_stats(rows)
    summaries = load_lesson_summaries(os.path.dirname(data_file))

    if detail_lesson_id:
        print_detail(detail_lesson_id, stats, summaries)
    else:
        print_summary(rows, stats)


if __name__ == "__main__":
    main()
PY
