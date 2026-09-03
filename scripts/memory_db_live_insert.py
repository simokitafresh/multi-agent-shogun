#!/usr/bin/env python3
# semantic-links: [[SQLite記憶DB]], [[eventsテーブル]], [[掲示板通信基盤]], [[セマンティック辞書構想]]
"""Append live inbox/bulletin/insight events to the local memory DB."""

import os
import sys
import json
import glob
import re
import tempfile
import shutil
import sqlite3
import subprocess
import time
import fcntl


# Resolve the module itself before deriving repository identity.  Fast deploy
# roots expose this file through a symlink; abspath() preserves that lexical
# root and used to create one cache key per deploy.  realpath() makes every
# such import share the canonical repository root.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
DEFAULT_DB_PATH = os.path.join(REPO_ROOT, "data", "multi_agent_shogun_memory.db")
DEFAULT_CACHE_DIR = os.path.join(tempfile.gettempdir(), "shogun_memory_db_cache")
DEFAULT_SEMANTIC_MAP_PATH = os.path.join(REPO_ROOT, "context", "semantic-map.md")
DEFAULT_SEMANTIC_INDEX_PATH = os.path.join(REPO_ROOT, "docs", "semantic-index", "index.md")
SUMMARY_LIMIT = 240
SQLITE_BUSY_TIMEOUT_MS = 5000
DEFAULT_CONFIDENCE = "medium"
DEFAULT_FRESHNESS = "current"
DEFAULT_SOURCE_TYPE = "fact"
VALID_EVENT_STATES = {
    "raw",
    "verified",
    "stale_candidate",
    "contradiction_candidate",
    "duplicate_candidate",
    "obsidian_candidate",
    "obsidian_promoted",
    "archived",
}
CONTRADICTION_TYPES = {
    "false_info",
    "outdated",
    "context_mismatch",
    "definition_mismatch",
    "domain_mismatch",
    "time_mismatch",
    "observation_condition_mismatch",
    "opinion_mismatch",
    "competing_hypotheses",
    "past_vs_current_judgment",
}
_SEMANTIC_CONCEPT_CACHE = None
_CMD_CONTEXT_CACHE: dict[str, str] = {}
OBSIDIAN_LINK_RE = re.compile(r"\[\[([^\[\]]+)\]\]")
OBSIDIAN_LINK_NOISE_TARGETS = {
    "リンク",
    "概念名",
    "ファイル名",
    "発端",
    "原因",
    "結果",
    "対象事象",
    "レビュー結果",
}
REPORT_METADATA_DOT_KEYS = {
    "ac_version_read",
    "files_modified",
    "hook_failures",
    "parent_cmd",
    "status",
    "status_detail",
    "task_id",
    "timestamp",
    "verdict",
    "worker_id",
}
REPORT_METADATA_PREFIXES = (
    "binary_checks.",
    "hook_failures.",
    "lessons_useful.",
    "self_gate_check.",
    "skill_candidate.",
    "task_clarity.",
    "test_triage.",
)
REPORT_MEANINGFUL_DOT_KEYS = {
    "assumption_check",
    "simplicity_check",
}
REPORT_MEANINGFUL_PREFIXES = (
    "assumption_invalidation.",
    "decision_candidate.",
    "knowledge_candidate.",
    "lesson_candidate.",
    "purpose_validation.",
    "result.",
)


def now_timestamp() -> str:
    from datetime import datetime

    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S%z")


def create_sqlite_backup(
    db_path: str,
    backup_dir: str | None = None,
    suffix: str = "state_transition",
    output_path: str | None = None,
) -> str:
    from datetime import datetime

    source_path = os.path.abspath(db_path)
    if output_path:
        backup_path = os.path.abspath(output_path)
        os.makedirs(os.path.dirname(backup_path), exist_ok=True)
    else:
        backup_root = os.path.abspath(backup_dir) if backup_dir else os.path.dirname(source_path)
        os.makedirs(backup_root, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%dT%H%M%S")
        backup_path = os.path.join(
            backup_root,
            f"{os.path.basename(source_path)}.bak_{suffix}_{stamp}",
        )
    if output_path:
        # The ext4-cache caller (create_memory_db_ext4_cache) is the only
        # user of this branch and treats backup_path as a disposable,
        # not-yet-published temp file that gets a full integrity check
        # before publication either way, so a faster copy mechanism here
        # cannot leak a bad snapshot even if this reasoning has a gap.
        # Named/milestone backups (the backup_dir/suffix branch below) keep
        # the original sqlite .backup() API untouched.
        _hot_copy_snapshot(source_path, backup_path)
    else:
        with sqlite3.connect(source_path) as src, sqlite3.connect(backup_path) as dst:
            src.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            dst.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            src.backup(dst)
    if (
        output_path is None
        and is_routine_backup_suffix(suffix)
        # Rotation is enabled in normal operation now that cmd_3869's legacy
        # backlog has been classified and removed.  Keep an explicit kill
        # switch for incident response without allowing an unset variable to
        # silently restore unbounded backup growth.
        and os.environ.get("SHOGUN_MEMORY_DB_BACKUP_ROTATION_ENABLED", "1") != "0"
    ):
        try:
            rotation_result = rotate_routine_backups(backup_root, os.path.basename(source_path))
            log_backup_rotation_fire(rotation_result)
        except Exception as exc:
            print(f"create_sqlite_backup: rotation skipped (non-fatal): {exc}", file=sys.stderr)
    return backup_path


# Suffixes produced by the current routine (auto-named) callers of create_sqlite_backup().
# A file only enters the rotation's DELETE_CANDIDATE pool when its suffix matches one of
# these; anything else (manually-created milestones like ".bak_cmd3153_...") is left
# untouched even though its name can superficially resemble the routine naming shape
# (cmd_3869 902件棚卸し: 名前付き節目は対象外).
ROUTINE_BACKUP_FIXED_SUFFIXES = {"obsidian_candidate", "obsidian_promote_finalize", "recall_control"}
ROUTINE_BACKUP_DYNAMIC_PREFIXES = ("candidate_resolve_",)
# Routine backups are recovery generations, not an audit archive.  Keep only
# the two newest generations; historical files are handled by the explicit
# archive plan and are never deleted implicitly by a refresh.
ROUTINE_BACKUP_KEEP_RECENT = 2
ROUTINE_BACKUP_KEEP_DAILY_DAYS = 0
ROUTINE_BACKUP_NAME_RE = re.compile(
    r"^(?P<base>.+)\.bak_(?P<suffix>.+)_(?P<stamp>\d{8}T\d{6})(?P<sidecar>-journal|-wal|-shm)?$"
)


def is_routine_backup_suffix(suffix: str) -> bool:
    if suffix in ROUTINE_BACKUP_FIXED_SUFFIXES:
        return True
    return any(suffix.startswith(prefix) for prefix in ROUTINE_BACKUP_DYNAMIC_PREFIXES)


def _scan_routine_backup_generations(backup_dir: str, db_basename: str) -> dict:
    """Group routine backup files in backup_dir by (suffix, stamp) generation key.

    Only files matching create_sqlite_backup()'s exact auto-naming scheme AND a known
    routine suffix are included; anything else (named milestones, health-check backups,
    unrelated files) is ignored so rotation never touches them.
    """
    generations: dict[tuple[str, str], dict] = {}
    try:
        entries = os.listdir(backup_dir)
    except OSError:
        return generations
    for name in entries:
        match = ROUTINE_BACKUP_NAME_RE.match(name)
        if not match or match.group("base") != db_basename:
            continue
        suffix = match.group("suffix")
        if not is_routine_backup_suffix(suffix):
            continue
        full_path = os.path.join(backup_dir, name)
        try:
            file_stat = os.stat(full_path)
        except OSError:
            continue
        key = (suffix, match.group("stamp"))
        generation = generations.setdefault(key, {"files": [], "mtime": 0.0, "bytes": 0})
        generation["files"].append(full_path)
        generation["bytes"] += file_stat.st_size
        if match.group("sidecar") is None:
            generation["mtime"] = file_stat.st_mtime
        elif generation["mtime"] == 0.0:
            generation["mtime"] = file_stat.st_mtime
    return generations


def rotate_routine_backups(
    backup_dir: str,
    db_basename: str,
    keep_recent: int = ROUTINE_BACKUP_KEEP_RECENT,
    keep_daily_days: int = ROUTINE_BACKUP_KEEP_DAILY_DAYS,
    now=None,
) -> dict:
    """Enforce retention on routine backup generations under backup_dir.

    Retention (global across all routine suffixes combined, matching cmd_3869's
    manual classification): the keep_recent most-recent generations by mtime, plus
    the single latest-mtime generation for each of the past keep_daily_days calendar
    days. Everything else matching the routine naming scheme is deleted. Named
    milestones and any file outside the routine naming scheme are never scanned/touched.
    Serialized via flock so concurrent callers never double-decide inconsistently.
    """
    from datetime import datetime, timedelta

    os.makedirs(backup_dir, exist_ok=True)
    result = {"deleted_count": 0, "deleted_bytes": 0, "kept_count": 0, "suffixes": {}, "deleted_files": []}
    lock_path = os.path.join(backup_dir, ".routine_backup_rotation.lock")
    with open(lock_path, "a", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        try:
            generations = _scan_routine_backup_generations(backup_dir, db_basename)
            if not generations:
                return result
            now_dt = now or datetime.now()
            ranked = sorted(generations.items(), key=lambda kv: kv[1]["mtime"], reverse=True)
            keep_keys = {key for key, _ in ranked[:keep_recent]}

            valid_dates = {(now_dt.date() - timedelta(days=offset)) for offset in range(keep_daily_days)}
            best_per_date: dict = {}
            for key, generation in ranked:
                gen_date = datetime.fromtimestamp(generation["mtime"]).date()
                if gen_date not in valid_dates:
                    continue
                current_key = best_per_date.get(gen_date)
                if current_key is None or generation["mtime"] > generations[current_key]["mtime"]:
                    best_per_date[gen_date] = key
            keep_keys.update(best_per_date.values())

            for key, generation in ranked:
                suffix = key[0]
                bucket = result["suffixes"].setdefault(suffix, {"kept": 0, "deleted": 0})
                if key in keep_keys:
                    result["kept_count"] += 1
                    bucket["kept"] += 1
                    continue
                bucket["deleted"] += 1
                for file_path in generation["files"]:
                    try:
                        size = os.path.getsize(file_path)
                        os.remove(file_path)
                    except FileNotFoundError:
                        continue
                    result["deleted_count"] += 1
                    result["deleted_bytes"] += size
                    result["deleted_files"].append(file_path)
        finally:
            fcntl.flock(lock_handle, fcntl.LOCK_UN)
    return result


def log_backup_rotation_fire(result: dict) -> None:
    """Append a rotation-fire event to logs/gate_fire_log.yaml (existing shared
    gate-firing log, one of detector_fp_rate.sh's measurement inputs) so backup
    rotation activity is observable through the same infrastructure."""
    from datetime import datetime

    log_path = os.environ.get("GATE_FIRE_LOG_FILE") or os.path.join(REPO_ROOT, "logs", "gate_fire_log.yaml")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    deleted = result.get("deleted_count", 0)
    kept = result.get("kept_count", 0)
    freed = result.get("deleted_bytes", 0)
    suffixes = ",".join(sorted(result.get("suffixes", {}).keys())) or "none"
    outcome = "ROTATED" if deleted else "NOOP"
    checks = f"deleted={deleted} kept={kept}".replace("\\", "\\\\").replace('"', '\\"')
    reasons = f"bytes_freed={freed} suffixes={suffixes}".replace("\\", "\\\\").replace('"', '\\"')
    line = (
        f'- ts: "{ts}", file: "memory_db_backup_rotation", gate: "memory_db_backup_rotation", '
        f'result: {outcome}, checks: "{checks}", reasons: "{reasons}"\n'
    )
    lock_path = f"{log_path}.lock"
    with open(lock_path, "a", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        try:
            with open(log_path, "a", encoding="utf-8") as log_handle:
                log_handle.write(line)
        finally:
            fcntl.flock(lock_handle, fcntl.LOCK_UN)


def ensure_event_state_transition_log(conn) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS event_state_transitions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT NOT NULL,
            from_state TEXT,
            to_state TEXT NOT NULL,
            reason TEXT NOT NULL,
            actor TEXT NOT NULL,
            transitioned_at TEXT NOT NULL
        )
        """
    )


def update_event_state(
    conn,
    event_ids: list[str] | tuple[str, ...],
    new_state: str,
    reason: str,
    actor: str = "memory_db_live_insert",
) -> int:
    state_value = normalize_text(new_state)
    reason_value = normalize_text(reason)
    actor_value = normalize_text(actor) or "memory_db_live_insert"
    if state_value not in VALID_EVENT_STATES:
        raise ValueError(f"invalid event state: {state_value}")
    if not reason_value:
        raise ValueError("state transition reason is required")
    if not event_ids:
        return 0

    ensure_event_attribute_columns(conn)
    ensure_event_state_transition_log(conn)
    transitioned_at = now_timestamp()
    updated = 0
    for event_id in event_ids:
        row = conn.execute(
            "SELECT state FROM events WHERE id = ?",
            (event_id,),
        ).fetchone()
        if row is None:
            continue
        from_state = row[0] or "raw"
        conn.execute(
            "UPDATE events SET state = ?, updated_at = ? WHERE id = ?",
            (state_value, transitioned_at, event_id),
        )
        conn.execute(
            """
            INSERT INTO event_state_transitions (
                event_id, from_state, to_state, reason, actor, transitioned_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (event_id, from_state, state_value, reason_value, actor_value, transitioned_at),
        )
        updated += 1
    return updated


def memory_db_cache_path(db_path: str) -> str:
    override = os.environ.get("SHOGUN_MEMORY_DB_CACHE_PATH", "").strip()
    if override:
        return override
    cache_dir = os.environ.get("SHOGUN_MEMORY_DB_CACHE_DIR", DEFAULT_CACHE_DIR)
    repo_key = re.sub(r"[^A-Za-z0-9_.-]", "_", REPO_ROOT)
    return os.path.join(cache_dir, f"{repo_key}_{os.path.basename(db_path)}")


def remove_memory_db_cache_sidecars(cache_path: str) -> None:
    for suffix in ("-wal", "-shm", "-journal"):
        cache_sidecar = f"{cache_path}{suffix}"
        if os.path.exists(cache_sidecar):
            os.unlink(cache_sidecar)


def _record_phase_point(check_id: str, wall_ms: int, verdict: str, event_id: str) -> None:
    """Append one sub-phase timing observation to the shared defense ledger.

    Reuses the existing five-field ledger contract (no new ledger) so
    refresh_window's internal cost breakdown (copy vs. verify) becomes
    directly greppable via check_id, per cmd_4174's measurement requirement.
    fail-open: never let instrumentation affect the cache data path.
    """
    try:
        writer = os.path.join(REPO_ROOT, "scripts", "lib", "defense_overhead_writer.sh")
        if not os.path.exists(writer):
            return
        subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; defense_overhead_write "$2" "$3" "$4" "$5" "$6"',
                "_",
                writer,
                "three_layer_health",
                check_id,
                str(int(wall_ms)),
                verdict,
                event_id,
            ],
            check=False,
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return


def _record_refresh_points(points: list[tuple[str, int, str, str]]) -> None:
    """Persist one refresh's telemetry batch without four hot-path forks.

    The normal refresh emits four records.  The shared shell writer is kept
    for all other callers, while this local batch uses the same JSONL schema,
    lock file, duplicate suppression, and fail-open behavior in one critical
    section.  It changes telemetry plumbing only; cache publication remains
    independent of every failure here.
    """
    if not points or os.environ.get("DEFENSE_OVERHEAD_ENABLED", "1") != "1":
        return
    try:
        from datetime import datetime, timezone

        ledger = os.environ.get(
            "DEFENSE_OVERHEAD_LEDGER",
            os.path.join(REPO_ROOT, "logs", "defense_overhead.jsonl"),
        )
        if not os.path.isdir(os.path.dirname(ledger)):
            return
        lock_path = f"{ledger}.lock"
        deadline = time.monotonic() + float(os.environ.get("DEFENSE_OVERHEAD_LOCK_TIMEOUT", "2"))
        lines = []
        event_ids = []
        for check_id, wall_ms, verdict, event_id in points:
            if not re.fullmatch(r"[A-Za-z0-9_.:-]+", check_id):
                return
            if int(wall_ms) < 0 or verdict not in {"PASS", "FAIL", "BLOCK", "WARN"}:
                return
            if not re.fullmatch(r"[A-Za-z0-9_.:-]+", event_id):
                return
            event_ids.append(event_id)
            lines.append(
                json.dumps(
                    {
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                        "source": "three_layer_health",
                        "check_id": check_id,
                        "wall_ms": int(wall_ms),
                        "verdict": verdict,
                        "event_id": event_id,
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
            )
        with open(lock_path, "a", encoding="utf-8") as lock_handle:
            while True:
                try:
                    fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        return
                    time.sleep(0.01)
            try:
                existing = b""
                try:
                    # Match the shared writer's exact event_id needle, but
                    # read the ledger once instead of parsing every JSON row
                    # on the refresh critical path.
                    with open(ledger, "rb") as ledger_handle:
                        existing = ledger_handle.read()
                except FileNotFoundError:
                    pass
                with open(ledger, "a", encoding="utf-8") as ledger_handle:
                    for event_id, line in zip(event_ids, lines):
                        needle = f'"event_id":"{event_id}"'.encode()
                        if needle not in existing:
                            ledger_handle.write(line + "\n")
            finally:
                fcntl.flock(lock_handle, fcntl.LOCK_UN)
    except Exception:
        return


def _hot_copy_snapshot(db_path: str, output_path: str) -> None:
    """Publish output_path as a byte-copy snapshot of db_path, WAL-safe.

    create_sqlite_backup()'s sqlite3 .backup() API copies page-by-page; over
    a 9p-backed /mnt/c source (measured: ~60s for an 883MB db, vs. ~9s for a
    plain sequential file copy of the same bytes) that page granularity is
    the dominant cost, not anything about the database's logical content.
    shutil.copyfile() reads in large sequential chunks and is what actually
    saves the time; the risk it introduces (a writer's autocheckpoint
    rewriting db_path's pages mid-copy, tearing the snapshot) is closed by
    holding an open read transaction on db_path for the copy's duration:
    WAL-mode checkpoints never overwrite frames still needed by a reader
    whose snapshot predates them, so the base file's pages this reader
    depends on cannot change while it is open. New writes still land in the
    WAL file; copying db_path/-wal after the read transaction is taken picks
    up a self-consistent (possibly slightly fresher) snapshot either way.
    The copied WAL is then checkpointed into output_path before the snapshot
    leaves this function. This is required because the published cache is a
    standalone database and its sidecars are removed after os.replace().
    Callers still run the existing
    require_cache_backup_healthy() integrity gate against the result before
    publishing it, so a torn copy (if this reasoning is ever wrong for some
    edge case) is caught there instead of silently corrupting the cache.
    """
    reader = sqlite3.connect(db_path)
    try:
        reader.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        reader.execute("BEGIN")
        reader.execute("SELECT 1 FROM sqlite_master LIMIT 1")
        shutil.copyfile(db_path, output_path)
        src_wal = f"{db_path}-wal"
        output_wal = f"{output_path}-wal"
        if os.path.exists(src_wal):
            shutil.copyfile(src_wal, output_wal)
    finally:
        reader.execute("COMMIT")
        reader.close()
    _checkpoint_snapshot(output_path)


def _checkpoint_snapshot(output_path: str) -> None:
    """Merge a private snapshot WAL before its DB file is atomically published."""
    output_wal = f"{output_path}-wal"
    if os.path.exists(output_wal) and os.path.getsize(output_wal) > 0:
        with sqlite3.connect(output_path) as snapshot:
            snapshot.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            checkpoint = snapshot.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
            if checkpoint and (checkpoint[0] != 0 or checkpoint[1] != 0):
                raise sqlite3.DatabaseError(
                    f"WAL checkpoint incomplete: busy={checkpoint[0]} frames={checkpoint[1]}"
                )
        if os.path.exists(output_wal) and os.path.getsize(output_wal) > 0:
            raise sqlite3.DatabaseError("WAL checkpoint left unmerged frames")
    fd = os.open(output_path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _sqlite_table_columns(conn, table_name: str) -> list[str]:
    return [row[1] for row in conn.execute(f"PRAGMA table_info({table_name})")]


def _enable_prefix_scan_mmap(conn: sqlite3.Connection, schema: str) -> None:
    """Use a bounded read mapping for the cross-database prefix comparison."""
    try:
        page_size = int(conn.execute(f"PRAGMA {schema}.page_size").fetchone()[0])
        page_count = int(conn.execute(f"PRAGMA {schema}.page_count").fetchone()[0])
        mapping_bytes = min(1 << 30, max(page_size, page_size * page_count))
        conn.execute(f"PRAGMA {schema}.mmap_size={mapping_bytes}")
    except (TypeError, ValueError, sqlite3.DatabaseError):
        # mmap is an optimization only; the exact SQL comparison remains the
        # correctness boundary when the platform declines the mapping.
        return


def _events_prefix_matches(
    source_conn: sqlite3.Connection,
    published_path: str,
    event_columns: list[str],
    max_rowid: int,
) -> bool:
    """Check every value in the cached events prefix without Python row marshaling.

    The source and published cache have independent SQLite layouts, so a
    page-level comparison is not valid.  Attach the stable published cache to
    the source read transaction instead and let SQLite compare corresponding
    rows and columns.  This catches payload-only mutations whose timestamps,
    counts, and rowids are unchanged while keeping the large-value scan inside
    SQLite rather than copying every prefix row through Python.
    """
    changed_columns = " OR ".join(
        f'source."{column}" IS NOT cached."{column}"' for column in event_columns
    )
    source_conn.execute("ATTACH DATABASE ? AS cached_prefix", (published_path,))
    _enable_prefix_scan_mmap(source_conn, "main")
    _enable_prefix_scan_mmap(source_conn, "cached_prefix")
    mismatch = source_conn.execute(
        f"""
        SELECT 1
          FROM main.events AS source
          JOIN cached_prefix.events AS cached ON cached.rowid = source.rowid
         WHERE source.rowid <= ?
           AND ({changed_columns})
         LIMIT 1
        """,
        (max_rowid,),
    ).fetchone()
    return mismatch is None


def _signature_from_connection(conn: sqlite3.Connection) -> str | None:
    """Return the cheap append watermark for an already-open source connection."""
    row = conn.execute(
        "SELECT MAX(rowid), COUNT(*), MAX(COALESCE(updated_at, recorded_at, ts)) FROM events"
    ).fetchone()
    if not row or row[0] is None:
        return None
    return f"rowid:{row[0]}|count:{row[1]}|maxts:{row[2]}"


def _table_exists(conn: sqlite3.Connection, table_name: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE name = ? AND type IN ('table', 'virtual table') LIMIT 1",
        (table_name,),
    ).fetchone() is not None


def _try_incremental_cache_update(
    db_path: str, cache_path: str
) -> tuple[bool, str | None, str | None, tuple[str, ...]]:
    """Append a proven rowid suffix directly to the published ext4 cache.

    SQLite transactions already give readers an old-or-new snapshot, so an
    in-place append avoids copying the 1.39GB cache merely to publish a tiny
    suffix.  The source is read from one snapshot and every new event/FTS/
    projection row is checked after commit.  Any schema, deletion, prefix,
    child-table, or verification uncertainty returns ``(False, None, reason, ids)`` and
    leaves the caller's existing atomic full-refresh fallback in charge.
    """
    source_path = os.path.abspath(db_path)
    published_path = os.path.abspath(cache_path)
    event_ids: list[str] = []
    if source_path == published_path or not os.path.exists(published_path):
        return False, None, "cache_unavailable_or_same_path", ()
    try:
        source_uri = f"file:{source_path}?mode=ro"
        with sqlite3.connect(source_uri, uri=True) as source_conn, sqlite3.connect(
            published_path
        ) as cache_conn:
            source_conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            cache_conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            source_conn.execute("BEGIN")
            cache_conn.execute("BEGIN IMMEDIATE")

            source_columns = _sqlite_table_columns(source_conn, "events")
            cache_columns = _sqlite_table_columns(cache_conn, "events")
            required_columns = {"id", "summary", "detail", "updated_at", "recorded_at", "ts"}
            if not required_columns.issubset(source_columns) or source_columns != cache_columns:
                raise sqlite3.DatabaseError("events schema is not append-compatible")

            source_count, source_max_rowid = source_conn.execute(
                "SELECT COUNT(*), COALESCE(MAX(rowid), 0) FROM events"
            ).fetchone()
            cache_count, cache_max_rowid = cache_conn.execute(
                "SELECT COUNT(*), COALESCE(MAX(rowid), 0) FROM events"
            ).fetchone()
            if "id" in source_columns:
                event_ids = [
                    str(row[0])
                    for row in source_conn.execute(
                        "SELECT id FROM events WHERE rowid > ? ORDER BY rowid",
                        (cache_max_rowid,),
                    ).fetchall()
                    if row[0] is not None
                ]
            if source_count <= cache_count or source_max_rowid <= cache_max_rowid:
                raise sqlite3.DatabaseError("source is not a strict append")

            source_delta_count = source_conn.execute(
                "SELECT COUNT(*) FROM events WHERE rowid > ?", (cache_max_rowid,)
            ).fetchone()[0]
            if source_delta_count != source_count - cache_count:
                raise sqlite3.DatabaseError("source prefix contains a deletion or gap")

            # Small fixtures and recovery-sized caches retain the exact prefix
            # comparison as an additional mutation guard.  Production caches
            # are much larger than this bound; their append-only writer
            # contract uses the rowid/count watermark and skips the O(N)
            # prefix scan that dominated the old refresh cost.
            try:
                prefix_verify_max_bytes = int(
                    os.environ.get("SHOGUN_MEMORY_DB_INCREMENTAL_PREFIX_VERIFY_MAX_BYTES", str(64 * 1024 * 1024))
                )
            except ValueError:
                prefix_verify_max_bytes = 64 * 1024 * 1024
            if prefix_verify_max_bytes > 0 and os.path.getsize(published_path) <= prefix_verify_max_bytes:
                if not _events_prefix_matches(
                    source_conn, published_path, source_columns, cache_max_rowid
                ):
                    raise sqlite3.DatabaseError("source prefix content changed")

            quoted_events = ", ".join(f'"{column}"' for column in source_columns)
            delta_rows = source_conn.execute(
                f"SELECT rowid, {quoted_events} FROM events WHERE rowid > ? ORDER BY rowid",
                (cache_max_rowid,),
            ).fetchall()
            if len(delta_rows) != source_delta_count:
                raise sqlite3.DatabaseError("source suffix changed during snapshot")

            child_rows_by_table: dict[str, list[tuple]] = {}
            expected_child_counts: dict[str, int] = {}
            event_ids = [
                str(row[source_columns.index("id") + 1])
                for row in delta_rows
                if row[source_columns.index("id") + 1] is not None
            ]
            for table_name, key_column in (
                ("event_concepts", "event_id"),
                ("event_links", "source_event_id"),
            ):
                source_has_table = _table_exists(source_conn, table_name)
                cache_has_table = _table_exists(cache_conn, table_name)
                if source_has_table != cache_has_table:
                    raise sqlite3.DatabaseError(f"{table_name} presence changed")
                if not source_has_table:
                    continue
                source_table_columns = _sqlite_table_columns(source_conn, table_name)
                cache_table_columns = _sqlite_table_columns(cache_conn, table_name)
                if source_table_columns != cache_table_columns:
                    raise sqlite3.DatabaseError(f"{table_name} schema is not append-compatible")
                source_total = source_conn.execute(
                    f"SELECT COUNT(*) FROM {table_name}"
                ).fetchone()[0]
                cache_total = cache_conn.execute(
                    f"SELECT COUNT(*) FROM {table_name}"
                ).fetchone()[0]
                rows: list[tuple] = []
                for offset in range(0, len(event_ids), 500):
                    chunk = event_ids[offset : offset + 500]
                    placeholders = ", ".join("?" for _ in chunk)
                    quoted_child = ", ".join(f'child."{column}"' for column in source_table_columns)
                    rows.extend(
                        source_conn.execute(
                            f"SELECT {quoted_child} FROM {table_name} AS child "
                            f"WHERE {key_column} IN ({placeholders})",
                            chunk,
                        ).fetchall()
                    )
                if source_total - cache_total != len(rows):
                    raise sqlite3.DatabaseError(f"{table_name} prefix changed")
                child_rows_by_table[table_name] = rows
                expected_child_counts[table_name] = cache_total + len(rows)

            event_placeholders = ", ".join("?" for _ in range(len(source_columns) + 1))
            cache_conn.executemany(
                f"INSERT INTO events(rowid, {quoted_events}) VALUES ({event_placeholders})",
                delta_rows,
            )

            if _table_exists(source_conn, "events_fts") and _table_exists(cache_conn, "events_fts"):
                summary_index = source_columns.index("summary") + 1
                detail_index = source_columns.index("detail") + 1
                cache_conn.executemany(
                    "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
                    ((row[0], row[summary_index], row[detail_index]) for row in delta_rows),
                )

            for table_name, rows in child_rows_by_table.items():
                child_columns = _sqlite_table_columns(cache_conn, table_name)
                quoted_child = ", ".join(f'"{column}"' for column in child_columns)
                placeholders = ", ".join("?" for _ in child_columns)
                cache_conn.executemany(
                    f"INSERT OR IGNORE INTO {table_name}({quoted_child}) VALUES ({placeholders})",
                    rows,
                )
            # Differential verification: only the suffix and its projections
            # are read back.  Full quick_check/FTS integrity belongs to the
            # cold or uncertain full-refresh path, not every append.
            for row in delta_rows:
                rowid = row[0]
                actual = cache_conn.execute(
                    f"SELECT rowid, {quoted_events} FROM events WHERE rowid = ?", (rowid,)
                ).fetchone()
                if actual != tuple(row):
                    raise sqlite3.DatabaseError(f"incremental event verification failed: {rowid}")
            if _table_exists(cache_conn, "events_fts"):
                for row in delta_rows:
                    if cache_conn.execute(
                        "SELECT 1 FROM events_fts WHERE rowid = ?", (row[0],)
                    ).fetchone() is None:
                        raise sqlite3.DatabaseError(f"incremental FTS verification failed: {row[0]}")
            for table_name, rows in child_rows_by_table.items():
                actual_count = cache_conn.execute(
                    f"SELECT COUNT(*) FROM {table_name}"
                ).fetchone()[0]
                if actual_count != expected_child_counts[table_name]:
                    raise sqlite3.DatabaseError(f"incremental {table_name} verification failed")
            cache_conn.commit()
            return True, _signature_from_connection(source_conn), None, tuple(event_ids)
    except Exception as exc:
        reason = f"{type(exc).__name__}:{str(exc).strip()}"[:240]
        return False, None, reason or "unknown_incremental_failure", tuple(event_ids)


def _telemetry_token(value: object) -> str:
    """Encode arbitrary event/reason text for the ledger's token contract."""
    token = re.sub(r"[^A-Za-z0-9_.:-]+", "_", str(value))
    return token[:160] or "unknown"


def _telemetry_reason(value: object) -> str:
    """Encode a fallback reason without colliding with ledger separators."""
    token = re.sub(r"[^A-Za-z0-9_.-]+", "_", str(value))
    return token[:160] or "unknown"


def _try_incremental_cache_snapshot(
    db_path: str, cache_path: str, output_path: str, source_signature: str | None = None
) -> bool:
    """Build an atomic cache snapshot by applying a proven append-only suffix.

    The canonical DB is on 9P while the published cache is normally on ext4.
    Re-copying the whole canonical file for each append is the measured hot
    path.  This optimization copies the already-published cache locally, then
    applies only rows whose source rowid is beyond the cache watermark.  It is
    deliberately conservative: any schema drift, prefix mutation/deletion,
    auxiliary-table drift, or read failure returns False so the caller uses
    the existing full snapshot path.  The caller still runs the unchanged
    integrity checks and publishes with the same os.replace() boundary.
    """
    source_path = os.path.abspath(db_path)
    published_path = os.path.abspath(cache_path)
    if source_path == published_path or not os.path.exists(published_path):
        return False
    try:
        incremental_min_bytes = int(
            os.environ.get("SHOGUN_MEMORY_DB_INCREMENTAL_MIN_BYTES", str(64 * 1024 * 1024))
        )
    except ValueError:
        incremental_min_bytes = 64 * 1024 * 1024
    if incremental_min_bytes > 0 and os.path.getsize(published_path) < incremental_min_bytes:
        return False

    try:
        _hot_copy_snapshot(published_path, output_path)
        source_uri = f"file:{source_path}?mode=ro"
        with sqlite3.connect(source_uri, uri=True) as source_conn, sqlite3.connect(
            output_path
        ) as cache_conn:
            source_conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            cache_conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            source_conn.execute("BEGIN")
            # The output is a private temp snapshot.  Keep its append
            # transaction out of WAL so the published cache remains a
            # standalone DB and needs no whole-file checkpoint afterward.
            cache_conn.execute("PRAGMA journal_mode=DELETE")
            cache_conn.execute("PRAGMA synchronous=FULL")
            cache_conn.execute("BEGIN IMMEDIATE")

            source_columns = _sqlite_table_columns(source_conn, "events")
            cache_columns = _sqlite_table_columns(cache_conn, "events")
            required_columns = {"id", "summary", "detail", "updated_at", "recorded_at", "ts"}
            if not required_columns.issubset(source_columns) or source_columns != cache_columns:
                raise sqlite3.DatabaseError("events schema is not append-compatible")

            # Use the read transaction's snapshot for eligibility.  The
            # caller's signature is intentionally measured before this
            # function starts; on a live writer that value can already be
            # stale by the time the incremental read begins, which used to
            # force a safe but needlessly expensive full refresh.  These two
            # values are now read together with the suffix below, so the
            # append check is both current and internally consistent.
            source_count, source_max_rowid = source_conn.execute(
                "SELECT COUNT(*), COALESCE(MAX(rowid), 0) FROM events"
            ).fetchone()
            cache_count, cache_max_rowid = cache_conn.execute(
                "SELECT COUNT(*), COALESCE(MAX(rowid), 0) FROM events"
            ).fetchone()
            if source_count <= cache_count or source_max_rowid <= cache_max_rowid:
                raise sqlite3.DatabaseError("source is not a strict append")
            if not _events_prefix_matches(
                source_conn, published_path, source_columns, cache_max_rowid
            ):
                raise sqlite3.DatabaseError("source prefix content changed")
            source_delta_count = source_conn.execute(
                "SELECT COUNT(*) FROM events WHERE rowid > ?", (cache_max_rowid,)
            ).fetchone()[0]
            if source_delta_count != source_count - cache_count:
                raise sqlite3.DatabaseError("source prefix contains a deletion or gap")
            quoted_events = ", ".join(f'"{column}"' for column in source_columns)
            delta_rows = source_conn.execute(
                f"SELECT rowid, {quoted_events} FROM events WHERE rowid > ? ORDER BY rowid",
                (cache_max_rowid,),
            ).fetchall()
            if len(delta_rows) != source_delta_count:
                raise sqlite3.DatabaseError("source suffix changed during snapshot")

            transition_tables = (
                _sqlite_table_columns(source_conn, "event_state_transitions"),
                _sqlite_table_columns(cache_conn, "event_state_transitions"),
            )
            if transition_tables[0] != transition_tables[1]:
                raise sqlite3.DatabaseError("state transition schema is not append-compatible")
            if transition_tables[0]:
                source_transition_count = source_conn.execute(
                    "SELECT COUNT(*) FROM event_state_transitions"
                ).fetchone()[0]
                cache_transition_count = cache_conn.execute(
                    "SELECT COUNT(*) FROM event_state_transitions"
                ).fetchone()[0]
                if source_transition_count != cache_transition_count:
                    raise sqlite3.DatabaseError("managed state transition changed")

            for table_name, key_column in (
                ("event_concepts", "event_id"),
                ("event_links", "source_event_id"),
            ):
                source_table_columns = _sqlite_table_columns(source_conn, table_name)
                cache_table_columns = _sqlite_table_columns(cache_conn, table_name)
                if source_table_columns != cache_table_columns:
                    raise sqlite3.DatabaseError(f"{table_name} schema is not append-compatible")
            event_placeholders = ", ".join("?" for _ in range(len(source_columns) + 1))
            cache_conn.executemany(
                f"INSERT INTO events(rowid, {quoted_events}) VALUES ({event_placeholders})",
                delta_rows,
            )

            if "events_fts" in {
                row[0] for row in cache_conn.execute(
                    "SELECT name FROM sqlite_master WHERE name = 'events_fts'"
                )
            }:
                source_summary_index = source_columns.index("summary") + 1
                source_detail_index = source_columns.index("detail") + 1
                cache_conn.executemany(
                    "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
                    (
                        (row[0], row[source_summary_index], row[source_detail_index])
                        for row in delta_rows
                    ),
                )

            for table_name, key_column in (
                ("event_concepts", "event_id"),
                ("event_links", "source_event_id"),
            ):
                child_columns = _sqlite_table_columns(source_conn, table_name)
                quoted_child = ", ".join(
                    f'"{column}"' for column in child_columns
                )
                quoted_child_select = ", ".join(f'child."{column}"' for column in child_columns)
                child_placeholders = ", ".join("?" for _ in child_columns)
                child_rows = []
                event_ids = [row[source_columns.index("id") + 1] for row in delta_rows]
                source_total = source_conn.execute(
                    f"SELECT COUNT(*) FROM {table_name}"
                ).fetchone()[0]
                cache_total = cache_conn.execute(
                    f"SELECT COUNT(*) FROM {table_name}"
                ).fetchone()[0]
                for offset in range(0, len(event_ids), 500):
                    chunk = event_ids[offset : offset + 500]
                    placeholders = ", ".join("?" for _ in chunk)
                    child_rows.extend(
                        source_conn.execute(
                            f"SELECT {quoted_child_select} FROM {table_name} AS child "
                            f"WHERE {key_column} IN ({placeholders})",
                            chunk,
                        ).fetchall()
                    )
                if source_total - cache_total != len(child_rows):
                    raise sqlite3.DatabaseError(f"{table_name} prefix changed")
                cache_conn.executemany(
                    f"INSERT INTO {table_name}({quoted_child}) VALUES ({child_placeholders})",
                    child_rows,
                )

            cache_conn.commit()
            source_conn.commit()
            _checkpoint_snapshot(output_path)
            return True
    except Exception:
        return False


def require_cache_backup_healthy(db_path: str) -> None:
    """Verify a freshly-built cache copy before it is published.

    PRAGMA quick_check validates ordinary b-tree structure but does not
    exercise FTS5's own index-vs-content consistency, so a page-level "ok"
    can still hide a search-time failure. Run FTS5's dedicated
    'integrity-check' command too when the table exists. Only call this
    against a private, not-yet-published temp copy — never the live
    primary DB — since the FTS check needs a writable connection.
    """
    db_uri = f"file:{os.path.abspath(db_path)}?mode=ro"
    with sqlite3.connect(db_uri, uri=True) as conn:
        result = conn.execute("PRAGMA quick_check").fetchone()
        if result is None or result[0] != "ok":
            detail = result[0] if result else "no result"
            raise sqlite3.DatabaseError(f"database disk image is malformed ({detail})")
        has_fts = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'events_fts'"
        ).fetchone() is not None
    if has_fts:
        with sqlite3.connect(db_path) as conn:
            conn.execute("INSERT INTO events_fts(events_fts) VALUES ('integrity-check')")


def _memory_db_source_max_rowid(db_path: str) -> str:
    """Read the source DB write watermark, or "na" when it cannot be measured.

    Never raises: this is observation only and must not affect cache creation.
    """
    try:
        with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
            conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            row = conn.execute("SELECT MAX(rowid) FROM events").fetchone()
    except Exception:
        return "na"
    if not row or row[0] is None:
        return "na"
    return str(int(row[0]))


def _memory_db_source_signature(db_path: str):
    """Cheap change-detection signature of the events content, or None.

    (MAX(rowid), COUNT(*), MAX(updated_at/recorded_at/ts)) of events in one
    read-only query. Catches inserts, deletes and state updates (which set
    updated_at). Concepts-only updates (memory_db_import / semantic_index_
    update) do NOT touch updated_at, so callers must pair this signature with
    a TTL bound — see create_memory_db_ext4_cache. File mtimes are unusable
    here: unrelated search_logs writes touch the -wal on every prompt and
    would make the signature never match. Returns None on any failure so
    callers fall back to a full refresh (never a stale skip).
    """
    try:
        with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
            conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            row = conn.execute(
                "SELECT MAX(rowid), COUNT(*),"
                " MAX(COALESCE(updated_at, recorded_at, ts)) FROM events"
            ).fetchone()
        if not row or row[0] is None:
            return None
        return f"rowid:{row[0]}|count:{row[1]}|maxts:{row[2]}"
    except Exception:
        return None


def _source_signature_rowid(source_signature: str | None) -> str | None:
    """Extract the already-measured source watermark from a signature."""
    match = re.search(r"(?:^|\|)rowid:(\d+)(?:\||$)", source_signature or "")
    return match.group(1) if match else None


def _record_refresh_window_point(
    phase: str, rowid: str, group: str, wall_ms: int = 0, extra: str = ""
) -> None:
    """Append one refresh-window observation to the shared defense ledger.

    Event-driven counterpart of gate_three_layer_health.sh's cache_rowid_gap
    row: that one only exists when a startup gate happens to run (measured
    interval median 97s, max 44 days), so "no record" and "no event" are
    indistinguishable.  Recording at the refresh itself makes the window
    length a measured value instead of a derived one, and makes the number of
    writes that arrived during the window (end rowid - begin rowid) fall out
    directly, so no threshold is needed to interpret it.

    The existing five-field ledger contract is reused unchanged (no new
    ledger): the window length in milliseconds goes into wall_ms and the
    remaining values are packed into event_id, so the current grep + json
    parse aggregation keeps working.  check_id is refresh_window, distinct
    from cache_rowid_gap, so both coexist.

    fail-open: any failure here is swallowed.  Cache creation is a data path
    and must never be broken, delayed into failure, or aborted by its own
    instrumentation.
    """
    try:
        writer = os.path.join(REPO_ROOT, "scripts", "lib", "defense_overhead_writer.sh")
        if not os.path.exists(writer):
            return
        event_id = (
            f"refresh_window:{phase}:rowid-{rowid}:grp-{group}{extra}"
        )
        subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; defense_overhead_write "$2" "$3" "$4" "$5" "$6"',
                "_",
                writer,
                "three_layer_health",
                "refresh_window",
                str(int(wall_ms)),
                "PASS" if rowid != "na" else "WARN",
                event_id,
            ],
            check=False,
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return


def create_memory_db_ext4_cache(db_path: str) -> str:
    if os.environ.get("SHOGUN_DISABLE_MEMORY_DB_CACHE", "0") == "1":
        return db_path
    if not os.path.exists(db_path):
        return db_path

    import fcntl

    cache_path = memory_db_cache_path(db_path)
    cache_dir = os.path.dirname(cache_path)
    os.makedirs(cache_dir, exist_ok=True)
    lock_path = f"{cache_path}.lock"
    with open(lock_path, "w", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        # cmd-lord-20260803 D0速度: skip-if-unchanged。前回publish時のsource署名
        # (db/-wal/-shmのmtime_ns+size+max_rowid)が現在と一致し、cacheが実在する
        # なら、コピー(mean13.5s)+検証(11.5s)を丸ごと省く。committedな書込みは
        # 必ず-walのmtime/sizeを動かすため、偽の「変更なし」判定は起きない。
        # 署名不一致・sidecar欠損・読取失敗はすべてfull refreshへfall through
        # (fail-open側は常にrefresh=品質不変)。
        _sig_path = f"{cache_path}.srcsig"
        _cur_sig = _memory_db_source_signature(db_path)
        # TTL bound: concepts-only updates don't move the events signature,
        # so a signature match may only skip while the cache is younger than
        # SHOGUN_MEMORY_CACHE_SKIP_TTL_SEC (default 600). Staleness is thereby
        # bounded to one TTL for concepts-only changes and zero for event
        # inserts/deletes/state updates.
        try:
            _skip_ttl = int(os.environ.get("SHOGUN_MEMORY_CACHE_SKIP_TTL_SEC", "600"))
        except ValueError:
            _skip_ttl = 600
        if _cur_sig is not None and _skip_ttl > 0 and os.path.exists(cache_path):
            try:
                if (time.time() - os.stat(cache_path).st_mtime) < _skip_ttl:
                    with open(_sig_path, "r", encoding="utf-8") as _sf:
                        if _sf.read().strip() == _cur_sig:
                            _record_phase_point(
                                "refresh_skip_unchanged", 0, "PASS",
                                "refresh_skip:sig-match"
                            )
                            return cache_path
            except OSError:
                pass
        # Orphan sweep: remove any stale tmp files left by pre-fix runs or
        # edge cases.  The exclusive flock guarantees no other backup is live.
        # Two patterns cover both old-style ({basename}.tmp.{PID}) and new-style
        # (.{basename}.{random}.tmp) naming in case of future regressions.
        _cache_base = os.path.basename(cache_path)
        _stale_patterns = [
            os.path.join(cache_dir, f".{_cache_base}.*.tmp*"),
            os.path.join(cache_dir, f"{_cache_base}.tmp.*"),
        ]
        for stale in [f for p in _stale_patterns for f in glob.glob(p)]:
            try:
                os.unlink(stale)
            except OSError:
                pass
        # Build a verified replacement beside cache_path, then publish it with
        # os.replace(). Readers open cache_path via brand-new connections at
        # any time, without taking this lock; writing the backup directly
        # into cache_path (the pre-fix behavior) let a reader observe a torn,
        # mid-copy file — the direct cause of intermittent "database disk
        # image is malformed" errors and stale row counts. os.replace() is a
        # single atomic directory-entry swap: a reader with an fd already
        # open keeps seeing the fully-old file; a reader that opens after the
        # swap sees the fully-new one. Never a partial file either way, and a
        # SIGKILL mid-backup only leaves an orphaned temp file (swept above),
        # never a corrupted cache_path.
        # Refresh window, point 1 of 2: the source watermark as it stands the
        # instant before the snapshot starts.  Everything committed to the
        # source after this point is, by construction, absent from the cache
        # this refresh publishes.
        _window_group = f"{os.getpid()}-{time.monotonic_ns()}"
        _window_begin_rowid = "na"
        _window_begin_ns = time.monotonic_ns()
        _refresh_points = []
        try:
            # _cur_sig queried MAX(rowid) immediately before the window. Use
            # that value instead of opening a second SQLite connection and
            # repeating the same source read; retain the fallback when
            # signature collection failed.
            _window_begin_rowid = _source_signature_rowid(_cur_sig) or _memory_db_source_max_rowid(db_path)
            _refresh_points.append(
                (
                    "refresh_window",
                    0,
                    "PASS" if _window_begin_rowid != "na" else "WARN",
                    f"refresh_window:begin:rowid-{_window_begin_rowid}:grp-{_window_group}",
                )
            )
        except Exception:
            pass
        # The common append-only case can commit directly to the published
        # SQLite cache.  This avoids copying the cache itself and uses only a
        # differential read-back for verification.  A false result preserves
        # the existing temp-file/full-integrity path below.
        _incremental_t0 = time.monotonic_ns()
        (
            _incremental_ok,
            _incremental_sig,
            _incremental_reason,
            _incremental_event_ids,
        ) = _try_incremental_cache_update(
            db_path, cache_path
        )
        if _incremental_ok:
            _incremental_ms = (time.monotonic_ns() - _incremental_t0) // 1_000_000
            _refresh_points.append(
                (
                    "refresh_copy",
                    _incremental_ms,
                    "PASS",
                    f"refresh_copy:grp-{_window_group}:mode-incremental-in-place",
                )
            )
            _refresh_points.append(
                ("refresh_verify", 0, "PASS", f"refresh_verify:grp-{_window_group}:mode-delta")
            )
            _refresh_points.extend(
                (
                    "refresh_incremental_event",
                    0,
                    "PASS",
                    f"refresh_incremental:event-{_telemetry_token(_event_id)}:grp-{_window_group}",
                )
                for _event_id in _incremental_event_ids
            )
            try:
                _window_end_rowid = _memory_db_source_max_rowid(db_path)
                _window_ms = (time.monotonic_ns() - _window_begin_ns) // 1_000_000
                _arrived = (
                    str(int(_window_end_rowid) - int(_window_begin_rowid))
                    if _window_begin_rowid != "na" and _window_end_rowid != "na"
                    else "na"
                )
                _refresh_points.append(
                    (
                        "refresh_window",
                        _window_ms,
                        "PASS" if _window_end_rowid != "na" else "WARN",
                        f"refresh_window:end:rowid-{_window_end_rowid}:grp-{_window_group}"
                        f":arrived-{_arrived}:beginrowid-{_window_begin_rowid}",
                    )
                )
            except Exception:
                pass
            remove_memory_db_cache_sidecars(cache_path)
            try:
                # The signature belongs to the source snapshot used by the
                # direct update.  If it is unavailable, leave the old sig so
                # the next caller takes the safe refresh path.
                if _incremental_sig is not None:
                    with open(f"{_sig_path}.tmp.{os.getpid()}", "w", encoding="utf-8") as _sf:
                        _sf.write(_incremental_sig + "\n")
                    os.replace(f"{_sig_path}.tmp.{os.getpid()}", _sig_path)
            except OSError:
                pass
            _record_refresh_points(_refresh_points)
            return cache_path
        if _incremental_reason and (
            _incremental_event_ids
            or _incremental_reason != "cache_unavailable_or_same_path"
        ):
            _fallback_event_ids = _incremental_event_ids or ("na",)
            _refresh_points.extend(
                (
                    "refresh_fallback",
                    0,
                    "WARN",
                    f"refresh_fallback:event-{_telemetry_token(_event_id)}"
                    f":reason-{_telemetry_reason(_incremental_reason)}:grp-{_window_group}",
                )
                for _event_id in _fallback_event_ids
            )
        fd, temp_name = tempfile.mkstemp(
            prefix=f".{_cache_base}.", suffix=".tmp", dir=cache_dir
        )
        os.close(fd)
        temp_path = temp_name
        try:
            _copy_t0 = time.monotonic_ns()
            incremental = _try_incremental_cache_snapshot(
                db_path, cache_path, temp_path, source_signature=_cur_sig
            )
            if not incremental:
                create_sqlite_backup(db_path, output_path=temp_path, suffix="ext4_cache")
            _copy_ms = (time.monotonic_ns() - _copy_t0) // 1_000_000
            _refresh_points.append(
                (
                    "refresh_copy",
                    _copy_ms,
                    "PASS",
                    f"refresh_copy:grp-{_window_group}:mode-{'incremental' if incremental else 'full'}",
                )
            )
            _verify_t0 = time.monotonic_ns()
            require_cache_backup_healthy(temp_path)
            _verify_ms = (time.monotonic_ns() - _verify_t0) // 1_000_000
            _refresh_points.append(
                ("refresh_verify", _verify_ms, "PASS", f"refresh_verify:grp-{_window_group}")
            )
            os.replace(temp_path, cache_path)
            _cache_dir_fd = os.open(cache_dir, os.O_RDONLY)
            try:
                os.fsync(_cache_dir_fd)
            finally:
                os.close(_cache_dir_fd)
            # Refresh window, point 2 of 2: the watermark at publication.  The
            # difference against point 1 is the number of writes that arrived
            # while the window was open; whether they are merely delayed or
            # actually lost is answered by the next refresh's begin record,
            # not by a threshold.
            try:
                _window_end_rowid = _memory_db_source_max_rowid(db_path)
                _window_ms = (time.monotonic_ns() - _window_begin_ns) // 1_000_000
                if _window_begin_rowid != "na" and _window_end_rowid != "na":
                    _arrived = str(int(_window_end_rowid) - int(_window_begin_rowid))
                else:
                    _arrived = "na"
                _refresh_points.append(
                    (
                        "refresh_window",
                        _window_ms,
                        "PASS" if _window_end_rowid != "na" else "WARN",
                        f"refresh_window:end:rowid-{_window_end_rowid}:grp-{_window_group}"
                        f":arrived-{_arrived}:beginrowid-{_window_begin_rowid}",
                    )
                )
            except Exception:
                pass
            remove_memory_db_cache_sidecars(cache_path)
            # skip-if-unchangedの署名はコピー開始前(_cur_sig)を記録する。
            # コピー中に到着した書込みは署名を必ずずらすため、次回は
            # full refreshになる(stale skipは構造的に起きない)。
            try:
                if _cur_sig is not None:
                    with open(f"{_sig_path}.tmp.{os.getpid()}", "w", encoding="utf-8") as _sf:
                        _sf.write(_cur_sig + "\n")
                    os.replace(f"{_sig_path}.tmp.{os.getpid()}", _sig_path)
            except OSError:
                pass
        finally:
            _record_refresh_points(_refresh_points)
            # os.replace() only renames temp_path itself; a WAL-mode backup
            # (inherited from db_path's own journal_mode) leaves -wal/-shm
            # sidecars named after the temp path, which os.replace() does not
            # follow. Sweep those immediately rather than leaving them for
            # the next invocation's orphan sweep to find.
            remove_memory_db_cache_sidecars(temp_path)
            try:
                os.unlink(temp_path)
            except OSError:
                pass
    return cache_path


def _cache_sync_debounce_seconds() -> float:
    try:
        return max(0.0, float(os.environ.get("SHOGUN_MEMORY_DB_CACHE_DEBOUNCE_SEC", "0.25")))
    except ValueError:
        return 0.25


def _cache_sync_is_debounced(cache_path: str, debounce: float) -> bool:
    marker_path = f"{cache_path}.debounce"
    lock_path = f"{marker_path}.lock"
    try:
        with open(lock_path, "a+", encoding="utf-8") as lock_handle:
            fcntl.flock(lock_handle, fcntl.LOCK_EX)
            try:
                with open(marker_path, encoding="utf-8") as marker:
                    raw = marker.read().strip()
            except FileNotFoundError:
                raw = ""
            if raw and time.time() - float(raw) < debounce:
                return True
    except (OSError, ValueError):
        return False
    return False


def _cache_sync_mark(cache_path: str) -> None:
    marker_path = f"{cache_path}.debounce"
    lock_path = f"{marker_path}.lock"
    try:
        with open(lock_path, "a+", encoding="utf-8") as lock_handle:
            fcntl.flock(lock_handle, fcntl.LOCK_EX)
            with open(marker_path, "w", encoding="utf-8") as marker:
                marker.write(f"{time.time():.9f}\n")
    except OSError:
        return


def sync_memory_db_ext4_cache(db_path: str) -> None:
    cache_path = memory_db_cache_path(db_path)
    debounce = _cache_sync_debounce_seconds()
    if debounce > 0 and _cache_sync_is_debounced(cache_path, debounce):
        return
    create_memory_db_ext4_cache(db_path)
    if debounce > 0:
        _cache_sync_mark(cache_path)


def upsert_lord_ruling_cache_event(cache_path: str, db_path: str, event_id: str) -> None:
    """Synchronously project one committed event into the prompt cache.

    Knowledge writes used to rebuild the complete cache after every insert.
    Read the committed source row, update only its cache projection under the
    same cache lock used by full rebuilds, and read it back before returning.
    """
    import memory_db_import

    with sqlite3.connect(db_path) as source_conn:
        source_conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        row = source_conn.execute(
            """
            SELECT id, ts, event_type, cmd_id, summary, detail, target,
                   concepts, raw_content
            FROM events
            WHERE id = ?
              AND ((event_type = 'conversation' AND agent = 'lord' AND direction = 'inbound')
                   OR (event_type = 'knowledge' AND (target = '' OR target IS NULL)))
            """,
            (event_id,),
        ).fetchone()
    if row is None:
        raise sqlite3.DatabaseError(f"prompt cache source event missing: {event_id}")

    source_id, ts, event_type, cmd_id, summary, detail, target, concepts, raw_content = row
    projected_summary = memory_db_import._prompt_cache_summary(
        source_id, ts, event_type, summary, detail, concepts, raw_content
    )
    cache_path = os.path.abspath(cache_path)
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    lock_path = f"{cache_path}.lock"
    with open(lock_path, "a", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        with sqlite3.connect(cache_path) as cache_conn:
            cache_conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            cache_conn.execute(
                """
                CREATE TABLE IF NOT EXISTS lord_rulings (
                    event_id TEXT PRIMARY KEY,
                    ts TEXT,
                    event_type TEXT,
                    cmd_id TEXT,
                    summary TEXT,
                    detail TEXT,
                    target TEXT DEFAULT ''
                )
                """
            )
            cache_conn.execute(
                """
                INSERT OR REPLACE INTO lord_rulings (
                    event_id, ts, event_type, cmd_id, summary, detail, target
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (source_id, ts, event_type, cmd_id, projected_summary, detail, target or ""),
            )
            cache_conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_lord_rulings_ts ON lord_rulings(ts)"
            )
            cached = cache_conn.execute(
                "SELECT event_id FROM lord_rulings WHERE event_id = ?", (event_id,)
            ).fetchone()
            if cached is None or cached[0] != event_id:
                raise sqlite3.DatabaseError(f"prompt cache verification failed: {event_id}")


def normalize_text(value: object) -> str:
    if value is None:
        return ""
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def summarize(text: str) -> str:
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    if not first_line:
        return ""
    return first_line[:SUMMARY_LIMIT]


def infer_cmd_id(summary: str, detail: str) -> str:
    text = f"{summary}\n{detail}"
    start = text.find("cmd_")
    while start != -1:
        end = start + 4
        while end < len(text) and (text[end].isalnum() or text[end] == "_"):
            end += 1
        if end > start + 4:
            return text[start:end]
        start = text.find("cmd_", start + 4)
    return ""


def _yaml_scalar_value(raw_value: str) -> str:
    value = normalize_text(raw_value)
    if len(value) >= 2:
        if value[0] == value[-1] == '"':
            return value[1:-1].replace('\\"', '"')
        if value[0] == value[-1] == "'":
            return value[1:-1].replace("''", "'")
    return value


def _line_indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _extract_scalar_in_block(lines: list[str], start_index: int, base_indent: int, key: str) -> str:
    prefix = f"{key}:"
    for line in lines[start_index + 1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = _line_indent(line)
        stripped = line.strip()
        if base_indent >= 0 and indent <= base_indent:
            break
        if stripped.startswith(prefix):
            return _yaml_scalar_value(stripped[len(prefix):])
    return ""


def _extract_cmd_context_from_text(text: str, cmd_id: str) -> str:
    lines = text.splitlines()
    candidates: list[tuple[int, int]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        indent = _line_indent(line)
        if stripped == f"{cmd_id}:":
            candidates.append((index, indent))
            continue
        if stripped.startswith("- id:") and _yaml_scalar_value(stripped[len("- id:"):]) == cmd_id:
            candidates.append((index, indent))
            continue
        if stripped.startswith("id:") and _yaml_scalar_value(stripped[len("id:"):]) == cmd_id:
            candidates.append((index, -1))

    for index, indent in candidates:
        title = _extract_scalar_in_block(lines, index, indent, "title")
        purpose = _extract_scalar_in_block(lines, index, indent, "purpose")
        if title or purpose:
            return "\n".join(
                line for line in [
                    f"cmd_id: {cmd_id}",
                    f"cmd_title: {title}" if title else "",
                    f"cmd_purpose: {purpose}" if purpose else "",
                ]
                if line
            )
    return ""


def _extract_task_context_from_text(text: str, cmd_id: str) -> str:
    lines = text.splitlines()
    candidates: list[tuple[int, int]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        indent = _line_indent(line)
        for key in ("task_id", "parent_cmd"):
            prefix = f"{key}:"
            if stripped.startswith(prefix) and _yaml_scalar_value(stripped[len(prefix):]) == cmd_id:
                candidates.append((index, max(indent - 2, -1)))

    for index, indent in candidates:
        title = _extract_scalar_in_block(lines, index, indent, "title")
        purpose = _extract_scalar_in_block(lines, index, indent, "purpose")
        command = _extract_scalar_in_block(lines, index, indent, "command")
        result_summary = _extract_scalar_in_block(lines, index, indent, "result_summary")
        if title or purpose or command or result_summary:
            return "\n".join(
                line for line in [
                    f"cmd_id: {cmd_id}",
                    f"cmd_title: {title}" if title else "",
                    f"cmd_purpose: {purpose}" if purpose else "",
                    f"cmd_command: {command}" if command else "",
                    f"cmd_result_summary: {result_summary}" if result_summary else "",
                ]
                if line
            )
    return ""


def command_context_text(cmd_id: str) -> str:
    cmd_id = normalize_text(cmd_id)
    if not cmd_id:
        return ""
    if cmd_id in _CMD_CONTEXT_CACHE:
        return _CMD_CONTEXT_CACHE[cmd_id]

    source_paths = [
        os.path.join(REPO_ROOT, "queue", "shogun_to_karo.yaml"),
        os.path.join(REPO_ROOT, "queue", "archive", "shogun_to_karo_done.yaml"),
    ]
    source_paths.extend(glob.glob(os.path.join(REPO_ROOT, "queue", "archive", "cmds", f"{cmd_id}*.yaml")))

    for path in source_paths:
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            context = _extract_cmd_context_from_text(handle.read(), cmd_id)
        if context:
            _CMD_CONTEXT_CACHE[cmd_id] = context
            return context

    for path in glob.glob(os.path.join(REPO_ROOT, "queue", "tasks", "*.yaml")):
        with open(path, encoding="utf-8", errors="replace") as handle:
            context = _extract_task_context_from_text(handle.read(), cmd_id)
        if context:
            _CMD_CONTEXT_CACHE[cmd_id] = context
            return context

    _CMD_CONTEXT_CACHE[cmd_id] = ""
    return ""


def _split_markdown_row(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return []
    return [cell.strip() for cell in stripped.strip("|").split("|")]


def _semantic_index_label_to_id(index_path: str) -> dict[str, str]:
    if not os.path.exists(index_path):
        return {}
    mapping: dict[str, str] = {}
    concept_id = ""
    with open(index_path, encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if line.startswith("## ") and " — " in line:
                heading = line[3:].strip()
                concept_id, label = heading.split(" — ", 1)
                mapping[normalize_text(label)] = normalize_text(concept_id)
                continue
            cells = _split_markdown_row(line)
            if len(cells) >= 2 and cells[0] == "id":
                concept_id = normalize_text(cells[1])
                if concept_id:
                    mapping[concept_id] = concept_id
            elif len(cells) >= 2 and cells[0] == "label":
                label = normalize_text(cells[1])
                if label and concept_id:
                    mapping[label] = concept_id
    return mapping


def load_semantic_map_concept_cache(
    semantic_map_path: str = DEFAULT_SEMANTIC_MAP_PATH,
    semantic_index_path: str = DEFAULT_SEMANTIC_INDEX_PATH,
) -> list[dict[str, object]]:
    """Load concept aliases from index.md (SSOT) for live inserts.

    Bug 4 fix: Previously read semantic-map.md (generated), causing alias divergence
    with batch import (which reads index.md). Now both use the same source.
    semantic-map.md is kept as fallback only if index.md is unavailable.
    """
    import re as _re

    # Primary: index.md (SSOT, same as batch import memory_db_import.py)
    if os.path.exists(semantic_index_path):
        concepts: list[dict[str, object]] = []
        current_id = ""
        current_label = ""
        current_aliases: list[str] = []
        for raw_line in open(semantic_index_path, encoding="utf-8", errors="replace"):
            heading = _re.match(r"^##\s+([A-Za-z0-9_-]+)\s+—\s+(.+?)\s*$", raw_line)
            if heading:
                if current_id:
                    terms = [current_id, current_label, *current_aliases]
                    concepts.append({
                        "id": current_id,
                        "terms": [t for t in terms if len(t) >= 3],
                    })
                current_id = heading.group(1).strip()
                current_label = heading.group(2).strip()
                current_aliases = []
                continue
            alias_match = _re.match(r"^\|\s*aliases\s*\|\s*(.*?)\s*\|$", raw_line)
            if alias_match and current_id:
                current_aliases = [
                    normalize_text(a) for a in alias_match.group(1).split(",")
                    if normalize_text(a) and len(normalize_text(a)) >= 3
                ]
        if current_id:
            terms = [current_id, current_label, *current_aliases]
            concepts.append({
                "id": current_id,
                "terms": [t for t in terms if len(t) >= 3],
            })
        return concepts

    # Fallback: semantic-map.md (generated) — only if index.md unavailable
    label_to_id = _semantic_index_label_to_id(semantic_index_path)
    if not os.path.exists(semantic_map_path):
        return []

    concepts = []
    with open(semantic_map_path, encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            cells = _split_markdown_row(raw_line)
            if len(cells) < 2:
                continue
            label = normalize_text(cells[0])
            if not label or label in {"概念", "------"} or set(label) <= {"-"}:
                continue
            concept_id = label_to_id.get(label, label)
            aliases = [normalize_text(part) for part in cells[1].split(",") if normalize_text(part)]
            terms_list = [concept_id, label, *aliases]
            concepts.append({
                "id": concept_id,
                "terms": [term for term in terms_list if len(term) >= 3],
            })
    return concepts


def semantic_concept_cache() -> list[dict[str, object]]:
    global _SEMANTIC_CONCEPT_CACHE
    if _SEMANTIC_CONCEPT_CACHE is None:
        _SEMANTIC_CONCEPT_CACHE = load_semantic_map_concept_cache()
    return _SEMANTIC_CONCEPT_CACHE


def _concept_term_matches(term: object, haystack: str) -> bool:
    needle = normalize_text(term).casefold()
    if not needle:
        return False
    if len(needle) <= 3:
        return re.fullmatch(rf"\b{re.escape(needle)}\b", haystack) is not None
    return needle in haystack


def concepts_for_text(text: str, concepts: list[dict[str, object]] | None = None) -> str:
    haystack = normalize_text(text).casefold()
    matched: list[str] = []
    for concept in semantic_concept_cache() if concepts is None else concepts:
        terms = concept.get("terms", [])
        if any(_concept_term_matches(term, haystack) for term in terms):
            matched.append(str(concept["id"]))
    return json.dumps(sorted(set(matched)), ensure_ascii=False)


def event_concept_rows(event_id: object, concepts_json: str) -> list[tuple[str, str]]:
    try:
        concepts = json.loads(concepts_json)
    except json.JSONDecodeError:
        return []
    if not isinstance(concepts, list):
        return []
    return [(str(event_id), str(concept)) for concept in concepts if str(concept).strip()]


def event_link_rows(event_id: object, text: str) -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for match in OBSIDIAN_LINK_RE.finditer(normalize_text(text)):
        concept = match.group(1).strip()
        if not concept or concept in OBSIDIAN_LINK_NOISE_TARGETS:
            continue
        key = (str(event_id), concept, "obsidian")
        if key in seen:
            continue
        seen.add(key)
        rows.append(key)
    return rows


def require_live_tables(conn) -> bool:
    for table_name in ("events", "events_fts"):
        if conn.execute(
            "SELECT 1 FROM sqlite_master WHERE name = ? AND type IN ('table', 'virtual table') LIMIT 1",
            (table_name,),
        ).fetchone() is None:
            return False
    return True


def ensure_event_attribute_columns(conn) -> None:
    cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
    if "confidence" not in cols:
        conn.execute(f"ALTER TABLE events ADD COLUMN confidence TEXT DEFAULT '{DEFAULT_CONFIDENCE}'")
    if "freshness" not in cols:
        conn.execute(f"ALTER TABLE events ADD COLUMN freshness TEXT DEFAULT '{DEFAULT_FRESHNESS}'")
    if "source_type" not in cols:
        conn.execute(f"ALTER TABLE events ADD COLUMN source_type TEXT DEFAULT '{DEFAULT_SOURCE_TYPE}'")
    if "state" not in cols:
        conn.execute("ALTER TABLE events ADD COLUMN state TEXT DEFAULT 'raw'")
    if "raw_content" not in cols:
        conn.execute("ALTER TABLE events ADD COLUMN raw_content TEXT")


def append_event(
    db_path: str,
    row: tuple[object, ...],
    concept_text_extra: str | None = "",
    raw_content: object | None = None,
    state: str = "raw",
) -> None:
    if not os.path.exists(db_path):
        return
    import sqlite3

    state_value = normalize_text(state) or "raw"
    if state_value not in VALID_EVENT_STATES:
        raise ValueError(f"invalid event state: {state_value}")

    mutable_row = list(row)
    link_text_extra = "" if concept_text_extra is None else concept_text_extra
    link_text = f"{mutable_row[6]}\n{mutable_row[7]}\n{link_text_extra}"
    if concept_text_extra is not None:
        concept_text = f"{mutable_row[6]}\n{mutable_row[7]}\n{concept_text_extra}"
        mutable_row[10] = concepts_for_text(concept_text)
    row = tuple(mutable_row)
    raw_content_value = normalize_text(raw_content if raw_content is not None else row[7])

    with sqlite3.connect(db_path) as conn:
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        if not require_live_tables(conn):
            return
        ensure_event_attribute_columns(conn)
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS event_concepts (
                event_id TEXT NOT NULL,
                concept_name TEXT NOT NULL,
                PRIMARY KEY (event_id, concept_name),
                FOREIGN KEY (event_id) REFERENCES events(id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS event_links (
                source_event_id TEXT NOT NULL,
                target_concept TEXT NOT NULL,
                link_type TEXT NOT NULL DEFAULT 'obsidian',
                PRIMARY KEY (source_event_id, target_concept, link_type),
                FOREIGN KEY (source_event_id) REFERENCES events(id)
            )
            """
        )
        cursor = conn.execute(
            """
            INSERT OR IGNORE INTO events (
                id, ts, event_type, agent, target, direction, summary, detail,
                session_id, cmd_id, concepts, source_file, parent_event_id, importance,
                confidence, freshness, source_type, state, raw_content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'medium', 'current', 'fact', ?, ?)
            """,
            row + (state_value, raw_content_value),
        )
        if cursor.rowcount == 1:
            rowid = conn.execute("SELECT rowid FROM events WHERE id = ?", (row[0],)).fetchone()[0]
            conn.execute(
                "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
                (rowid, row[6], row[7]),
            )
            conn.executemany(
                "INSERT OR IGNORE INTO event_concepts (event_id, concept_name) VALUES (?, ?)",
                event_concept_rows(row[0], str(row[10])),
            )
            conn.executemany(
                "INSERT OR IGNORE INTO event_links (source_event_id, target_concept, link_type) VALUES (?, ?, ?)",
                event_link_rows(row[0], link_text),
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_source_event_id ON event_links(source_event_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_target_concept ON event_links(target_concept)")


def append_bulletin(args) -> None:
    content = normalize_text(args.content)
    action_type = normalize_text(args.action_type) or "info"
    status = normalize_text(args.status) or "open"
    requires_confirmation = normalize_text(args.requires_confirmation)
    actioned_by = normalize_text(args.actioned_by)
    summary = summarize(content) or "bulletin"
    detail = "\n".join(
        line
        for line in [
            content,
            f"action_type: {action_type}" if action_type else "",
            f"status: {status}" if status else "",
            f"actioned_by: {actioned_by}" if actioned_by else "",
            f"requires_confirmation: {requires_confirmation}",
        ]
        if line
    )
    importance = "high" if action_type == "action_required" and status != "closed" else "normal"
    append_event(
        args.db_path,
        (
            f"bulletin:{normalize_text(args.entry_id)}",
            normalize_text(args.ts),
            "bulletin",
            normalize_text(args.agent),
            actioned_by,
            action_type,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=content,
    )


def append_insight(args) -> None:
    insight = normalize_text(args.insight)
    status = normalize_text(args.status) or "pending"
    priority = normalize_text(args.priority) or "medium"
    source = normalize_text(args.source) or "manual"
    resolved_at = normalize_text(args.resolved_at)
    summary = summarize(insight) or "insight"
    detail = "\n".join(
        line
        for line in [
            insight,
            f"status: {status}" if status else "",
            f"priority: {priority}" if priority else "",
            f"source: {source}" if source else "",
            f"resolved_at: {resolved_at}" if resolved_at else "",
        ]
        if line
    )
    importance = "high" if priority == "high" or status == "pending" else "normal"
    append_event(
        args.db_path,
        (
            f"insight:{normalize_text(args.entry_id)}",
            normalize_text(args.ts),
            "insight",
            source,
            "",
            status,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=insight,
    )


def append_inbox(args) -> None:
    content = normalize_text(args.content)
    message_type = normalize_text(args.message_type) or "wake_up"
    action = normalize_text(args.action)
    from_agent = normalize_text(args.from_agent) or "unknown"
    target_agent = normalize_text(args.target_agent)
    summary = summarize(content) or "inbox"
    detail = "\n".join(
        line
        for line in [
            content,
            f"type: {message_type}" if message_type else "",
            f"action: {action}" if action else "",
            f"from: {from_agent}" if from_agent else "",
            f"target: {target_agent}" if target_agent else "",
        ]
        if line
    )
    importance = "high" if message_type in {"cmd_new", "task_assigned", "report_received", "task_done"} else "normal"
    cmd_id = infer_cmd_id(summary, detail)
    append_event(
        args.db_path,
        (
            f"inbox:{normalize_text(args.message_id)}",
            normalize_text(args.ts),
            "inbox",
            from_agent,
            target_agent,
            message_type,
            summary,
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        concept_text_extra=command_context_text(cmd_id),
        raw_content=content,
    )


def append_cmd_save(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    summary = normalize_text(args.summary) or f"{cmd_id} saved"
    detail = normalize_text(args.detail) or summary
    append_event(
        args.db_path,
        (
            f"cmd_save:{cmd_id}:{normalize_text(args.ts)}",
            normalize_text(args.ts),
            "cmd_save",
            "shogun",
            "",
            "save",
            summary,
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        concept_text_extra=command_context_text(cmd_id),
        raw_content=detail,
    )


def append_cmd_quality(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    gate_result = normalize_text(args.gate_result)
    source = normalize_text(args.source) or "cmd_quality_log"
    ts = normalize_text(args.ts)
    notes = normalize_text(args.notes)
    diagnosis = normalize_text(args.diagnosis)
    project = normalize_text(args.project)
    summary = f"{cmd_id} quality: {gate_result}" if cmd_id else f"quality: {gate_result}"
    detail = "\n".join(
        line
        for line in [
            f"gate_result: {gate_result}" if gate_result else "",
            f"karo_rework: {normalize_text(args.karo_rework)}",
            f"gunshi_verdict: {normalize_text(args.gunshi_verdict)}",
            f"ninja_blockers: {normalize_text(args.ninja_blockers)}",
            f"ac_count: {normalize_text(args.ac_count)}",
            f"supplementary_cmds: {normalize_text(args.supplementary_cmds)}",
            f"project: {project}" if project else "",
            f"source: {source}" if source else "",
            f"diagnosis: {diagnosis}" if diagnosis else "",
            f"notes: {notes}" if notes else "",
        ]
        if line
    )
    importance = "high" if gate_result in ("FAIL", "BLOCK") else "normal"
    append_event(
        args.db_path,
        (
            f"cmd_quality:{cmd_id}:{gate_result}:{source}:{ts}",
            ts,
            "cmd_quality",
            "shogun",
            cmd_id,
            gate_result,
            summary[:SUMMARY_LIMIT],
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=detail,
    )


def append_cmd_delegate(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    message = normalize_text(args.message)
    delegated_at = normalize_text(args.delegated_at)
    summary = normalize_text(args.summary) or summarize(message) or f"{cmd_id} delegated"
    detail = "\n".join(
        line
        for line in [
            message,
            f"delegated_at: {delegated_at}" if delegated_at else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"cmd_delegate:{cmd_id}:{delegated_at or normalize_text(args.ts)}",
            normalize_text(args.ts),
            "cmd_delegate",
            "shogun",
            "karo",
            "delegate",
            summary,
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        concept_text_extra=command_context_text(cmd_id),
        raw_content=message,
    )


def append_lesson(args) -> None:
    lesson_id = normalize_text(args.lesson_id)
    title = normalize_text(args.title)
    detail = normalize_text(args.detail)
    source_cmd = normalize_text(args.source_cmd)
    agent = normalize_text(args.agent) or "karo"
    project = normalize_text(args.project)
    ts = normalize_text(args.ts)
    summary = summarize(title) or lesson_id
    detail_full = "\n".join(
        line
        for line in [
            detail,
            f"project: {project}" if project else "",
            f"source_cmd: {source_cmd}" if source_cmd else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"lesson:{lesson_id}",
            ts,
            "lesson",
            agent,
            project,
            "",
            summary,
            detail_full,
            "",
            source_cmd or infer_cmd_id(summary, detail_full),
            "[]",
            normalize_text(args.source_file),
            None,
            "normal",
        ),
        raw_content=detail,
    )


def append_gate(args) -> None:
    gate_name = normalize_text(args.gate_name)
    result = normalize_text(args.result)
    cmd_id = normalize_text(args.cmd_id)
    detail = normalize_text(args.detail)
    ts = normalize_text(args.ts)
    summary = f"{gate_name}: {result}"
    if detail:
        summary = f"{gate_name}: {result} — {detail[:80]}"
    summary = summary[:SUMMARY_LIMIT]
    importance = "high" if result in ("FAIL", "BLOCK") else "normal"
    event_id = f"gate:{gate_name}:{cmd_id}:{ts}" if cmd_id else f"gate:{gate_name}:{ts}"
    detail_full = "\n".join(
        line
        for line in [
            detail,
            f"cmd_id: {cmd_id}" if cmd_id else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            event_id,
            ts,
            "gate",
            gate_name,
            cmd_id,
            result,
            summary,
            detail_full,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=detail,
    )


def _report_dot_key(dot_key: str) -> str:
    dot_key = normalize_text(dot_key)
    if dot_key.startswith("report_field_set."):
        return dot_key[len("report_field_set."):]
    return dot_key


def _report_field_has_concepts(dot_key: str) -> bool:
    normalized = _report_dot_key(dot_key)
    if normalized in REPORT_METADATA_DOT_KEYS:
        return False
    if any(normalized.startswith(prefix) for prefix in REPORT_METADATA_PREFIXES):
        return False
    if normalized in REPORT_MEANINGFUL_DOT_KEYS:
        return True
    return any(normalized.startswith(prefix) for prefix in REPORT_MEANINGFUL_PREFIXES)


def _report_value_to_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        return "\n".join(_report_value_to_text(v) for v in value.values())
    if isinstance(value, list):
        return "\n".join(_report_value_to_text(v) for v in value)
    return normalize_text(value)


def _resolve_report_path(report_path: str) -> str:
    if not report_path:
        return ""
    if os.path.isabs(report_path):
        return report_path
    repo_relative = os.path.join(REPO_ROOT, report_path)
    if os.path.exists(repo_relative):
        return repo_relative
    return report_path


def _extract_report_field_value(report_path: str, dot_key: str) -> str:
    path = _resolve_report_path(report_path)
    if not path or not os.path.exists(path):
        return ""
    try:
        import yaml
    except ImportError:
        return ""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            data = yaml.safe_load(handle) or {}
    except Exception:
        return ""
    current: object = data
    for part in _report_dot_key(dot_key).split("."):
        if isinstance(current, dict):
            current = current.get(part)
        else:
            return ""
    return _report_value_to_text(current)


def append_report(args) -> None:
    report_path = normalize_text(args.report_path)
    agent = normalize_text(args.agent) or "unknown"
    parent_cmd = normalize_text(args.parent_cmd)
    verdict = normalize_text(args.verdict)
    dot_key = normalize_text(args.dot_key)
    report_base = os.path.basename(report_path) if report_path else ""
    summary = f"{agent} report:{report_base} field:{dot_key}"
    if verdict:
        summary = f"{summary} verdict:{verdict}"
    summary = summary[:SUMMARY_LIMIT]
    detail = "\n".join(
        line
        for line in [
            f"report_path: {report_path}",
            f"dot_key: {dot_key}",
            f"verdict: {verdict}" if verdict else "",
            f"parent_cmd: {parent_cmd}" if parent_cmd else "",
        ]
        if line
    )
    importance = "high" if verdict in ("PASS", "FAIL", "PASS_NO_IMPROVEMENT") else "normal"
    ts = normalize_text(args.ts)
    concept_text_extra = None
    raw_field_value = ""
    if _report_field_has_concepts(dot_key):
        raw_field_value = _extract_report_field_value(report_path, dot_key)
        concept_text_extra = "\n".join(
            line for line in [
                raw_field_value,
                command_context_text(parent_cmd),
            ] if line
        )

    append_event(
        args.db_path,
        (
            f"report:{report_base}:{dot_key}:{ts}",
            ts,
            "report",
            agent,
            report_path,
            dot_key,
            summary,
            detail,
            "",
            parent_cmd,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        concept_text_extra=concept_text_extra,
        raw_content=raw_field_value or detail,
    )


def append_workaround(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    ninja = normalize_text(args.ninja)
    category = normalize_text(args.category)
    issue = normalize_text(args.issue)
    root_cause = normalize_text(args.root_cause)
    ts = normalize_text(args.ts)
    summary = summarize(issue) or f"{cmd_id} workaround"
    detail = "\n".join(
        line
        for line in [
            issue,
            f"root_cause: {root_cause}" if root_cause else "",
            f"category: {category}" if category else "",
            f"ninja: {ninja}" if ninja else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"workaround:{cmd_id}:{ninja}:{ts}",
            ts,
            "workaround",
            "karo",
            ninja,
            category,
            summary,
            detail,
            "",
            cmd_id or infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        raw_content=issue,
    )


def append_contradiction_candidate(args) -> None:
    contradiction_type = normalize_text(args.contradiction_type)
    if contradiction_type not in CONTRADICTION_TYPES:
        allowed = ", ".join(sorted(CONTRADICTION_TYPES))
        raise ValueError(f"invalid contradiction_type: {contradiction_type}; allowed: {allowed}")
    candidate_id = normalize_text(args.candidate_id)
    source_event_id = normalize_text(args.source_event_id)
    conflicting_event_id = normalize_text(args.conflicting_event_id)
    ts = normalize_text(args.ts)
    summary = summarize(args.summary) or f"contradiction candidate: {contradiction_type}"
    detail = "\n".join(
        line
        for line in [
            normalize_text(args.detail),
            f"contradiction_type: {contradiction_type}",
            f"source_event_id: {source_event_id}" if source_event_id else "",
            f"conflicting_event_id: {conflicting_event_id}" if conflicting_event_id else "",
            f"current_event_id: {normalize_text(args.current_event_id)}" if normalize_text(args.current_event_id) else "",
            f"historical_decision: {normalize_text(args.historical_decision)}" if normalize_text(args.historical_decision) else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"contradiction_candidate:{candidate_id}",
            ts,
            "memory_candidate",
            normalize_text(args.agent) or "memory_db_live_insert",
            source_event_id,
            contradiction_type,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        raw_content=normalize_text(args.detail),
        state="contradiction_candidate",
    )


def append_duplicate_candidate(args) -> None:
    candidate_id = normalize_text(args.candidate_id)
    primary_event_id = normalize_text(args.primary_event_id)
    duplicate_event_id = normalize_text(args.duplicate_event_id)
    ts = normalize_text(args.ts)
    similarity = normalize_text(args.similarity)
    summary = summarize(args.summary) or "duplicate candidate"
    detail = "\n".join(
        line
        for line in [
            normalize_text(args.detail),
            f"primary_event_id: {primary_event_id}" if primary_event_id else "",
            f"duplicate_event_id: {duplicate_event_id}" if duplicate_event_id else "",
            f"similarity: {similarity}" if similarity else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"duplicate_candidate:{candidate_id}",
            ts,
            "memory_candidate",
            normalize_text(args.agent) or "memory_db_live_insert",
            primary_event_id,
            "duplicate",
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            "normal",
        ),
        raw_content=normalize_text(args.detail),
        state="duplicate_candidate",
    )


def parse_args():
    specs = {
        "inbox": (
            {
                "action": "",
            },
            ["message_id", "ts", "target_agent", "from_agent", "content", "message_type", "source_file"],
        ),
        "cmd_save": (
            {
                "summary": "",
                "detail": "",
            },
            ["cmd_id", "ts", "source_file"],
        ),
        "cmd_quality": (
            {
                "gunshi_verdict": "",
                "ninja_blockers": "0",
                "ac_count": "0",
                "supplementary_cmds": "0",
                "project": "",
                "source": "cmd_quality_log",
                "diagnosis": "",
                "notes": "",
            },
            ["cmd_id", "ts", "gate_result", "karo_rework", "source_file"],
        ),
        "cmd_delegate": (
            {
                "delegated_at": "",
                "summary": "",
            },
            ["cmd_id", "ts", "message", "source_file"],
        ),
        "bulletin": (
            {
                "requires_confirmation": "",
                "action_type": "info",
                "actioned_by": "",
                "status": "open",
            },
            ["entry_id", "ts", "agent", "content", "source_file"],
        ),
        "insight": (
            {
                "priority": "medium",
                "source": "manual",
                "status": "pending",
                "resolved_at": "",
            },
            ["entry_id", "ts", "insight", "source_file"],
        ),
        "report": (
            {
                "agent": "unknown",
                "parent_cmd": "",
                "verdict": "",
            },
            ["report_path", "ts", "dot_key", "source_file"],
        ),
        "workaround": (
            {
                "root_cause": "",
            },
            ["cmd_id", "ts", "ninja", "category", "issue", "source_file"],
        ),
        "lesson": (
            {
                "detail": "",
                "source_cmd": "",
                "agent": "karo",
                "project": "",
            },
            ["lesson_id", "title", "ts", "source_file"],
        ),
        "gate": (
            {
                "cmd_id": "",
                "detail": "",
            },
            ["gate_name", "result", "ts", "source_file"],
        ),
        "contradiction_candidate": (
            {
                "agent": "memory_db_live_insert",
                "current_event_id": "",
                "historical_decision": "",
            },
            [
                "candidate_id", "ts", "contradiction_type", "source_event_id",
                "conflicting_event_id", "summary", "detail", "source_file",
            ],
        ),
        "duplicate_candidate": (
            {
                "agent": "memory_db_live_insert",
                "similarity": "",
            },
            ["candidate_id", "ts", "primary_event_id", "duplicate_event_id", "summary", "detail", "source_file"],
        ),
    }

    argv = sys.argv[1:]
    values = {"db_path": os.environ.get("SHOGUN_MEMORY_DB", DEFAULT_DB_PATH)}
    while argv and argv[0].startswith("--"):
        key = argv.pop(0)
        if key in ("-h", "--help"):
            print(__doc__ or "")
            raise SystemExit(0)
        if key != "--db-path" or not argv:
            print(f"FATAL: invalid global argument: {key}", file=sys.stderr)
            raise SystemExit(2)
        values["db_path"] = argv.pop(0)

    if not argv:
        print("FATAL: event_type is required", file=sys.stderr)
        raise SystemExit(2)
    event_type = argv.pop(0)
    if event_type not in specs:
        print(f"FATAL: unknown event_type: {event_type}", file=sys.stderr)
        raise SystemExit(2)

    defaults, required = specs[event_type]
    values.update(defaults)
    values["event_type"] = event_type

    while argv:
        option = argv.pop(0)
        if not option.startswith("--") or not argv:
            print(f"FATAL: invalid argument for {event_type}: {option}", file=sys.stderr)
            raise SystemExit(2)
        values[option[2:].replace("-", "_")] = argv.pop(0)

    missing = [name for name in required if name not in values or values[name] == ""]
    if missing:
        print(f"FATAL: missing required argument(s): {', '.join(missing)}", file=sys.stderr)
        raise SystemExit(2)

    return type("Args", (), values)()


def main() -> int:
    args = parse_args()
    if args.event_type == "inbox":
        append_inbox(args)
    elif args.event_type == "cmd_save":
        append_cmd_save(args)
    elif args.event_type == "cmd_quality":
        append_cmd_quality(args)
    elif args.event_type == "cmd_delegate":
        append_cmd_delegate(args)
    elif args.event_type == "bulletin":
        append_bulletin(args)
    elif args.event_type == "insight":
        append_insight(args)
    elif args.event_type == "report":
        append_report(args)
    elif args.event_type == "workaround":
        append_workaround(args)
    elif args.event_type == "lesson":
        append_lesson(args)
    elif args.event_type == "gate":
        append_gate(args)
    elif args.event_type == "contradiction_candidate":
        append_contradiction_candidate(args)
    elif args.event_type == "duplicate_candidate":
        append_duplicate_candidate(args)
    # Do not rebuild the complete 700MB+ read cache after every live event.
    # Readers already reject a stale generation by comparing the source DB/WAL
    # mtimes and schedule a single-flight asynchronous refresh while continuing
    # to use the last atomically-published snapshot (or the primary DB when the
    # cache is cold).  Eager rebuilding here duplicated that mechanism for every
    # inbox/gate/report write and made refresh frequency, rather than copy method,
    # the dominant cost.  Keep an explicit opt-in for recovery/diagnostic callers.
    if (
        os.environ.get("SHOGUN_MEMORY_DB_EAGER_CACHE_SYNC", "0") == "1"
        and os.environ.get("SHOGUN_MEMORY_DB_SKIP_CACHE_SYNC", "0") != "1"
    ):
        try:
            sync_memory_db_ext4_cache(args.db_path)
        except Exception as exc:
            print(f"WARN: memory DB ext4 cache sync failed: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
