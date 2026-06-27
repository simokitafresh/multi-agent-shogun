#!/usr/bin/env bash
# weekly_metrics_trend.sh — weekly snapshot for silent metric drift

set -euo pipefail

ROOT="${WEEKLY_METRICS_ROOT:-}"
if [ -z "$ROOT" ]; then
    self="${BASH_SOURCE[0]}"
    case "$self" in
        */scripts/weekly_metrics_trend.sh) ROOT="${self%/scripts/weekly_metrics_trend.sh}" ;;
        *) ROOT="$(cd "$(dirname "$self")/.." && pwd)" ;;
    esac
fi

LESSON_IMPACT="${WEEKLY_METRICS_LESSON_IMPACT:-$ROOT/logs/lesson_impact.tsv}"
CMD_QUALITY="${WEEKLY_METRICS_CMD_QUALITY:-$ROOT/logs/cmd_design_quality.yaml}"
OUT_FILE="${WEEKLY_METRICS_OUT:-$ROOT/logs/weekly_metrics_trend.yaml}"
NOW="${WEEKLY_METRICS_NOW:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
WINDOW_DAYS="${WEEKLY_METRICS_WINDOW_DAYS:-7}"
MIN_WEEKS="${WEEKLY_METRICS_MIN_WEEKS:-3}"
CHECK_CRON="${WEEKLY_METRICS_CHECK_CRON:-0}"
CRON_MARKER="# shogun-weekly-metrics-trend"
CRON_SCHEDULE="${WEEKLY_METRICS_CRON_SCHEDULE:-17 0 * * 1}"
CRON_LINE="$CRON_SCHEDULE cd \"$ROOT\" && \"$ROOT/scripts/weekly_metrics_trend.sh\" >/dev/null 2>&1 $CRON_MARKER"

check_cron_registered() {
    local cron_text
    cron_text="$(crontab -l 2>/dev/null || true)"
    grep -q 'shogun-weekly-metrics-trend\|scripts/weekly_metrics_trend.sh' <<< "$cron_text"
}

if [ "${1:-}" = "--install-cron" ]; then
    cron_text="$(crontab -l 2>/dev/null || true)"
    if check_cron_registered; then
        echo "OK: weekly_metrics_trend cron already registered"
        exit 0
    fi
    {
        [ -n "$cron_text" ] && printf '%s\n' "$cron_text"
        printf '%s\n' "$CRON_LINE"
    } | crontab -
    echo "OK: weekly_metrics_trend cron installed"
    exit 0
fi

python3 - "$LESSON_IMPACT" "$CMD_QUALITY" "$OUT_FILE" "$NOW" "$WINDOW_DAYS" "$MIN_WEEKS" <<'PY'
import datetime as dt
import re
import sys
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

lesson_path = Path(sys.argv[1])
quality_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])
now_raw = sys.argv[4]
window_days = int(sys.argv[5])
min_weeks = int(sys.argv[6])

def parse_ts(value):
    text = str(value or "").strip().strip('"').strip("'")
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)

now = parse_ts(now_raw) or dt.datetime.now(dt.timezone.utc)
week_start = (now - dt.timedelta(days=window_days)).isoformat().replace("+00:00", "Z")
week_end = now.isoformat().replace("+00:00", "Z")
cutoff = now - dt.timedelta(days=window_days)

def pct(part, total):
    if total <= 0:
        return 0.0
    return round(part * 100.0 / total, 1)

def count_lesson_feedback():
    useful = 0
    total = 0
    if not lesson_path.is_file():
        return useful, total
    with lesson_path.open(encoding="utf-8", errors="replace") as fh:
        header_seen = False
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            cols = line.split("\t")
            if not header_seen and cols and cols[0] == "timestamp":
                header_seen = True
                continue
            if len(cols) < 6:
                continue
            ts = parse_ts(cols[0])
            if ts is None or ts < cutoff or ts > now:
                continue
            action = cols[4].strip().lower()
            result = cols[5].strip().upper()
            if action != "feedback":
                continue
            if result not in {"USEFUL", "NOT_USEFUL"}:
                continue
            total += 1
            if result == "USEFUL":
                useful += 1
    return useful, total

def load_quality_entries():
    if not quality_path.is_file():
        return []
    text = quality_path.read_text(encoding="utf-8", errors="replace")
    if yaml is not None:
        try:
            loaded = yaml.safe_load(text) or {}
            if isinstance(loaded, dict):
                entries = loaded.get("entries") or []
            elif isinstance(loaded, list):
                entries = loaded
            else:
                entries = []
            return [entry for entry in entries if isinstance(entry, dict)]
        except Exception:
            pass

    entries = []
    current = None
    for line in text.splitlines():
        if line.startswith("- "):
            if current:
                entries.append(current)
            current = {}
            rest = line[2:].strip()
            if rest:
                key, _, value = rest.partition(":")
                current[key.strip()] = value.strip().strip('"')
        elif current is not None and re.match(r"^\s+[A-Za-z0-9_]+:", line):
            key, _, value = line.strip().partition(":")
            current[key.strip()] = value.strip().strip('"')
    if current:
        entries.append(current)
    return entries

quality_entries = []
for entry in load_quality_entries():
    ts = parse_ts(entry.get("timestamp"))
    if ts is None or ts < cutoff or ts > now:
        continue
    quality_entries.append(entry)

useful, feedback_total = count_lesson_feedback()
quality_total = len(quality_entries)
rework = sum(1 for e in quality_entries if str(e.get("karo_rework", "")).strip().lower() in {"yes", "true", "1"})
blocks = sum(1 for e in quality_entries if str(e.get("gate_result", "")).strip().upper() == "BLOCK")

snapshot = {
    "week_start": week_start,
    "week_end": week_end,
    "useful_rate": pct(useful, feedback_total),
    "useful": useful,
    "feedback_total": feedback_total,
    "rework_rate": pct(rework, quality_total),
    "rework": rework,
    "cmd_quality_total": quality_total,
    "block_rate": pct(blocks, quality_total),
    "blocks": blocks,
    "source": "weekly_metrics_trend.sh",
}

def load_existing(path):
    if not path.is_file() or yaml is None:
        return []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return []
    if isinstance(data, dict):
        items = data.get("snapshots") or []
    elif isinstance(data, list):
        items = data
    else:
        items = []
    return [item for item in items if isinstance(item, dict)]

snapshots = load_existing(out_path)
snapshots = [s for s in snapshots if str(s.get("week_end")) != week_end]

previous_snapshot = snapshots[-1] if snapshots else None
delta = {}
if previous_snapshot:
    for metric in ("useful_rate", "rework_rate", "block_rate"):
        current_value = float(snapshot.get(metric, 0) or 0)
        previous_value = float(previous_snapshot.get(metric, 0) or 0)
        delta[metric] = round(current_value - previous_value, 1)
snapshot["delta"] = delta
snapshots.append(snapshot)
snapshots = snapshots[-52:]

def worsened(metric, previous, current):
    pv = float(previous.get(metric, 0) or 0)
    cv = float(current.get(metric, 0) or 0)
    if metric == "useful_rate":
        return cv < pv
    return cv > pv

alerts = []
if len(snapshots) >= min_weeks:
    recent = snapshots[-min_weeks:]
    for metric in ("useful_rate", "rework_rate", "block_rate"):
        if all(worsened(metric, recent[i - 1], recent[i]) for i in range(1, len(recent))):
            values = " -> ".join(f"{float(s.get(metric, 0) or 0):.1f}%" for s in recent)
            alerts.append(f"{metric} 3週連続悪化: {values}")

def q(value):
    text = str(value)
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

def emit_snapshot(item):
    lines = [
        f"- week_start: {q(item.get('week_start', ''))}",
        f"  week_end: {q(item.get('week_end', ''))}",
        f"  useful_rate: {float(item.get('useful_rate', 0) or 0):.1f}",
        f"  useful: {int(item.get('useful', 0) or 0)}",
        f"  feedback_total: {int(item.get('feedback_total', 0) or 0)}",
        f"  rework_rate: {float(item.get('rework_rate', 0) or 0):.1f}",
        f"  rework: {int(item.get('rework', 0) or 0)}",
        f"  cmd_quality_total: {int(item.get('cmd_quality_total', 0) or 0)}",
        f"  block_rate: {float(item.get('block_rate', 0) or 0):.1f}",
        f"  blocks: {int(item.get('blocks', 0) or 0)}",
        f"  source: {q(item.get('source', 'weekly_metrics_trend.sh'))}",
    ]
    delta_item = item.get("delta") if isinstance(item.get("delta"), dict) else {}
    if delta_item:
        lines.append("  delta:")
        for metric in ("useful_rate", "rework_rate", "block_rate"):
            if metric in delta_item:
                lines.append(f"    {metric}: {float(delta_item.get(metric, 0) or 0):+.1f}")
    return "\n".join(lines)

out_path.parent.mkdir(parents=True, exist_ok=True)
content = ["# weekly_metrics_trend.yaml — generated by scripts/weekly_metrics_trend.sh", "snapshots:"]
content.extend(emit_snapshot(item) for item in snapshots)
content.append("alerts:")
if alerts:
    content.extend(f"- {q(alert)}" for alert in alerts)
else:
    content.append("[]")
out_path.write_text("\n".join(content) + "\n", encoding="utf-8")

print(
    "METRIC: weekly_metrics_trend "
    f"useful_rate={snapshot['useful_rate']:.1f}%({useful}/{feedback_total}) "
    f"rework_rate={snapshot['rework_rate']:.1f}%({rework}/{quality_total}) "
    f"block_rate={snapshot['block_rate']:.1f}%({blocks}/{quality_total}) "
    f"out={out_path}"
)
if delta:
    print(
        "DELTA: weekly_metrics_trend "
        f"useful_rate={delta.get('useful_rate', 0):+.1f}pp "
        f"rework_rate={delta.get('rework_rate', 0):+.1f}pp "
        f"block_rate={delta.get('block_rate', 0):+.1f}pp"
    )
else:
    print("DELTA: weekly_metrics_trend baseline=no_previous_snapshot")
if alerts:
    for alert in alerts:
        print(f"ALERT: {alert}")
    raise SystemExit(1)
print("OK: weekly metrics trend")
PY

if [ "$CHECK_CRON" = "1" ]; then
    if check_cron_registered; then
        echo "OK: weekly_metrics_trend cron registered"
    else
        echo "ALERT: weekly_metrics_trend cron missing"
        exit 1
    fi
fi
