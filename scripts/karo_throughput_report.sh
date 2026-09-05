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
export KARO_THROUGHPUT_DEFENSE_ARCHIVE="${KARO_THROUGHPUT_DEFENSE_ARCHIVE:-$(dirname "$KARO_THROUGHPUT_DEFENSE_LOG")/archive}"
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
import yaml

DATE = os.environ["KARO_THROUGHPUT_DATE"]
AS_OF = os.environ["KARO_THROUGHPUT_AS_OF"]
OUT = Path(os.environ["KARO_THROUGHPUT_OUT"])

UTC = dt.timezone.utc
JST = dt.timezone(dt.timedelta(hours=9), "JST")

def parse_iso(value, default_timezone=UTC):
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
        parsed = parsed.replace(tzinfo=default_timezone)
    return parsed.astimezone(UTC)

cutoff = parse_iso(AS_OF) if AS_OF else None
day_start = dt.datetime.fromisoformat(DATE).replace(tzinfo=JST).astimezone(UTC)
day_end = day_start + dt.timedelta(days=1)
wait_end = min(day_end, cutoff or dt.datetime.now(UTC))

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
        return
    with fh:
        for raw in fh:
            try:
                row = json.loads(raw)
            except (TypeError, ValueError):
                continue
            if isinstance(row, dict):
                yield row

def read_yaml_rows(path):
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8")) or []
    except (OSError, yaml.YAMLError):
        return []
    return payload if isinstance(payload, list) else []

def failure_origin_counts():
    """Count report FAIL events without merging generations or old rows."""
    paths = sorted(Path(os.environ["KARO_THROUGHPUT_ROOT"]).glob("logs/archive/gunshi_review_log*.yaml"))
    paths.append(Path(os.environ["KARO_THROUGHPUT_ROOT"]) / "logs/gunshi_review_log.yaml")
    seen_events = set()
    counts = Counter()
    total = 0
    classes = {"A", "B", "C", "D", "E"}
    for path in paths:
        for item in read_yaml_rows(path):
            if not isinstance(item, dict):
                continue
            stamp = item.get("reviewed_at") or item.get("timestamp")
            parsed = parse_iso(stamp, JST)
            if parsed is None or parsed.astimezone(JST).date().isoformat() != DATE:
                continue
            if cutoff is not None and parsed > cutoff:
                continue
            verdict = str(item.get("verdict") or item.get("review_verdict") or "").strip().upper()
            report_verdict = str(item.get("report_verdict") or "").strip().upper()
            if verdict not in {"FAIL", "REQUEST_CHANGES"} and report_verdict != "FAIL":
                continue
            event_id = str(item.get("review_event_id") or "").strip()
            if event_id:
                if event_id in seen_events:
                    continue
                seen_events.add(event_id)
            code = item.get("failure_origin_code")
            primary = str(code.get("primary") or "").strip() if isinstance(code, dict) else ""
            counts[primary if primary in classes else "unclassified"] += 1
            total += 1
    return counts, total

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
    return parse_iso(value.split("\t", 1)[0], JST) if value[:4].isdigit() else parse_iso(date_text(value))

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
    defense_paths = sorted(Path(os.environ["KARO_THROUGHPUT_DEFENSE_ARCHIVE"]).glob("defense_overhead_*.jsonl"))
    defense_paths.append(Path(os.environ["KARO_THROUGHPUT_DEFENSE_LOG"]))
    seen_events = set()
    for item in (item for path in defense_paths for item in read_jsonl(path)):
        stamp = item.get("timestamp")
        if not in_domain(stamp, local_date=True):
            continue
        try:
            wall = int(item.get("wall_ms"))
        except (TypeError, ValueError):
            continue
        identity = item.get("event_id") or json.dumps(item, sort_keys=True, ensure_ascii=False)
        if identity in seen_events:
            continue
        seen_events.add(identity)
        defense.append(item | {"_wall": wall})
    grouped = defaultdict(list)
    for item in defense:
        grouped[source_key(item)].append(item["_wall"])
    for key in sorted(grouped):
        output.append("| " + " | ".join(row(key, grouped[key])) + " |")
    output.append("| " + " | ".join(row("defense_overhead / total", [x["_wall"] for x in defense])) + " |") if defense else output.append("| defense_overhead / total | 0 | - | - | 0 | ms |")
    output.append("")
    output.append("- total・agent 合計は重なりを含むイベント加算値。拘束時間・CPU時間には使わない。")
    output.append("## health refresh（親windowと内訳を分離、wall time）")
    table(output)
    for check in ("refresh_window", "refresh_copy", "refresh_verify"):
        values = [x["_wall"] for x in defense if x.get("source") == "three_layer_health" and x.get("check_id") == check
                  and (check != "refresh_window" or ":end:" in str(x.get("event_id", "")))]
        output.append("| " + " | ".join(row(check, values)) + " |")
    output.append("- refresh_window=end の完了イベントのみ。copy/verifyはwindowの内訳なので足さない。未完了windowは含まない。CPU使用時間は未計測。")
    output.append("")
    table(output)

    timing = []
    call_sites = defaultdict(list)
    for path in split_paths(os.environ["KARO_THROUGHPUT_TIMING_LOGS"]):
        for item in read_jsonl(path):
            stamp = legacy_time(item)
            if not in_domain(stamp, local_date=True):
                continue
            try:
                elapsed = int(item.get("elapsed_us")) / 1000.0
            except (TypeError, ValueError):
                continue
            if item.get("schema") == "call_site_timing.v1":
                call_sites[str(item.get("call_site", "-"))].append(elapsed)
                continue
            timing.append((item.get("script", path.name), item.get("function", "-"), elapsed, str(item.get("execution_id", "-"))))
    timing_groups = defaultdict(list)
    for name, _, elapsed, _ in timing:
        timing_groups[name].append(elapsed)
    for name in sorted(timing_groups):
        output.append("| " + " | ".join(row(f"function_timing / {name}", timing_groups[name])) + " |")
    if not timing:
        output.append("| function_timing / total | 0 | - | - | 0 | ms |")

    # §7-4: deploy_task の全関数を集計してから合計時間順に上位を表示する。
    # 表示件数は可読性の上限であり、集計対象は全関数（件数を併記）とする。
    deploy_functions = defaultdict(list)
    deploy_executions = set()
    for name, function, elapsed, execution_id in timing:
        if name == "deploy_task.sh" and function != "-":
            deploy_functions[function].append(elapsed)
            deploy_executions.add(execution_id)
    output.append("")
    output.append("## deploy_task 関数別内訳（全関数集計・合計時間上位20）")
    output.append(f"- 実行数: {len(deploy_executions)} / 集計関数数: {len(deploy_functions)} / elapsed は関数計測値であり経路間の加算は禁止")
    table(output, ("関数", "実行数", "p50 ms", "p95 ms", "合計 ms"))
    ranked_functions = sorted(deploy_functions.items(), key=lambda item: (-sum(item[1]), item[0]))
    for function, values in ranked_functions[:20]:
        output.append(
            f"| {function} | {len(values)} | {fmt(percentile(values, .5))} | "
            f"{fmt(percentile(values, .95))} | {fmt(sum(values))} |"
        )
    if not deploy_functions:
        output.append("| - | 0 | - | - | 0 |")

    output.append("")
    output.append("## run_python_logged 呼出し元別（関数合計の内訳、加算禁止）")
    table(output)
    for site, values in sorted(call_sites.items()):
        output.append("| " + " | ".join(row(site, values)) + " |")
    if not call_sites:
        output.append("| 未計測（導入後の配備から記録） | 0 | - | - | 0 | ms |")

    gate = []
    waits = Counter()
    per_cmd = defaultdict(list)
    for path in [Path(os.environ["KARO_THROUGHPUT_GATE_LOG"])] :
        try:
            raw_lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            raw_lines = []
        for line in raw_lines:
            fields = line.split("\t")
            if len(fields) < 4:
                continue
            stamp = log_line_time(line)
            if stamp is None or stamp > wait_end:
                continue
            state, reason = fields[2], fields[3]
            within_day = keep_log_line(line, local_date=True)
            if state == "WAIT" and within_day:
                waits[reason] += 1
            per_cmd[fields[1]].append((stamp, state, reason))
            match = re.search(r"(?:^|\s)duration_sec=([0-9]+(?:\.[0-9]+)?)", line)
            if match and within_day and state == "CLEAR":
                gate.append(float(match.group(1)) * 1000)
    # 待ち理由別の時間: 同一 cmd の連続 gate 行の間隔を、前行の state:reason に帳付けする。
    # 「手」の p50 と足せない「待ち」の軸(設計書 §4.2)。reason は先頭 2 要素で丸める。
    wait_minutes = Counter()
    open_tail_minutes = 0.0
    wait_cmds = defaultdict(set)
    for cmd_id, entries in per_cmd.items():
        entries.sort(key=lambda e: e[0])
        for (t0, state, reason), (t1, next_state, _) in zip(entries, entries[1:] + [(wait_end, "", "")]):
            if state not in ("WAIT", "BLOCK"):
                continue
            start, end = max(t0, day_start), min(t1, wait_end)
            if end <= start:
                continue
            normalized = reason.removeprefix(state + ":")
            key = state + ":" + ":".join(normalized.split(":")[:2])
            wait_minutes[key] += (end - start).total_seconds() / 60.0
            if not next_state:
                open_tail_minutes += (end - start).total_seconds() / 60.0
            wait_cmds[key].add(cmd_id)
    output.append("| " + " | ".join(row("cmd_complete_gate / CLEAR duration", gate)) + " |" if gate else "| cmd_complete_gate / CLEAR duration | 0 | - | - | 0 | ms |")
    output.append("")
    output.append("## GATE WAIT 理由")
    table(output, ("理由", "回数"))
    for reason in sorted(waits):
        output.append(f"| {reason} | {waits[reason]} |")
    if not waits:
        output.append("| - | 0 |")

    origin_counts, origin_total = failure_origin_counts()
    output.append("")
    output.append("## failure origin（canonical + unclassified）")
    table(output, ("分類", "件数"))
    for label in ("A", "B", "C", "D", "E", "unclassified"):
        output.append(f"| {label} | {origin_counts[label]} |")
    canonical_total = sum(origin_counts[label] for label in ("A", "B", "C", "D", "E"))
    output.append(f"- canonical+unclassified={canonical_total}+{origin_counts['unclassified']}={origin_total}; 全FAIL={origin_total}")

    output.append("")
    output.append("## GATE 待ち理由別 時間（便の待ち。手の p50 と足せない）")
    output.append(f"- JST日境界で区間を切り、最終WAIT/BLOCKは締切 {wait_end.isoformat()} まで継続と推定。終端ログ欠落は過大推定となる。")
    table(output, ("state:reason", "待ち分", "比率", "cmd 数"))
    total_wait = sum(wait_minutes.values())
    output.append(f"- 総待ち {total_wait:.3f} 分のうち、後続ログ未観測の末尾推定 {open_tail_minutes:.3f} 分。残りは連続ログ間の状態推定であり実作業時間ではない。")
    for key, minutes in sorted(wait_minutes.items(), key=lambda kv: (-kv[1], kv[0])):
        share = f"{minutes / total_wait * 100:.0f}%" if total_wait else "-"
        output.append(f"| {key} | {minutes:.0f} | {share} | {len(wait_cmds[key])} |")
    if not wait_minutes:
        output.append("| - | 0 | - | 0 |")

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
    # held の正本は defense_overhead の inbox_watcher/delivery_held event(§6.1 行 8)。
    # watcher stderr 行(旧定義: first_unread_seen→send 成功)は legacy 行として併記し、同名で混ぜない。
    held_events = [x["_wall"] for x in defense if x.get("source") == "inbox_watcher" and x.get("check_id") == "delivery_held"]
    held_warn = sum(1 for x in defense if x.get("source") == "inbox_watcher" and x.get("check_id") == "delivery_held" and x.get("verdict") == "WARN")
    output.append("")
    output.append("## 配達 held")
    table(output)
    output.append("| " + " | ".join(row(f"inbox_watcher / delivery_held (event, WARN {held_warn})", held_events)) + " |" if held_events else "| inbox_watcher / delivery_held (event, WARN 0) | 0 | - | - | 0 | ms |")
    output.append("| " + " | ".join(row("inbox_watcher_karo / delivery_held (legacy stderr)", held)) + " |" if held else "| inbox_watcher_karo / delivery_held (legacy stderr) | 0 | - | - | 0 | ms |")

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

    # 負荷 proxy: 全 agent の全 tool 呼出しに乗る three_layer_preflight_total の時間帯別 p50。
    # load average の直接記録は無いため proxy と明記(§8 穴 4)。前後比較は同じ時間帯・同程度の proxy で行う。
    hourly = defaultdict(list)
    for item in defense:
        if item.get("source") == "three_layer_preflight" and item.get("check_id") == "three_layer_preflight_total":
            stamp = parse_iso(item.get("timestamp"))
            if stamp is not None:
                hourly[stamp.astimezone(JST).strftime("%H")].append(item["_wall"])
    output.append("")
    output.append("## 負荷 proxy（three_layer_preflight_total の時間帯別 p50、JST）")
    table(output, ("時間帯", "回数", "p50 ms", "p95 ms"))
    for hour in sorted(hourly):
        vals = hourly[hour]
        output.append(f"| {hour} | {len(vals)} | {fmt(percentile(vals, .5))} | {fmt(percentile(vals, .95))} |")
    if not hourly:
        output.append("| - | 0 | - | - |")

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
    print(f"karo_throughput_report: wrote {OUT} defense={len(defense)} timing={len(timing)} gate_clear={len(gate)} held_event={len(held_events)} held_legacy={len(held)} retry={sum(retry_counts.values())}")

main()
PY
