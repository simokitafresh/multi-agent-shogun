#!/usr/bin/env python3
"""Registered DB tool. SQL arrives via stdin, never argv."""
from __future__ import annotations

import os
import subprocess
import sys
import argparse
import importlib.util
import hashlib
import json
import secrets
from pathlib import Path
from urllib.parse import unquote, urlsplit


def _sqlstate(exc: BaseException) -> str:
    return str(getattr(exc, "pgcode", None) or "XXXXX")


def _nologin_rehearsal(dsn: str, app_role: str, keeper_role: str, output: Path) -> int:
    """Rehearse LOGIN fencing solely on two disposable, prefix-scoped roles."""
    import psycopg2
    from psycopg2 import sql

    prefix = "cmd3881_nologin_"
    if app_role == keeper_role or any(not r.startswith(prefix) for r in (app_role, keeper_role)):
        raise SystemExit("BLOCK: rehearsal roles must be distinct and use cmd3881_nologin_ prefix")
    password = secrets.token_urlsafe(32)
    admin = psycopg2.connect(dsn)
    admin.autocommit = True
    app = None
    before_rows = []
    result = {
        "decision": "FAIL", "app_role": app_role, "keeper_role": keeper_role,
        "initial_connect": False, "connection_refused": False, "restored_connect": False,
        "catalog_exact": False, "roles_remaining": None, "business_relation_access": 0,
        "dm_signal_user_alter": 0, "sqlstates": {},
    }
    try:
        snapshot_sql = """SELECT r.rolname, r.rolcanlogin, COALESCE(array_agg(m.rolname ORDER BY m.rolname) FILTER (WHERE m.rolname IS NOT NULL), ARRAY[]::name[])
                          FROM pg_catalog.pg_roles r
                          LEFT JOIN pg_catalog.pg_auth_members am ON am.roleid=r.oid
                          LEFT JOIN pg_catalog.pg_roles m ON m.oid=am.member
                          WHERE r.rolname IN (%s,%s) GROUP BY r.rolname,r.rolcanlogin ORDER BY r.rolname"""
        with admin.cursor() as cur:
            cur.execute(snapshot_sql, (app_role, keeper_role))
            before_rows = cur.fetchall()
            if before_rows:
                raise RuntimeError("disposable rehearsal role already exists")
            cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN").format(sql.Identifier(keeper_role)))
            result["sqlstates"]["create_keeper"] = "00000"
            cur.execute(sql.SQL("CREATE ROLE {} LOGIN PASSWORD %s").format(sql.Identifier(app_role)), (password,))
            result["sqlstates"]["create_app"] = "00000"
            cur.execute(sql.SQL("GRANT {} TO CURRENT_USER").format(sql.Identifier(app_role)))
            result["sqlstates"]["grant_app_admin"] = "00000"

        parsed = urlsplit(dsn)
        app_dsn = dsn.replace(parsed.username or "", app_role, 1)
        if parsed.password:
            app_dsn = app_dsn.replace(parsed.password, password, 1)
        app = psycopg2.connect(app_dsn, connect_timeout=10, application_name="cmd3881_nologin_rehearsal")
        result["initial_connect"] = True
        with admin.cursor() as cur:
            cur.execute(sql.SQL("ALTER ROLE {} NOLOGIN").format(sql.Identifier(app_role)))
            result["sqlstates"]["alter_nologin"] = "00000"
            cur.execute("SELECT pg_terminate_backend(pid) FROM pg_catalog.pg_stat_activity WHERE usename=%s AND application_name=%s AND pid<>pg_backend_pid()", (app_role, "cmd3881_nologin_rehearsal"))
        app.close(); app = None
        try:
            rejected = psycopg2.connect(app_dsn, connect_timeout=10, application_name="cmd3881_nologin_rehearsal_rejected")
        except Exception as exc:
            result["connection_refused"] = True
            result["sqlstates"]["rejected_connect"] = _sqlstate(exc)
        else:
            rejected.close()
        with admin.cursor() as cur:
            cur.execute(sql.SQL("ALTER ROLE {} LOGIN").format(sql.Identifier(app_role)))
            result["sqlstates"]["alter_login"] = "00000"
        restored = psycopg2.connect(app_dsn, connect_timeout=10, application_name="cmd3881_nologin_rehearsal_restored")
        restored.close()
        result["restored_connect"] = True
    finally:
        if app is not None:
            app.close()
        with admin.cursor() as cur:
            for role in (app_role, keeper_role):
                try:
                    cur.execute(sql.SQL("DROP ROLE IF EXISTS {}").format(sql.Identifier(role)))
                except Exception as exc:
                    result["sqlstates"][f"drop_{role}"] = _sqlstate(exc)
            cur.execute(snapshot_sql, (app_role, keeper_role))
            after_rows = cur.fetchall()
        admin.close()
        result["roles_remaining"] = len(after_rows)
        before_hash = hashlib.sha256(json.dumps(before_rows, separators=(",", ":")).encode()).hexdigest()
        after_hash = hashlib.sha256(json.dumps(after_rows, separators=(",", ":")).encode()).hexdigest()
        result["catalog_before_hash"] = before_hash
        result["catalog_after_hash"] = after_hash
        result["catalog_exact"] = before_hash == after_hash
        if result["initial_connect"] and result["connection_refused"] and result["restored_connect"] and result["catalog_exact"] and result["roles_remaining"] == 0:
            result["decision"] = "PASS"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if result["decision"] == "PASS" else 1


def _keeper_owns_advisory_lock(cur, lock_key: int) -> bool:
    """Return whether this backend owns the exact bigint advisory lock."""
    unsigned = lock_key & ((1 << 64) - 1)
    class_id = (unsigned >> 32) & 0xFFFFFFFF
    object_id = unsigned & 0xFFFFFFFF
    cur.execute(
        """SELECT EXISTS(
               SELECT 1 FROM pg_catalog.pg_locks
               WHERE locktype='advisory' AND pid=pg_backend_pid() AND granted
                 AND classid=%s AND objid=%s AND objsubid=1
           )""",
        (class_id, object_id),
    )
    return bool(cur.fetchone()[0])


def _canonical_table_hash(module, cur, artifact: Path, manifest: dict, table: str) -> str:
    meta = manifest["tables"][table]
    with module.tempfile.NamedTemporaryFile() as verify:
        module.copy_out(cur, table, meta["columns"], meta["order"], Path(verify.name))
        return module.sha256(Path(verify.name))


def restore_with_keeper_connection(module, conn, artifact: Path, expected_commit: str) -> dict:
    """Restore F17 and verify immutable G1 on the keeper-owned transaction.

    The caller must pass the same live connection that owns the recalculation
    advisory lock.  This function never opens another connection and owns the
    commit/rollback boundary for the restore transaction.
    """
    try:
        cur = conn.cursor()
        manifest = module.validate_artifact(artifact, cur, expected_commit)
        if not _keeper_owns_advisory_lock(cur, module.LOCK_KEY):
            raise RuntimeError("keeper connection does not own recalculation advisory lock")

        guard_table = "signal_decision_ledger"
        inventory = list(module.contract().INVENTORY)
        if guard_table not in inventory:
            raise RuntimeError("restore contract is missing immutable ledger guard")
        output_tables = [table for table in inventory if table != guard_table]
        if len(output_tables) != 17:
            raise RuntimeError(f"restore contract requires F17 exactly, got {len(output_tables)}")
        lock_tables = sorted([*output_tables, guard_table])
        cur.execute("SET LOCAL lock_timeout = '30s'")
        cur.execute(
            module.sql.SQL("LOCK TABLE {} IN SHARE ROW EXCLUSIVE MODE").format(
                module.sql.SQL(", ").join(map(module.sql.Identifier, lock_tables))
            )
        )
        guard_before = _canonical_table_hash(module, cur, artifact, manifest, guard_table)
        for table in reversed(output_tables):
            cur.execute(module.sql.SQL("DELETE FROM {}").format(module.sql.Identifier(table)))
        for table in output_tables:
            cur.execute(module.sql.SQL("SELECT count(*) FROM {}").format(module.sql.Identifier(table)))
            remaining = int(cur.fetchone()[0])
            if remaining != 0:
                raise RuntimeError(f"table not empty after delete: {table} ({remaining})")

        restored = {}
        for table in output_tables:
            meta = manifest["tables"][table]
            columns = module.sql.SQL(", ").join(map(module.sql.Identifier, meta["columns"]))
            with (artifact / f"{table}.copy").open("rb") as stream:
                cur.copy_expert(
                    module.sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT binary)")
                    .format(module.sql.Identifier(table), columns)
                    .as_string(cur),
                    stream,
                )
            cur.execute(module.sql.SQL("SELECT count(*) FROM {}").format(module.sql.Identifier(table)))
            if int(cur.fetchone()[0]) != meta["rows"]:
                raise RuntimeError(f"row count mismatch after restore: {table}")
            actual_hash = _canonical_table_hash(module, cur, artifact, manifest, table)
            if actual_hash != meta["sha256"]:
                raise RuntimeError(f"content mismatch after restore: {table}")
            restored[table] = {"rows": meta["rows"], "sha256": actual_hash}
        guard_after = _canonical_table_hash(module, cur, artifact, manifest, guard_table)
        if guard_after != guard_before or guard_after != manifest["tables"][guard_table]["sha256"]:
            raise RuntimeError("immutable ledger guard changed during restore")
        conn.commit()
        return {
            "output_tables_restored": len(restored),
            "guard_tables_mutated": 0,
            "guard_sha256": guard_after,
            "transaction": "committed",
        }
    except Exception:
        conn.rollback()
        raise


def _restore_with_writer_lock(module, dsn: str, artifact: Path, expected_commit: str) -> dict:
    """Standalone recovery wrapper; P4 keeper paths call the core directly."""
    conn = module.psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        cur = conn.cursor()
        cur.execute("SELECT pg_try_advisory_lock(%s)", (module.LOCK_KEY,))
        if not cur.fetchone()[0]:
            raise RuntimeError("recalculate advisory lock is held")
        cur.execute("SELECT EXISTS(SELECT 1 FROM recalculation_status WHERE status='running' AND end_time IS NULL)")
        if cur.fetchone()[0]:
            raise RuntimeError("running recalculation exists")
        return restore_with_keeper_connection(module, conn, artifact, expected_commit)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _restore_signal_window_20260714(dsn: str, output: Path) -> dict:
    """Restore exactly the 2026-07-14 alert window from its recorded old values.

    This is deliberately not a generic SQL capability.  The table, column,
    UTC window, expected row/key/portfolio counts, advisory lock, ledger
    comparison, and postcondition are all fixed here.  Any drift rolls the
    transaction back before it can commit.
    """
    import psycopg2

    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    cursor = None
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT current_user, session_user, current_database(), "
            "COALESCE(inet_server_addr()::text, '')"
        )
        current_user, session_user, database_name, server_address = cursor.fetchone()
        if database_name != "dm_signal":
            raise RuntimeError("bounded restore requires dm_signal database")

        cursor.execute("SELECT pg_try_advisory_lock(%s)", (8675309,))
        if not cursor.fetchone()[0]:
            raise RuntimeError("recalculate advisory lock is held")
        cursor.execute(
            "SELECT EXISTS(SELECT 1 FROM recalculation_status "
            "WHERE status='running' AND end_time IS NULL)"
        )
        if cursor.fetchone()[0]:
            raise RuntimeError("running recalculation exists")

        cursor.execute("SET LOCAL lock_timeout = '30s'")
        cursor.execute(
            "LOCK TABLE signals, signal_change_log, signal_decision_ledger "
            "IN SHARE ROW EXCLUSIVE MODE"
        )
        cursor.execute(
            """
            SELECT c.portfolio_id, c.date, c.old_holding_signal,
                   c.new_holding_signal, s.holding_signal
            FROM signal_change_log c
            JOIN signals s ON s.portfolio_id=c.portfolio_id AND s.date=c.date
            WHERE c.changed_at >= TIMESTAMP '2026-07-14 01:48:00'
              AND c.changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            ORDER BY c.portfolio_id, c.date
            """
        )
        target_rows = cursor.fetchall()
        keys = {(row[0], row[1]) for row in target_rows}
        portfolios = {row[0] for row in target_rows}
        if len(target_rows) != 161 or len(keys) != 161 or len(portfolios) != 23:
            raise RuntimeError(
                f"target cardinality drift: rows={len(target_rows)} "
                f"keys={len(keys)} portfolios={len(portfolios)}"
            )
        if any(row[2] is None for row in target_rows):
            raise RuntimeError("target contains null old_holding_signal")
        if any(row[4] != row[3] for row in target_rows):
            raise RuntimeError("current holding_signal no longer equals recorded new value")

        cursor.execute(
            """
            WITH target AS (
              SELECT c.portfolio_id, c.date, c.old_holding_signal
              FROM signal_change_log c
              WHERE c.changed_at >= TIMESTAMP '2026-07-14 01:48:00'
                AND c.changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            )
            SELECT t.portfolio_id, t.date, t.old_holding_signal,
                   l.decision_holding_signal
            FROM target t
            LEFT JOIN LATERAL (
              SELECT decision_holding_signal
              FROM signal_decision_ledger d
              WHERE d.portfolio_id=t.portfolio_id
                AND d.effective_start_date <= t.date
              ORDER BY d.effective_start_date DESC, d.recorded_at DESC, d.id DESC
              LIMIT 1
            ) l ON TRUE
            ORDER BY t.portfolio_id, t.date
            """
        )
        ledger_rows = cursor.fetchall()
        ledger_exact = sum(1 for row in ledger_rows if row[2] == row[3])
        if len(ledger_rows) != 161 or ledger_exact != 161:
            raise RuntimeError(
                f"ledger precondition mismatch: rows={len(ledger_rows)} exact={ledger_exact}"
            )

        serialized_rows = [
            {
                "portfolio_id": str(row[0]),
                "date": row[1].isoformat() if hasattr(row[1], "isoformat") else str(row[1]),
                "old_holding_signal": row[2],
                "new_holding_signal": row[3],
                "pre_restore_holding_signal": row[4],
            }
            for row in target_rows
        ]
        rows_json = json.dumps(serialized_rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        backup = {
            "capability": "bounded_signal_restore_20260714",
            "window_utc": ["2026-07-14T01:48:00Z", "2026-07-14T01:50:00Z"],
            "row_count": 161,
            "portfolio_count": 23,
            "rows_sha256": hashlib.sha256(rows_json.encode("utf-8")).hexdigest(),
            "identity": {
                "current_user": current_user,
                "session_user": session_user,
                "database": database_name,
                "server_address": server_address,
            },
            "rows": serialized_rows,
        }
        output.parent.mkdir(parents=True, exist_ok=True)
        payload = (json.dumps(backup, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
        fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())

        cursor.execute(
            """
            WITH target AS (
              SELECT c.portfolio_id, c.date, c.old_holding_signal
              FROM signal_change_log c
              WHERE c.changed_at >= TIMESTAMP '2026-07-14 01:48:00'
                AND c.changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            )
            UPDATE signals s
               SET holding_signal = target.old_holding_signal
              FROM target
             WHERE s.portfolio_id=target.portfolio_id AND s.date=target.date
            RETURNING s.portfolio_id, s.date
            """
        )
        updated = cursor.fetchall()
        if len(updated) != 161 or len(set(updated)) != 161:
            raise RuntimeError(f"update cardinality mismatch: {len(updated)}")

        cursor.execute(
            """
            WITH target AS (
              SELECT c.portfolio_id, c.date, c.old_holding_signal
              FROM signal_change_log c
              WHERE c.changed_at >= TIMESTAMP '2026-07-14 01:48:00'
                AND c.changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            )
            SELECT COUNT(*) AS target_rows,
                   COUNT(*) FILTER (
                     WHERE s.holding_signal IS NOT DISTINCT FROM t.old_holding_signal
                   ) AS restored_exact,
                   COUNT(*) FILTER (
                     WHERE l.decision_holding_signal IS NOT DISTINCT FROM t.old_holding_signal
                   ) AS ledger_exact
            FROM target t
            JOIN signals s ON s.portfolio_id=t.portfolio_id AND s.date=t.date
            LEFT JOIN LATERAL (
              SELECT decision_holding_signal
              FROM signal_decision_ledger d
              WHERE d.portfolio_id=t.portfolio_id
                AND d.effective_start_date <= t.date
              ORDER BY d.effective_start_date DESC, d.recorded_at DESC, d.id DESC
              LIMIT 1
            ) l ON TRUE
            """
        )
        target_count, restored_exact, post_ledger_exact = map(int, cursor.fetchone())
        if (target_count, restored_exact, post_ledger_exact) != (161, 161, 161):
            raise RuntimeError(
                "postcondition mismatch: "
                f"target={target_count} restored={restored_exact} ledger={post_ledger_exact}"
            )
        conn.commit()
        return {
            "decision": "PASS",
            "backup": str(output),
            "backup_bytes": len(payload),
            "target_rows": target_count,
            "updated_rows": len(updated),
            "restored_exact": restored_exact,
            "ledger_exact": post_ledger_exact,
            "other_table_writes": 0,
            "recalculate_runs": 0,
            "identity": backup["identity"],
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()


def _restore_signal_july_drift_20260714(dsn: str, output: Path) -> dict:
    """Restore every July ledger drift row for the exact 23 affected FoFs.

    The affected portfolio set is derived from the immutable 01:48-01:50 UTC
    change-log window used by the original restore.  Scope comes from the
    invariant (all July rows equal the latest ledger decision), not from an
    alert's incomplete row list.  The month, portfolio set, ledger ordering,
    lock, backup and zero-drift postcondition are fixed here.
    """
    import psycopg2

    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    cursor = None
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT current_user, session_user, current_database(), "
            "COALESCE(inet_server_addr()::text, '')"
        )
        current_user, session_user, database_name, server_address = cursor.fetchone()
        if database_name != "dm_signal":
            raise RuntimeError("bounded July drift restore requires dm_signal database")

        cursor.execute("SELECT pg_try_advisory_lock(%s)", (8675309,))
        if not cursor.fetchone()[0]:
            raise RuntimeError("recalculate advisory lock is held")
        cursor.execute(
            "SELECT EXISTS(SELECT 1 FROM recalculation_status "
            "WHERE status='running' AND end_time IS NULL)"
        )
        if cursor.fetchone()[0]:
            raise RuntimeError("running recalculation exists")

        cursor.execute("SET LOCAL lock_timeout = '30s'")
        cursor.execute(
            "LOCK TABLE signals, signal_change_log, signal_decision_ledger "
            "IN SHARE ROW EXCLUSIVE MODE"
        )
        cursor.execute(
            """
            WITH affected AS (
              SELECT DISTINCT portfolio_id
              FROM signal_change_log
              WHERE changed_at >= TIMESTAMP '2026-07-14 01:48:00'
                AND changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            )
            SELECT s.portfolio_id, s.date, s.holding_signal,
                   l.effective_start_date, l.decision_holding_signal
            FROM signals s
            JOIN affected a ON a.portfolio_id=s.portfolio_id
            LEFT JOIN LATERAL (
              SELECT effective_start_date, decision_holding_signal
              FROM signal_decision_ledger d
              WHERE d.portfolio_id=s.portfolio_id
                AND d.effective_start_date <= s.date
              ORDER BY d.effective_start_date DESC, d.recorded_at DESC, d.id DESC
              LIMIT 1
            ) l ON TRUE
            WHERE s.date >= DATE '2026-07-01'
              AND s.date <  DATE '2026-08-01'
            ORDER BY s.portfolio_id, s.date
            """
        )
        target_rows = cursor.fetchall()
        keys = {(row[0], row[1]) for row in target_rows}
        portfolios = {row[0] for row in target_rows}
        if len(target_rows) < 161 or len(target_rows) > 713:
            raise RuntimeError(
                f"July comparison cardinality drift: rows={len(target_rows)} "
                f"keys={len(keys)} portfolios={len(portfolios)}"
            )
        if len(keys) != len(target_rows) or len(portfolios) != 23:
            raise RuntimeError(
                f"July comparison key drift: rows={len(target_rows)} "
                f"keys={len(keys)} portfolios={len(portfolios)}"
            )
        if any(row[4] is None for row in target_rows):
            raise RuntimeError("July comparison has no ledger decision")
        if any(str(row[3]) != "2026-07-01" for row in target_rows):
            raise RuntimeError("July comparison latest ledger is not the 2026-07-01 decision")
        drift_rows = [row for row in target_rows if row[2] != row[4]]
        if not drift_rows:
            raise RuntimeError("July comparison has no drift to restore")

        serialized_rows = [
            {
                "portfolio_id": str(row[0]),
                "date": row[1].isoformat() if hasattr(row[1], "isoformat") else str(row[1]),
                "pre_restore_holding_signal": row[2],
                "ledger_effective_start_date": (
                    row[3].isoformat() if hasattr(row[3], "isoformat") else str(row[3])
                ),
                "restored_holding_signal": row[4],
            }
            for row in drift_rows
        ]
        rows_json = json.dumps(serialized_rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        backup = {
            "capability": "bounded_signal_july_drift_restore_20260714",
            "source_window_utc": ["2026-07-14T01:48:00Z", "2026-07-14T01:50:00Z"],
            "target_month": "2026-07",
            "comparison_row_count": len(target_rows),
            "row_count": len(drift_rows),
            "portfolio_count": 23,
            "rows_sha256": hashlib.sha256(rows_json.encode("utf-8")).hexdigest(),
            "identity": {
                "current_user": current_user,
                "session_user": session_user,
                "database": database_name,
                "server_address": server_address,
            },
            "rows": serialized_rows,
        }
        output.parent.mkdir(parents=True, exist_ok=True)
        payload = (json.dumps(backup, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
        fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())

        cursor.execute(
            """
            WITH affected AS (
              SELECT DISTINCT portfolio_id
              FROM signal_change_log
              WHERE changed_at >= TIMESTAMP '2026-07-14 01:48:00'
                AND changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            ), target AS (
              SELECT s.portfolio_id, s.date, l.decision_holding_signal
              FROM signals s
              JOIN affected a ON a.portfolio_id=s.portfolio_id
              JOIN LATERAL (
                SELECT decision_holding_signal
                FROM signal_decision_ledger d
                WHERE d.portfolio_id=s.portfolio_id
                  AND d.effective_start_date <= s.date
                ORDER BY d.effective_start_date DESC, d.recorded_at DESC, d.id DESC
                LIMIT 1
              ) l ON TRUE
              WHERE s.date >= DATE '2026-07-01'
                AND s.date <  DATE '2026-08-01'
                AND s.holding_signal IS DISTINCT FROM l.decision_holding_signal
            )
            UPDATE signals s
               SET holding_signal=target.decision_holding_signal
              FROM target
             WHERE s.portfolio_id=target.portfolio_id AND s.date=target.date
            RETURNING s.portfolio_id, s.date
            """
        )
        updated = cursor.fetchall()
        if len(updated) != len(drift_rows) or len(set(updated)) != len(drift_rows):
            raise RuntimeError(
                f"July drift update cardinality mismatch: "
                f"expected={len(drift_rows)} actual={len(updated)}"
            )

        cursor.execute(
            """
            WITH affected AS (
              SELECT DISTINCT portfolio_id
              FROM signal_change_log
              WHERE changed_at >= TIMESTAMP '2026-07-14 01:48:00'
                AND changed_at <  TIMESTAMP '2026-07-14 01:50:00'
            ), compared AS (
              SELECT s.portfolio_id, s.date, s.holding_signal,
                     l.effective_start_date, l.decision_holding_signal
              FROM signals s
              JOIN affected a ON a.portfolio_id=s.portfolio_id
              LEFT JOIN LATERAL (
                SELECT effective_start_date, decision_holding_signal
                FROM signal_decision_ledger d
                WHERE d.portfolio_id=s.portfolio_id
                  AND d.effective_start_date <= s.date
                ORDER BY d.effective_start_date DESC, d.recorded_at DESC, d.id DESC
                LIMIT 1
              ) l ON TRUE
              WHERE s.date >= DATE '2026-07-01'
                AND s.date <  DATE '2026-08-01'
            )
            SELECT COUNT(*),
                   COUNT(*) FILTER (
                     WHERE holding_signal IS NOT DISTINCT FROM decision_holding_signal
                   ),
                   COUNT(*) FILTER (WHERE effective_start_date=DATE '2026-07-01')
            FROM compared
            """
        )
        target_count, restored_exact, ledger_date_exact = map(int, cursor.fetchone())
        if (target_count, restored_exact, ledger_date_exact) != (
            len(target_rows), len(target_rows), len(target_rows)
        ):
            raise RuntimeError(
                "July drift postcondition mismatch: "
                f"target={target_count} restored={restored_exact} ledger_date={ledger_date_exact}"
            )
        conn.commit()
        return {
            "decision": "PASS",
            "backup": str(output),
            "backup_bytes": len(payload),
            "comparison_rows": target_count,
            "drift_rows": len(drift_rows),
            "updated_rows": len(updated),
            "restored_exact": restored_exact,
            "ledger_date_exact": ledger_date_exact,
            "other_table_writes": 0,
            "recalculate_runs": 0,
            "identity": backup["identity"],
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()


def _freeze_signal_ledger_baseline_20260715(dsn: str, output: Path) -> dict:
    """Freeze every currently uncovered confirmed signal without fixed counts."""
    import psycopg2
    from psycopg2.extras import Json, execute_values

    target_sql = """
        SELECT s.portfolio_id, s.date, s.signal, s.holding_signal,
               s.momentum_data -> 'weights' AS ticker_weights
        FROM signals s
        JOIN (SELECT DISTINCT portfolio_id FROM signal_decision_ledger) confirmed
          ON confirmed.portfolio_id = s.portfolio_id
        WHERE s.holding_signal IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM signal_decision_ledger d
              WHERE d.portfolio_id = s.portfolio_id
                AND d.effective_start_date <= s.date
                AND d.decision_holding_signal IS NOT NULL
          )
        ORDER BY s.portfolio_id, s.date
    """
    coverage_sql = """
        WITH scope AS (
          SELECT s.portfolio_id, s.date
          FROM signals s
          JOIN (SELECT DISTINCT portfolio_id FROM signal_decision_ledger) confirmed
            ON confirmed.portfolio_id = s.portfolio_id
          WHERE s.holding_signal IS NOT NULL
        )
        SELECT COUNT(*), COUNT(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM signal_decision_ledger d
          WHERE d.portfolio_id = scope.portfolio_id
            AND d.effective_start_date <= scope.date
            AND d.decision_holding_signal IS NOT NULL
        )) FROM scope
    """
    insert_sql = """
        INSERT INTO signal_decision_ledger (
          portfolio_id, rebalance_decision_date, effective_start_date,
          effective_end_date, decision_holding_signal, decision_ticker_weights,
          source_signal_date, source_signal, source_ticker_weights,
          event_type, correction_reason_code, correction_reason,
          source_table, source_row_ref, decided_at, recorded_at, created_by
        ) VALUES %s
    """
    insert_template = (
        "(%s, %s, %s, NULL, %s, %s, %s, %s, %s, "
        "'baseline', NULL, NULL, 'signals', %s, CURRENT_TIMESTAMP, "
        "CURRENT_TIMESTAMP, 'cmd_3947_predicate_freeze')"
    )
    snapshot_sql = """
        SELECT id, portfolio_id, rebalance_decision_date, effective_start_date,
               effective_end_date, decision_holding_signal,
               decision_ticker_weights, source_signal_date, source_signal,
               source_ticker_weights, event_type, correction_reason_code,
               correction_reason, source_table, source_row_ref, decided_at,
               recorded_at, created_by
        FROM signal_decision_ledger
        ORDER BY id
    """
    snapshot_columns = (
        "id", "portfolio_id", "rebalance_decision_date", "effective_start_date",
        "effective_end_date", "decision_holding_signal", "decision_ticker_weights",
        "source_signal_date", "source_signal", "source_ticker_weights", "event_type",
        "correction_reason_code", "correction_reason", "source_table",
        "source_row_ref", "decided_at", "recorded_at", "created_by",
    )

    def serialize_snapshot(snapshot_rows):
        return [dict(zip(snapshot_columns, row)) for row in snapshot_rows]

    def snapshot_hash(serialized_rows):
        canonical = json.dumps(
            serialized_rows, ensure_ascii=False, sort_keys=True,
            separators=(",", ":"), default=str,
        ).encode()
        return hashlib.sha256(canonical).hexdigest()

    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    cursor = None
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT current_user, session_user, current_database(), "
            "COALESCE(inet_server_addr()::text, '')"
        )
        current_user, session_user, database_name, server_address = cursor.fetchone()
        if database_name != "dm_signal":
            raise RuntimeError("baseline freeze requires dm_signal database")

        cursor.execute("SELECT pg_try_advisory_lock(%s)", (8675309,))
        if not cursor.fetchone()[0]:
            raise RuntimeError("recalculate advisory lock is held")
        cursor.execute(
            "SELECT EXISTS(SELECT 1 FROM recalculation_status "
            "WHERE status='running' AND end_time IS NULL)"
        )
        if cursor.fetchone()[0]:
            raise RuntimeError("running recalculation exists")
        cursor.execute("SET LOCAL lock_timeout = '30s'")
        cursor.execute(
            "LOCK TABLE signals, signal_decision_ledger IN SHARE ROW EXCLUSIVE MODE"
        )

        cursor.execute(snapshot_sql)
        existing_rows_before = cursor.fetchall()
        existing_snapshot = serialize_snapshot(existing_rows_before)
        existing_snapshot_sha256 = snapshot_hash(existing_snapshot)
        ledger_before = len(existing_rows_before)
        max_existing_id = max((int(row[0]) for row in existing_rows_before), default=0)
        cursor.execute(target_sql)
        rows = cursor.fetchall()
        keys = {(str(row[0]), row[1]) for row in rows}
        portfolios = {str(row[0]) for row in rows}
        if len(rows) != len(keys):
            raise RuntimeError(
                f"baseline target contains duplicate keys: rows={len(rows)} keys={len(keys)}"
            )
        if any(row[3] is None or not str(row[3]).strip() for row in rows):
            raise RuntimeError("baseline target contains empty holding_signal")

        cursor.execute(coverage_sql)
        scope_before, covered_before = map(int, cursor.fetchone())
        if scope_before - covered_before != len(rows):
            raise RuntimeError(
                "baseline predicate/coverage mismatch before insert: "
                f"scope={scope_before} covered={covered_before} targets={len(rows)}"
            )

        inventory = {
            "cmd": "cmd_3947",
            "identity": {
                "current_user": current_user,
                "session_user": session_user,
                "database": database_name,
                "server_address": server_address,
            },
            "row_count": len(rows),
            "portfolio_count": len(portfolios),
            "scope_rows_before": scope_before,
            "covered_rows_before": covered_before,
            "ledger_rows_before": ledger_before,
            "existing_ledger_max_id": max_existing_id,
            "existing_ledger_sha256": existing_snapshot_sha256,
            "target_sql": target_sql.strip(),
            "coverage_sql": coverage_sql.strip(),
            "insert_sql": insert_sql.strip(),
            "restore": {
                "physical_delete": "forbidden",
                "procedure": "For a wrong frozen value, append a correction event through POST /admin/signal-decision-ledger/corrections using this backup row and reason/actor; never UPDATE or DELETE existing ledger rows.",
            },
            "rows": [
                {
                    "portfolio_id": str(row[0]),
                    "date": row[1].isoformat(),
                    "signal": row[2],
                    "holding_signal": row[3],
                    "ticker_weights": row[4],
                }
                for row in rows
            ],
            "existing_ledger_rows": existing_snapshot,
        }
        payload = (json.dumps(inventory, ensure_ascii=False, indent=2, default=str) + "\n").encode()
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            if output.read_bytes() != payload:
                raise RuntimeError("existing inventory differs from live target")
        else:
            fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            try:
                with os.fdopen(fd, "wb") as stream:
                    stream.write(payload)
                    stream.flush()
                    os.fsync(stream.fileno())
            except Exception:
                if output.exists():
                    output.unlink()
                raise

        values = [
            (
                str(row[0]), row[1], row[1], row[3], Json(row[4]) if row[4] is not None else None,
                row[1], row[2], Json(row[4]) if row[4] is not None else None,
                Json({"portfolio_id": str(row[0]), "date": row[1].isoformat(), "cutover": "cmd_3947"}),
            )
            for row in rows
        ]
        if values:
            execute_values(
                cursor, insert_sql, values, template=insert_template,
                page_size=len(values),
            )
            inserted = int(cursor.rowcount)
        else:
            inserted = 0
        if inserted != len(rows):
            raise RuntimeError(f"baseline insert count drift: inserted={inserted}")

        cursor.execute("SELECT COUNT(*) FROM signal_decision_ledger")
        ledger_after = int(cursor.fetchone()[0])
        cursor.execute(snapshot_sql.replace("ORDER BY id", "WHERE id <= %s ORDER BY id"), (max_existing_id,))
        existing_rows_after = cursor.fetchall()
        existing_snapshot_after = serialize_snapshot(existing_rows_after)
        existing_snapshot_sha256_after = snapshot_hash(existing_snapshot_after)
        cursor.execute(coverage_sql)
        scope_after, covered_after = map(int, cursor.fetchone())
        if ledger_after - ledger_before != inserted:
            raise RuntimeError(
                f"ledger row delta drift: before={ledger_before} after={ledger_after}"
            )
        if existing_snapshot_after != existing_snapshot:
            raise RuntimeError(
                "existing ledger rows changed during append-only baseline freeze: "
                f"before={existing_snapshot_sha256} after={existing_snapshot_sha256_after}"
            )
        if scope_after != scope_before or covered_after != scope_after:
            raise RuntimeError(
                "baseline coverage drift after insert: "
                f"scope={scope_after} covered={covered_after}"
            )
        conn.commit()
        return {
            "decision": "PASS",
            "inventory": str(output),
            "inventory_bytes": len(payload),
            "inserted_rows": inserted,
            "portfolio_count": len(portfolios),
            "ledger_rows_before": ledger_before,
            "ledger_rows_after": ledger_after,
            "existing_ledger_sha256_before": existing_snapshot_sha256,
            "existing_ledger_sha256_after": existing_snapshot_sha256_after,
            "existing_ledger_unchanged": True,
            "scope_rows": scope_after,
            "covered_rows": covered_after,
            "coverage_percent": 100.0,
            "other_table_writes": 0,
            "recalculate_runs": 0,
            "restore_procedure": inventory["restore"]["procedure"],
            "correction_path": "POST /admin/signal-decision-ledger/corrections",
            "identity": inventory["identity"],
        }
    except Exception:
        conn.rollback()
        raise
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()


def main() -> int:
    capability = os.environ.get("DB_CAPABILITY")
    mode = os.environ.get("DB_CAPABILITY_MODE")
    if capability == "readonly_query":
        sql = sys.stdin.read().strip()
        if not sql:
            raise SystemExit("empty SQL")
        if mode != "readonly" or not sql.lstrip().upper().startswith(("SELECT", "WITH", "EXPLAIN")):
            raise SystemExit("readonly capability rejects non-read SQL")
        import psycopg2
        conn = psycopg2.connect(os.environ["DATABASE_URL"])
        try:
            conn.set_session(readonly=True, autocommit=False)
            with conn.cursor() as cur:
                cur.execute(sql)
                for row in cur.fetchall() if cur.description else ():
                    print(row)
            conn.rollback()
        finally:
            conn.close()
        return 0
    if capability == "bounded_signal_restore_20260714":
        if mode != "bounded_signal_restore":
            raise SystemExit("unknown capability or mode")
        parser = argparse.ArgumentParser()
        parser.add_argument("action", choices=("restore",))
        parser.add_argument("--output", required=True)
        args = parser.parse_args()
        project_root = Path(os.environ["DB_CAPABILITY_PROJECT_ROOT"]).resolve()
        output = Path(args.output).resolve()
        allowed_output_root = (project_root / "outputs" / "analysis").resolve()
        if allowed_output_root not in output.parents or output.suffix != ".json":
            raise SystemExit("BLOCK: backup output must be a JSON file under outputs/analysis")
        dsn = os.environ["DATABASE_URL"]
        parsed = urlsplit(dsn)
        resource_identity = parsed.hostname or ""
        database_identity = unquote(parsed.path.lstrip("/").split("/", 1)[0])
        if not resource_identity.endswith(".singapore-postgres.render.com"):
            raise SystemExit("BLOCK: DATABASE_URL is not the registered Render production resource")
        if database_identity != "dm_signal":
            raise SystemExit("BLOCK: DATABASE_URL is not the registered production database")
        result = _restore_signal_window_20260714(dsn, output)
        print(json.dumps(result, sort_keys=True, ensure_ascii=False))
        return 0
    if capability == "bounded_signal_july_drift_restore_20260714":
        if mode != "bounded_signal_july_drift_restore":
            raise SystemExit("unknown capability or mode")
        parser = argparse.ArgumentParser()
        parser.add_argument("action", choices=("restore",))
        parser.add_argument("--output", required=True)
        args = parser.parse_args()
        project_root = Path(os.environ["DB_CAPABILITY_PROJECT_ROOT"]).resolve()
        output = Path(args.output).resolve()
        allowed_output_root = (project_root / "outputs" / "analysis").resolve()
        if allowed_output_root not in output.parents or output.suffix != ".json":
            raise SystemExit("BLOCK: backup output must be a JSON file under outputs/analysis")
        dsn = os.environ["DATABASE_URL"]
        parsed = urlsplit(dsn)
        resource_identity = parsed.hostname or ""
        database_identity = unquote(parsed.path.lstrip("/").split("/", 1)[0])
        if not resource_identity.endswith(".singapore-postgres.render.com"):
            raise SystemExit("BLOCK: DATABASE_URL is not the registered Render production resource")
        if database_identity != "dm_signal":
            raise SystemExit("BLOCK: DATABASE_URL is not the registered production database")
        result = _restore_signal_july_drift_20260714(dsn, output)
        print(json.dumps(result, sort_keys=True, ensure_ascii=False))
        return 0
    if capability == "bounded_signal_ledger_baseline_20260715":
        if mode != "bounded_signal_ledger_baseline":
            raise SystemExit("unknown capability or mode")
        parser = argparse.ArgumentParser()
        parser.add_argument("action", choices=("freeze",))
        parser.add_argument("--output", required=True)
        args = parser.parse_args()
        project_root = Path(os.environ["DB_CAPABILITY_PROJECT_ROOT"]).resolve()
        output = Path(args.output).resolve()
        expected_output = (project_root / "outputs" / "analysis" / "cmd_3947_baseline_freeze_backup.json").resolve()
        if output != expected_output:
            raise SystemExit("BLOCK: baseline backup must use the cmd_3947 canonical output path")
        dsn = os.environ["DATABASE_URL"]
        parsed = urlsplit(dsn)
        resource_identity = parsed.hostname or ""
        database_identity = unquote(parsed.path.lstrip("/").split("/", 1)[0])
        if not resource_identity.endswith(".singapore-postgres.render.com"):
            raise SystemExit("BLOCK: DATABASE_URL is not the registered Render production resource")
        if database_identity != "dm_signal":
            raise SystemExit("BLOCK: DATABASE_URL is not the registered production database")
        result = _freeze_signal_ledger_baseline_20260715(dsn, output)
        print(json.dumps(result, sort_keys=True, ensure_ascii=False))
        return 0
    if capability == "production_role_probe":
        if mode != "production_role_probe":
            raise SystemExit("unknown capability or mode")
        parser = argparse.ArgumentParser()
        parser.add_argument("action", choices=("run", "nologin-rehearsal"))
        parser.add_argument("--probe-role")
        parser.add_argument("--app-role")
        parser.add_argument("--keeper-role")
        parser.add_argument("--output", required=True)
        args = parser.parse_args()

        dsn = os.environ["DATABASE_URL"]
        parsed = urlsplit(dsn)
        resource_identity = parsed.hostname or ""
        database_identity = unquote(parsed.path.lstrip("/").split("/", 1)[0])
        if not resource_identity.endswith(".singapore-postgres.render.com"):
            raise SystemExit("BLOCK: DATABASE_URL is not the registered Render production resource")
        if database_identity != "dm_signal":
            raise SystemExit("BLOCK: DATABASE_URL is not the registered production database")

        project_root = Path(os.environ["DB_CAPABILITY_PROJECT_ROOT"]).resolve()
        output = Path(args.output).resolve()
        allowed_output_root = (project_root / "outputs" / "analysis").resolve()
        if allowed_output_root not in output.parents:
            raise SystemExit("BLOCK: probe output must be under outputs/analysis")

        if args.action == "nologin-rehearsal":
            if args.probe_role or not args.app_role or not args.keeper_role:
                raise SystemExit("BLOCK: rehearsal requires app/keeper roles only")
            return _nologin_rehearsal(dsn, args.app_role, args.keeper_role, output)
        if not args.probe_role or args.app_role or args.keeper_role:
            raise SystemExit("BLOCK: run requires probe role only")

        child_env = os.environ.copy()
        child_env["CMD3881_PRODUCTION_PROBE_DSN"] = dsn
        dependency = os.environ["DB_CAPABILITY_DEPENDENCY_TOOL"]
        command = [
            sys.executable,
            dependency,
            "--production-capability-probe",
            "--arm-production-capability-probe",
            "--environment",
            "production",
            "--resource-identity",
            resource_identity,
            "--expected-resource-identity",
            resource_identity,
            "--database-identity",
            database_identity,
            "--expected-database-identity",
            database_identity,
            "--probe-role",
            args.probe_role,
            "--output",
            str(output),
        ]
        return subprocess.run(command, env=child_env).returncode
    if capability != "transactional_restore" or mode != "transactional_restore":
        raise SystemExit("unknown capability or mode")
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("backup", "dry-run", "restore", "restore-locked"))
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--service", default="dm-signal-backend")
    args = parser.parse_args()
    dependency = os.environ["DB_CAPABILITY_DEPENDENCY_TOOL"]
    spec = importlib.util.spec_from_file_location("p4_restore_contract", dependency)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load restore dependency")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if args.action == "backup":
        module.backup(
            os.environ["DATABASE_URL"], Path(args.artifact), args.service,
            os.environ["DB_CAPABILITY_EXPECTED_COMMIT"],
        )
    elif args.action == "restore-locked":
        _restore_with_writer_lock(
            module,
            os.environ["DATABASE_URL"],
            Path(args.artifact),
            os.environ["DB_CAPABILITY_EXPECTED_COMMIT"],
        )
    else:
        module.restore(
            os.environ["DATABASE_URL"], Path(args.artifact),
            os.environ["DB_CAPABILITY_EXPECTED_COMMIT"], True,
            "P4_RESTORE", os.environ["DB_CAPABILITY_EXPECTED_COMMIT"], False,
            dry_run=args.action == "dry-run",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
