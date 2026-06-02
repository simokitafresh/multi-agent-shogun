#!/usr/bin/env bash
# Ensure operational shell scripts do not synchronously call memory_db_live_insert.py.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

violations="$(
    rg -n \
        -g '*.sh' \
        -g '!**/gate_memory_db_live_insert_async.sh' \
        'python3 .*memory_db_live_insert\.py|MEMORY_DB_LIVE_INSERT=.*memory_db_live_insert\.py|memory_db_live_insert\.py' \
        "$repo_root/scripts" \
        2>/dev/null || true
)"

if [ -n "$violations" ]; then
    echo "BLOCK: synchronous memory_db_live_insert.py calls are forbidden in shell scripts." >&2
    echo "Use scripts/memory_db_live_insert_async.py so operational YAML writes never wait on SQLite/NTFS locks." >&2
    printf '%s\n' "$violations" >&2
    exit 1
fi

echo "OK: memory_db live inserts use async wrapper"
