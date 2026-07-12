#!/usr/bin/env python3
"""Registered DB tool. SQL arrives via stdin, never argv."""
from __future__ import annotations

import os
import sys
import argparse
import importlib.util


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
    parser.add_argument("action", choices=("dry-run", "restore"))
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--service", default="dm-signal-backend")
    args = parser.parse_args()
    dependency = os.environ["DB_CAPABILITY_DEPENDENCY_TOOL"]
    spec = importlib.util.spec_from_file_location("p4_restore_contract", dependency)
    if spec is None or spec.loader is None:
        raise SystemExit("cannot load restore dependency")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.restore(
        os.environ["DATABASE_URL"], args.artifact,
        os.environ["DB_CAPABILITY_EXPECTED_COMMIT"], True,
        "P4_RESTORE", os.environ["DB_CAPABILITY_EXPECTED_COMMIT"], False,
        dry_run=args.action == "dry-run",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
