#!/usr/bin/env bash
# cleanup_three_layer_tmp.sh — Remove stale tmp files from the ext4 memory DB cache.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run=1
ttl_hours="${SHOGUN_THREE_LAYER_TMP_TTL_HOURS:-24}"
cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"

usage() {
    cat <<'EOF' >&2
Usage: cleanup_three_layer_tmp.sh [--dry-run] [--apply] [--ttl-hours N] [--cache-dir DIR]

Deletes only stale temporary files directly under the memory DB ext4 cache dir.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1; shift ;;
        --apply) dry_run=0; shift ;;
        --ttl-hours)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            ttl_hours="$2"; shift 2 ;;
        --cache-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            cache_dir="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

case "$ttl_hours" in
    ''|*[!0-9]*) echo "ERROR: --ttl-hours must be a non-negative integer" >&2; exit 2 ;;
esac

if [ ! -d "$cache_dir" ]; then
    echo "tmp cleanup: cache_dir=$cache_dir exists=no candidates=0 bytes=0 mode=$([ "$dry_run" -eq 1 ] && echo dry-run || echo apply)"
    exit 0
fi

real_cache_dir="$(realpath -m "$cache_dir")"
case "$real_cache_dir" in
    /|/home|/home/*|/mnt/c|/mnt/c/Windows|/mnt/c/Windows/*|/mnt/c/Users|/mnt/c/Users/*|/mnt/c/Program\ Files|/mnt/c/Program\ Files/*)
        echo "ERROR: unsafe cleanup cache_dir: $real_cache_dir" >&2
        exit 2
        ;;
esac
if [[ "$real_cache_dir" == /mnt/c/* && "${SHOGUN_THREE_LAYER_CLEANUP_ALLOW_NTFS:-0}" != "1" ]]; then
    echo "ERROR: refusing tmp cleanup under /mnt/c without SHOGUN_THREE_LAYER_CLEANUP_ALLOW_NTFS=1: $real_cache_dir" >&2
    exit 2
fi

ttl_minutes=$((ttl_hours * 60))
mapfile -d '' candidates < <(
    find "$real_cache_dir" -maxdepth 1 -type f \
        \( -name '*.tmp' -o -name '.*.tmp' -o -name '*.tmp.*' \) \
        -mmin +"$ttl_minutes" -print0
)

count="${#candidates[@]}"
bytes=0
for path in "${candidates[@]}"; do
    size="$(stat -c '%s' "$path" 2>/dev/null || echo 0)"
    bytes=$((bytes + size))
done

mode="apply"
[ "$dry_run" -eq 1 ] && mode="dry-run"
echo "tmp cleanup: cache_dir=$real_cache_dir ttl_hours=$ttl_hours candidates=$count bytes=$bytes mode=$mode"

if [ "$count" -eq 0 ] || [ "$dry_run" -eq 1 ]; then
    exit 0
fi

for path in "${candidates[@]}"; do
    rm -f -- "$path"
done
echo "tmp cleanup: deleted=$count"
