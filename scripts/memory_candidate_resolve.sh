#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[L7候補確定パイプライン]], [[三層記憶アーキテクチャ]]
# Resolve reviewed memory candidates through a single approve/reject/defer flow.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="$script_dir/data/multi_agent_shogun_memory.db"
backup_dir=""
notes_dir="$script_dir/docs/obsidian-promoted"
dry_run=0

usage() {
    cat <<'EOF' >&2
Usage: memory_candidate_resolve.sh [--db PATH] [--backup-dir DIR] [--notes-dir DIR]
                                   [--dry-run]
                                   <candidate_type> <event_id> <action> <reason>

candidate_type: contradiction_candidate | duplicate_candidate | obsidian_candidate | stale_candidate
action: approve | reject | defer

State-changing runs always create a SQLite backup before UPDATE, verify the
post-update state with SELECT, and notify through scripts/ntfy.sh.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --db)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            db_path="$2"
            shift 2
            ;;
        --backup-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            backup_dir="$2"
            shift 2
            ;;
        --notes-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            notes_dir="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

[ "$#" -ge 4 ] || { usage; exit 2; }
candidate_type="$1"
event_id="$2"
action="$3"
shift 3
reason="$*"

python3 - "$script_dir" "$db_path" "$backup_dir" "$notes_dir" "$dry_run" "$candidate_type" "$event_id" "$action" "$reason" <<'PY'
from __future__ import annotations

import importlib.util
import sqlite3
import subprocess
import sys
from pathlib import Path


SQLITE_BUSY_TIMEOUT_MS = 5000
ALLOWED_CANDIDATE_TYPES = {
    "contradiction_candidate",
    "duplicate_candidate",
    "obsidian_candidate",
    "stale_candidate",
}
ALLOWED_ACTIONS = {"approve", "reject", "defer"}


def load_state_module(repo_root: Path):
    module_path = repo_root / "scripts" / "memory_db_live_insert.py"
    spec = importlib.util.spec_from_file_location("memory_db_live_insert", module_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"memory_candidate_resolve: cannot load {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_columns(conn: sqlite3.Connection, table: str, columns: set[str]) -> None:
    existing = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    missing = sorted(columns - existing)
    if missing:
        raise SystemExit(
            f"memory_candidate_resolve: missing columns in {table}: {', '.join(missing)}"
        )


def resolved_state(candidate_type: str, action: str) -> str:
    if action == "defer":
        return candidate_type
    if candidate_type == "stale_candidate":
        return "archived" if action == "approve" else "verified"
    if candidate_type == "obsidian_candidate":
        return "obsidian_promoted" if action == "approve" else "verified"
    return "archived"


def send_ntfy(repo_root: Path, message: str, dry_run: bool) -> None:
    if dry_run:
        print(f"ntfy_dry_run={message}")
        return
    subprocess.run(
        ["bash", str(repo_root / "scripts" / "ntfy.sh"), message],
        check=False,
    )


def verify_state(conn: sqlite3.Connection, event_id: str) -> str:
    row = conn.execute("SELECT state FROM events WHERE id = ?", (event_id,)).fetchone()
    if row is None:
        raise SystemExit(f"memory_candidate_resolve: event not found after update: {event_id}")
    return row["state"] or "raw"


def finalize_obsidian(
    repo_root: Path,
    db_path: Path,
    backup_dir: str,
    notes_dir: Path,
    event_id: str,
    reason: str,
    dry_run: bool,
) -> int:
    cmd = [
        "bash",
        str(repo_root / "scripts" / "obsidian_promote_finalize.sh"),
        "--db",
        str(db_path),
        "--notes-dir",
        str(notes_dir),
        "--event-id",
        event_id,
        "--reason",
        reason,
    ]
    if backup_dir:
        cmd.extend(["--backup-dir", backup_dir])
    if dry_run:
        cmd.append("--dry-run")
    result = subprocess.run(cmd, check=False, text=True, capture_output=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def main() -> int:
    repo_root = Path(sys.argv[1])
    state_module = load_state_module(repo_root)
    db_path = Path(sys.argv[2])
    backup_dir = sys.argv[3]
    notes_dir = Path(sys.argv[4])
    dry_run = sys.argv[5] == "1"
    candidate_type = sys.argv[6].strip()
    event_id = sys.argv[7].strip()
    action = sys.argv[8].strip()
    reason = sys.argv[9].strip()

    if candidate_type not in ALLOWED_CANDIDATE_TYPES:
        allowed = ", ".join(sorted(ALLOWED_CANDIDATE_TYPES))
        raise SystemExit(f"memory_candidate_resolve: invalid candidate_type: {candidate_type}; allowed: {allowed}")
    if action not in ALLOWED_ACTIONS:
        allowed = ", ".join(sorted(ALLOWED_ACTIONS))
        raise SystemExit(f"memory_candidate_resolve: invalid action: {action}; allowed: {allowed}")
    if not event_id:
        raise SystemExit("memory_candidate_resolve: event_id is required")
    if not reason:
        raise SystemExit("memory_candidate_resolve: reason is required")
    if not db_path.exists():
        raise SystemExit(f"memory_candidate_resolve: database not found: {db_path}")

    with sqlite3.connect(db_path) as conn:
        conn.row_factory = sqlite3.Row
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        require_columns(conn, "events", {"id", "state", "summary", "updated_at"})
        row = conn.execute(
            "SELECT id, state, summary FROM events WHERE id = ?",
            (event_id,),
        ).fetchone()
        if row is None:
            raise SystemExit(f"memory_candidate_resolve: event not found: {event_id}")
        current_state = row["state"] or "raw"
        if current_state != candidate_type:
            raise SystemExit(
                f"memory_candidate_resolve: state mismatch for {event_id}: "
                f"expected {candidate_type}, actual {current_state}"
            )

    new_state = resolved_state(candidate_type, action)
    transition_reason = f"{action}: {reason}"

    if dry_run:
        print(f"event_id={event_id}")
        print(f"candidate_type={candidate_type}")
        print(f"action={action}")
        print(f"from_state={candidate_type}")
        print(f"to_state={new_state}")
        print("dry_run=true")
        return 0

    if candidate_type == "obsidian_candidate" and action == "approve":
        rc = finalize_obsidian(repo_root, db_path, backup_dir, notes_dir, event_id, transition_reason, False)
        if rc != 0:
            return rc
        with sqlite3.connect(db_path) as conn:
            conn.row_factory = sqlite3.Row
            conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
            verified_state = verify_state(conn, event_id)
        if verified_state != new_state:
            raise SystemExit(
                f"memory_candidate_resolve: verification failed for {event_id}: "
                f"expected {new_state}, actual {verified_state}"
            )
        print(f"verified_state={verified_state}")
        send_ntfy(repo_root, f"【memory_candidate_resolve】{candidate_type} {event_id} {action} -> {new_state}", False)
        return 0

    with sqlite3.connect(db_path) as conn:
        conn.row_factory = sqlite3.Row
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        backup_path = state_module.create_sqlite_backup(
            str(db_path), backup_dir or None, f"candidate_resolve_{candidate_type}_{action}"
        )
        with conn:
            updated = state_module.update_event_state(
                conn,
                [event_id],
                new_state,
                transition_reason,
                "memory_candidate_resolve",
            )
        verified_state = verify_state(conn, event_id)
        if updated != 1 or verified_state != new_state:
            raise SystemExit(
                f"memory_candidate_resolve: verification failed for {event_id}: "
                f"updated={updated}, expected={new_state}, actual={verified_state}"
            )

    print(f"backup={backup_path}")
    print(f"updated=1")
    print(f"verified_state={verified_state}")
    send_ntfy(repo_root, f"【memory_candidate_resolve】{candidate_type} {event_id} {action} -> {new_state}", False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
