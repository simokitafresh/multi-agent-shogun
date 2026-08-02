#!/usr/bin/env python3
"""Classify the invalidated Phase-0 three-way population under §0.6.

The source CSV does not contain portfolio operational-start dates or the
ledger/expanded-weight evidence needed to resolve monthly boundary dates.
The classifier therefore fails visible instead of treating the invalidated
``position_start_date`` as either fact.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path


CLASSES = ("Normal", "Partial", "MTD", "未開始", "要調査")
REQUIRED_COLUMNS = {
    "portfolio_id",
    "year_month",
    "position_start_date",
    "classification",
}


def classify(row: dict[str, str], as_of: date) -> tuple[str, dict[str, str]]:
    year_month = row["year_month"]
    current_month = as_of.strftime("%Y-%m")
    q = {
        "q1_operational_start": "unknown: source CSV has no PF operational_start_date",
        "q2_finality": "current/MTD" if year_month == current_month else "historical/completed",
        "q3_monthly_boundary": (
            "unknown: position_start_date belongs to the invalidated month-start oracle; "
            "ledger/expanded-weight boundary evidence is absent"
        ),
        "q4_window_separation": "pass: row represents monthly return, not a momentum window",
    }
    # Q1 is ordered first by the verifier contract. Without the operational
    # start, even a current-month row could be pre-start rather than MTD.
    return "要調査", q


def render_markdown(
    source: Path,
    output: Path,
    as_of: date,
    rows: list[dict[str, str]],
) -> str:
    totals = Counter(row["monthly_classification"] for row in rows)
    by_pf: dict[str, Counter[str]] = defaultdict(Counter)
    by_year: dict[str, Counter[str]] = defaultdict(Counter)
    for row in rows:
        cls = row["monthly_classification"]
        by_pf[row["portfolio_id"]][cls] += 1
        by_year[row["year_month"][:4]][cls] += 1

    def table(counter_map: dict[str, Counter[str]], key: str) -> list[str]:
        lines = [f"| {key} | " + " | ".join(CLASSES) + " | Total |", "|---|---:|---:|---:|---:|---:|---:|"]
        for name in sorted(counter_map):
            counts = counter_map[name]
            lines.append(
                f"| {name} | "
                + " | ".join(str(counts[c]) for c in CLASSES)
                + f" | {sum(counts.values())} |"
            )
        return lines

    lines = [
        "# cmd_4220 A0-0a classification",
        "",
        f"- Source: `{source}`",
        f"- Output: `{output}`",
        f"- As-of: `{as_of.isoformat()}` (source artifact date)",
        f"- Data rows: {len(rows)}",
        "- Classification order: §0.6 verifier questions Q1→Q4; unresolved required evidence is `要調査`.",
        "- Boundary safeguard: `position_start_date` is not reused as SSOT because §1d invalidates the source oracle's month-start boundary.",
        "- D7: docs/data-only. No runtime behavior changed; executable test scope is exempt. The classifier's own exact recount is the binary contract.",
        "",
        "## Decision conditions",
        "",
        "| Class | Mechanical condition |",
        "|---|---|",
        "| Normal | Q1 operational start known and reached; historical completed month; Q3 boundary evidence resolved; Q4 separated |",
        "| Partial | Q1 identifies the first incomplete operational interval; completed at next monthly boundary |",
        "| MTD | Q1 operational start known and reached; `year_month == as_of YYYY-MM`; dynamic end is as_of |",
        "| 未開始 | Q1 proves month precedes PF operational start |",
        "| 要調査 | Any required Q1-Q4 evidence is absent or contradictory |",
        "",
        "The supplied CSV has neither PF operational-start dates (Q1) nor ledger/expanded-weight monthly-boundary evidence (Q3). Therefore all rows fail visible as `要調査`; guessing from each PF's earliest changed row would confuse a changed-row subset with operational history.",
        "",
        "## Total recount",
        "",
        "| Normal | Partial | MTD | 未開始 | 要調査 | Sum | Source data rows | Unclassified |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|",
        "| " + " | ".join(str(totals[c]) for c in CLASSES) + f" | {sum(totals.values())} | {len(rows)} | 0 |",
        "",
        "## PF breakdown",
        "",
        *table(by_pf, "portfolio_id"),
        "",
        "## Year breakdown",
        "",
        *table(by_year, "year"),
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_csv", type=Path)
    parser.add_argument("output_md", type=Path)
    parser.add_argument("--as-of", type=date.fromisoformat, required=True)
    args = parser.parse_args()

    with args.source.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing:
            raise SystemExit(f"missing source columns: {sorted(missing)}")
        source_rows = list(reader)
        fieldnames = list(reader.fieldnames or [])

    classified: list[dict[str, str]] = []
    for source_row_number, row in enumerate(source_rows, start=2):
        monthly_classification, q = classify(row, args.as_of)
        classified.append(
            {
                **row,
                "source_row_number": str(source_row_number),
                "monthly_classification": monthly_classification,
                **q,
            }
        )

    output_fields = fieldnames + [
        "source_row_number",
        "monthly_classification",
        "q1_operational_start",
        "q2_finality",
        "q3_monthly_boundary",
        "q4_window_separation",
    ]
    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=output_fields)
        writer.writeheader()
        writer.writerows(classified)

    counts = Counter(row["monthly_classification"] for row in classified)
    unclassified = sum(row["monthly_classification"] not in CLASSES for row in classified)
    total = sum(counts[c] for c in CLASSES)
    if unclassified or total != len(source_rows):
        raise SystemExit(
            f"RECOUNT FAIL rows={len(source_rows)} classified_sum={total} unclassified={unclassified}"
        )

    args.output_md.write_text(
        render_markdown(args.source, args.output_csv, args.as_of, classified),
        encoding="utf-8",
    )
    print(
        "RECOUNT PASS "
        f"rows={len(source_rows)} "
        + " ".join(f"{name}={counts[name]}" for name in CLASSES)
        + f" classified_sum={total} unclassified={unclassified}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
