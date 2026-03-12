#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHRONICLE_FILE="${ROOT_DIR}/context/cmd-chronicle.md"

if [[ ! -f "${CHRONICLE_FILE}" ]]; then
  echo "ERROR: chronicle file not found: ${CHRONICLE_FILE}" >&2
  exit 1
fi

python3 - "${CHRONICLE_FILE}" <<'PY'
from __future__ import annotations

import re
import sys
from collections import Counter
from datetime import date, timedelta
from pathlib import Path


MONTH_RE = re.compile(r"^##\s+(\d{4})-(\d{2})\s*$")


def blankish(value: str) -> bool:
    return value.strip() in {"", "-", "--", "---", "\u2014"}


def normalize_project(value: str) -> str:
    return "(missing)" if blankish(value) else value.strip()


def infer_type(title: str, key_result: str) -> str:
    text = " ".join(part.strip() for part in (title, key_result) if not blankish(part))
    if not text:
        return "other"

    if re.search(r"(?i)\bre-?review\b|\breview\b|レビュー", text):
        return "review"

    if re.search(
        r"偵察|調査|棚卸し|監査|分析|検証|照合|可否|実現可能性|合議|比較|深掘り|洗い出し|研究",
        text,
    ):
        return "recon"

    if re.search(
        r"(?i)\bimpl\b|\bfix\b|実装|修正|追加|導入|改善|更新|復旧|回復|高速化|最適化|構築|作成|対応|一掃|全緑化|ビルド|リリース",
        text,
    ):
        return "impl"

    return "other"


def print_table(title: str, headers: list[str], rows: list[list[str]]) -> None:
    widths = [len(header) for header in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def fmt(row: list[str]) -> str:
        return "| " + " | ".join(cell.ljust(widths[index]) for index, cell in enumerate(row)) + " |"

    print(title)
    print(fmt(headers))
    print("| " + " | ".join("-" * widths[index] for index in range(len(headers))) + " |")
    for row in rows:
        print(fmt(row))
    print()


def parse_row(raw_line: str, lineno: int) -> tuple[str, str, str, str, str]:
    normalized = raw_line if raw_line.rstrip().endswith("|") else f"{raw_line} |"
    cells = [cell.strip() for cell in normalized.split("|")[1:-1]]

    if len(cells) == 5:
        cmd_id, title, project, mm_dd, key_result = cells
        return cmd_id, title, project, mm_dd, key_result

    if len(cells) == 6 and cells[1] == "" and cells[2] == "":
        cmd_id, _blank_title, _legacy_blank, project, mm_dd, key_result = cells
        return cmd_id, "", project, mm_dd, key_result

    print(f"ERROR: malformed chronicle row at line {lineno}: {raw_line}", file=sys.stderr)
    sys.exit(1)


chronicle_path = Path(sys.argv[1])
records: list[dict[str, object]] = []
current_year: int | None = None

for lineno, raw_line in enumerate(chronicle_path.read_text(encoding="utf-8").splitlines(), start=1):
    month_match = MONTH_RE.match(raw_line)
    if month_match:
        current_year = int(month_match.group(1))
        continue

    if not raw_line.startswith("| cmd_"):
        continue

    if current_year is None:
        print(f"ERROR: row encountered before month heading at line {lineno}", file=sys.stderr)
        sys.exit(1)

    cmd_id, title, project, mm_dd, key_result = parse_row(raw_line, lineno)

    month, day = (int(piece) for piece in mm_dd.split("-", 1))
    try:
        record_date = date(current_year, month, day)
    except ValueError as exc:
        print(f"ERROR: invalid date at line {lineno}: {mm_dd} ({exc})", file=sys.stderr)
        sys.exit(1)

    records.append(
        {
            "cmd_id": cmd_id,
            "title": title,
            "project": normalize_project(project),
            "date": record_date,
            "key_result": "" if blankish(key_result) else key_result,
            "type": infer_type(title, key_result),
        }
    )


today = date.today()

recent_rows: list[list[str]] = []
for days in (7, 30):
    start = today - timedelta(days=days - 1)
    count = sum(1 for record in records if start <= record["date"] <= today)
    recent_rows.append([f"last_{days}_days", start.isoformat(), today.isoformat(), str(count)])

project_counts = Counter(str(record["project"]) for record in records)
project_rows = [[project, str(count)] for project, count in sorted(project_counts.items(), key=lambda item: (-item[1], item[0]))]

type_counts = Counter(str(record["type"]) for record in records)
type_rows = [[type_name, str(count)] for type_name, count in sorted(type_counts.items(), key=lambda item: (-item[1], item[0]))]

print_table("Recent completion counts", ["window", "start_date", "end_date", "count"], recent_rows)
print_table("Project distribution", ["project", "count"], project_rows)
print_table("Type distribution", ["type", "count"], type_rows)
PY
