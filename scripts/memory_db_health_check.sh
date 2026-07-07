#!/usr/bin/env bash
# memory_db_health_check.sh — Check and lightly maintain the local memory DB.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
db_path="$script_dir/data/multi_agent_shogun_memory.db"
cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
backup_dir="$script_dir/data/backups"
apply=0
backup=0
quick_timeout=30
tmp_ttl_hours=6

usage() {
    cat <<'EOF' >&2
Usage: memory_db_health_check.sh [--apply] [--backup] [--db PATH] [--cache-dir DIR]
                                 [--backup-dir DIR] [--quick-timeout SEC] [--tmp-ttl-hours N]

Default mode is read-only. --apply runs safe maintenance:
  - WAL checkpoint(TRUNCATE) on the live DB
  - stale memory DB cache tmp cleanup via cleanup_three_layer_tmp.sh

--backup creates a SQLite backup with the backup API before checks.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) apply=1; shift ;;
        --backup) backup=1; shift ;;
        --db)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            db_path="$2"; shift 2 ;;
        --cache-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            cache_dir="$2"; shift 2 ;;
        --backup-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            backup_dir="$2"; shift 2 ;;
        --quick-timeout)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            quick_timeout="$2"; shift 2 ;;
        --tmp-ttl-hours)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            tmp_ttl_hours="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

case "$quick_timeout" in ''|*[!0-9]*) echo "ERROR: --quick-timeout must be an integer" >&2; exit 2 ;; esac
case "$tmp_ttl_hours" in ''|*[!0-9]*) echo "ERROR: --tmp-ttl-hours must be an integer" >&2; exit 2 ;; esac

if [ ! -f "$db_path" ]; then
    echo "memory_db_health: status=FAIL reason=db_not_found db=$db_path"
    exit 1
fi

cache_path_for() {
    python3 - "$script_dir" "$db_path" "$cache_dir" <<'PY'
import importlib.util
import os
import sys
repo_root, db_path, cache_dir = sys.argv[1:4]
os.environ["SHOGUN_MEMORY_DB_CACHE_DIR"] = cache_dir
module_path = os.path.join(repo_root, "scripts", "memory_db_live_insert.py")
spec = importlib.util.spec_from_file_location("memory_db_live_insert", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.memory_db_cache_path(db_path))
PY
}

create_backup() {
    python3 - "$db_path" "$backup_dir" <<'PY'
import datetime
import pathlib
import sqlite3
import sys
source = pathlib.Path(sys.argv[1])
backup_dir = pathlib.Path(sys.argv[2])
backup_dir.mkdir(parents=True, exist_ok=True)
stamp = datetime.datetime.now().strftime("%Y%m%dT%H%M%S")
dest = backup_dir / f"multi_agent_shogun_memory_health_{stamp}.db"
with sqlite3.connect(source) as src, sqlite3.connect(dest) as dst:
    src.backup(dst)
print(dest)
PY
}

# sqlite3 CLI不在環境(command -v sqlite3=不在)のためpython3のsqlite3モジュール経由にする。
# クエリ失敗時はここでexit 1し、呼び出し元の `var="$(sqlite_scalar ...)"` をset -eで
# 明示的に停止させる(無言の既定値へフォールバックしない)。
sqlite_scalar() {
    local target_db="$1"
    local sql="$2"
    python3 -c "
import sqlite3, sys
db_path, sql = sys.argv[1], sys.argv[2]
try:
    con = sqlite3.connect(db_path)
    row = con.execute(sql).fetchone()
    print(row[0] if row is not None else '')
except Exception as exc:
    print('ERROR:' + str(exc), file=sys.stderr)
    sys.exit(1)
" "$target_db" "$sql"
}

wal_checkpoint() {
    local target_db="$1"
    timeout 15 python3 -c "
import sqlite3, sys
db_path = sys.argv[1]
try:
    con = sqlite3.connect(db_path)
    con.execute('PRAGMA busy_timeout=1000')
    row = con.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()
    print('wal_checkpoint result=' + str(row))
except Exception as exc:
    print('ERROR:' + str(exc))
" "$target_db" 2>&1 || true
}

db_size="$(stat -c '%s' "$db_path")"
wal_size=0
[ -f "${db_path}-wal" ] && wal_size="$(stat -c '%s' "${db_path}-wal")"
shm_size=0
[ -f "${db_path}-shm" ] && shm_size="$(stat -c '%s' "${db_path}-shm")"

echo "memory_db_health: db=$db_path size_bytes=$db_size wal_bytes=$wal_size shm_bytes=$shm_size mode=$([ "$apply" -eq 1 ] && echo apply || echo check)"

if [ "$backup" -eq 1 ]; then
    backup_path="$(create_backup)"
    backup_size="$(stat -c '%s' "$backup_path")"
    echo "memory_db_health: backup=$backup_path size_bytes=$backup_size"
fi

if [ "$apply" -eq 1 ]; then
    checkpoint="$(wal_checkpoint "$db_path")"
    echo "memory_db_health: live_checkpoint=${checkpoint//$'\n'/;}"
    bash "$script_dir/scripts/cleanup_three_layer_tmp.sh" --apply --ttl-hours "$tmp_ttl_hours" --cache-dir "$cache_dir"
fi

events="$(sqlite_scalar "$db_path" "SELECT COUNT(*) FROM events;")"
event_concepts="$(sqlite_scalar "$db_path" "SELECT COUNT(*) FROM event_concepts;")"
event_links="$(sqlite_scalar "$db_path" "SELECT COUNT(*) FROM event_links;")"
page_count="$(sqlite_scalar "$db_path" "PRAGMA page_count;")"
page_size="$(sqlite_scalar "$db_path" "PRAGMA page_size;")"
echo "memory_db_health: events=$events event_concepts=$event_concepts event_links=$event_links page_count=$page_count page_size=$page_size"

cache_db="$(cache_path_for)"
if [ "$apply" -eq 1 ] && [ -f "$cache_db" ]; then
    cache_checkpoint="$(wal_checkpoint "$cache_db")"
    echo "memory_db_health: cache_checkpoint=${cache_checkpoint//$'\n'/;}"
fi
if [ -f "$cache_db" ]; then
    quick_target="$cache_db"
    quick_source="cache"
else
    quick_target="$db_path"
    quick_source="live"
fi

quick_result="$(timeout "$quick_timeout" python3 -c "
import sqlite3, sys
db_path = sys.argv[1]
try:
    con = sqlite3.connect(db_path)
    row = con.execute('PRAGMA quick_check').fetchone()
    print(row[0] if row else '')
except Exception as exc:
    print('ERROR:' + str(exc))
" "$quick_target" 2>&1 || true)"
if [ "$quick_result" != "ok" ]; then
    echo "memory_db_health: status=FAIL quick_check_source=$quick_source quick_check=${quick_result:-timeout_or_empty}"
    exit 1
fi
echo "memory_db_health: quick_check_source=$quick_source quick_check=ok"

if [ "$apply" -eq 1 ] && [ -f "$cache_db" ]; then
    final_cache_checkpoint="$(wal_checkpoint "$cache_db")"
    echo "memory_db_health: final_cache_checkpoint=${final_cache_checkpoint//$'\n'/;}"
fi

cache_size=0
[ -f "$cache_db" ] && cache_size="$(stat -c '%s' "$cache_db")"
cache_wal_size=0
[ -f "${cache_db}-wal" ] && cache_wal_size="$(stat -c '%s' "${cache_db}-wal")"
echo "memory_db_health: cache_db=$cache_db cache_size_bytes=$cache_size cache_wal_bytes=$cache_wal_size"
echo "memory_db_health: status=PASS"
