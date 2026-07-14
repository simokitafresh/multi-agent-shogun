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
        with admin.cursor() as cur:
            cur.execute("SELECT rolname, rolcanlogin FROM pg_catalog.pg_roles WHERE rolname IN (%s,%s) ORDER BY rolname", (app_role, keeper_role))
            before_rows = cur.fetchall()
            if before_rows:
                raise RuntimeError("disposable rehearsal role already exists")
            cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN").format(sql.Identifier(keeper_role)))
            result["sqlstates"]["create_keeper"] = "00000"
            cur.execute(sql.SQL("CREATE ROLE {} LOGIN PASSWORD %s").format(sql.Identifier(app_role)), (password,))
            result["sqlstates"]["create_app"] = "00000"

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
            cur.execute("SELECT rolname, rolcanlogin FROM pg_catalog.pg_roles WHERE rolname IN (%s,%s) ORDER BY rolname", (app_role, keeper_role))
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
