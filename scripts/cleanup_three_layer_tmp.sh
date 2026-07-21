#!/usr/bin/env bash
# cleanup_three_layer_tmp.sh — Remove stale tmp files from the ext4 memory DB cache.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run=1
ttl_hours="${SHOGUN_THREE_LAYER_TMP_TTL_HOURS:-6}"
cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
max_bytes="${SHOGUN_THREE_LAYER_CACHE_MAX_BYTES:-5368709120}"
approve_over_10=0

usage() {
    cat <<'EOF' >&2
Usage: cleanup_three_layer_tmp.sh [--dry-run] [--apply] [--ttl-hours N] [--cache-dir DIR]
                                  [--max-bytes N] [--approve-over-10]

Deletes stale *.tmp files and completed orphan caches created from
.deploy-report-fast.<pid>.<random> roots.  Apply refuses more than 10 files
unless --approve-over-10 is supplied explicitly.
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
        --max-bytes)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            max_bytes="$2"; shift 2 ;;
        --approve-over-10) approve_over_10=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

case "$ttl_hours" in
    ''|*[!0-9]*) echo "ERROR: --ttl-hours must be a non-negative integer" >&2; exit 2 ;;
esac
case "$max_bytes" in
    ''|*[!0-9]*) echo "ERROR: --max-bytes must be a non-negative integer" >&2; exit 2 ;;
esac

if [ ! -d "$cache_dir" ]; then
    echo "tmp cleanup: cache_dir=$cache_dir exists=no candidates=0 bytes=0 mode=$([ "$dry_run" -eq 1 ] && echo dry-run || echo apply)"
    exit 0
fi

real_cache_dir="$(cd "$cache_dir" && pwd -P)"
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
# A cache key embeds the absolute project root with non-portable characters
# replaced by underscores.  Only the deploy_task-owned shape below is eligible;
# canonical, preflight, and unknown cache names cannot match it.
repo_key="${repo_root//[^A-Za-z0-9_.-]/_}"
deploy_prefix="${repo_key}_.deploy-report-fast."
mapfile -d '' tmp_candidates < <(
    find "$real_cache_dir" -maxdepth 1 -type f \
        \( -name '*.tmp' -o -name '.*.tmp' -o -name '*.tmp.*' -o -name '.*.tmp.*' -o -name '*.tmp-*' -o -name '.*.tmp-*' -o -name '_tmp_*' \) \
        ! -name "${repo_key}*multi_agent_shogun_memory.db*" -mmin +"$ttl_minutes" -print0
)
declare -A orphan_groups=()
declare -A protected_groups=()
while IFS= read -r -d '' path; do
    name="${path##*/}"
    rest="${name#"$deploy_prefix"}"
    [[ "$rest" =~ ^([0-9]+\.[0-9]+)_multi_agent_shogun_memory\.db(\.lock|\.refresh\.lock|-wal|-shm)?$ ]] || continue
    token="${BASH_REMATCH[1]}"
    deploy_root="$repo_root/.deploy-report-fast.$token"
    if [ -e "$deploy_root" ] || ! find "$path" -mmin +"$ttl_minutes" -print -quit | grep -q .; then
        protected_groups["$token"]=1
    else
        orphan_groups["$token"]=1
    fi
done < <(find "$real_cache_dir" -maxdepth 1 -type f -name "${deploy_prefix}*" -print0)

declare -A candidate_set=()
declare -A tmp_set=()
for path in "${tmp_candidates[@]}"; do
    candidate_set["$path"]=1
    tmp_set["$path"]=1
done
protected=0
for token in "${!protected_groups[@]}"; do
    while IFS= read -r -d '' path; do
        protected=$((protected + 1))
    done < <(find "$real_cache_dir" -maxdepth 1 -type f -name "${deploy_prefix}${token}_multi_agent_shogun_memory.db*" -print0)
done
for token in "${!orphan_groups[@]}"; do
    # If any member is live or inside the grace period, protect the whole group.
    [ -z "${protected_groups[$token]:-}" ] || continue
    while IFS= read -r -d '' path; do
        candidate_set["$path"]=1
    done < <(find "$real_cache_dir" -maxdepth 1 -type f -name "${deploy_prefix}${token}_multi_agent_shogun_memory.db*" -print0)
done
candidates=("${!candidate_set[@]}")

count="${#candidates[@]}"
bytes=0
[ "$count" -eq 0 ] || bytes="$(stat -c '%s' -- "${candidates[@]}" | awk '{s+=$1} END{print s+0}')"
total_bytes="$(find "$real_cache_dir" -maxdepth 1 -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')"

mode="apply"
[ "$dry_run" -eq 1 ] && mode="dry-run"
echo "tmp cleanup: cache_dir=$real_cache_dir ttl_hours=$ttl_hours candidates=$count bytes=$bytes protected=$protected total_bytes=$total_bytes max_bytes=$max_bytes mode=$mode"

if [ "$count" -eq 0 ] || [ "$dry_run" -eq 1 ]; then
    exit 0
fi

if [ "$count" -gt 10 ] && [ "$approve_over_10" -ne 1 ]; then
    echo "BLOCK: apply would delete $count files; rerun with --approve-over-10 after explicit approval" >&2
    exit 3
fi

# Stale *.tmp hygiene is unconditional.  Orphan deploy caches are reclaimed
# oldest group first; a DB and all of its sidecars are one cleanup unit.
deleted=0
for path in "${tmp_candidates[@]}"; do
    [ -f "$path" ] || continue
    size="$(stat -c '%s' -- "$path")"
    rm -f -- "$path"
    total_bytes=$((total_bytes - size))
    deleted=$((deleted + 1))
done

mapfile -t ordered_groups < <(
    for token in "${!orphan_groups[@]}"; do
        [ -z "${protected_groups[$token]:-}" ] || continue
        oldest="$(find "$real_cache_dir" -maxdepth 1 -type f \
            -name "${deploy_prefix}${token}_multi_agent_shogun_memory.db*" \
            -printf '%T@\n' | sort -n | head -1)"
        [ -z "$oldest" ] || printf '%s %s\n' "$oldest" "$token"
    done | sort -n
)
for record in "${ordered_groups[@]}"; do
    [ "$total_bytes" -gt "$max_bytes" ] || break
    token="${record#* }"
    while IFS= read -r -d '' path; do
        size="$(stat -c '%s' -- "$path")"
        rm -f -- "$path"
        total_bytes=$((total_bytes - size))
        deleted=$((deleted + 1))
    done < <(find "$real_cache_dir" -maxdepth 1 -type f \
        -name "${deploy_prefix}${token}_multi_agent_shogun_memory.db*" -print0)
done
echo "tmp cleanup: deleted=$deleted remaining_bytes=$total_bytes"
