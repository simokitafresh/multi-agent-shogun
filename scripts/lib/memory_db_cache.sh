#!/usr/bin/env bash
# semantic-links: [[ローカル記憶DB]]
# scripts/lib/memory_db_cache.sh — data/multi_agent_shogun_memory.db 読取用ext4キャッシュ解決の共通実装
#
# WSL2 /mnt/c(9pファイルシステム)上でのSQLite random row I/O(行本体を読むSELECT)は
# ext4(/tmp)上の同一クエリと比べ約40倍遅い(COUNT(*)のみのインデックスカバークエリは差が小さい)。
# 既存のmemory_db_query.shが持つ「ext4キャッシュ + mtime/WAL鮮度判定 + 非同期リフレッシュ +
# 初回タイムアウトfail-safe」を全呼び出し元で共有し、独自複製を防ぐ。
# (cmd_karo_hotfix_infra_ops_speed_awaken_202607120130で抽出。呼び出し元: memory_db_query.sh, loop_ledger_update.sh)
#
# Usage:
#   source scripts/lib/memory_db_cache.sh
#   read_path="$(prepare_memory_db_for_read "$repo_root" "$source_db_path" ["$default_db_path"])"
#
# prepare_memory_db_for_read <repo_root> <source_db_path> [<default_db_path>]
#   ext4キャッシュが新鮮/構築可能ならそのパスを、そうでなければ<source_db_path>をstdoutへ印字する(fail-safe)。
#   <default_db_path>を渡すと、<source_db_path>がそれと一致しない限りキャッシュを使わない
#   (SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT=1で強制有効化可能)。テスト用DB等の巻き添えキャッシュ生成を防ぐ。

# Include guard
[[ -n "${_MEMORY_DB_CACHE_LOADED:-}" ]] && return 0
_MEMORY_DB_CACHE_LOADED=1

memory_db_cache_path() {
    local repo_root="$1" source_path="$2"
    python3 - "$source_path" "$repo_root" <<'PY'
import sys

db_path = sys.argv[1]
repo_root = sys.argv[2]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

print(live_insert.memory_db_cache_path(db_path))
PY
}

create_memory_db_cache() {
    local repo_root="$1" source_path="$2"
    python3 - "$source_path" "$repo_root" <<'PY'
import sys

db_path = sys.argv[1]
repo_root = sys.argv[2]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

live_insert.create_memory_db_ext4_cache(db_path)
PY
}

refresh_memory_db_cache_async() {
    local repo_root="$1"
    local source_path="$2"
    local cache_path="$3"
    local timeout_sec="${SHOGUN_MEMORY_DB_CACHE_REFRESH_TIMEOUT:-60}"
    export -f create_memory_db_cache
    (
        flock -n 8 2>/dev/null || exit 0
        if command -v timeout >/dev/null 2>&1; then
            # shellcheck disable=SC2016 # $1/$2 are intentionally expanded by bash -c.
            timeout -k 1 "$timeout_sec" bash -c 'create_memory_db_cache "$1" "$2"' _ "$repo_root" "$source_path" >/dev/null 2>&1 || true
        else
            create_memory_db_cache "$repo_root" "$source_path" >/dev/null 2>&1 || true
        fi
    ) 8>"${cache_path}.refresh.lock" >/dev/null 2>&1 </dev/null &
}

# warm_memory_db_cache_async <repo_root> <source_path>
# 起動フローから呼ぶ非同期warm-up入口。refreshと同じlockを使うため、複数の
# 起動フローや初回readが重なってもcache生成は常にsingle-flightになる。
warm_memory_db_cache_async() {
    local repo_root="$1"
    local source_path="$2"
    local cache_path

    [ -f "$source_path" ] || return 0
    cache_path="$(memory_db_cache_path "$repo_root" "$source_path" 2>/dev/null || true)"
    [ -n "$cache_path" ] || return 0
    refresh_memory_db_cache_async "$repo_root" "$source_path" "$cache_path"
}

notify_memory_db_cache_timeout() {
    local repo_root="$1"
    local timeout_sec="$2"
    if [ -x "$repo_root/scripts/ntfy.sh" ]; then
        bash "$repo_root/scripts/ntfy.sh" "【memory_db_cache】ext4 cache初期生成が${timeout_sec}sを超過。正本DBへfallback。" >/dev/null 2>&1 || true
    fi
}

prepare_memory_db_for_read() {
    local repo_root="$1"
    local source_path="$2"
    local default_path="${3:-}"

    if [ "${SHOGUN_MEMORY_DB_QUERY_DISABLE_CACHE:-0}" = "1" ] || [ "${SHOGUN_DISABLE_MEMORY_DB_CACHE:-0}" = "1" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi
    if [ ! -f "$source_path" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi
    if [ -n "$default_path" ] && [ "$source_path" != "$default_path" ] \
        && [ "${SHOGUN_MEMORY_DB_QUERY_CACHE_NONDEFAULT:-0}" != "1" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi

    local cache_path timeout_sec rc
    cache_path="$(memory_db_cache_path "$repo_root" "$source_path" 2>/dev/null || true)"
    if [ -z "$cache_path" ]; then
        printf '%s\n' "$source_path"
        return 0
    fi
    if [ -s "$cache_path" ]; then
        if [ "$source_path" -nt "$cache_path" ] \
            || { [ -f "${source_path}-wal" ] && [ "${source_path}-wal" -nt "$cache_path" ]; } \
            || { [ -f "${source_path}-shm" ] && [ "${source_path}-shm" -nt "$cache_path" ]; }; then
            refresh_memory_db_cache_async "$repo_root" "$source_path" "$cache_path"
        fi
        printf '%s\n' "$cache_path"
        return 0
    fi

    timeout_sec="${SHOGUN_MEMORY_DB_CACHE_INIT_TIMEOUT:-30}"
    rc=0
    # async warm-upと同じlockを非blocking取得する。warm-upが既に生成中なら
    # 待たずに正本へfallbackし、二重生成と初回read遅延をともに防ぐ。
    if command -v timeout >/dev/null 2>&1; then
        export -f create_memory_db_cache
        # shellcheck disable=SC2016 # $1/$2 are intentionally expanded by bash -c.
        timeout -k 1 "$timeout_sec" bash -c \
            'flock -n 8 2>/dev/null || exit 75; create_memory_db_cache "$1" "$2"' \
            _ "$repo_root" "$source_path" 8>"${cache_path}.refresh.lock" 2>/dev/null || rc=$?
    else
        { flock -n 8 2>/dev/null || exit 75; create_memory_db_cache "$repo_root" "$source_path"; } \
            8>"${cache_path}.refresh.lock" 2>/dev/null || rc=$?
    fi
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
        notify_memory_db_cache_timeout "$repo_root" "$timeout_sec"
    fi
    if [ "$rc" -eq 0 ] && [ -s "$cache_path" ]; then
        printf '%s\n' "$cache_path"
    else
        printf '%s\n' "$source_path"
    fi
}
