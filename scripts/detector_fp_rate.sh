#!/usr/bin/env bash
# detector_fp_rate.sh — gate/cmd_save detector false-positive rate ledger
# Usage: bash scripts/detector_fp_rate.sh [--out logs/detector_fp_rate.yaml]

set -euo pipefail

self="${BASH_SOURCE[0]}"
[[ "$self" != /* ]] && self="$PWD/$self"
ROOT="${DETECTOR_FP_ROOT:-${self%/scripts/detector_fp_rate.sh}}"

GATE_FIRE_LOG="${DETECTOR_FP_GATE_FIRE_LOG:-$ROOT/logs/gate_fire_log.yaml}"
CMD_QUALITY_LOG="${DETECTOR_FP_CMD_QUALITY_LOG:-$ROOT/logs/cmd_design_quality.yaml}"
GATE_ALERTS_LOG="${DETECTOR_FP_GATE_ALERTS_LOG:-$ROOT/logs/gate_alerts.yaml}"
LOOP_LEDGER_LOG="${DETECTOR_FP_LOOP_LEDGER_LOG:-$ROOT/logs/loop_ledger.yaml}"
OUT_FILE="${DETECTOR_FP_OUT:-$ROOT/logs/detector_fp_rate.yaml}"
NOW="${DETECTOR_FP_NOW:-$(date -Iseconds)}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)
            OUT_FILE="${2:?--out requires path}"
            shift 2
            ;;
        *)
            echo "Usage: bash scripts/detector_fp_rate.sh [--out path]" >&2
            exit 2
            ;;
    esac
done

python3 - "$GATE_FIRE_LOG" "$CMD_QUALITY_LOG" "$GATE_ALERTS_LOG" "$LOOP_LEDGER_LOG" "$OUT_FILE" "$NOW" <<'PY'
import collections
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"PyYAML required: {exc}", file=sys.stderr)
    sys.exit(2)

gate_fire_path, quality_path, alerts_path, loop_ledger_path, out_path, now = sys.argv[1:7]
root_dir = Path(quality_path).parent.parent
archive_cmd_dir = root_dir / "queue" / "archive" / "cmds"
queue_file = root_dir / "queue" / "shogun_to_karo.yaml"


def load_yaml(path):
    p = Path(path)
    if not p.is_file():
        return None
    try:
        return yaml.safe_load(p.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None


def loop_ledger_events(path):
    """Read explicit detector observations from the loop ledger.

    The ledger is the durable producer for memory/loop observations.  Older
    snapshots do not have detector observations and are deliberately ignored;
    absence must not be turned into a synthetic zero-rate claim.
    """
    data = load_yaml(path) or {}
    snapshots = data.get("snapshots") or []
    if not isinstance(snapshots, list):
        return []
    events = []
    for snapshot in snapshots:
        if not isinstance(snapshot, dict):
            continue
        ts = snapshot.get("generated_at") or snapshot.get("timestamp")
        for channel in ("memory", "loop_ledger"):
            section = snapshot.get(channel)
            if not isinstance(section, dict):
                continue
            observations = section.get("detector_observations") or section.get("detector_events")
            if isinstance(observations, list):
                for item in observations:
                    if not isinstance(item, dict) or not item.get("detector"):
                        continue
                    result = str(item.get("result") or item.get("outcome") or "UNKNOWN").upper()
                    fp = bool(item.get("false_positive")) or result in {"FALSE_POSITIVE", "FP"}
                    events.append({
                        "ts": item.get("ts") or ts,
                        "detector": f"loop_ledger:{channel}:{item['detector']}",
                        "cmd_id": item.get("cmd_id") or f"loop_ledger:{channel}",
                        # A labelled observation is still a detector firing;
                        # keep it in the WARN-like measurement domain while
                        # preserving its true/false classification separately.
                        "result": "WARN",
                        "reason": item.get("reason") or "loop ledger detector observation",
                        "source": "loop_ledger",
                        "outcome": "false_positive" if fp else str(item.get("classification") or "unknown").lower(),
                    })
            summary = section.get("detector_fp_rate") or section.get("fp_measurement")
            if isinstance(summary, dict) and summary.get("detector"):
                fires = int(summary.get("fires") or 0)
                false_positive = int(summary.get("false_positive") or summary.get("false_positives") or 0)
                for index in range(max(0, fires)):
                    events.append({
                        "ts": ts,
                        "detector": f"loop_ledger:{channel}:{summary['detector']}",
                        "cmd_id": f"loop_ledger:{channel}",
                        "result": "WARN",
                        "reason": "loop ledger fp summary",
                        "source": "loop_ledger",
                        "outcome": "false_positive" if index < false_positive else "unknown",
                    })
    return events


def parse_fire_log(path):
    p = Path(path)
    if not p.is_file():
        return []
    entries = []
    pattern = re.compile(r'- ts: "(?P<ts>[^"]+)", file: "(?P<file>[^"]*)", gate: "(?P<gate>[^"]+)", result: (?P<result>[A-Z_-]+)(?:, checks: "(?P<checks>[^"]*)")?(?:, reasons: "(?P<reasons>.*)")?')
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        m = pattern.match(line.strip())
        if not m:
            continue
        item = m.groupdict()
        item["cmd_id"] = item.get("file") or ""
        entries.append(item)
    return entries


def parse_ts(value):
    text = str(value or "").strip()
    if not text:
        return None
    text = re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", text)
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def cmd_save_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") == "cmd_save":
            events.append({
                "ts": e.get("ts"),
                "detector": f"cmd_save:{e.get('checks') or 'unknown'}",
                "cmd_id": e.get("cmd_id"),
                "result": e.get("result"),
                "reason": e.get("reasons") or "",
                "source": "gate_fire_log",
            })
    data = load_yaml(quality_path) or {}
    for e in data.get("entries") or []:
        if not isinstance(e, dict):
            continue
        src = str(e.get("source") or "")
        result = str(e.get("gate_result") or "").upper()
        if result in {"PASS", "CLEAR"}:
            events.append({
                "ts": e.get("timestamp"),
                "detector": "cmd_outcome",
                "cmd_id": e.get("cmd_id"),
                "result": "PASS",
                "reason": e.get("notes") or "",
                "source": "cmd_design_quality",
            })
            continue
        if src not in {"cmd_save_warn", "cmd_save"} or result not in {"WARN", "BLOCK"}:
            continue
        events.append({
            "ts": e.get("timestamp"),
            "detector": f"cmd_save:{e.get('checks') or 'unknown'}",
            "cmd_id": e.get("cmd_id"),
            "result": result,
            "reason": e.get("notes") or "",
            "source": "cmd_design_quality",
        })
    return events


def today_history_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "scripts_same_day_history":
            continue
        events.append({
            "ts": e.get("ts"),
            "detector": "scripts_same_day_history",
            "cmd_id": e.get("file") or "unknown",
            "result": e.get("result"),
            "reason": e.get("reasons") or "",
            "source": "gate_fire_log",
        })
    return events


def gunshi_cs_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "gunshi_cs_checklist":
            continue
        events.append({
            "ts": e.get("ts"), "detector": "gunshi_cs_checklist",
            "cmd_id": e.get("file") or "gunshi_cs_checklist",
            "result": e.get("result"), "reason": e.get("reasons") or "",
            "source": "gate_fire_log",
        })
    return events


def skill_script_ref_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "skill_script_refs":
            continue
        events.append({
            "ts": e.get("ts"),
            "detector": "skill_script_refs",
            "cmd_id": e.get("file") or "SKILL.md",
            "result": e.get("result"),
            "reason": e.get("reasons") or "",
            "source": "gate_fire_log",
        })
    return events


def daemon_watchdog_heartbeat_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "daemon_watchdog_heartbeat":
            continue
        events.append({
            "ts": e.get("ts"),
            "detector": "daemon_watchdog_heartbeat",
            "cmd_id": e.get("file") or "/tmp/daemon_watchdog_heartbeat",
            "result": e.get("result"),
            "reason": e.get("reasons") or "",
            "source": "gate_fire_log",
        })
    return events


def script_speed_record_real_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "script_speed_record_real":
            continue
        events.append({
            "ts": e.get("ts"), "detector": "script_speed_record_real",
            "cmd_id": e.get("file") or "script_speed_record_real",
            "result": e.get("result"), "reason": e.get("reasons") or "",
            "source": "gate_fire_log",
        })
    return events


def lgtm_bundle_guard_events():
    events = []
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "lgtm_bundle_guard":
            continue
        events.append({
            "ts": e.get("ts"), "detector": "lgtm_bundle_guard",
            "cmd_id": e.get("file") or "lgtm_bundle_guard",
            "result": e.get("result"), "reason": e.get("reasons") or "",
            "source": "gate_fire_log",
        })
    return events


def backup_rotation_summary():
    """Aggregate memory_db_backup_rotation fires (scripts/memory_db_live_insert.py's
    rotate_routine_backups) into their own measurement section. These fires are
    routine maintenance, not WARN/BLOCK/ALERT-style detector judgements, so they are
    summarized separately rather than forced through the true/false-positive outcome
    logic used for cmd_save/escalation detectors."""
    fires = 0
    rotated = 0
    noop = 0
    deleted_total = 0
    bytes_freed_total = 0
    for e in parse_fire_log(gate_fire_path):
        if e.get("gate") != "memory_db_backup_rotation":
            continue
        fires += 1
        result = e.get("result") or ""
        if result == "ROTATED":
            rotated += 1
        elif result == "NOOP":
            noop += 1
        checks = e.get("checks") or ""
        m = re.search(r"deleted=(\d+)", checks)
        if m:
            deleted_total += int(m.group(1))
        reasons = e.get("reasons") or ""
        m = re.search(r"bytes_freed=(\d+)", reasons)
        if m:
            bytes_freed_total += int(m.group(1))
    return {
        "fires": fires,
        "rotated": rotated,
        "noop": noop,
        "deleted_total": deleted_total,
        "bytes_freed_total": bytes_freed_total,
    }


def escalation_events():
    data = load_yaml(alerts_path) or {}
    events = []
    for e in data.get("alerts") or []:
        if not isinstance(e, dict):
            continue
        gate = str(e.get("gate") or "unknown")
        cmd = str(e.get("investigation_cmd") or e.get("alert_id") or "")
        improved = bool(e.get("improvement_done"))
        detail = str(e.get("alert_detail") or "")
        events.append({
            "ts": e.get("detected_at"),
            "detector": f"escalation:{gate}",
            "cmd_id": cmd,
            "result": "TRUE" if improved else "ALERT",
            "reason": detail,
            "source": "gate_alerts",
        })
    return events


def cmd_text_for(cmd_id):
    if not cmd_id:
        return ""
    candidates = []
    if archive_cmd_dir.is_dir():
        candidates.extend(sorted(archive_cmd_dir.glob(f"{cmd_id}_*.yaml")))
    if queue_file.is_file():
        candidates.append(queue_file)
    for path in candidates:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if cmd_id in text:
            return text
    return ""


def deferral_language_still_matches(cmd_id):
    text = cmd_text_for(cmd_id)
    if not text:
        return True
    hit_re = re.compile(r"低優先|後で|次セッション|非致命的|見送り|段階的に|後回し|severity.?normal", re.I)
    exclude_re = re.compile(
        r"前後|直後|以後|以前|以降|後続|次段|高優先.*低優先|低優先.*高優先|deadline|後でよい同期|async|非同期",
        re.I,
    )
    improve_re = re.compile(r"(向上|改善|強化).*(セッション|起動)|(セッション|起動).*(向上|改善|強化)", re.I)
    for line in text.splitlines():
        if re.match(r"^\s*diagnosis:", line):
            continue
        if hit_re.search(line) and not exclude_re.search(line) and not improve_re.search(line):
            return True
    return False


CURRENT_REEVALUATION_DETECTORS = {
    "cmd_save:check_ac_file_paths",
    "cmd_save:check_ac_param_sufficiency",
    "cmd_save:session_state_cmd_block_presence",
}


def cmd_archive_file(cmd_id):
    if not cmd_id or not archive_cmd_dir.is_dir():
        return None
    matches = sorted(archive_cmd_dir.glob(f"{cmd_id}_*.yaml"))
    return matches[0] if matches else None


def cmd_save_currently_emits_detector(cmd_id, detector):
    """Return False when the current cmd_save detector no longer fires for an archived FP."""
    if detector not in CURRENT_REEVALUATION_DETECTORS:
        return True
    archive_file = cmd_archive_file(cmd_id)
    if archive_file is None:
        return True
    check_name = detector.split(":", 1)[1]
    env = os.environ.copy()
    env["CMD_SAVE_QUEUE_FILE"] = str(archive_file)
    try:
        proc = subprocess.run(
            ["bash", str(root_dir / "scripts" / "cmd_save.sh"), "--preflight", cmd_id],
            cwd=str(root_dir),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
            check=False,
        )
    except Exception:
        return True
    return f"check={check_name}" in proc.stdout or f'checks: "{check_name}"' in proc.stdout


events = (
    cmd_save_events() + escalation_events() + today_history_events()
    + gunshi_cs_events() + skill_script_ref_events() + daemon_watchdog_heartbeat_events()
    + script_speed_record_real_events() + lgtm_bundle_guard_events()
    + loop_ledger_events(loop_ledger_path)
)
events.sort(key=lambda x: parse_ts(x.get("ts")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc))

by_cmd = collections.defaultdict(list)
for e in events:
    if e.get("cmd_id"):
        by_cmd[e["cmd_id"]].append(e)

rows = []
for cmd_id, cmd_events in by_cmd.items():
    final = cmd_events[-1].get("result")
    emitted = set()
    for e in cmd_events:
        if e.get("detector") == "script_speed_record_real" and e.get("result") in {"PASS", "CLEAR"}:
            event_key = (e.get("detector"), e.get("result"))
            if event_key not in emitted:
                emitted.add(event_key)
                rows.append({**e, "outcome": "true_positive"})
            continue
        if e.get("result") not in {"WARN", "BLOCK", "ALERT"}:
            continue
        if e.get("detector") == "cmd_save:cmd_text_deferral_language" and not deferral_language_still_matches(cmd_id):
            continue
        event_key = (
            (e.get("detector"), e.get("result"), e.get("outcome"))
            if e.get("source") == "loop_ledger"
            else (e.get("detector"), e.get("result"))
        )
        if event_key in emitted:
            continue
        emitted.add(event_key)
        outcome = "unknown"
        if e.get("source") == "loop_ledger" and e.get("outcome") in {
            "false_positive", "true_positive", "unknown"
        }:
            outcome = e["outcome"]
        if e.get("result") == "BLOCK" and any(x.get("result") in {"PASS", "CLEAR"} for x in cmd_events if x is not e):
            outcome = "true_positive"
        elif any(x.get("result") == "PASS" for x in cmd_events if x is not e):
            outcome = "false_positive"
        elif any(x.get("result") in {"TRUE", "CLEAR"} for x in cmd_events if x is not e):
            outcome = "true_positive"
        elif e.get("result") == "ALERT" and e.get("source") != "gate_alerts" and final == "ALERT":
            outcome = "false_positive"
        if outcome == "false_positive" and not cmd_save_currently_emits_detector(cmd_id, e.get("detector")):
            continue
        rows.append({**e, "outcome": outcome})

stats = collections.defaultdict(lambda: {"fires": 0, "false_positive": 0, "true_positive": 0, "unknown": 0})
for row in rows:
    s = stats[row["detector"]]
    s["fires"] += 1
    s[row["outcome"]] += 1

detectors = []
for name, s in sorted(stats.items()):
    fp = s["false_positive"]
    denom = s["fires"]
    detectors.append({
        "detector": name,
        **s,
        "fp_rate": round((fp / denom * 100.0), 1) if denom else 0.0,
    })

out = {
    "generated_at": now,
    "sources": {
        "gate_fire_log": str(gate_fire_path),
        "cmd_design_quality": str(quality_path),
        "gate_alerts": str(alerts_path),
        "loop_ledger": str(loop_ledger_path),
    },
    "detectors": detectors,
    "events": rows[-200:],
    "backup_rotation": backup_rotation_summary(),
}

def yaml_scalar(value):
    if value is None:
        return '""'
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{text}"'


def emit_yaml(value, indent=0):
    pad = " " * indent
    lines = []
    if isinstance(value, dict):
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                lines.append(f"{pad}{key}:")
                lines.extend(emit_yaml(child, indent + 2))
            else:
                lines.append(f"{pad}{key}: {yaml_scalar(child)}")
    elif isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                lines.append(f"{pad}- {next(iter(item))}: {yaml_scalar(next(iter(item.values())))}")
                rest = dict(list(item.items())[1:])
                lines.extend(emit_yaml(rest, indent + 2))
            else:
                lines.append(f"{pad}- {yaml_scalar(item)}")
    return lines


Path(out_path).parent.mkdir(parents=True, exist_ok=True)
Path(out_path).write_text("\n".join(emit_yaml(out)) + "\n", encoding="utf-8")
print(f"detectors={len(detectors)} events={len(rows)} out={out_path}")
for item in detectors:
    print(f"{item['detector']}: fp_rate={item['fp_rate']}% fp={item['false_positive']}/{item['fires']}")
PY
