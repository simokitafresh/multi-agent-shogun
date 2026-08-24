#!/usr/bin/env bash
# completion_gap_metrics.sh — report/review/CLEAR pipeline gap telemetry
#
# The command-completion path already records each event in a different
# durable source.  This read-only correlator turns those timestamps into one
# append-only JSONL record.  It is intentionally best-effort when called from
# the gate: telemetry must never change the gate verdict.

set -euo pipefail

SELF="${BASH_SOURCE[0]}"
[[ "$SELF" = /* ]] || SELF="$PWD/$SELF"
ROOT="${COMPLETION_GAP_ROOT:-${SELF%/scripts/completion_gap_metrics.sh}}"
LOG="${COMPLETION_GAP_LOG:-$ROOT/logs/completion_gap_metrics.log}"
ARCHIVE_DIR="${COMPLETION_GAP_ARCHIVE_DIR:-$ROOT/logs/archive}"

exec python3 - "$ROOT" "$LOG" "$ARCHIVE_DIR" "$@" <<'PY'
from __future__ import annotations

import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from statistics import mean, median
from zoneinfo import ZoneInfo

try:
    import yaml
except Exception as exc:  # pragma: no cover - deployment preflight
    print(f"completion_gap_metrics: PyYAML required: {exc}", file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(sys.argv[1]).resolve()
LOG = Path(sys.argv[2]).resolve()
ARCHIVE_DIR = Path(sys.argv[3]).resolve()
ARGS = sys.argv[4:]
JST = ZoneInfo("Asia/Tokyo")
MAX_LINES = int(os.environ.get("COMPLETION_GAP_MAX_LINES", "1000"))
KEEP_LINES = int(os.environ.get("COMPLETION_GAP_KEEP_LINES", "500"))


def parse_time(value):
    if value in (None, ""):
        return None
    text = str(value).strip().replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=JST)
    return parsed.astimezone(dt.timezone.utc)


def iso(value):
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z") if value else None


def load_yaml(path):
    try:
        with path.open(encoding="utf-8") as handle:
            return yaml.safe_load(handle) or {}
    except (OSError, yaml.YAMLError):
        return {}


def items_from_yaml(data):
    if isinstance(data, dict):
        value = data.get("messages", data.get("entries", data))
        return value if isinstance(value, list) else []
    return data if isinstance(data, list) else []


_INBOX_CACHE = {}


def unique_paths(patterns):
    seen = set()
    for pattern in patterns:
        for raw in glob.glob(str(ROOT / pattern), recursive=True):
            path = Path(raw)
            if path.is_file() and path not in seen:
                seen.add(path)
                yield path


def cmd_ids_from_metrics(limit):
    candidates = []
    paths = [ROOT / "logs/gate_metrics.log"]
    paths.extend(sorted((ROOT / "logs/archive").glob("gate_metrics_*.log")))
    for path in paths:
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            fields = line.split("\t")
            if len(fields) >= 3 and fields[2] in {"CLEAR", "OVERRIDE"}:
                cmd = fields[1].strip()
                if re.fullmatch(r"cmd_[A-Za-z0-9_]+", cmd):
                    candidates.append((parse_time(fields[0]), cmd))
    latest = {}
    for timestamp, cmd in candidates:
        if timestamp is not None and (cmd not in latest or timestamp > latest[cmd]):
            latest[cmd] = timestamp
    ordered = sorted(latest, key=lambda cmd: latest[cmd], reverse=True)
    return ordered[:limit]


def report_candidates(cmd):
    # Report directories are flat in the live/archive contract.  Avoid a
    # recursive glob here: queue/archive contains many retained worktrees on
    # WSL/DrvFs and a recursive scan can cost minutes for one cmd.
    pattern = f"*_report_{cmd}*.yaml"
    for path in unique_paths(["queue/reports/" + pattern, "queue/archive/reports/" + pattern, "archive/reports/" + pattern]):
        data = load_yaml(path)
        if str(data.get("parent_cmd") or "") != cmd:
            continue
        if str(data.get("status") or "") not in {"completed", "done", "revision_requested"}:
            continue
        # timestamp is the report authoring/deployment time. Terminal
        # publication records completed_at atomically; prefer it so the
        # report_done edge is not inflated by authoring or review revisions.
        timestamp = parse_time(data.get("completed_at") or data.get("done_at") or data.get("timestamp"))
        if timestamp is not None:
            yield timestamp, path


def report_done(cmd):
    values = list(report_candidates(cmd))
    return max(values, key=lambda pair: pair[0]) if values else (None, None)


def inbox_messages(cmd):
    paths = ["queue/inbox/*.yaml", "archive/inbox/*.yaml", "queue/archive/inbox/*.yaml"]
    for path in unique_paths(paths):
        # The inbox archive is append-heavy (some files are >1 MiB).  A cheap
        # byte prefilter avoids deserializing every historical mailbox for a
        # single cmd while retaining all matching archive sources.
        if path not in _INBOX_CACHE:
            try:
                _INBOX_CACHE[path] = [path.read_text(encoding="utf-8", errors="replace"), None]
            except OSError:
                continue
        raw, data = _INBOX_CACHE[path]
        if cmd not in raw:
            continue
        if data is None:
            try:
                data = yaml.safe_load(raw) or {}
            except yaml.YAMLError:
                data = {}
            _INBOX_CACHE[path][1] = data
        for message in items_from_yaml(data):
            if not isinstance(message, dict):
                continue
            text = " ".join(str(message.get(key) or "") for key in ("content", "report_path", "parent_cmd", "task_id"))
            if cmd not in text:
                continue
            timestamp = parse_time(message.get("timestamp"))
            if timestamp is not None:
                yield timestamp, message, path


def review_request(cmd, before=None):
    values = []
    for timestamp, message, path in inbox_messages(cmd):
        kind = str(message.get("type") or "")
        if kind not in {"report_review", "report_received"}:
            continue
        # Review context is copied into later messages and can mention many
        # older cmd ids.  Identity fields, when present, are authoritative;
        # fall back only to the explicit report filename, never free text.
        parent = str(message.get("parent_cmd") or "")
        task = str(message.get("task_id") or "")
        report = str(message.get("report_path") or "")
        identity_match = parent == cmd or task in {cmd, f"{cmd}_full"} or f"_report_{cmd}" in report
        if identity_match:
            # A resend/re-request for the same command can arrive after the
            # SG7 bundle was already created.  It is not the request that
            # caused that review and would otherwise make the preceding gap
            # negative.  Attribute the latest request at or before review
            # start; when review has not started yet, retain legacy latest
            # request selection for incomplete records.
            if before is None or timestamp <= before:
                values.append((timestamp, path, kind))
    return max(values, key=lambda value: value[0]) if values else (None, None, None)


def review_bundle(cmd):
    path = ROOT / "queue/gates" / cmd / "sg7_bundle.json"
    if not path.is_file():
        return None, None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, None
    review = data.get("review") if isinstance(data, dict) else {}
    if not isinstance(review, dict) or str(review.get("cmd_id") or "") != cmd:
        return None, None
    timestamp = parse_time(review.get("reviewed_at"))
    return timestamp, path


def approval_event(cmd, role, result):
    values = []
    base = ROOT / "queue/gates" / cmd / "review_approvals"
    for path in base.glob("reports/**/%s.yaml" % role):
        data = load_yaml(path)
        if str(data.get("result") or "").upper() != result:
            continue
        timestamp = parse_time(data.get("timestamp"))
        if timestamp is not None:
            values.append((timestamp, path))
    return max(values, key=lambda value: value[0]) if values else (None, None)


def gate_start(cmd, after):
    values = []
    phase_paths = [ROOT / "logs/cmd_complete_gate_phases.log"]
    phase_paths.extend(sorted((ROOT / "logs/archive").glob("cmd_complete_gate_phases*.log")))
    for path in phase_paths:
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            fields = line.split("\t")
            if len(fields) < 4 or fields[1] != cmd or fields[2] != "startup":
                continue
            timestamp = parse_time(fields[0])
            if timestamp is not None and (after is None or timestamp >= after):
                values.append((timestamp, path))
    if values:
        return min(values, key=lambda value: value[0])
    # A legacy/fixture run may not have a phase log.  The first gate metric
    # after ACCEPT is the durable fallback, never an invented timestamp.
    metric_paths = [ROOT / "logs/gate_metrics.log"]
    metric_paths.extend(sorted((ROOT / "logs/archive").glob("gate_metrics_*.log")))
    fallback = []
    for path in metric_paths:
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            fields = line.split("\t")
            if len(fields) < 3 or fields[1] != cmd:
                continue
            timestamp = parse_time(fields[0])
            if timestamp is not None and (after is None or timestamp >= after):
                fallback.append((timestamp, path))
    return min(fallback, key=lambda value: value[0]) if fallback else (None, None)


def gap_seconds(left, right):
    if left is None or right is None:
        return None
    return round((right - left).total_seconds(), 3)


def collect(cmd):
    report_ts, report_path = report_done(cmd)
    review_ts, review_path = review_bundle(cmd)
    request_ts, request_path, request_kind = review_request(cmd, review_ts)
    lgtm_ts, lgtm_path = approval_event(cmd, "gunshi", "LGTM")
    accept_ts, accept_path = approval_event(cmd, "karo", "ACCEPT")
    gate_ts, gate_path = gate_start(cmd, accept_ts)
    events = {
        "report_done": report_ts,
        "review_request": request_ts,
        "review_start": review_ts,
        "lgtm_sent": lgtm_ts,
        "karo_accept": accept_ts,
        "gate_start": gate_ts,
    }
    ordered = ["report_done", "review_request", "review_start", "lgtm_sent", "karo_accept", "gate_start"]
    gaps = {f"{left}_to_{right}_sec": gap_seconds(events[left], events[right]) for left, right in zip(ordered, ordered[1:])}
    missing = [name for name, timestamp in events.items() if timestamp is None]
    invalid = []
    for left, right in zip(ordered, ordered[1:]):
        if events[left] is not None and events[right] is not None and events[right] < events[left]:
            invalid.append(f"{left}_after_{right}")
    status = "complete" if not missing and not invalid else "incomplete"
    sources = {
        "report_done": str(report_path.relative_to(ROOT)) if report_path else None,
        "review_request": str(request_path.relative_to(ROOT)) if request_path else None,
        "review_start": str(review_path.relative_to(ROOT)) if review_path else None,
        "lgtm_sent": str(lgtm_path.relative_to(ROOT)) if lgtm_path else None,
        "karo_accept": str(accept_path.relative_to(ROOT)) if accept_path else None,
        "gate_start": str(gate_path.relative_to(ROOT)) if gate_path else None,
    }
    return {
        "schema_version": 1,
        "cmd_id": cmd,
        "status": status,
        "events": {name: iso(timestamp) for name, timestamp in events.items()},
        "gaps_sec": gaps,
        "missing": missing,
        "invalid": invalid,
        "review_request_type": request_kind,
        "sources": sources,
    }


def fingerprint(record):
    stable = {"cmd_id": record.get("cmd_id"), "events": record.get("events")}
    return hashlib.sha256(json.dumps(stable, sort_keys=True).encode()).hexdigest()


def rotate():
    if not LOG.is_file() or MAX_LINES <= KEEP_LINES:
        return
    lines = LOG.read_text(encoding="utf-8", errors="replace").splitlines()
    if len(lines) <= MAX_LINES:
        return
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    today = dt.datetime.now(JST).strftime("%Y%m%d")
    archive = ARCHIVE_DIR / f"completion_gap_metrics_{today}.log"
    archived = "\n".join(lines[:-KEEP_LINES]) + "\n"
    with archive.open("a", encoding="utf-8") as output:
        output.write(archived)
    LOG.write_text("\n".join(lines[-KEEP_LINES:]) + "\n", encoding="utf-8")


def append(records):
    if not records:
        return
    LOG.parent.mkdir(parents=True, exist_ok=True)
    lock = LOG.with_suffix(LOG.suffix + ".lock")
    import fcntl
    with lock.open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        existing = []
        if LOG.is_file():
            for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
                try:
                    old = json.loads(line)
                    if isinstance(old, dict):
                        existing.append(("record", old))
                    else:
                        existing.append(("raw", line))
                except ValueError:
                    existing.append(("raw", line))
        replacements = {record.get("cmd_id"): record for record in records if record.get("cmd_id")}
        if not replacements:
            return
        output_records = []
        replaced = set()
        for kind, value in existing:
            if kind == "raw":
                output_records.append(value)
                continue
            old = value
            cmd = old.get("cmd_id")
            if cmd not in replacements:
                output_records.append(old)
                continue
            # A corrected re-aggregation supersedes every older row for the
            # same command.  Keep one canonical row and make replay idempotent.
            if cmd not in replaced:
                output_records.append(replacements[cmd])
                replaced.add(cmd)
        for cmd, record in replacements.items():
            if cmd not in replaced:
                output_records.append(record)
        import tempfile
        fd, temporary = tempfile.mkstemp(prefix=f".{LOG.name}.", dir=LOG.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                for record in output_records:
                    if isinstance(record, str):
                        output.write(record + "\n")
                    else:
                        output.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, LOG)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        rotate()


def write_report(path, records):
    complete = [record for record in records if record.get("status") == "complete"]
    gap_names = list((complete[0].get("gaps_sec") or {}).keys()) if complete else []
    rows = [
        "# Completion pipeline gap analysis",
        "",
        f"Generated: {dt.datetime.now(JST).isoformat(timespec='seconds')}",
        f"Source records: {len(complete)} complete / {len(records)} total",
        "",
        "| Gap | N | Median (s) | Mean (s) | Max (s) |",
        "|---|---:|---:|---:|---:|",
    ]
    for name in gap_names:
        values = [record["gaps_sec"].get(name) for record in complete if record.get("gaps_sec", {}).get(name) is not None]
        if not values:
            rows.append(f"| {name} | 0 | — | — | — |")
        else:
            rows.append(f"| {name} | {len(values)} | {median(values):.3f} | {mean(values):.3f} | {max(values):.3f} |")
    if complete:
        totals = [sum(v for v in record["gaps_sec"].values() if v is not None) for record in complete]
        dominant = max(gap_names, key=lambda name: median([r["gaps_sec"][name] for r in complete if r["gaps_sec"].get(name) is not None]), default="unknown")
        rows += ["", f"Next individual shortening target: `{dominant}` (highest median contribution).", f"Total pipeline gap median: `{median(totals):.3f}s`."]
    else:
        rows += ["", "No complete records were available; no shortening target was selected."]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(rows) + "\n", encoding="utf-8")


def load_log():
    if not LOG.is_file():
        return []
    records = []
    for line in LOG.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict):
            records.append(value)
    return records


parser = argparse.ArgumentParser(description="Correlate command completion pipeline timestamps")
parser.add_argument("--cmd", action="append", help="command id; may be repeated")
parser.add_argument("--limit", type=int, default=10)
parser.add_argument("--backfill", action="store_true", help="collect latest CLEAR commands from gate_metrics")
parser.add_argument("--append", action="store_true", dest="append_records")
parser.add_argument("--write-report", type=Path)
args = parser.parse_args(ARGS)

cmds = list(args.cmd or [])
if args.backfill or not cmds:
    for cmd in cmd_ids_from_metrics(max(1, args.limit)):
        if cmd not in cmds:
            cmds.append(cmd)
if not cmds:
    print("completion_gap_metrics: no command ids found", file=sys.stderr)
    raise SystemExit(1)

records = [collect(cmd) for cmd in cmds[: max(1, args.limit)]]
if args.append_records:
    append(records)
if args.write_report:
    source_records = load_log() if args.append_records else records
    write_report(args.write_report if args.write_report.is_absolute() else ROOT / args.write_report, source_records)
for record in records:
    print(json.dumps(record, ensure_ascii=False, sort_keys=True))
PY
