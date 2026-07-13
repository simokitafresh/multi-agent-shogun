#!/usr/bin/env python3
"""Registered DB tool. SQL arrives via stdin, never argv."""
from __future__ import annotations

import os
import sys
import argparse
import importlib.util
from pathlib import Path


def _restore_with_writer_lock(module, dsn: str, artifact: Path, expected_commit: str) -> None:
    """Restore while excluding ordinary writers that do not take the recalc lock."""
    conn = module.psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        cur = conn.cursor()
        manifest = module.validate_artifact(artifact, cur, expected_commit)
        cur.execute("SELECT pg_try_advisory_lock(%s)", (module.LOCK_KEY,))
        if not cur.fetchone()[0]:
            raise RuntimeError("recalculate advisory lock is held")
        cur.execute("SELECT EXISTS(SELECT 1 FROM recalculation_status WHERE status='running' AND end_time IS NULL)")
        if cur.fetchone()[0]:
            raise RuntimeError("running recalculation exists")

        tables = list(module.contract().INVENTORY)
        cur.execute("SET LOCAL lock_timeout = '30s'")
        cur.execute(
            module.sql.SQL("LOCK TABLE {} IN SHARE ROW EXCLUSIVE MODE").format(
                module.sql.SQL(", ").join(map(module.sql.Identifier, tables))
            )
        )
        for table in reversed(tables):
            cur.execute(module.sql.SQL("DELETE FROM {}").format(module.sql.Identifier(table)))
        for table in tables:
            cur.execute(module.sql.SQL("SELECT count(*) FROM {}").format(module.sql.Identifier(table)))
            remaining = int(cur.fetchone()[0])
            if remaining != 0:
                raise RuntimeError(f"table not empty after delete: {table} ({remaining})")

        for table in tables:
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
            with module.tempfile.NamedTemporaryFile() as verify:
                module.copy_out(cur, table, meta["columns"], meta["order"], Path(verify.name))
                if module.sha256(Path(verify.name)) != meta["sha256"]:
                    raise RuntimeError(f"content mismatch after restore: {table}")
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
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
