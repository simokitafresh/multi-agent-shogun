#!/usr/bin/env python3
"""Render a 12-month return table PNG for the public universe (SPY/VEU/SGOV).

Data source: EODHD (https://eodhd.com/api/eod/{SYMBOL}.US), read-only, as
directed by the task. The token is read from EODHD_API_TOKEN (never printed
or logged) and is not embedded in this script. Adjusted close is used for
the monthly return calculation. If EODHD cannot be reached or a ticker is
missing, the script fails closed (exit 1, result=FAIL) rather than silently
falling back to another source.

No portfolio names, holdings, or secret-tier data are included by design:
the output only ever contains ticker symbols and their public price returns.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import date, timedelta

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import requests

EODHD_BASE_URL = "https://eodhd.com/api/eod"
EODHD_TOKEN_ENV = "EODHD_API_TOKEN"
UNIVERSE = ["SPY", "VEU", "SGOV"]


def fetch_prices(symbols: list[str], date_from: str, date_to: str, token: str) -> list[dict]:
    rows: list[dict] = []
    for symbol in symbols:
        resp = requests.get(
            f"{EODHD_BASE_URL}/{symbol}.US",
            params={
                "api_token": token,
                "fmt": "json",
                "period": "d",
                "order": "a",
                "from": date_from,
                "to": date_to,
            },
            timeout=30,
        )
        resp.raise_for_status()
        payload = resp.json()
        if not isinstance(payload, list):
            raise ValueError(f"unexpected EODHD response for {symbol}: {payload!r}"[:200])
        for row in payload:
            close = row.get("adjusted_close", row.get("close"))
            if close is None:
                continue
            rows.append({"symbol": symbol, "date": row["date"], "close": float(close)})
    return rows


def month_end_closes(rows: list[dict]) -> dict[str, dict[str, float]]:
    by_symbol: dict[str, dict[str, tuple[str, float]]] = {}
    for row in rows:
        symbol = row["symbol"]
        ym = row["date"][:7]
        prior = by_symbol.setdefault(symbol, {}).get(ym)
        if prior is None or row["date"] > prior[0]:
            by_symbol[symbol][ym] = (row["date"], float(row["close"]))
    return {sym: {ym: close for ym, (_, close) in ym_map.items()} for sym, ym_map in by_symbol.items()}


def last_complete_month_end(as_of: date) -> date:
    first_of_this_month = as_of.replace(day=1)
    return first_of_this_month - timedelta(days=1)


def trailing_12_month_labels(as_of: date) -> list[str]:
    year, month = as_of.year, as_of.month
    labels = []
    for _ in range(13):
        labels.append(f"{year:04d}-{month:02d}")
        month -= 1
        if month == 0:
            month = 12
            year -= 1
    return list(reversed(labels))


def build_return_table(closes: dict[str, dict[str, float]], symbols: list[str], as_of: date):
    labels = trailing_12_month_labels(as_of)
    months = labels[1:]
    table_rows = []
    missing = {sym: 0 for sym in symbols}
    for i in range(1, len(labels)):
        prev_ym, cur_ym = labels[i - 1], labels[i]
        row = [cur_ym]
        for sym in symbols:
            prev_close = closes.get(sym, {}).get(prev_ym)
            cur_close = closes.get(sym, {}).get(cur_ym)
            if prev_close is None or cur_close is None:
                row.append(None)
                missing[sym] += 1
            else:
                row.append((cur_close / prev_close - 1.0) * 100.0)
        table_rows.append(row)
    return months, table_rows, missing


def render_png(months: list[str], rows: list[list], symbols: list[str], out_path: str, as_of: date) -> None:
    col_labels = ["Month"] + symbols
    cell_text = []
    for row in rows:
        cells = [row[0]]
        for val in row[1:]:
            cells.append("—" if val is None else f"{val:+.1f}%")
        cell_text.append(cells)

    fig_height = 0.34 * (len(rows) + 1) + 0.7
    fig, ax = plt.subplots(figsize=(6.4, fig_height), dpi=150)
    ax.axis("off")
    ax.set_title(
        f"Public universe — trailing 12-month returns (through {as_of.isoformat()})",
        fontsize=11,
        pad=10,
    )
    table = ax.table(
        cellText=cell_text,
        colLabels=col_labels,
        cellLoc="center",
        bbox=[0.0, 0.0, 1.0, 0.92],
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    for (r, c), cell in table.get_celld().items():
        if r == 0:
            cell.set_facecolor("#eef1f5")
            cell.set_text_props(weight="bold")
    fig.tight_layout()
    fig.savefig(out_path, format="png", bbox_inches="tight")
    plt.close(fig)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="output PNG path")
    parser.add_argument(
        "--as-of",
        default=None,
        help="YYYY-MM-DD month-end to end the table at; default=last complete month-end",
    )
    parser.add_argument(
        "--symbols", default=",".join(UNIVERSE), help="comma-separated ticker list"
    )
    args = parser.parse_args()

    symbols = [s.strip().upper() for s in args.symbols.split(",") if s.strip()]
    as_of = (
        date.fromisoformat(args.as_of)
        if args.as_of
        else last_complete_month_end(date.today())
    )

    token = os.environ.get(EODHD_TOKEN_ENV, "").strip()
    if not token:
        print(json.dumps({"result": "FAIL", "reason": f"{EODHD_TOKEN_ENV} is not set"}))
        return 1

    date_to = (as_of + timedelta(days=1)).isoformat()
    date_from = (as_of - timedelta(days=410)).isoformat()

    try:
        rows_raw = fetch_prices(symbols, date_from, date_to, token)
    except (requests.RequestException, ValueError) as exc:
        print(json.dumps({"result": "FAIL", "reason": f"eodhd_fetch_error: {exc}"}))
        return 1

    if not rows_raw:
        print(json.dumps({"result": "FAIL", "reason": "empty_response"}))
        return 1

    closes = month_end_closes(rows_raw)
    months, table_rows, missing = build_return_table(closes, symbols, as_of)

    present = [sym for sym in symbols if closes.get(sym)]
    if len(present) != len(symbols):
        print(
            json.dumps(
                {
                    "result": "FAIL",
                    "reason": "ticker_missing",
                    "present": present,
                    "requested": symbols,
                }
            )
        )
        return 1

    render_png(months, table_rows, symbols, args.out, as_of)

    with open(args.out, "rb") as handle:
        data = handle.read()
    sha256 = hashlib.sha256(data).hexdigest()

    summary = {
        "result": "PASS",
        "path": args.out,
        "bytes": len(data),
        "sha256": sha256,
        "tickers": symbols,
        "tickers_ok": f"{len(present)}/{len(symbols)}",
        "period_months": [months[0], months[-1]],
        "missing_month_counts": missing,
        "as_of": as_of.isoformat(),
        "source": "eodhd.com /api/eod (adjusted_close)",
    }
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
