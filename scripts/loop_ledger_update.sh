#!/usr/bin/env bash
# loop_ledger_update.sh — 学習ループ別(教訓/insight/semantic/obsidian/memory/skill)統合台帳 (T7, cmd_3720)
# 目的: 各ループの生産量・消化量・在庫・最終消化時刻を既存ログ/DBから集計し、
#       律速段階(最も詰まった段階)と空転(生産継続なのに消化ゼロ)を可視化する。
# Usage: bash scripts/loop_ledger_update.sh
# Exit: 0=空転/在庫超過なし, 1=1件以上のALERTあり(WARN表示用。BLOCKはしない)

set -euo pipefail

self="${BASH_SOURCE[0]}"
[[ "$self" != /* ]] && self="$PWD/$self"
SCRIPT_ROOT="${self%/scripts/loop_ledger_update.sh}"
ROOT="${LOOP_LEDGER_ROOT:-$SCRIPT_ROOT}"

LESSON_IMPACT="${LOOP_LEDGER_LESSON_IMPACT:-$ROOT/logs/lesson_impact.tsv}"
INSIGHTS_FILE="${LOOP_LEDGER_INSIGHTS_FILE:-$ROOT/queue/insights.yaml}"
DB_PATH="${LOOP_LEDGER_DB:-$ROOT/data/multi_agent_shogun_memory.db}"
SKILL_RECOMMEND_LOG="${LOOP_LEDGER_SKILL_RECOMMEND_LOG:-$ROOT/logs/skill_recommend_log.yaml}"
SKILL_EXECUTION_LOG="${LOOP_LEDGER_SKILL_EXECUTION_LOG:-$ROOT/logs/skill_execution_log.yaml}"
REPORT_DIRS="${LOOP_LEDGER_REPORT_DIRS:-$ROOT/queue/reports:$ROOT/queue/archive/reports}"
REPORT_MAX_FILES="${LOOP_LEDGER_REPORT_MAX_FILES:-500}"
OUT_FILE="${LOOP_LEDGER_OUT:-$ROOT/logs/loop_ledger.yaml}"
NOW="${LOOP_LEDGER_NOW:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
WINDOW_DAYS="${LOOP_LEDGER_WINDOW_DAYS:-14}"
SKILL_EXEC_TAIL_LINES="${LOOP_LEDGER_SKILL_EXEC_TAIL_LINES:-30000}"
MAX_SNAPSHOTS="${LOOP_LEDGER_MAX_SNAPSHOTS:-100}"
STARTUP_ALERT_HISTORY="${LOOP_LEDGER_STARTUP_ALERT_HISTORY:-$ROOT/logs/shogun_startup_alert_history.tsv}"
GATE_METRICS_LOG="${LOOP_LEDGER_GATE_METRICS_LOG:-$ROOT/logs/gate_metrics.log}"

# obsidian_loop/memory_loopはevents.summary/detailの行本体を読むため、WSL2 /mnt/c(9p)上だと
# 行本体読取が約40倍遅い(citation_countクエリ実測3.3s vs ext4コピー0.085s)。
# memory_db_query.shと同じext4キャッシュ+鮮度判定+fail-safeを共有ライブラリ経由で再利用する。
# repo_root(モジュール解決)は常にSCRIPT_ROOT(実スクリプト位置)を使う。ROOTはLOOP_LEDGER_ROOTで
# テスト用に差し替え可能なデータルートであり、memory_db_live_insert.pyの所在とは無関係。
DB_DEFAULT_PATH="$ROOT/data/multi_agent_shogun_memory.db"
DB_READ_PATH="$DB_PATH"
if [ -f "$SCRIPT_ROOT/scripts/lib/memory_db_cache.sh" ]; then
    # shellcheck source=lib/memory_db_cache.sh
    source "$SCRIPT_ROOT/scripts/lib/memory_db_cache.sh"
    DB_READ_PATH="$(prepare_memory_db_for_read "$SCRIPT_ROOT" "$DB_PATH" "$DB_DEFAULT_PATH" 2>/dev/null || printf '%s' "$DB_PATH")"
    [ -n "$DB_READ_PATH" ] || DB_READ_PATH="$DB_PATH"
fi

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
    "$REPORT_DIRS" "$REPORT_MAX_FILES" "$OUT_FILE" "$NOW" "$WINDOW_DAYS" "$MAX_SNAPSHOTS" "$ROOT" \
    "$STARTUP_ALERT_HISTORY" "$GATE_METRICS_LOG" "$DB_READ_PATH" <<'PY'
import datetime as dt
import os
import re
import sqlite3
import sys
import subprocess
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

(lesson_impact_path, insights_path, db_path, skill_recommend_path,
 skill_exec_chunk_path, report_dirs_raw, report_max_files_raw, out_path, now_raw,
 window_days_raw, max_snapshots_raw, root_path_raw, startup_alert_history_path) = sys.argv[1:14]
gate_metrics_path = sys.argv[14]
# ext4キャッシュ解決済みの読取パス(memory_db_cache.sh側でstale/missing/timeout時はdb_pathへfallback済み)。
# 空/未指定ならdb_path(正本)を使う。
db_read_path = sys.argv[15] if len(sys.argv) > 15 and sys.argv[15] else db_path

out_path = Path(out_path)
root_path = Path(root_path_raw)
window_days = int(window_days_raw)
max_snapshots = int(max_snapshots_raw)
report_max_files = int(report_max_files_raw)


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
        # naive timestamps come from local-clock writers (gate_metrics.log,
        # lesson impact log); interpreting them as UTC shifts JST entries 9h
        # into the future and in_window() drops them
        parsed = parsed.astimezone()
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


def median(values):
    nums = sorted(v for v in values if isinstance(v, (int, float)))
    if not nums:
        return None
    mid = len(nums) // 2
    if len(nums) % 2:
        return float(nums[mid])
    return (nums[mid - 1] + nums[mid]) / 2.0


def round1(value):
    return None if value is None else round(float(value), 1)


def as_float(value):
    try:
        if value is None:
            return None
        return float(value)
    except Exception:
        return None


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


def age_hours_since(ts):
    if ts is None:
        return 0.0
    return round(max((now - ts).total_seconds(), 0) / 3600, 2)


def loop_from_insights(entries, predicate):
    produced = 0
    consumed = 0
    stock = 0
    consumption_ts_all = []
    pending_ts_all = []
    invalid_resolution_count = 0
    for entry in entries:
        if not predicate(entry):
            continue
        ts = parse_ts(entry.get("ts"))
        status = str(entry.get("status") or "").strip().lower()
        if in_window(ts):
            produced += 1
        if status == "pending":
            stock += 1
            pending_ts_all.append(ts)
        elif status in {"resolved", "done"}:
            # A status flip alone is not consumption.  Require both the reason
            # and the concrete artifact/cmd/path that proves the action.
            if not str(entry.get("resolved_reason") or "").strip() or not str(entry.get("action_artifact") or "").strip():
                invalid_resolution_count += 1
                continue
            consumption_ts = parse_ts(entry.get("resolved_at")) or ts
            consumption_ts_all.append(consumption_ts)
            if in_window(consumption_ts):
                consumed += 1
    # W6(cmd_3748): 気づき在庫の初回検出(first_seen)からの経過時間を可視化(滞留コスト)
    oldest_pending = min((t for t in pending_ts_all if t is not None), default=None)
    return {
        "produced": produced,
        "consumed": consumed,
        "stock": stock,
        "last_consumption_ts": iso(max_ts(consumption_ts_all)),
        "oldest_pending_ts": iso(oldest_pending),
        "oldest_pending_age_hours": age_hours_since(oldest_pending),
        "invalid_resolution_count": invalid_resolution_count,
    }


insight_entries = load_insight_entries(insights_path)
insight_loop = loop_from_insights(insight_entries, lambda e: True)


def is_semantic(entry):
    source = str(entry.get("source") or "").lower()
    insight_text = str(entry.get("insight") or "")
    return "semantic" in source or "NO_MATCH" in insight_text


semantic_loop = loop_from_insights(insight_entries, is_semantic)


# --- promotion loop: lesson enforcement candidates below Level4 ---
def load_promotion_consumption(root_path, metrics_path):
    consumed_by_cmd = {}

    def record(cmd_id, ts):
        if not cmd_id.startswith("cmd_reflux_promotion_"):
            return
        if not in_window(ts):
            return
        prev = consumed_by_cmd.get(cmd_id)
        if prev is None or (ts is not None and ts > prev):
            consumed_by_cmd[cmd_id] = ts

    # gate_metrics.log is the primary source: reflux auto-generated cmds skip
    # cmd_save, so they never appear in logs/cmd_design_quality.yaml
    metrics = Path(metrics_path)
    if metrics.is_file():
        for line in metrics.read_text(encoding="utf-8", errors="replace").splitlines():
            cols = line.split("\t")
            if len(cols) < 3 or cols[2].strip().upper() != "CLEAR":
                continue
            record(cols[1].strip(), parse_ts(cols[0]))

    quality_path = Path(root_path) / "logs" / "cmd_design_quality.yaml"
    if quality_path.is_file() and yaml is not None:
        try:
            entries = yaml.safe_load(quality_path.read_text(encoding="utf-8")) or []
        except Exception:
            entries = []
        if isinstance(entries, dict):
            entries = entries.get("entries") or []
        if isinstance(entries, list):
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                if str(entry.get("gate_result") or "").upper() != "CLEAR":
                    continue
                record(str(entry.get("cmd_id") or ""), parse_ts(entry.get("timestamp")))

    return len(consumed_by_cmd), max_ts(consumed_by_cmd.values())


def load_promotion_loop(root_path, metrics_path):
    consumed, last_consumption_ts = load_promotion_consumption(root_path, metrics_path)
    helper = Path(root_path) / "scripts" / "gates" / "gate_lesson_enforcement_level.sh"
    if not helper.is_file():
        return {"produced": 0, "consumed": consumed, "stock": 0, "last_consumption_ts": iso(last_consumption_ts), "note": "gate_lesson_enforcement_level.sh not found"}
    try:
        env = os.environ.copy()
        env["LESSON_ENFORCEMENT_ROOT"] = str(root_path)
        proc = subprocess.run(
            ["bash", str(helper)],
            cwd=str(root_path),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=20,
            check=False,
        )
    except Exception as exc:
        return {"produced": 0, "consumed": consumed, "stock": 0, "last_consumption_ts": iso(last_consumption_ts), "note": f"promotion scan failed: {exc}"}
    if proc.returncode != 0:
        return {"produced": 0, "consumed": consumed, "stock": 0, "last_consumption_ts": iso(last_consumption_ts), "note": f"promotion scan status {proc.returncode}"}
    count = 0
    first_candidate = None
    lines = proc.stdout.splitlines()
    for idx, line in enumerate(lines):
        if line.startswith("##ENFORCEMENT_LEVEL_BELOW4_COUNT##") and idx + 1 < len(lines):
            try:
                count = int(str(lines[idx + 1]).strip())
            except ValueError:
                count = 0
        if first_candidate is None and line.startswith("  - "):
            first_candidate = line[4:].strip()
    return {
        "produced": count,
        "consumed": consumed,
        "stock": count,
        "last_consumption_ts": iso(last_consumption_ts),
        "first_candidate": first_candidate,
    }


# --- warn backlog loop: logs/shogun_startup_alert_history.tsv (未解消WARNの初回検出からの経過時間, W6) ---
def load_warn_backlog(path):
    p = Path(path)
    if not p.is_file():
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None,
                "note": "shogun_startup_alert_history.tsv not found", "items": []}
    rows = []
    with p.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 1)
            if len(parts) != 2:
                continue
            ts = parse_ts(parts[0])
            text = parts[1].strip()
            if not text or text == "__OK__":
                continue
            key = text.split(":", 1)[0].strip() if ":" in text else text
            rows.append((ts, key, text))
    if not rows:
        return {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "items": []}

    latest_run_ts = max_ts([r[0] for r in rows])
    active_keys = {key for ts, key, _ in rows if ts is not None and ts == latest_run_ts}

    first_seen = {}
    sample_text = {}
    for ts, key, text in rows:
        if ts is None:
            continue
        if key not in first_seen or ts < first_seen[key]:
            first_seen[key] = ts
        if key in active_keys:
            sample_text[key] = text

    produced = len({key for ts, key, _ in rows if in_window(ts)})
    items = []
    for key in sorted(active_keys):
        fs = first_seen.get(key)
        items.append({
            "key": key,
            "first_seen": iso(fs),
            "age_hours": age_hours_since(fs),
            "sample": sample_text.get(key, key),
        })
    items.sort(key=lambda item: item["age_hours"], reverse=True)
    return {
        "produced": produced,
        "consumed": 0,
        "stock": len(active_keys),
        "last_consumption_ts": None,
        "items": items,
    }


# memory dbはext4キャッシュ(read_path)を優先して開く。キャッシュが未生成/欠損/破損(corrupt)の
# 場合のみ正本(source_path)へ1回だけfallbackする。正本との全行/件数完全一致を守るための最終防御。
def _run_with_cache_fallback(read_path, source_path, query_fn, empty_result):
    candidates = [read_path]
    if source_path and source_path != read_path:
        candidates.append(source_path)

    existing = [c for c in candidates if Path(c).is_file()]
    if not existing:
        return {**empty_result, "note": "memory db not found"}

    last_exc = None
    for candidate in existing:
        try:
            conn = sqlite3.connect(f"file:{candidate}?mode=ro", uri=True)
        except Exception as exc:
            last_exc = exc
            continue
        try:
            return query_fn(conn)
        except sqlite3.DatabaseError as exc:
            last_exc = exc
            continue
        finally:
            conn.close()
    return {**empty_result, "note": f"db read failed: {last_exc}"}


# --- obsidian loop: data/multi_agent_shogun_memory.db (event_state_transitions) ---
def load_obsidian_loop(path, source_path=None):
    empty = {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None}

    def _query(conn):
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "event_state_transitions" not in tables or "events" not in tables:
            return {**empty, "note": "required tables missing"}
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

    return _run_with_cache_fallback(path, source_path, _query, empty)


obsidian_loop = load_obsidian_loop(db_read_path, db_path)


# --- memory candidate loop + recall usage diagnostics ---
MEMORY_CITATION_PATTERN = re.compile(
    r"(?:\[(?:memory|mem|記憶|三層記憶)[^\]]*\]|"
    r"【(?:memory|mem|記憶|三層記憶)[^】]*】|"
    r"（(?:memory|mem|記憶|三層記憶)[^）]*）)",
    re.IGNORECASE,
)


def load_memory_loop(path, source_path=None):
    empty = {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "search_count": 0, "citation_count": 0}

    def _query(conn):
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "events" not in tables:
            return {**empty, "note": "events table missing"}
        event_cols = {row[1] for row in conn.execute("PRAGMA table_info(events)")}
        if "state" not in event_cols:
            return {**empty, "note": "events.state missing"}

        cutoff_iso = cutoff.isoformat().replace("+00:00", "")
        now_iso = now.isoformat().replace("+00:00", "")
        candidate_states = ("contradiction_candidate", "duplicate_candidate", "obsidian_candidate")
        stock = conn.execute(
            "SELECT COUNT(*) FROM events WHERE state IN (?,?,?)", candidate_states
        ).fetchone()[0]

        produced = consumed = 0
        consumption_ts_all = []
        if "event_state_transitions" in tables:
            produced = conn.execute(
                "SELECT COUNT(*) FROM event_state_transitions WHERE transitioned_at >= ? AND transitioned_at <= ? AND to_state IN (?,?,?)",
                (cutoff_iso, now_iso, *candidate_states),
            ).fetchone()[0]
            rows = conn.execute(
                "SELECT transitioned_at FROM event_state_transitions WHERE transitioned_at >= ? AND transitioned_at <= ? AND from_state IN (?,?,?) AND to_state NOT IN (?,?,?)",
                (cutoff_iso, now_iso, *candidate_states, *candidate_states),
            ).fetchall()
            consumed = len(rows)
            consumption_ts_all = [parse_ts(row[0]) for row in rows]

        search_count = 0
        if "search_logs" in tables:
            search_count = conn.execute(
                "SELECT COUNT(*) FROM search_logs WHERE ts >= ? AND ts <= ?", (cutoff_iso, now_iso)
            ).fetchone()[0]
        citation_count = 0
        if {"ts", "agent", "summary", "detail"}.issubset(event_cols):
            for _, agent, summary, detail in conn.execute(
                "SELECT ts, agent, summary, detail FROM events WHERE ts >= ? AND ts <= ? AND lower(coalesce(agent, '')) = 'shogun'",
                (cutoff_iso, now_iso),
            ):
                if MEMORY_CITATION_PATTERN.search(f"{summary or ''}\n{detail or ''}"):
                    citation_count += 1

        return {
            "produced": int(produced or 0),
            "consumed": int(consumed or 0),
            "stock": int(stock or 0),
            "last_consumption_ts": iso(max_ts(consumption_ts_all)),
            "search_count": int(search_count or 0),
            "citation_count": int(citation_count or 0),
        }

    return _run_with_cache_fallback(path, source_path, _query, empty)


def load_memory_reference_effectiveness(report_dirs_raw):
    evaluated = 0
    useful = 0
    irrelevant_by_source = {}
    latest_by_source = {}
    report_count = 0
    candidates = []
    for raw_dir in str(report_dirs_raw or "").split(":"):
        if not raw_dir:
            continue
        directory = Path(raw_dir)
        if not directory.is_dir():
            continue
        candidates.extend(directory.glob("*.yaml"))
    candidates = sorted(candidates, key=lambda path: str(path), reverse=True)
    if report_max_files > 0:
        candidates = candidates[:report_max_files]

    def extract_memory_references(path):
        block = []
        in_block = False
        try:
            with path.open(encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if not in_block:
                        if line.startswith("memory_references:"):
                            in_block = True
                            block.append(line)
                        continue
                    if line and not line.startswith((" ", "-", "\t")) and not line.lstrip().startswith("#"):
                        break
                    block.append(line)
        except OSError:
            return None
        if not block:
            return None
        try:
            parsed = yaml.safe_load("".join(block)) or {}
        except Exception:
            return None
        if not isinstance(parsed, dict):
            return None
        return parsed.get("memory_references")

    for report in candidates:
        if yaml is None:
            continue
        refs = extract_memory_references(report)
        if not isinstance(refs, list):
            continue
        report_count += 1
        for item in refs:
            if not isinstance(item, dict):
                continue
            if not isinstance(item.get("useful"), bool):
                continue
            source = str(item.get("source") or "unknown").strip() or "unknown"
            query = str(item.get("query") or "").strip()
            reason = str(item.get("reason") or "").strip()
            evaluated += 1
            if item.get("useful") is True:
                useful += 1
            else:
                irrelevant_by_source[source] = irrelevant_by_source.get(source, 0) + 1
                latest_by_source[source] = {
                    "source": source,
                    "count": irrelevant_by_source[source],
                    "sample_query": query[:160],
                    "sample_reason": reason[:160],
                }
    useful_rate = round((useful / evaluated) * 100, 1) if evaluated else 0.0
    reflux_targets = [
        latest_by_source[source]
        for source, _ in sorted(irrelevant_by_source.items(), key=lambda kv: (-kv[1], kv[0]))
    ]
    return {
        "evaluated": evaluated,
        "useful": useful,
        "useful_rate_pct": useful_rate,
        "irrelevant_by_source": irrelevant_by_source,
        "reflux_targets": reflux_targets,
        "report_count": report_count,
    }


memory_loop = load_memory_loop(db_read_path, db_path)
memory_effectiveness = load_memory_reference_effectiveness(report_dirs_raw)
memory_loop.update(memory_effectiveness)


# --- throughput loop: gate_metrics CLEAR rows with cmd-level stage durations ---
def parse_metric_pairs(text):
    pairs = {}
    for part in str(text or "").split():
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        pairs[key.strip()] = value.strip()
    return pairs


def parse_num(value):
    try:
        text = str(value).strip()
        if text in {"", "na", "unknown", "null", "None"}:
            return None
        return float(text)
    except Exception:
        return None


def load_throughput_loop(path):
    p = Path(path)
    if not p.is_file():
        return {
            "produced": 0,
            "consumed": 0,
            "stock": 0,
            "last_consumption_ts": None,
            "note": "gate_metrics.log not found",
            "completed_cmds": 0,
            "e2e_median_sec": None,
            "overhead_rate_median_pct": None,
            "deploy_median_sec": None,
            "work_median_sec": None,
            "finalize_median_sec": None,
        }
    latest = {}
    with p.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            cols = line.rstrip("\n").split("\t")
            if len(cols) < 4:
                continue
            ts = parse_ts(cols[0])
            if not in_window(ts):
                continue
            cmd_id = cols[1].strip()
            status = cols[2].strip().upper()
            if status != "CLEAR" or not cmd_id:
                continue
            throughput_field = next((c for c in cols[8:] if "e2e_sec=" in c and "work_sec=" in c), "")
            if not throughput_field:
                continue
            prev = latest.get(cmd_id)
            if prev is None or (ts is not None and ts > prev[0]):
                latest[cmd_id] = (ts, parse_metric_pairs(throughput_field))
    rows = list(latest.values())
    deploy = []
    work = []
    finalize = []
    e2e = []
    overhead_rates = []
    for _, metrics in rows:
        d = parse_num(metrics.get("deploy_sec"))
        w = parse_num(metrics.get("work_sec"))
        f = parse_num(metrics.get("finalize_sec"))
        e = parse_num(metrics.get("e2e_sec"))
        if d is not None:
            deploy.append(d)
        if w is not None:
            work.append(w)
        if f is not None:
            finalize.append(f)
        if e is not None:
            e2e.append(e)
        if e is not None and w is not None and e > 0:
            overhead_rates.append(max((e - w) / e * 100.0, 0.0))
    last_ts = max_ts([ts for ts, _ in rows])
    completed = len(rows)
    return {
        "produced": completed,
        "consumed": completed,
        "stock": 0,
        "last_consumption_ts": iso(last_ts),
        "completed_cmds": completed,
        "e2e_median_sec": round1(median(e2e)),
        "overhead_rate_median_pct": round1(median(overhead_rates)),
        "deploy_median_sec": round1(median(deploy)),
        "work_median_sec": round1(median(work)),
        "finalize_median_sec": round1(median(finalize)),
    }


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
    "promotion": load_promotion_loop(root_path, gate_metrics_path),
    "obsidian": obsidian_loop,
    "memory": memory_loop,
    "skill": skill_loop,
    "throughput": load_throughput_loop(gate_metrics_path),
}

warn_backlog = load_warn_backlog(startup_alert_history_path)

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
stock_increase_grace_hours = int(os.environ.get("LOOP_LEDGER_STOCK_INCREASE_GRACE_HOURS", "24"))
for name in ("lesson", "insight", "semantic", "promotion", "obsidian", "memory", "skill", "throughput"):
    loop = loops[name]
    if loop["stalled"]:
        alerts.append(f"{name}: 空転(produced={loop['produced']}, consumed=0, window={window_days}d)")
    prev = previous_loops.get(name) if isinstance(previous_loops, dict) else None
    if isinstance(prev, dict):
        prev_stock = prev.get("stock")
        if isinstance(prev_stock, int) and loop["stock"] > prev_stock:
            # New production can legitimately outrun the consumer between adjacent
            # startup snapshots.  Escalate only after the consumer has had a full
            # cycle to react; otherwise every newly produced lesson becomes an
            # immediate false positive despite recent consumption.
            last_consumption = parse_ts(loop.get("last_consumption_ts"))
            consumption_age_hours = (
                max((now - last_consumption).total_seconds(), 0) / 3600
                if last_consumption is not None else float("inf")
            )
            if consumption_age_hours >= stock_increase_grace_hours:
                alerts.append(f"{name}: 在庫超過(前回{prev_stock}→今回{loop['stock']})")
    if name == "throughput" and isinstance(prev, dict):
        prev_e2e = as_float(prev.get("e2e_median_sec"))
        curr_e2e = as_float(loop.get("e2e_median_sec"))
        if prev_e2e is not None and curr_e2e is not None and curr_e2e > prev_e2e:
            alerts.append(f"throughput: E2E中央値悪化(前回{prev_e2e}→今回{curr_e2e}秒)")
        prev_overhead = as_float(prev.get("overhead_rate_median_pct"))
        curr_overhead = as_float(loop.get("overhead_rate_median_pct"))
        if prev_overhead is not None and curr_overhead is not None and curr_overhead > prev_overhead:
            alerts.append(f"throughput: オーバーヘッド率悪化(前回{prev_overhead}→今回{curr_overhead}%)")

promotion_loop = loops["promotion"]
prev_promotion = previous_loops.get("promotion") if isinstance(previous_loops, dict) else None
if int(promotion_loop.get("stock", 0) or 0) > 0:
    started = None
    if isinstance(prev_promotion, dict) and int(prev_promotion.get("stock", 0) or 0) > 0:
        started = parse_ts(prev_promotion.get("stock_started_at"))
    if started is None:
        started = now
    promotion_loop["stock_started_at"] = iso(started)
    promotion_loop["age_hours"] = round(max((now - started).total_seconds(), 0) / 3600, 2)
else:
    promotion_loop["stock_started_at"] = None
    promotion_loop["age_hours"] = 0.0


def q(value):
    if value is None:
        return "null"
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_snapshot(generated_at, window_days, loops, warn_backlog=None):
    lines = [
        f"- generated_at: {q(generated_at)}",
        f"  window_days: {window_days}",
        "  loops:",
    ]
    for name in ("lesson", "insight", "semantic", "promotion", "obsidian", "memory", "skill", "throughput"):
        loop = loops[name]
        lines.append(f"    {name}:")
        lines.append(f"      produced: {int(loop['produced'])}")
        lines.append(f"      consumed: {int(loop['consumed'])}")
        lines.append(f"      stock: {int(loop['stock'])}")
        lines.append(f"      last_consumption_ts: {q(loop['last_consumption_ts'])}")
        lines.append(f"      stalled: {'true' if loop['stalled'] else 'false'}")
        if loop.get("note"):
            lines.append(f"      note: {q(loop['note'])}")
        if name in ("insight", "semantic"):
            lines.append(f"      oldest_pending_ts: {q(loop.get('oldest_pending_ts'))}")
            lines.append(f"      oldest_pending_age_hours: {float(loop.get('oldest_pending_age_hours', 0.0) or 0.0)}")
            lines.append(f"      invalid_resolution_count: {int(loop.get('invalid_resolution_count', 0) or 0)}")
        if name == "promotion":
            lines.append(f"      stock_started_at: {q(loop.get('stock_started_at'))}")
            lines.append(f"      age_hours: {float(loop.get('age_hours', 0.0) or 0.0)}")
            lines.append(f"      first_candidate: {q(loop.get('first_candidate'))}")
        if name == "memory":
            lines.append(f"      search_count: {int(loop.get('search_count', 0) or 0)}")
            lines.append(f"      citation_count: {int(loop.get('citation_count', 0) or 0)}")
            lines.append(f"      evaluated: {int(loop.get('evaluated', 0) or 0)}")
            lines.append(f"      useful: {int(loop.get('useful', 0) or 0)}")
            lines.append(f"      useful_rate_pct: {float(loop.get('useful_rate_pct', 0.0) or 0.0)}")
            lines.append(f"      report_count: {int(loop.get('report_count', 0) or 0)}")
            irrelevant = loop.get("irrelevant_by_source") or {}
            if irrelevant:
                lines.append("      irrelevant_by_source:")
                for source, count in sorted(irrelevant.items()):
                    lines.append(f"        {q(source)}: {int(count)}")
            else:
                lines.append("      irrelevant_by_source: {}")
            targets = [target for target in (loop.get("reflux_targets") or []) if isinstance(target, dict)]
            if targets:
                lines.append("      reflux_targets:")
                for target in targets:
                    lines.append(f"        - source: {q(target.get('source'))}")
                    lines.append(f"          count: {int(target.get('count', 0) or 0)}")
                    lines.append(f"          sample_query: {q(target.get('sample_query'))}")
                    lines.append(f"          sample_reason: {q(target.get('sample_reason'))}")
            else:
                lines.append("      reflux_targets: []")
        if name == "throughput":
            lines.append(f"      completed_cmds: {int(loop.get('completed_cmds', 0) or 0)}")
            lines.append(f"      e2e_median_sec: {q(loop.get('e2e_median_sec'))}")
            lines.append(f"      overhead_rate_median_pct: {q(loop.get('overhead_rate_median_pct'))}")
            lines.append(f"      deploy_median_sec: {q(loop.get('deploy_median_sec'))}")
            lines.append(f"      work_median_sec: {q(loop.get('work_median_sec'))}")
            lines.append(f"      finalize_median_sec: {q(loop.get('finalize_median_sec'))}")
    if warn_backlog is not None:
        lines.append("  warn_backlog:")
        lines.append(f"    produced: {int(warn_backlog.get('produced', 0) or 0)}")
        lines.append(f"    consumed: {int(warn_backlog.get('consumed', 0) or 0)}")
        lines.append(f"    stock: {int(warn_backlog.get('stock', 0) or 0)}")
        lines.append(f"    last_consumption_ts: {q(warn_backlog.get('last_consumption_ts'))}")
        if warn_backlog.get("note"):
            lines.append(f"    note: {q(warn_backlog.get('note'))}")
        items = [item for item in (warn_backlog.get("items") or []) if isinstance(item, dict)]
        if items:
            lines.append("    items:")
            for item in items:
                lines.append(f"      - key: {q(item.get('key'))}")
                lines.append(f"        first_seen: {q(item.get('first_seen'))}")
                lines.append(f"        age_hours: {float(item.get('age_hours', 0.0) or 0.0)}")
                lines.append(f"        sample: {q(item.get('sample'))}")
        else:
            lines.append("    items: []")
    return "\n".join(lines)


snapshot_text = emit_snapshot(iso(now), window_days, loops)
snapshots_text = [snapshot_text] if not existing_snapshots else None

# Re-emit all prior snapshots (already-validated dicts) + the new one, capped to max_snapshots
all_snapshot_dicts = existing_snapshots + [{
    "generated_at": iso(now),
    "window_days": window_days,
    "loops": {name: dict(loop) for name, loop in loops.items()},
    "warn_backlog": dict(warn_backlog),
}]
all_snapshot_dicts = all_snapshot_dicts[-max_snapshots:]

rendered = []
for snap in all_snapshot_dicts:
    snap_loops = snap.get("loops", {})
    rendered.append(emit_snapshot(snap.get("generated_at"), snap.get("window_days", window_days), {
        name: snap_loops.get(name, {"produced": 0, "consumed": 0, "stock": 0, "last_consumption_ts": None, "stalled": False})
        for name in ("lesson", "insight", "semantic", "promotion", "obsidian", "memory", "skill", "throughput")
    }, snap.get("warn_backlog")))

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
for name in ("lesson", "insight", "semantic", "promotion", "obsidian", "memory", "skill", "throughput"):
    loop = loops[name]
    note = f" note={loop['note']}" if loop.get("note") else ""
    print(
        f"  {name}: produced={loop['produced']} consumed={loop['consumed']} "
        f"stock={loop['stock']} last_consumption={loop['last_consumption_ts']} "
        f"stalled={loop['stalled']}{note}"
    )
    if name == "memory":
        print(
            f"    effectiveness: evaluated={loop.get('evaluated', 0)} "
            f"useful={loop.get('useful', 0)} useful_rate_pct={loop.get('useful_rate_pct', 0.0)} "
            f"reflux_targets={len(loop.get('reflux_targets') or [])}"
        )
    if name in ("insight", "semantic"):
        print(
            f"    aging: oldest_pending_ts={loop.get('oldest_pending_ts')} "
            f"oldest_pending_age_hours={loop.get('oldest_pending_age_hours', 0.0)}"
        )
    if name == "promotion":
        print(
            f"    aging: stock_started_at={loop.get('stock_started_at')} "
            f"age_hours={loop.get('age_hours', 0.0)} first_candidate={loop.get('first_candidate')}"
        )
    if name == "throughput":
        print(
            f"    daily: completed_cmds={loop.get('completed_cmds', 0)} "
            f"e2e_median_sec={loop.get('e2e_median_sec')} "
            f"overhead_rate_median_pct={loop.get('overhead_rate_median_pct')} "
            f"deploy_median_sec={loop.get('deploy_median_sec')} "
            f"work_median_sec={loop.get('work_median_sec')} "
            f"finalize_median_sec={loop.get('finalize_median_sec')}"
        )
warn_note = f" note={warn_backlog['note']}" if warn_backlog.get("note") else ""
print(
    f"  warn_backlog: produced={warn_backlog['produced']} consumed={warn_backlog['consumed']} "
    f"stock={warn_backlog['stock']}{warn_note}"
)
for item in (warn_backlog.get("items") or []):
    print(
        f"    aging: key={item.get('key')} first_seen={item.get('first_seen')} "
        f"age_hours={item.get('age_hours', 0.0)}"
    )
if alerts:
    for a in alerts:
        print(f"ALERT: {a}")
    raise SystemExit(1)
print("OK: loop ledger updated, no stall/stock-increase detected")
PY
