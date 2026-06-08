#!/usr/bin/env python3
"""Search memory DB for events related to cmd title/purpose.

Called by pre-write-edit-combined.sh during cmd preflight.
Usage: memory_db_fts5_preflight.py <db_path> <query>
Output: tab-separated rows (id, ts, agent, cmd_id, importance, summary)
"""
import hashlib
import os
import re
import sqlite3
import sys
from pathlib import Path

CJK_RE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]")


def has_cjk(text: str) -> bool:
    return bool(CJK_RE.search(text))


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
        return cache_path
    return source_path


def main() -> int:
    if len(sys.argv) < 3:
        return 1
    db_path = resolve_db_path(Path(sys.argv[1]))
    query = sys.argv[2].strip()
    if not db_path.exists() or not query:
        return 0

    db_uri = f"{db_path.resolve().as_uri()}?mode=ro"
    conn = sqlite3.connect(db_uri, uri=True)
    conn.execute("PRAGMA busy_timeout=3000")
    conn.row_factory = sqlite3.Row

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
                   ({score_expr}) AS match_count
            FROM events AS e
            WHERE {where}
            ORDER BY match_count DESC, e.importance DESC, e.ts DESC
            LIMIT 3
        """
        score_params: list[object] = []
        for t in terms:
            pat = f"%{t}%"
            score_params.extend([pat, pat])
        rows = conn.execute(sql, params + score_params).fetchall()
    else:
        def escape_fts5(val: str) -> str:
            return '"' + val.replace('"', '""') + '"'

        fts_terms = [w for w in query.split() if len(w) >= 2][:16]
        if not fts_terms:
            return 0
        fts_query = " OR ".join(escape_fts5(t) for t in fts_terms)
        rows = conn.execute(
            """
            SELECT e.id, e.ts, e.agent, e.cmd_id, e.importance, e.summary,
                   bm25(events_fts) AS rank
            FROM events_fts
            JOIN events AS e ON e.rowid = events_fts.rowid
            WHERE events_fts MATCH ?
            ORDER BY rank, e.ts DESC
            LIMIT 3
            """,
            (fts_query,),
        ).fetchall()

    for row in rows:
        summary = (row["summary"] or "").replace("\t", " ").replace("\n", " ").strip()
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
    raise SystemExit(main())
