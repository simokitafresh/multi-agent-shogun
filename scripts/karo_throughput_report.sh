#!/usr/bin/env bash
# Build the deterministic daily throughput table for the karo lane.
# Inputs are append-only ledgers; no live state or network is consulted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATE="${1:-}"
AS_OF=""
if [[ -z "$DATE" || ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf 'usage: %s <YYYY-MM-DD> [--as-of <ISO-8601>]\n' "${BASH_SOURCE[0]}" >&2
    exit 2
fi
shift || true
if [[ "${1:-}" == "--as-of" ]]; then
    AS_OF="${2:-}"
    [[ "$AS_OF" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)$ ]] || {
        printf 'karo_throughput_report: --as-of requires ISO-8601 timestamp\n' >&2
        exit 2
    }
    shift 2
fi
[[ $# -eq 0 ]] || { printf 'karo_throughput_report: unexpected argument\n' >&2; exit 2; }

OUT_DIR="${KARO_THROUGHPUT_OUTPUT_DIR:-$ROOT/docs/research/karo_throughput_daily}"
OUT="$OUT_DIR/$DATE"
[[ -n "$AS_OF" ]] && OUT="${OUT}_${AS_OF}"
OUT+='.md'
mkdir -p "$OUT_DIR"

export KARO_THROUGHPUT_DATE="$DATE"
export KARO_THROUGHPUT_AS_OF="$AS_OF"
export KARO_THROUGHPUT_ROOT="$ROOT"
export KARO_THROUGHPUT_OUT="$OUT"
export KARO_THROUGHPUT_DEFENSE_LOG="${KARO_THROUGHPUT_DEFENSE_LOG:-$ROOT/logs/defense_overhead.jsonl}"
export KARO_THROUGHPUT_GATE_LOG="${KARO_THROUGHPUT_GATE_LOG:-$ROOT/logs/gate_metrics.log}"
export KARO_THROUGHPUT_WATCHER_LOGS="${KARO_THROUGHPUT_WATCHER_LOGS:-$ROOT/logs/inbox_watcher_karo.log.1:$ROOT/logs/inbox_watcher_karo.log}"
export KARO_THROUGHPUT_TIMING_LOGS="${KARO_THROUGHPUT_TIMING_LOGS:-$ROOT/logs/cmd_complete_gate_function_timing.jsonl:$ROOT/logs/deploy_task_function_timing.jsonl}"
export KARO_THROUGHPUT_RETRY_ROOT="${KARO_THROUGHPUT_RETRY_ROOT:-$ROOT/queue/gates}"

exec python3 - <<'PY'
import datetime as dt
import glob
import json
import os
import re
from collections import Counter, defaultdict
from pathlib import Path

DATE = os.environ["KARO_THROUGHPUT_DATE"]
AS_OF = os.environ["KARO_THROUGHPUT_AS_OF"]
OUT = Path(os.environ["KARO_THROUGHPUT_OUT"])

UTC = dt.timezone.utc
JST = dt.timezone(dt.timedelta(hours=9), "JST")

def parse_iso(value):
    if not value:
        return None
    raw = str(value).strip()
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)

cutoff = parse_iso(AS_OF) if AS_OF else None

def in_domain(stamp, local_date=False):
    parsed = parse_iso(stamp)
    if parsed is None:
        return False
    if local_date:
        matches = parsed.astimezone(JST).date().isoformat() == DATE
    else:
        matches = parsed.date().isoformat() == DATE
    return matches and (cutoff is None or parsed <= cutoff)

def legacy_time(row):
    observed = row.get("observed_at")
    if observed:
        return observed
    match = re.search(r"-(\d{13,})$", str(row.get("execution_id", "")))
    if not match:
        return None
    try:
        return dt.datetime.fromtimestamp(int(match.group(1)) / 1_000_000, UTC).isoformat().replace("+00:00", "Z")
    except (OverflowError, OSError, ValueError):
        return None

def read_jsonl(path):
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return []
    rows = []
    with fh:
        for raw in fh:
            try:
                row = json.loads(raw)
            except (TypeError, ValueError):
                continue
            if isinstance(row, dict):
                rows.append(row)
    return rows

def percentile(values, q):
    if not values:
        return None
    values = sorted(values)
    # Nearest-rank is stable for small fixtures and matches the operational
    # p95 convention used by the existing throughput reports.
    rank = max(1, int(len(values) * q + 0.999999))
    return values[rank - 1]

def fmt(value):
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.3f}".rstrip("0").rstrip(".")
    return str(value)

def row(label, values, unit="ms"):
    vals = [float(v) for v in values]
    return [label, str(len(vals)), fmt(percentile(vals, .5)), fmt(percentile(vals, .95)), fmt(sum(vals)), unit]

def table(lines, headers=("経路/指標", "回数", "p50", "p95", "合計", "単位")):
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("|" + "|".join("---" for _ in headers) + "|")
    return lines

def split_paths(value):
    return [Path(p) for p in str(value).split(":") if p]

def date_text(value):
    match = re.search(r"\[[A-Z][a-z]{2} ([A-Z][a-z]{2})\s+(\d{1,2}) (\d{2}:\d{2}:\d{2}) [A-Z]+ (\d{4})\]", value)
    if not match:
        return None
    return f"{match.group(4)}-{dt.datetime.strptime(match.group(1), '%b').month:02d}-{int(match.group(2)):02d}T{match.group(3)}+09:00"

def log_line_time(value):
    return parse_iso(value.split("\t", 1)[0]) if value[:4].isdigit() else parse_iso(date_text(value))

def keep_log_line(value, local_date=True):
    parsed = log_line_time(value)
    if parsed is None:
        return False
    return in_domain(parsed.isoformat(), local_date=local_date) and (cutoff is None or parsed <= cutoff)

def source_key(row_data):
    return f"{row_data.get('source', '-')} / {row_data.get('check_id', '-')}"

def agent_key(row_data):
    agent = row_data.get("agent", "-")
    return agent if isinstance(agent, str) and re.fullmatch(r"[a-z0-9_-]{1,32}", agent) else "-"

def main():
    output = [f"# 家老スループット日次表 — {DATE}", "", f"- 対象日: `{DATE}`", f"- as-of: `{AS_OF or '終日確定'}`", "- 入力: append-only logs のみ（ネットワーク・live state 不使用）", ""]
    output.append("## 経路別計測")
    table(output)

    defense = []
    for item in read_jsonl(os.environ["KARO_THROUGHPUT_DEFENSE_LOG"]):
        stamp = item.get("timestamp")
        if not in_domain(stamp, local_date=True):
            continue
        try:
            wall = int(item.get("wall_ms"))
        except (TypeError, ValueError):
            continue
        defense.append(item | {"_wall": wall})
    grouped = defaultdict(list)
    for item in defense:
        grouped[source_key(item)].append(item["_wall"])
    for key in sorted(grouped):
        output.append("| " + " | ".join(row(key, grouped[key])) + " |")
    output.append("| " + " | ".join(row("defense_overhead / total", [x["_wall"] for x in defense])) + " |") if defense else output.append("| defense_overhead / total | 0 | - | - | 0 | ms |")

    timing = []
    for path in split_paths(os.environ["KARO_THROUGHPUT_TIMING_LOGS"]):
        for item in read_jsonl(path):
            stamp = legacy_time(item)
            if not in_domain(stamp):
                continue
            try:
                elapsed = int(item.get("elapsed_us")) / 1000.0
            except (TypeError, ValueError):
                continue
            timing.append((item.get("script", path.name), elapsed))
    timing_groups = defaultdict(list)
    for name, elapsed in timing:
        timing_groups[name].append(elapsed)
    for name in sorted(timing_groups):
        output.append("| " + " | ".join(row(f"function_timing / {name}", timing_groups[name])) + " |")
    if not timing:
        output.append("| function_timing / total | 0 | - | - | 0 | ms |")

    gate = []
    waits = Counter()
    for path in [Path(os.environ["KARO_THROUGHPUT_GATE_LOG"])] :
        try:
            raw_lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            raw_lines = []
        for line in raw_lines:
            if not keep_log_line(line, local_date=True):
                continue
            fields = line.split("\t")
            if len(fields) < 4:
                continue
            state, reason = fields[2], fields[3]
            if state == "WAIT":
                waits[reason] += 1
            match = re.search(r"(?:^|\s)duration_sec=([0-9]+(?:\.[0-9]+)?)", line)
            if match:
                gate.append(float(match.group(1)) * 1000)
    output.append("| " + " | ".join(row("cmd_complete_gate / CLEAR duration", gate)) + " |" if gate else "| cmd_complete_gate / CLEAR duration | 0 | - | - | 0 | ms |")
    output.append("")
    output.append("## GATE WAIT 理由")
    table(output, ("理由", "回数"))
    for reason in sorted(waits):
        output.append(f"| {reason} | {waits[reason]} |")
    if not waits:
        output.append("| - | 0 |")

    held = []
    for path in split_paths(os.environ["KARO_THROUGHPUT_WATCHER_LOGS"]):
        try:
            watcher_lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            watcher_lines = []
        for line in watcher_lines:
            if "[DELIVERY-LATENCY]" not in line or not keep_log_line(line, local_date=True):
                continue
            match = re.search(r"held\s+([0-9]+)s", line)
            if match:
                held.append(int(match.group(1)) * 1000)
    output.append("")
    output.append("## 配達 held")
    table(output)
    output.append("| " + " | ".join(row("inbox_watcher_karo / delivery_held", held)) + " |" if held else "| inbox_watcher_karo / delivery_held | 0 | - | - | 0 | ms |")

    retry_counts = Counter()
    retry_paths = sorted(glob.glob(str(Path(os.environ["KARO_THROUGHPUT_RETRY_ROOT"]) / "*" / "auto_push_ancestry_retry.log")))
    for path in retry_paths:
        try:
            retry_lines = Path(path).read_text(encoding="utf-8").splitlines()
        except OSError:
            retry_lines = []
        for line in retry_lines:
            if not keep_log_line(line, local_date=True):
                continue
            fields = line.split("\t")
            if len(fields) >= 4:
                match = re.search(r"result=([^ ]+)", fields[3])
                retry_counts[match.group(1) if match else "unknown"] += 1
    output.append("")
    output.append("## auto-push retry")
    table(output, ("結果", "回数"))
    for result in sorted(retry_counts):
        output.append(f"| {result} | {retry_counts[result]} |")
    if not retry_counts:
        output.append("| - | 0 |")

    output.append("")
    output.append("## agent 按分（defense_overhead）")
    table(output, ("agent", "回数", "wall_ms 合計"))
    by_agent = defaultdict(lambda: [0, 0])
    for item in defense:
        agent = agent_key(item)
        by_agent[agent][0] += 1
        by_agent[agent][1] += item["_wall"]
    for agent in sorted(by_agent):
        output.append(f"| {agent} | {by_agent[agent][0]} | {by_agent[agent][1]} |")
    if not by_agent:
        output.append("| - | 0 | 0 |")

    OUT.write_text("\n".join(output) + "\n", encoding="utf-8")
    print(f"karo_throughput_report: wrote {OUT} defense={len(defense)} timing={len(timing)} gate_clear={len(gate)} held={len(held)} retry={sum(retry_counts.values())}")

main()
PY
