#!/usr/bin/env python3
"""Extract frequent topics from lord conversation inbound summaries.

Output is designed to be embedded directly into startup gate text output.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


ASCII_PHRASE_RE = re.compile(
    r"[A-Za-z0-9_.:/+\-]+(?: [A-Za-z0-9_.:/+\-]+){0,2}"
)
MIXED_TOPIC_RE = re.compile(
    r"[A-Za-zΑ-Ωα-ωβΒ0-9_.:/+-]*[一-龠々ァ-ヴー]{2,}[A-Za-zΑ-Ωα-ωβΒ0-9_.:/+-]*"
)
JAPANESE_TOKEN_RE = re.compile(r"[一-龠々ァ-ヴー]{2,}")

ASCII_STOPWORDS = {
    "a",
    "ac",
    "agent",
    "alert",
    "all",
    "and",
    "bash",
    "by",
    "ci",
    "clear",
    "cmd",
    "completed",
    "confirm",
    "done",
    "end_turn",
    "gate",
    "info",
    "inbound",
    "jsonl",
    "karo",
    "lord",
    "meta",
    "ntfy",
    "ok",
    "outbound",
    "pass",
    "pending",
    "response",
    "run",
    "shogun",
    "summary",
    "task",
    "terminal",
    "tool_use",
    "warn",
    "y",
}

JP_STOPWORDS = {
    "こと",
    "これ",
    "それ",
    "ため",
    "どこ",
    "まだ",
    "ようだ",
    "確認",
    "検証",
    "完了",
    "実行",
    "指示",
    "作業",
    "修正",
    "出力",
    "判断",
    "対応",
    "調査",
    "追加",
    "確認せよ",
    "実行せよ",
    "確認だけ",
    "途中経過",
    "将軍",
    "殿",
    "家老",
    "軍師",
    "忍者",
    "本番",
    "指摘",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract frequent topics from lord conversation inbound summaries."
    )
    parser.add_argument(
        "--archive-dir",
        default="logs/lord_conversation_archive",
        help="Directory containing daily *.jsonl conversation archives.",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=20,
        help="Maximum number of topics to output.",
    )
    return parser.parse_args()


def normalize_candidate(raw: str) -> tuple[str, str] | None:
    candidate = raw.strip(" \t\r\n'\"`[](){}<>|,.;:!?。、，．「」『』（）")
    candidate = re.sub(r"\s+", " ", candidate)
    if not candidate:
        return None

    if re.fullmatch(r"cmd_\d+", candidate, re.IGNORECASE):
        return None
    if re.fullmatch(r"\d+", candidate):
        return None

    lowered = candidate.lower()
    if lowered in ASCII_STOPWORDS:
        return None
    if candidate in JP_STOPWORDS:
        return None

    if re.fullmatch(r"[A-Za-z0-9_.:/+\- ]+", candidate):
        words = candidate.split()
        if all(word.lower() in ASCII_STOPWORDS for word in words):
            return None
        if len(candidate) < 3 and not any(ch.isdigit() for ch in candidate):
            return None
        return lowered, candidate

    if len(candidate) < 2:
        return None
    return candidate, candidate


def extract_terms(summary: str) -> list[tuple[str, str]]:
    candidates = []
    for pattern in (ASCII_PHRASE_RE, MIXED_TOPIC_RE, JAPANESE_TOKEN_RE):
        candidates.extend(pattern.findall(summary))

    expanded_candidates = list(candidates)
    for candidate in candidates:
        if " " not in candidate:
            continue
        expanded_candidates.extend(part for part in candidate.split() if part)

    seen: set[str] = set()
    normalized_terms: list[tuple[str, str]] = []
    for raw in expanded_candidates:
        normalized = normalize_candidate(raw)
        if normalized is None:
            continue
        key, display = normalized
        if key in seen:
            continue
        seen.add(key)
        normalized_terms.append((key, display))
    return normalized_terms


def load_inbound_summaries(archive_dir: Path) -> list[str]:
    summaries: list[str] = []
    if not archive_dir.is_dir():
        return summaries

    for path in sorted(archive_dir.glob("*.jsonl")):
        try:
            with path.open(encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if entry.get("direction") != "inbound":
                        continue
                    summary = entry.get("summary")
                    if isinstance(summary, str) and summary.strip():
                        summaries.append(summary.strip())
        except OSError:
            continue
    return summaries


def build_topic_index(summaries: list[str], topn: int) -> tuple[list[tuple[str, int]], int]:
    counts: Counter[str] = Counter()
    display_names: dict[str, str] = {}

    for summary in summaries:
        for key, display in extract_terms(summary):
            counts[key] += 1
            display_names.setdefault(key, display)

    ranked = sorted(
        ((display_names[key], count) for key, count in counts.items()),
        key=lambda item: (-item[1], item[0].lower()),
    )
    return ranked[:topn], len(counts)


def main() -> int:
    args = parse_args()
    archive_dir = Path(args.archive_dir)
    summaries = load_inbound_summaries(archive_dir)

    if not archive_dir.is_dir():
        print("INFO: lord_conversation_archiveディレクトリ不在")
        return 0

    if not summaries:
        print("INFO: inbound要約0件")
        return 0

    ranked, unique_count = build_topic_index(summaries, args.top)
    day_count = len(list(archive_dir.glob("*.jsonl")))

    print(
        f"会話トピック索引: inbound要約{len(summaries)}件 / {day_count}日 / unique={unique_count}"
    )
    if not ranked:
        print("  (抽出トピックなし)")
        return 0

    for idx, (display, count) in enumerate(ranked, start=1):
        print(f"{idx}. {display} ({count})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
