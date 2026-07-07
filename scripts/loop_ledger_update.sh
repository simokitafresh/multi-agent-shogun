#!/usr/bin/env bash
# loop_ledger_update.sh — 学習ループ別(教訓/insight/semantic/obsidian/memory/skill)統合台帳 (T7, cmd_3720)
# 目的: 各ループの生産量・消化量・在庫・最終消化時刻を既存ログ/DBから集計し、
#       律速段階(最も詰まった段階)と空転(生産継続なのに消化ゼロ)を可視化する。
# Usage: bash scripts/loop_ledger_update.sh
# Exit: 0=空転/在庫超過なし, 1=1件以上のALERTあり(WARN表示用。BLOCKはしない)

set -euo pipefail

self="${BASH_SOURCE[0]}"
[[ "$self" != /* ]] && self="$PWD/$self"
ROOT="${LOOP_LEDGER_ROOT:-${self%/scripts/loop_ledger_update.sh}}"

LESSON_IMPACT="${LOOP_LEDGER_LESSON_IMPACT:-$ROOT/logs/lesson_impact.tsv}"
INSIGHTS_FILE="${LOOP_LEDGER_INSIGHTS_FILE:-$ROOT/queue/insights.yaml}"
DB_PATH="${LOOP_LEDGER_DB:-$ROOT/data/multi_agent_shogun_memory.db}"
SKILL_RECOMMEND_LOG="${LOOP_LEDGER_SKILL_RECOMMEND_LOG:-$ROOT/logs/skill_recommend_log.yaml}"
SKILL_EXECUTION_LOG="${LOOP_LEDGER_SKILL_EXECUTION_LOG:-$ROOT/logs/skill_execution_log.yaml}"
OUT_FILE="${LOOP_LEDGER_OUT:-$ROOT/logs/loop_ledger.yaml}"
NOW="${LOOP_LEDGER_NOW:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
WINDOW_DAYS="${LOOP_LEDGER_WINDOW_DAYS:-14}"
SKILL_EXEC_TAIL_LINES="${LOOP_LEDGER_SKILL_EXEC_TAIL_LINES:-30000}"
MAX_SNAPSHOTS="${LOOP_LEDGER_MAX_SNAPSHOTS:-100}"

# skill_execution_log.yaml は数万行規模になるためtailで有界化する(境界の壊れたエントリは破棄)
SKILL_EXEC_CHUNK="$(mktemp)"
trap 'rm -f "$SKILL_EXEC_CHUNK"' EXIT
if [ -f "$SKILL_EXECUTION_LOG" ]; then
    {
        printf 'executions:\n'
        tail -n "$SKILL_EXEC_TAIL_LINES" "$SKILL_EXECUTION_LOG" \
            | awk 'BEGIN{in_entry=0} /^executions:[[:space:]]*$/{next} /^[[:space:]]*-[[:space:]]+ts:/{in_entry=1} in_entry{print}'
    } > "$SKILL_EXEC_CHUNK"
else
    printf 'executions: []\n' > "$SKILL_EXEC_CHUNK"
fi

python3 - "$LESSON_IMPACT" "$INSIGHTS_FILE" "$DB_PATH" "$SKILL_RECOMMEND_LOG" "$SKILL_EXEC_CHUNK" \
    "$OUT_FILE" "$NOW" "$WINDOW_DAYS" "$MAX_SNAPSHOTS" <<'PY'
import datetime as dt
import re
import sqlite3
import sys
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

(lesson_impact_path, insights_path, db_path, skill_recommend_path,
 skill_exec_chunk_path, out_path, now_raw, window_days_raw, max_snapshots_raw) = sys.argv[1:10]

out_path = Path(out_path)
window_days = int(window_days_raw)
max_snapshots = int(max_snapshots_raw)


def parse_ts(value):
    text = str(value or "").strip().strip('"').strip("'")
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


now = parse_ts(now_raw) or dt.datetime.now(dt.timezone.utc)
cutoff = now - dt.timedelta(days=window_days)


def in_window(ts):
    return ts is not None and cutoff <= ts <= now


def iso(ts):
    if ts is None:
        return None
    return ts.isoformat().replace("+00:00", "Z")


def max_ts(values):
    values = [v for v in values if v is not None]
    return max(values) if values else None


# --- lesson loop: logs/lesson_impact.tsv (action=injected/feedback) ---
def load_lesson_loop(path):
    injected_window = 0
    feedback_window = 0
    injected_ids = set()
    feedback_ids = set()
    feedback_ts_all = []
    p = Path(path)
    if not p.is_file():
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "lesson_impact.tsv not found"}
    with p.open(encoding="utf-8", errors="replace") as fh:
        header = None
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            cols = line.split("\t")
            if header is None:
                header = cols
                continue
            if len(cols) < 6:
                continue
            ts = parse_ts(cols[0])
            lesson_id = cols[3].strip()
            action = cols[4].strip().lower()
            result = cols[5].strip().upper()
            if not lesson_id:
                continue
            if action == "injected":
                injected_ids.add(lesson_id)
                if in_window(ts):
                    injected_window += 1
            elif action == "feedback" and result in {"USEFUL", "NOT_USEFUL"}:
                feedback_ids.add(lesson_id)
                feedback_ts_all.append(ts)
                if in_window(ts):
                    feedback_window += 1
    stock = len(injected_ids - feedback_ids)
    return {
        "produced": injected_window,
        "consumed": feedback_window,
        "stock": stock,
        "last_consumption_ts": iso(max_ts(feedback_ts_all)),
    }


# --- insight / semantic loop: queue/insights.yaml ---
def load_insight_entries(path):
    p = Path(path)
    if not p.is_file():
        return []
    text = p.read_text(encoding="utf-8", errors="replace")
    entries = []
    if yaml is not None:
        try:
            data = yaml.safe_load(text) or {}
            raw = data.get("insights") or []
            for item in raw:
                if isinstance(item, dict):
                    entries.append(item)
            return entries
        except Exception:
            entries = []
    # Fallback: minimal line scanner (insights.yaml has a corrupt-backup history)
    current = None
    for line in text.splitlines():
        if line.startswith("- id:"):
            if current:
                entries.append(current)
            current = {"id": line.split(":", 1)[1].strip()}
            continue
        if current is None:
            continue
        m = re.match(r"^  (\w+):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip().strip('"').strip("'")
            current[key] = val
    if current:
        entries.append(current)
    return entries


def loop_from_insights(entries, predicate):
    produced = 0
    consumed = 0
    stock = 0
    consumption_ts_all = []
    for entry in entries:
        if not predicate(entry):
            continue
        ts = parse_ts(entry.get("ts"))
        status = str(entry.get("status") or "").strip().lower()
        if in_window(ts):
            produced += 1
        if status == "pending":
            stock += 1
        elif status in {"resolved", "done"}:
            consumption_ts = parse_ts(entry.get("resolved_at")) or ts
            consumption_ts_all.append(consumption_ts)
            if in_window(consumption_ts):
                consumed += 1
    return {
        "produced": produced,
        "consumed": consumed,
        "stock": stock,
        "last_consumption_ts": iso(max_ts(consumption_ts_all)),
    }


insight_entries = load_insight_entries(insights_path)
insight_loop = loop_from_insights(insight_entries, lambda e: True)


def is_semantic(entry):
    source = str(entry.get("source") or "").lower()
    insight_text = str(entry.get("insight") or "")
    return "semantic" in source or "NO_MATCH" in insight_text


semantic_loop = loop_from_insights(insight_entries, is_semantic)


# --- obsidian loop: data/multi_agent_shogun_memory.db (event_state_transitions) ---
def load_obsidian_loop(path):
    p = Path(path)
    if not p.is_file():
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "memory db not found"}
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except Exception as exc:
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": f"db connect failed: {exc}"}
    try:
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "event_state_transitions" not in tables or "events" not in tables:
            return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "required tables missing"}
        cutoff_iso = cutoff.isoformat().replace("+00:00", "")
        now_iso = now.isoformat().replace("+00:00", "")
        produced = conn.execute(
            "SELECT COUNT(*) FROM event_state_transitions "
            "WHERE to_state = 'obsidian_candidate' AND transitioned_at >= ? AND transitioned_at <= ?",
            (cutoff_iso, now_iso),
        ).fetchone()[0]
        consumed = conn.execute(
            "SELECT COUNT(*) FROM event_state_transitions "
            "WHERE to_state = 'obsidian_promoted' AND transitioned_at >= ? AND transitioned_at <= ?",
            (cutoff_iso, now_iso),
        ).fetchone()[0]
        stock = conn.execute(
            "SELECT COUNT(*) FROM events WHERE state = 'obsidian_candidate'"
        ).fetchone()[0]
        last_consumption = conn.execute(
            "SELECT MAX(transitioned_at) FROM event_state_transitions WHERE to_state = 'obsidian_promoted'"
        ).fetchone()[0]
        return {
            "produced": int(produced or 0),
            "consumed": int(consumed or 0),
            "stock": int(stock or 0),
            "last_consumption_ts": iso(parse_ts(last_consumption)) if last_consumption else None,
        }
    finally:
        conn.close()


obsidian_loop = load_obsidian_loop(db_path)


# --- memory recall loop: search_logs production + tagged shogun answer consumption ---
MEMORY_CITATION_PATTERN = re.compile(
    r"(?:\[(?:memory|mem|記憶|三層記憶)[^\]]*\]|"
    r"【(?:memory|mem|記憶|三層記憶)[^】]*】|"
    r"（(?:memory|mem|記憶|三層記憶)[^）]*）)",
    re.IGNORECASE,
)


def load_memory_loop(path):
    p = Path(path)
    if not p.is_file():
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "memory db not found"}
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except Exception as exc:
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": f"db connect failed: {exc}"}
    try:
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "search_logs" not in tables:
            return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "search_logs table missing"}
        if "events" not in tables:
            return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "events table missing"}
        event_cols = {row[1] for row in conn.execute("PRAGMA table_info(events)")}
        if not {"ts", "agent", "summary", "detail"}.issubset(event_cols):
            return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "note": "events citation columns missing"}

        cutoff_iso = cutoff.isoformat().replace("+00:00", "")
        now_iso = now.isoformat().replace("+00:00", "")
        produced = conn.execute(
            "SELECT COUNT(*) FROM search_logs WHERE ts >= ? AND ts <= ?",
            (cutoff_iso, now_iso),
        ).fetchone()[0]

        consumed = 0
        consumption_ts_all = []
        for raw_ts, agent, summary, detail in conn.execute(
            "SELECT ts, agent, summary, detail FROM events "
            "WHERE ts >= ? AND ts <= ? "
            "AND lower(coalesce(agent, '')) = 'shogun'",
            (cutoff_iso, now_iso),
        ):
            body = f"{summary or ''}\n{detail or ''}"
            if MEMORY_CITATION_PATTERN.search(body):
                consumed += 1
                consumption_ts_all.append(parse_ts(raw_ts))

        return {
            "produced": int(produced or 0),
            "consumed": int(consumed or 0),
            "stock": max(int(produced or 0) - consumed, 0),
            "last_consumption_ts": iso(max_ts(consumption_ts_all)),
        }
    finally:
        conn.close()


memory_loop = load_memory_loop(db_path)


# --- skill loop: logs/skill_recommend_log.yaml + logs/skill_execution_log.yaml ---
def load_skill_recommend(path):
    """Returns list of (ts, skill) tuples, one per recommended skill mention."""
    p = Path(path)
    if not p.is_file():
        return []
    events = []
    current_ts = None
    in_recommended = False
    with p.open(encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if line.startswith("- "):
                in_recommended = False
                current_ts = None
                rest = stripped[2:]
                if rest.startswith("ts:"):
                    current_ts = parse_ts(rest.split(":", 1)[1].strip())
                continue
            if not line.startswith("  "):
                in_recommended = False
                continue
            if stripped.startswith("ts:"):
                current_ts = parse_ts(stripped.split(":", 1)[1].strip())
                continue
            if stripped.startswith("recommended_skills:"):
                in_recommended = True
                tail = stripped.split(":", 1)[1].strip()
                if tail.startswith("[") and tail.endswith("]"):
                    for item in tail[1:-1].split(","):
                        skill = item.strip().strip('"').strip("'")
                        if skill:
                            events.append((current_ts, skill))
                    in_recommended = False
                continue
            if in_recommended and stripped.startswith("- "):
                skill = stripped[2:].strip().strip('"').strip("'")
                if skill:
                    events.append((current_ts, skill))
                continue
            if in_recommended and stripped and not stripped.startswith("- "):
                in_recommended = False
    return events


def load_skill_execution(path):
    """Returns list of (ts, skill, used_bool) from the bounded tail chunk."""
    p = Path(path)
    if not p.is_file():
        return []
    text = p.read_text(encoding="utf-8", errors="replace")
    entries = []
    if yaml is not None:
        try:
            data = yaml.safe_load(text) or {}
            for item in data.get("executions") or []:
                if isinstance(item, dict):
                    entries.append(item)
            return entries
        except Exception:
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
            continue
        if current is not None:
            m = re.match(r"^\s+([A-Za-z0-9_]+):\s*(.*)$", line)
            if m:
                current[m.group(1)] = m.group(2).strip().strip('"')
    if current:
        entries.append(current)
    return entries


recommend_events = load_skill_recommend(skill_recommend_path)
exec_entries = load_skill_execution(skill_exec_chunk_path)

produced_skill = sum(1 for ts, _ in recommend_events if in_window(ts))
recommended_all = {skill for _, skill in recommend_events}

used_exec = [
    (parse_ts(e.get("ts")), str(e.get("skill") or ""))
    for e in exec_entries
    if str(e.get("used") or "").strip().lower() == "true"
]
consumed_skill = sum(1 for ts, _ in used_exec if in_window(ts))
executed_skills = {skill for _, skill in used_exec if skill}
skill_stock = len({s for s in recommended_all if s and s not in executed_skills})
skill_last_consumption = iso(max_ts([ts for ts, _ in used_exec]))

skill_loop = {
    "produced": produced_skill,
    "consumed": consumed_skill,
    "stock": skill_stock,
    "last_consumption_ts": skill_last_consumption,
}

loops = {
    "lesson": load_lesson_loop(lesson_impact_path),
    "insight": insight_loop,
    "semantic": semantic_loop,
    "obsidian": obsidian_loop,
    "memory": memory_loop,
    "skill": skill_loop,
}

for name, loop in loops.items():
    loop["stalled"] = bool(loop["produced"] > 0 and loop["consumed"] == 0)


# --- load existing snapshots (never yaml.dump — manual emit, this file is fully owned by this script) ---
def load_existing_snapshots(path):
    if not path.is_file() or yaml is None:
        return []
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return []
    items = data.get("snapshots") if isinstance(data, dict) else None
    return [item for item in (items or []) if isinstance(item, dict)]


existing_snapshots = load_existing_snapshots(out_path)
previous_snapshot = existing_snapshots[-1] if existing_snapshots else None
previous_loops = previous_snapshot.get("loops", {}) if previous_snapshot else {}

alerts = []
for name in ("lesson", "insight", "semantic", "obsidian", "memory", "skill"):
    loop = loops[name]
    if loop["stalled"]:
        alerts.append(f"{name}: 空転(produced={loop['produced']}, consumed=0, window={window_days}d)")
    prev = previous_loops.get(name) if isinstance(previous_loops, dict) else None
    if isinstance(prev, dict):
        prev_stock = prev.get("stock")
        if isinstance(prev_stock, int) and loop["stock"] > prev_stock:
            alerts.append(f"{name}: 在庫超過(前回{prev_stock}→今回{loop['stock']})")


def q(value):
    if value is None:
        return "null"
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_snapshot(generated_at, window_days, loops):
    lines = [
        f"- generated_at: {q(generated_at)}",
        f"  window_days: {window_days}",
        "  loops:",
    ]
    for name in ("lesson", "insight", "semantic", "obsidian", "memory", "skill"):
        loop = loops[name]
        lines.append(f"    {name}:")
        lines.append(f"      produced: {int(loop['produced'])}")
        lines.append(f"      consumed: {int(loop['consumed'])}")
        lines.append(f"      stock: {int(loop['stock'])}")
        lines.append(f"      last_consumption_ts: {q(loop['last_consumption_ts'])}")
        lines.append(f"      stalled: {'true' if loop['stalled'] else 'false'}")
        if loop.get("note"):
            lines.append(f"      note: {q(loop['note'])}")
    return "\n".join(lines)


snapshot_text = emit_snapshot(iso(now), window_days, loops)
snapshots_text = [snapshot_text] if not existing_snapshots else None

# Re-emit all prior snapshots (already-validated dicts) + the new one, capped to max_snapshots
all_snapshot_dicts = existing_snapshots + [{
    "generated_at": iso(now),
    "window_days": window_days,
    "loops": {name: dict(loop) for name, loop in loops.items()},
}]
all_snapshot_dicts = all_snapshot_dicts[-max_snapshots:]

rendered = []
for snap in all_snapshot_dicts:
    snap_loops = snap.get("loops", {})
    rendered.append(emit_snapshot(snap.get("generated_at"), snap.get("window_days", window_days), {
        name: snap_loops.get(name, {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "stalled": False})
        for name in ("lesson", "insight", "semantic", "obsidian", "memory", "skill")
    }))

out_path.parent.mkdir(parents=True, exist_ok=True)
content = ["# loop_ledger.yaml — generated by scripts/loop_ledger_update.sh (T7, cmd_3720)", "snapshots:"]
content.extend(rendered)
if alerts:
    content.append("alerts:")
    content.extend(f"- {q(a)}" for a in alerts)
else:
    # "alerts:\n[]" (key/value split across lines) is invalid YAML —
    # empty flow sequences must stay on the same line as the key.
    content.append("alerts: []")
out_path.write_text("\n".join(content) + "\n", encoding="utf-8")

print("=== Loop Ledger (T7) ===")
for name in ("lesson", "insight", "semantic", "obsidian", "memory", "skill"):
    loop = loops[name]
    note = f" note={loop['note']}" if loop.get("note") else ""
    print(
        f"  {name}: produced={loop['produced']} consumed={loop['consumed']} "
        f"stock={loop['stock']} last_consumption={loop['last_consumption_ts']} "
        f"stalled={loop['stalled']}{note}"
    )
if alerts:
    for a in alerts:
        print(f"ALERT: {a}")
    raise SystemExit(1)
print("OK: loop ledger updated, no stall/stock-increase detected")
PY
