#!/usr/bin/env bash
# Ensure operational shell scripts do not synchronously call memory_db_live_insert.py.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
root_key="${repo_root//[^A-Za-z0-9._-]/_}"
cache_file="${TMPDIR:-/tmp}/gate_memory_db_live_insert_async_${root_key}.cache"
cache_ttl="${MEMORY_DB_LIVE_INSERT_GATE_CACHE_TTL:-2}"

if [[ "$cache_ttl" =~ ^[0-9]+$ && "$cache_ttl" -gt 0 && -f "$cache_file" ]]; then
    cache_mtime="$(stat -c '%Y' "$cache_file" 2>/dev/null || printf 0)"
    now="$(date +%s)"
    if (( now - cache_mtime < cache_ttl )); then
        IFS=' ' read -r _cached_signature cached_rc < "$cache_file" || true
        if [ -n "${cached_rc:-}" ]; then
            if [ "$cached_rc" -eq 0 ]; then
                tail -n +2 "$cache_file"
            else
                tail -n +2 "$cache_file" >&2
            fi
            exit "$cached_rc"
        fi
    fi
fi

signature="$(
    find "$repo_root/scripts" -type f -name '*.sh' -printf '%T@ %p\n' 2>/dev/null \
        | sort \
        | sha1sum \
        | awk '{print $1}'
)"

if [ -n "$signature" ] && [ -f "$cache_file" ]; then
    IFS=' ' read -r cached_signature cached_rc < "$cache_file" || true
    if [ "${cached_signature:-}" = "$signature" ] && [ -n "${cached_rc:-}" ]; then
        if [ "$cached_rc" -eq 0 ]; then
            tail -n +2 "$cache_file"
        else
            tail -n +2 "$cache_file" >&2
        fi
        exit "$cached_rc"
    fi
fi

violations="$(
    rg -n \
        -g '*.sh' \
        -g '!**/gate_memory_db_live_insert_async.sh' \
        -g '!**/gate_hot_path_no_sync_io.sh' \
        'python3 .*memory_db_live_insert\.py|MEMORY_DB_LIVE_INSERT=.*memory_db_live_insert\.py|memory_db_live_insert\.py' \
        "$repo_root/scripts" \
        2>/dev/null \
        | sort || true
)"

if [ -n "$violations" ]; then
    output="$(
        printf '%s\n' "BLOCK: synchronous memory_db_live_insert.py calls are forbidden in shell scripts."
        printf '%s\n' "Use scripts/memory_db_live_insert_async.py so operational YAML writes never wait on SQLite/NTFS locks."
        printf '%s\n' "$violations"
    )"
    if [ -n "$signature" ]; then
        {
            printf '%s %s\n' "$signature" 1
            printf '%s\n' "$output"
        } > "${cache_file}.$$" 2>/dev/null && mv "${cache_file}.$$" "$cache_file" 2>/dev/null || true
    fi
    printf '%s\n' "$output" >&2
    exit 1
fi

output="OK: memory_db live inserts use async wrapper"
if [ -n "$signature" ]; then
    {
        printf '%s %s\n' "$signature" 0
        printf '%s\n' "$output"
    } > "${cache_file}.$$" 2>/dev/null && mv "${cache_file}.$$" "$cache_file" 2>/dev/null || true
fi
printf '%s\n' "$output"
