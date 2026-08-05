#!/usr/bin/env python3
"""Search memory DB for events related to cmd title/purpose.

Called by pre-write-edit-combined.sh during cmd preflight.
Usage: memory_db_fts5_preflight.py <db_path> <query> <agent_id>
       memory_db_fts5_preflight.py --backup <db_path> <backup_path>
       memory_db_fts5_preflight.py --migrate-skill-metadata <db_path>
       memory_db_fts5_preflight.py --inspect-skill-metadata <db_path>
Output: tab-separated rows (id, ts, agent, cmd_id, importance, summary)
"""
import hashlib
import os
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

CJK_RE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]")
AGENT_ID_RE = re.compile(r"[a-z][a-z0-9_-]*\Z")
SKILL_NAME_RE = re.compile(r"[a-z][a-z0-9-]*\Z")
CDP_SKILL = "claude-in-chrome"
CDP_TERMS = ("cdp", "getcomputedstyle", "remote-debugging")

_DEFENSE_OVERHEAD_START_NS = time.monotonic_ns()
_DEFENSE_OVERHEAD_WRITER = Path(__file__).resolve().parents[1] / "lib" / "defense_overhead_writer.sh"


def _write_defense_overhead(rc: int) -> None:
    wall_ms = max(0, (time.monotonic_ns() - _DEFENSE_OVERHEAD_START_NS) // 1_000_000)
    verdict = "PASS" if rc == 0 else "FAIL"
    event_id = f"memory_db_fts5_preflight-{os.getpid()}-{time.time_ns()}"
    command = 'source "$1"; defense_overhead_write_async "$2" "$3" "$4" "$5" "$6" "{}" || true'
    try:
        subprocess.Popen(
            [
                "bash", "-c", command, "defense-overhead",
                str(_DEFENSE_OVERHEAD_WRITER), "memory_db_fts5_preflight",
                "memory_db_fts5_preflight_total", str(wall_ms), verdict, event_id,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def has_cjk(text: str) -> bool:
    return bool(CJK_RE.search(text))


def resolve_agent_id(explicit: str = "") -> str:
    candidate = explicit.strip()
    if AGENT_ID_RE.fullmatch(candidate):
        return candidate
    pane = os.environ.get("TMUX_PANE", "").strip()
    if not pane:
        return ""
    try:
        result = subprocess.run(
            ["tmux", "display-message", "-t", pane, "-p", "#{@agent_id}"],
            check=True,
            capture_output=True,
            text=True,
            timeout=1,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    candidate = result.stdout.strip()
    return candidate if AGENT_ID_RE.fullmatch(candidate) else ""


def cjk_char_group(ch: str) -> str:
    cp = ord(ch)
    if 0x3040 <= cp <= 0x309F:
        return "h"
    if 0x30A0 <= cp <= 0x30FF:
        return "k"
    if (0x3400 <= cp <= 0x9FFF) or (0xF900 <= cp <= 0xFAFF):
        return "c"
    if ch.isascii() and (ch.isalnum() or ch == "_"):
        return "a"
    return ""


def split_cjk_terms(query: str, max_terms: int = 8) -> list[str]:
    terms: list[str] = []
    current: list[str] = []
    current_group = ""
    for ch in query:
        g = cjk_char_group(ch)
        if not g:
            if current:
                t = "".join(current)
                if len(t) >= 2:
                    terms.append(t)
                current, current_group = [], ""
            continue
        if current and g != current_group:
            t = "".join(current)
            if len(t) >= 2:
                terms.append(t)
            current, current_group = [], ""
        current_group = g
        current.append(ch)
    if current:
        t = "".join(current)
        if len(t) >= 2:
            terms.append(t)
    seen: set[str] = set()
    unique: list[str] = []
    for t in terms:
        key = t.casefold()
        if key not in seen:
            seen.add(key)
            unique.append(t)
    return unique[:max_terms]


def resolve_db_path(source_path: Path) -> Path:
    """Use ext4 cache if available (WSL2: /mnt/c is 9p, ext4 cache is faster)."""
    cache_dir = Path("/tmp/shogun_memory_db_cache")
    if not cache_dir.is_dir():
        return source_path
    safe_name = str(source_path).replace("/", "_")
    cache_path = cache_dir / safe_name
    if cache_path.is_file() and cache_path.stat().st_size > 0:
        # A schema migration can land before the asynchronous cache refresh.
        # Never let a stale cache erase newly structured metadata at recall.
        try:
            with sqlite3.connect(
                f"{source_path.resolve().as_uri()}?mode=ro", uri=True
            ) as source:
                source_columns = {
                    str(row[1]) for row in source.execute("PRAGMA table_info(events)")
                }
            with sqlite3.connect(
                f"{cache_path.resolve().as_uri()}?mode=ro", uri=True
            ) as cache:
                cache_columns = {
                    str(row[1]) for row in cache.execute("PRAGMA table_info(events)")
                }
            if "skill" in source_columns and "skill" not in cache_columns:
                return source_path
        except sqlite3.Error:
            return source_path
        return cache_path
    return source_path


def migrate_skill_metadata(db_path: Path) -> tuple[int, int]:
    """Add the nullable skill column and classify CDP knowledge idempotently."""
    conn = sqlite3.connect(db_path)
    try:
        columns = {str(row[1]) for row in conn.execute("PRAGMA table_info(events)")}
        if "skill" not in columns:
            conn.execute("ALTER TABLE events ADD COLUMN skill TEXT")
        predicate = " OR ".join(
            "(lower(coalesce(summary, '')) LIKE ? OR lower(coalesce(detail, '')) LIKE ?)"
            for _ in CDP_TERMS
        )
        params: list[str] = []
        for term in CDP_TERMS:
            params.extend((f"%{term}%", f"%{term}%"))
        conn.execute(
            f"""
            UPDATE events
               SET skill = ?
             WHERE event_type = 'knowledge'
               AND ({predicate})
               AND skill IS NOT ?
            """,
            [CDP_SKILL, *params, CDP_SKILL],
        )
        conn.commit()
        target_count = int(
            conn.execute(
                f"""
                SELECT count(*) FROM events
                 WHERE event_type = 'knowledge' AND ({predicate})
                """,
                params,
            ).fetchone()[0]
        )
        false_positive = int(
            conn.execute(
                f"""
                SELECT count(*) FROM events
                 WHERE skill = ? AND NOT (
                       event_type = 'knowledge' AND ({predicate})
                 )
                """,
                [CDP_SKILL, *params],
            ).fetchone()[0]
        )
        return target_count, false_positive
    finally:
        conn.close()


def backup_database(db_path: Path, backup_path: Path) -> int:
    """Create a transactionally consistent SQLite online backup."""
    source = sqlite3.connect(f"{db_path.resolve().as_uri()}?mode=ro", uri=True)
    destination = sqlite3.connect(backup_path)
    try:
        source.backup(destination)
        result = str(destination.execute("PRAGMA quick_check").fetchone()[0])
        destination.commit()
        return 0 if result == "ok" else 1
    finally:
        destination.close()
        source.close()


def inspect_skill_metadata(db_path: Path) -> tuple[int, int, int, int, int, int]:
    conn = sqlite3.connect(f"{db_path.resolve().as_uri()}?mode=ro", uri=True)
    try:
        columns = {str(row[1]) for row in conn.execute("PRAGMA table_info(events)")}
        if "skill" not in columns:
            return 0, 0, 0, 0, 0, 0
        predicate = " OR ".join(
            "(lower(coalesce(summary, '')) LIKE ? OR lower(coalesce(detail, '')) LIKE ?)"
            for _ in CDP_TERMS
        )
        params: list[str] = []
        for term in CDP_TERMS:
            params.extend((f"%{term}%", f"%{term}%"))
        targets = int(
            conn.execute(
                f"SELECT count(*) FROM events WHERE event_type='knowledge' AND ({predicate})",
                params,
            ).fetchone()[0]
        )
        skill_set = int(
            conn.execute("SELECT count(*) FROM events WHERE skill=?", (CDP_SKILL,)).fetchone()[0]
        )
        false_positive = int(
            conn.execute(
                f"""
                SELECT count(*) FROM events WHERE skill=? AND NOT (
                    event_type='knowledge' AND ({predicate})
                )
                """,
                [CDP_SKILL, *params],
            ).fetchone()[0]
        )
        false_negative = int(
            conn.execute(
                f"""
                SELECT count(*) FROM events
                 WHERE event_type='knowledge' AND ({predicate})
                   AND coalesce(skill, '') != ?
                """,
                [*params, CDP_SKILL],
            ).fetchone()[0]
        )
        null_events = int(
            conn.execute("SELECT count(*) FROM events WHERE skill IS NULL").fetchone()[0]
        )
        return 1, targets, skill_set, false_positive, false_negative, null_events
    finally:
        conn.close()


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "--backup":
        db_path, backup_path = Path(sys.argv[2]), Path(sys.argv[3])
        if not db_path.is_file() or backup_path.resolve() == db_path.resolve():
            return 2
        rc = backup_database(db_path, backup_path)
        print(f"backup={backup_path}\tquick_check={'ok' if rc == 0 else 'failed'}")
        return rc
    if len(sys.argv) == 3 and sys.argv[1] == "--inspect-skill-metadata":
        db_path = Path(sys.argv[2])
        if not db_path.is_file():
            return 2
        values = inspect_skill_metadata(db_path)
        labels = ("skill_column", "targets", "skill_set", "false_positive", "false_negative", "null_events")
        print("\t".join(f"{label}={value}" for label, value in zip(labels, values)))
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--migrate-skill-metadata":
        db_path = Path(sys.argv[2])
        if not db_path.is_file():
            return 2
        target_count, false_positive = migrate_skill_metadata(db_path)
        print(f"targets={target_count}\tfalse_positive={false_positive}")
        return 0 if false_positive == 0 else 1
    if len(sys.argv) < 3:
        return 0
    db_path = resolve_db_path(Path(sys.argv[1]))
    query = sys.argv[2].strip()
    agent_id = resolve_agent_id(sys.argv[3] if len(sys.argv) >= 4 else "")
    if not db_path.exists() or not query or not AGENT_ID_RE.fullmatch(agent_id):
        return 0

    db_uri = f"{db_path.resolve().as_uri()}?mode=ro"
    conn = sqlite3.connect(db_uri, uri=True)
    conn.execute("PRAGMA busy_timeout=3000")
    conn.row_factory = sqlite3.Row
    event_columns = {str(row[1]) for row in conn.execute("PRAGMA table_info(events)")}
    if "target" not in event_columns:
        return 0
    skill_expr = "e.skill" if "skill" in event_columns else "''"

    if has_cjk(query):
        terms = split_cjk_terms(query)
        if not terms:
            return 0
        like_parts = []
        params: list[object] = []
        for t in terms:
            pat = f"%{t}%"
            like_parts.append("(e.summary LIKE ? OR e.detail LIKE ?)")
            params.extend([pat, pat])
        where = " OR ".join(like_parts)
        score_expr = " + ".join(
            "(CASE WHEN e.summary LIKE ? OR e.detail LIKE ? THEN 1 ELSE 0 END)"
            for _ in terms
        )
        sql = f"""
            SELECT e.id, e.ts, e.agent, e.cmd_id, e.importance, e.summary,
                   {skill_expr} AS skill,
                   ({score_expr}) AS match_count
            FROM events AS e
            WHERE ({where}) AND (e.target = '' OR e.target = ?)
            ORDER BY match_count DESC, e.importance DESC, e.ts DESC
            LIMIT 3
        """
        score_params: list[object] = []
        for t in terms:
            pat = f"%{t}%"
            score_params.extend([pat, pat])
        rows = conn.execute(sql, score_params + params + [agent_id]).fetchall()
    else:
        def escape_fts5(val: str) -> str:
            return '"' + val.replace('"', '""') + '"'

        fts_terms = [w for w in query.split() if len(w) >= 2][:16]
        if not fts_terms:
            return 0
        fts_query = " OR ".join(escape_fts5(t) for t in fts_terms)
        rows = conn.execute(
            f"""
            SELECT e.id, e.ts, e.agent, e.cmd_id, e.importance, e.summary,
                   {skill_expr} AS skill,
                   bm25(events_fts) AS rank
            FROM events_fts
            JOIN events AS e ON e.rowid = events_fts.rowid
            WHERE events_fts MATCH ?
              AND (e.target = '' OR e.target = ?)
            ORDER BY rank, e.ts DESC
            LIMIT 3
            """,
            (fts_query, agent_id),
        ).fetchall()

    for row in rows:
        summary = (row["summary"] or "").replace("\t", " ").replace("\n", " ").strip()
        skill = str(row["skill"] or "").strip()
        if SKILL_NAME_RE.fullmatch(skill):
            summary = f"{summary} ★このknowledgeの実行にはSkill({skill})を起動せよ"
        print(
            "\t".join(
                [
                    str(row["id"] or ""),
                    str(row["ts"] or ""),
                    str(row["agent"] or ""),
                    str(row["cmd_id"] or ""),
                    str(row["importance"] or ""),
                    summary,
                ]
            )
        )
    return 0


if __name__ == "__main__":
    _rc = 0
    try:
        _rc = main()
    except BaseException:
        _rc = 1
        raise
    finally:
        _write_defense_overhead(_rc)
    raise SystemExit(_rc)
