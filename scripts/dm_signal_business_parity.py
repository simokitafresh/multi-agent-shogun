#!/usr/bin/env python3
"""Compare DM-Signal business-result snapshots.

The snapshot lane obtains both business tables through the registered
``readonly_query`` capability.  The compare lane is deliberately independent
of a database connection so that all mismatch classes can be exercised with
short-lived JSON fixtures.
"""

from __future__ import annotations

import argparse
import ast
import datetime as dt
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "scripts" / "db_capability_launcher.py"
DM_SIGNAL_ROOT = Path("/mnt/c/Python_app/DM-signal")

MONTHLY_COLUMNS = [
    "portfolio_id",
    "year_month",
    "cumulative_return",
    "cumulative_return_open",
    "monthly_return",
    "monthly_return_open",
    "benchmark_cumulative",
    "benchmark_cumulative_open",
    "benchmark_return",
    "benchmark_return_open",
    "in_market",
    "holding_signal",
]
MONTHLY_PK = ["portfolio_id", "year_month"]
METRICS_PK = ["portfolio_id", "years"]
METRICS_COLUMNS = [
    "portfolio_id",
    "years",
    "metrics_json",
    "data_start_date",
    "data_end_date",
    "months_count",
]
EXCLUDED_COLUMNS = ["calculated_at", "run_provenance", "provenance"]


def _json_default(value: Any) -> str:
    if isinstance(value, (dt.date, dt.datetime)):
        return value.isoformat()
    raise TypeError(f"unsupported JSON value: {type(value).__name__}")


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"FAIL: cannot read snapshot {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"FAIL: snapshot root must be an object: {path}")
    return value


def _rows(table: dict[str, Any], name: str) -> list[dict[str, Any]]:
    rows = table.get("rows", [])
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise SystemExit(f"FAIL: {name}.rows must be a list of objects")
    return rows


def _table_payload(snapshot: dict[str, Any], name: str) -> dict[str, Any]:
    tables = snapshot.get("tables")
    if not isinstance(tables, dict):
        raise SystemExit("FAIL: snapshot.tables must be an object")
    table = tables.get(name)
    if not isinstance(table, dict):
        raise SystemExit(f"FAIL: snapshot.tables.{name} must be an object")
    return table


def _pk(row: dict[str, Any], columns: list[str]) -> tuple[Any, ...]:
    missing = [column for column in columns if column not in row]
    if missing:
        raise SystemExit(f"FAIL: row is missing primary-key column(s): {missing}")
    return tuple(row[column] for column in columns)


def _pk_text(key: tuple[Any, ...]) -> dict[str, Any]:
    return {"values": list(key)}


def _leaf_values(value: Any, prefix: str = "") -> Iterable[tuple[str, Any]]:
    if isinstance(value, dict):
        for key in sorted(value):
            child = f"{prefix}.{key}" if prefix else str(key)
            yield from _leaf_values(value[key], child)
    elif isinstance(value, list):
        for index, child_value in enumerate(value):
            yield from _leaf_values(child_value, f"{prefix}[{index}]")
    else:
        yield prefix, value


def _metric_fields(row: dict[str, Any]) -> dict[str, Any]:
    metrics = row.get("metrics_json")
    if not isinstance(metrics, (dict, list)):
        raise SystemExit("FAIL: portfolio_metrics.metrics_json must be an object or array")
    fields = {f"metrics_json.{path}": value for path, value in _leaf_values(metrics)}
    for column in ("data_start_date", "data_end_date", "months_count"):
        fields[column] = row.get(column)
    return fields


def _business_fields(name: str, row: dict[str, Any]) -> dict[str, Any]:
    if name == "monthly_returns":
        return {column: row.get(column) for column in MONTHLY_COLUMNS[2:]}
    if name == "portfolio_metrics":
        return _metric_fields(row)
    raise AssertionError(name)


def _compare_table(
    name: str,
    before: dict[str, Any],
    after: dict[str, Any],
    pk_columns: list[str],
    samples: list[dict[str, Any]],
) -> dict[str, Any]:
    before_rows = _rows(before, name)
    after_rows = _rows(after, name)
    before_map = {_pk(row, pk_columns): row for row in before_rows}
    after_map = {_pk(row, pk_columns): row for row in after_rows}
    duplicate_before = len(before_rows) - len(before_map)
    duplicate_after = len(after_rows) - len(after_map)
    missing = sorted(set(before_map) - set(after_map), key=repr)
    extra = sorted(set(after_map) - set(before_map), key=repr)
    mismatched_rows = 0
    mismatched_fields = 0
    compared_rows = 0
    for key in sorted(set(before_map) & set(after_map), key=repr):
        compared_rows += 1
        fields_before = _business_fields(name, before_map[key])
        fields_after = _business_fields(name, after_map[key])
        row_mismatch = False
        for column in sorted(set(fields_before) | set(fields_after)):
            pre = fields_before.get(column)
            post = fields_after.get(column)
            if pre != post:
                row_mismatch = True
                mismatched_fields += 1
                if len(samples) < 10:
                    samples.append(
                        {
                            "table": name,
                            "pk": _pk_text(key),
                            "column": column,
                            "pre": pre,
                            "post": post,
                        }
                    )
        if row_mismatch:
            mismatched_rows += 1
    return {
        "before_rows": len(before_rows),
        "after_rows": len(after_rows),
        "compared_rows": compared_rows,
        "missing_rows": len(missing),
        "extra_rows": len(extra),
        "mismatched_rows": mismatched_rows,
        "mismatched_fields": mismatched_fields,
        "duplicate_before_rows": duplicate_before,
        "duplicate_after_rows": duplicate_after,
        "missing_pk_sample": [_pk_text(key) for key in missing[:10]],
        "extra_pk_sample": [_pk_text(key) for key in extra[:10]],
    }


def compare(before_path: Path, after_path: Path) -> int:
    before = _read_json(before_path)
    after = _read_json(after_path)
    samples: list[dict[str, Any]] = []
    monthly_before = _table_payload(before, "monthly_returns")
    monthly_after = _table_payload(after, "monthly_returns")
    metrics_before = _table_payload(before, "portfolio_metrics")
    metrics_after = _table_payload(after, "portfolio_metrics")
    monthly = _compare_table(
        "monthly_returns", monthly_before, monthly_after, MONTHLY_PK, samples
    )
    metrics = _compare_table(
        "portfolio_metrics", metrics_before, metrics_after, METRICS_PK, samples
    )
    totals = {
        key: monthly[key] + metrics[key]
        for key in (
            "missing_rows",
            "extra_rows",
            "mismatched_rows",
            "mismatched_fields",
            "duplicate_before_rows",
            "duplicate_after_rows",
        )
    }
    difference_count = sum(
        totals[key]
        for key in (
            "missing_rows",
            "extra_rows",
            "mismatched_fields",
            "duplicate_before_rows",
            "duplicate_after_rows",
        )
    )
    result = {
        "status": "PASS" if difference_count == 0 else "FAIL",
        "definition": "Business parity compares only declared business fields by table primary key; calculated_at and run provenance are excluded.",
        "snapshot_versions": {
            "pre": before.get("snapshot_version"),
            "post": after.get("snapshot_version"),
        },
        "tables": {
            "monthly_returns": {
                "primary_key": MONTHLY_PK,
                "business_columns": MONTHLY_COLUMNS[2:],
                **monthly,
            },
            "portfolio_metrics": {
                "primary_key": METRICS_PK,
                "business_columns": ["metrics_json.<all leaf>", "data_start_date", "data_end_date", "months_count"],
                **metrics,
            },
        },
        "totals": totals | {"difference_count": difference_count},
        "samples": samples,
        "sample_limit": 10,
        "excluded_columns": EXCLUDED_COLUMNS,
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, default=_json_default))
    return 0 if difference_count == 0 else 1


def _sql() -> str:
    monthly_columns = ", ".join(MONTHLY_COLUMNS)
    return f"""
WITH meta AS (
  SELECT txid_current_snapshot()::text AS snapshot_version,
         clock_timestamp()::text AS captured_at
),
monthly AS (
  SELECT COALESCE(json_agg(to_jsonb(m) ORDER BY m.portfolio_id, m.year_month), '[]'::json) AS rows,
         count(*) AS row_count
  FROM (SELECT {monthly_columns} FROM monthly_returns) AS m
),
metrics AS (
  SELECT COALESCE(json_agg(to_jsonb(pm) ORDER BY pm.portfolio_id, pm.years), '[]'::json) AS rows,
         count(*) AS row_count
  FROM (
    SELECT portfolio_id, years, metrics_json, data_start_date, data_end_date, months_count
    FROM portfolio_metrics
  ) AS pm
)
SELECT json_build_object(
  'schema_version', 1,
  'snapshot_version', meta.snapshot_version,
  'captured_at', meta.captured_at,
  'tables', json_build_object(
    'monthly_returns', json_build_object(
      'primary_key', json_build_array('portfolio_id', 'year_month'),
      'columns', json_build_array({', '.join(repr(c) for c in MONTHLY_COLUMNS)}),
      'rows', monthly.rows,
      'row_count', monthly.row_count
    ),
    'portfolio_metrics', json_build_object(
      'primary_key', json_build_array('portfolio_id', 'years'),
      'columns', json_build_array({', '.join(repr(c) for c in METRICS_COLUMNS)}),
      'rows', metrics.rows,
      'row_count', metrics.row_count
    )
  )
)::text
FROM meta, monthly, metrics
""".strip()


def _launcher_json(sql: str) -> dict[str, Any]:
    nonce = secrets.token_urlsafe(24)
    credential_path = Path(tempfile.mktemp(prefix="dm-signal-db-", suffix=".env", dir="/tmp"))
    source = DM_SIGNAL_ROOT / "backend" / ".env"
    try:
        prepare = [
            sys.executable,
            str(LAUNCHER),
            "--capability", "readonly_query",
            "--mode", "readonly",
            "--confirm", "READONLY_DB_CHECK",
            "--credential-file", str(credential_path),
            "--credential-source-file", str(source),
            "--prepare-only",
        ]
        prepared = subprocess.run(prepare, text=True, capture_output=True)
        if prepared.returncode != 0:
            raise SystemExit(f"FAIL: readonly credential preparation: {prepared.stderr.strip()}")
        command = [
            sys.executable,
            str(LAUNCHER),
            "--capability", "readonly_query",
            "--mode", "readonly",
            "--confirm", "READONLY_DB_CHECK",
            "--credential-file", str(credential_path),
            "--nonce", nonce,
        ]
        result = subprocess.run(command, input=sql, text=True, capture_output=True)
        if result.returncode != 0:
            raise SystemExit(f"FAIL: readonly_query: {result.stderr.strip()}")
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if len(lines) != 1:
            raise SystemExit(f"FAIL: readonly_query returned {len(lines)} rows; expected 1")
        raw = ast.literal_eval(lines[0])
        if not isinstance(raw, tuple) or len(raw) != 1 or not isinstance(raw[0], str):
            raise SystemExit("FAIL: readonly_query returned an unexpected row shape")
        payload = json.loads(raw[0])
        if not isinstance(payload, dict):
            raise SystemExit("FAIL: snapshot payload is not an object")
        return payload
    finally:
        if credential_path.exists():
            credential_path.unlink()


def snapshot(output: Path) -> int:
    payload = _launcher_json(_sql())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True, default=_json_default) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "output": str(output), "snapshot_version": payload.get("snapshot_version")}, ensure_ascii=False))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    snapshot_parser = subparsers.add_parser("snapshot", help="capture a read-only business snapshot")
    snapshot_parser.add_argument("--output", type=Path, required=True)
    compare_parser = subparsers.add_parser("compare", help="compare two business snapshots")
    compare_parser.add_argument("--before", type=Path, required=True)
    compare_parser.add_argument("--after", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == "snapshot":
        return snapshot(args.output)
    return compare(args.before, args.after)


if __name__ == "__main__":
    raise SystemExit(main())
