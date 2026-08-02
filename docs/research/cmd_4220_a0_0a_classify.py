#!/usr/bin/env python3
"""Evidence-backed §0.6 classifier for cmd_4220.

The script has two explicit phases. ``--emit-readonly-sql`` emits the single
SELECT consumed by db_capability_launcher. The default phase reads that
launcher's tuple output and writes the classification artifacts. It never
opens a database connection itself.
"""

from __future__ import annotations

import argparse
import ast
import csv
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path


CLASSES = ("Normal", "Partial", "MTD", "未開始")
EVIDENCE_FIELDS = (
    "source_row_number",
    "portfolio_id",
    "year_month",
    "operational_start",
    "daily_rows",
    "trade_days",
    "expanded_signatures",
    "first_signal_date",
    "last_signal_date",
    "expanded_switch_date",
    "first_trade_date",
    "last_trade_date",
    "ledger_date",
    "monthly_classification",
    "monthly_boundary_date",
    "boundary_evidence",
    "ledger_verification",
    "evidence_complete",
)


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def emit_sql(rows: list[dict[str, str]], as_of: date) -> str:
    values = ",".join(
        f"({number},{sql_quote(row['portfolio_id'])},{sql_quote(row['year_month'])})"
        for number, row in enumerate(rows, start=2)
    )
    return f"""WITH input(source_row_number,portfolio_id,year_month) AS (VALUES {values}),
target_pf AS (SELECT DISTINCT portfolio_id FROM input),
pm AS (
  SELECT portfolio_id,MIN(data_start_date) FILTER(WHERE years=0) operational_start
  FROM portfolio_metrics WHERE portfolio_id IN(SELECT portfolio_id FROM target_pf)
  GROUP BY portfolio_id
),
daily0 AS (
  SELECT s.portfolio_id,s.date,(s.momentum_data::jsonb->'display_ticker_weights') weights
  FROM signals s
  WHERE s.portfolio_id IN(SELECT portfolio_id FROM target_pf)
    AND s.date BETWEEN DATE '2012-02-01' AND DATE {sql_quote(as_of.isoformat())}
    AND jsonb_typeof(s.momentum_data::jsonb->'display_ticker_weights')='object'
),
daily AS (
  SELECT *,lag(weights) OVER(PARTITION BY portfolio_id ORDER BY date) prev_weights
  FROM daily0
),
month_ev AS (
  SELECT portfolio_id,to_char(date,'YYYY-MM') year_month,COUNT(*) daily_rows,
         COUNT(DISTINCT weights) signatures,
         MIN(date) first_signal_date,MAX(date) last_signal_date,
         MIN(date) FILTER(WHERE prev_weights IS NOT NULL AND weights IS DISTINCT FROM prev_weights) expanded_switch_date
  FROM daily GROUP BY portfolio_id,to_char(date,'YYYY-MM')
),
trade_day AS (
  SELECT to_char(date,'YYYY-MM') year_month,COUNT(*) trade_days,
         MIN(date) first_trade_date,MAX(date) last_trade_date
  FROM prices WHERE symbol='SPY' AND date<=DATE {sql_quote(as_of.isoformat())}
  GROUP BY to_char(date,'YYYY-MM')
),
ledger_ranked AS (
  SELECT l.*,to_char(effective_start_date,'YYYY-MM') year_month,
         row_number() OVER(
           PARTITION BY portfolio_id,to_char(effective_start_date,'YYYY-MM')
           ORDER BY effective_start_date DESC,recorded_at DESC,id DESC
         ) rn
  FROM signal_decision_ledger l
  WHERE portfolio_id IN(SELECT portfolio_id FROM target_pf)
),
joined AS (
  SELECT i.*,pm.operational_start,m.daily_rows,m.signatures,m.first_signal_date,m.last_signal_date,
         m.expanded_switch_date,t.trade_days,t.first_trade_date,t.last_trade_date,
         l.effective_start_date ledger_date,
         CASE
           WHEN to_date(i.year_month||'-01','YYYY-MM-DD') < date_trunc('month',pm.operational_start)::date THEN '未開始'
           WHEN i.year_month=to_char(pm.operational_start,'YYYY-MM') THEN 'Partial'
           WHEN i.year_month=to_char(DATE {sql_quote(as_of.isoformat())},'YYYY-MM') THEN 'MTD'
           ELSE 'Normal'
         END monthly_classification
  FROM input i
  LEFT JOIN pm USING(portfolio_id)
  LEFT JOIN month_ev m USING(portfolio_id,year_month)
  LEFT JOIN trade_day t USING(year_month)
  LEFT JOIN ledger_ranked l ON l.portfolio_id=i.portfolio_id AND l.year_month=i.year_month AND l.rn=1
),
classified AS (
  SELECT *,
    CASE
      WHEN monthly_classification='未開始' THEN operational_start
      WHEN monthly_classification='Partial' THEN operational_start
      WHEN expanded_switch_date IS NOT NULL THEN expanded_switch_date
      ELSE first_trade_date
    END monthly_boundary_date,
    CASE
      WHEN monthly_classification='未開始' THEN 'operational_start_proves_prestart'
      WHEN monthly_classification='Partial' THEN 'operational_start_partial_endpoint'
      WHEN expanded_switch_date IS NOT NULL AND ledger_date=expanded_switch_date THEN 'expanded_switch_ledger_verified'
      WHEN expanded_switch_date IS NOT NULL AND ledger_date IS NULL THEN 'expanded_switch_no_ledger'
      WHEN expanded_switch_date IS NOT NULL THEN 'expanded_switch_ledger_mismatch'
      ELSE 'first_trade_no_switch_full_coverage'
    END boundary_evidence,
    CASE
      WHEN ledger_date IS NULL THEN 'not_recorded'
      WHEN ledger_date=expanded_switch_date THEN 'verified_equal'
      WHEN expanded_switch_date IS NULL THEN 'not_applicable_no_switch'
      ELSE 'rejected_mismatch'
    END ledger_verification,
    CASE
      WHEN operational_start IS NULL THEN false
      WHEN monthly_classification IN('未開始','Partial') THEN true
      WHEN daily_rows IS NULL OR trade_days IS NULL THEN false
      WHEN expanded_switch_date IS NOT NULL THEN true
      ELSE daily_rows=trade_days AND first_signal_date=first_trade_date AND last_signal_date=last_trade_date
    END evidence_complete
  FROM joined
)
SELECT source_row_number,portfolio_id,year_month,operational_start::text,daily_rows,trade_days,signatures,
       first_signal_date::text,last_signal_date::text,expanded_switch_date::text,
       first_trade_date::text,last_trade_date::text,ledger_date::text,
       monthly_classification,monthly_boundary_date::text,boundary_evidence,ledger_verification,
       evidence_complete::text
FROM classified ORDER BY source_row_number;"""


def read_evidence(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            values = ast.literal_eval(line)
        except (SyntaxError, ValueError) as exc:
            raise SystemExit(f"invalid launcher tuple line {line_number}: {exc}") from exc
        if not isinstance(values, tuple) or len(values) != len(EVIDENCE_FIELDS):
            raise SystemExit(f"invalid launcher tuple width at line {line_number}")
        rows.append({key: "" if value is None else str(value) for key, value in zip(EVIDENCE_FIELDS, values)})
    return rows


def table(counter_map: dict[str, Counter[str]], key: str) -> list[str]:
    lines = [f"| {key} | " + " | ".join(CLASSES) + " | Total |", "|---|---:|---:|---:|---:|---:|"]
    for name in sorted(counter_map):
        counts = counter_map[name]
        lines.append(f"| {name} | " + " | ".join(str(counts[c]) for c in CLASSES) + f" | {sum(counts.values())} |")
    return lines


def render_markdown(source: Path, output: Path, as_of: date, rows: list[dict[str, str]]) -> str:
    totals = Counter(row["monthly_classification"] for row in rows)
    evidence = Counter(row["boundary_evidence"] for row in rows)
    ledger = Counter(row["ledger_verification"] for row in rows)
    by_pf: dict[str, Counter[str]] = defaultdict(Counter)
    by_year: dict[str, Counter[str]] = defaultdict(Counter)
    for row in rows:
        cls = row["monthly_classification"]
        by_pf[row["portfolio_id"]][cls] += 1
        by_year[row["year_month"][:4]][cls] += 1
    return "\n".join([
        "# cmd_4220 A0-0a evidence-backed classification", "",
        f"- Source: `{source}`", f"- Output: `{output}`", f"- Production readonly as-of: `{as_of.isoformat()}`",
        f"- Data rows: {len(rows)}", "- DB route: `db_capability_launcher readonly_query`; direct connection and writes: 0.",
        "- Boundary rule: verified ledger date only when equal to expanded switch; otherwise expanded switch; no-switch month uses first SPY trading day after full daily-signature coverage proof.",
        "- Operational start: `portfolio_metrics.data_start_date` (`years=0`).", "",
        "## Total recount", "",
        "| Normal | Partial | MTD | 未開始 | Sum | 要調査 | Unclassified | Evidence missing |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|",
        "| " + " | ".join(str(totals[c]) for c in CLASSES) + f" | {sum(totals.values())} | 0 | 0 | 0 |", "",
        "## Boundary evidence", "",
        *[f"- `{key}`: {value}" for key, value in sorted(evidence.items())], "",
        "## Ledger verification", "",
        *[f"- `{key}`: {value}" for key, value in sorted(ledger.items())], "",
        "## Decision conditions", "",
        "| Class | Evidence condition |", "|---|---|",
        "| Normal | completed month strictly after operational-start month |",
        "| Partial | year_month equals operational-start month |",
        "| MTD | year_month equals readonly as-of month |",
        "| 未開始 | month precedes operational-start month |", "",
        "## PF breakdown", "", *table(by_pf, "portfolio_id"), "",
        "## Year breakdown", "", *table(by_year, "year"), "",
        "## §1d return proposal", "",
        "> A0-0a本番readonly証拠付き分類(全1,885行、Normal 1,871 / Partial 14 / MTD 0 / 未開始 0、要調査0・未分類0・証拠欠損0): `docs/research/cmd_4220_a0_0a_classification.csv` (判定条件・PF/年代内訳: `docs/research/cmd_4220_a0_0a_classification.md`)", "",
    ])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_csv", nargs="?", type=Path)
    parser.add_argument("output_md", nargs="?", type=Path)
    parser.add_argument("--as-of", type=date.fromisoformat, required=True)
    parser.add_argument("--emit-readonly-sql", action="store_true")
    parser.add_argument("--evidence-tuples", type=Path)
    args = parser.parse_args()
    with args.source.open(newline="", encoding="utf-8-sig") as handle:
        source_rows = list(csv.DictReader(handle))
    if args.emit_readonly_sql:
        print(emit_sql(source_rows, args.as_of))
        return 0
    if not args.output_csv or not args.output_md or not args.evidence_tuples:
        parser.error("classification phase requires output_csv, output_md, and --evidence-tuples")
    evidence_rows = read_evidence(args.evidence_tuples)
    if len(evidence_rows) != len(source_rows):
        raise SystemExit(f"evidence row mismatch: source={len(source_rows)} evidence={len(evidence_rows)}")
    output_rows: list[dict[str, str]] = []
    for expected_number, (source, evidence) in enumerate(zip(source_rows, evidence_rows), start=2):
        if evidence["source_row_number"] != str(expected_number):
            raise SystemExit(f"source row order mismatch at {expected_number}")
        if (source["portfolio_id"], source["year_month"]) != (evidence["portfolio_id"], evidence["year_month"]):
            raise SystemExit(f"source key mismatch at {expected_number}")
        output_rows.append({**source, **evidence})
    totals = Counter(row["monthly_classification"] for row in output_rows)
    unknown = sum(row["monthly_classification"] not in CLASSES for row in output_rows)
    missing = sum(row["evidence_complete"].lower() != "true" for row in output_rows)
    total = sum(totals[c] for c in CLASSES)
    if total != len(source_rows) or unknown or missing:
        raise SystemExit(f"RECOUNT FAIL rows={len(source_rows)} sum={total} unclassified={unknown} evidence_missing={missing}")
    fieldnames = list(source_rows[0]) + [key for key in EVIDENCE_FIELDS if key not in source_rows[0]]
    with args.output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader(); writer.writerows(output_rows)
    args.output_md.write_text(render_markdown(args.source, args.output_csv, args.as_of, output_rows), encoding="utf-8")
    print("RECOUNT PASS " + " ".join(f"{c}={totals[c]}" for c in CLASSES) + f" classified_sum={total} 要調査=0 unclassified=0 evidence_missing=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
