#!/usr/bin/env bash
# gate_three_layer_health.sh — Three-layer memory cache capacity and tmp hygiene gate.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
db_path="${SHOGUN_MEMORY_DB:-$repo_root/data/multi_agent_shogun_memory.db}"
warn_bytes="${SHOGUN_THREE_LAYER_CACHE_WARN_BYTES:-10737418240}"
cleanup_script="$repo_root/scripts/cleanup_three_layer_tmp.sh"
overall="PASS"

cache_path="$(
    python3 - "$db_path" "$repo_root" <<'PY' 2>/dev/null || true
import sys

db_path = sys.argv[1]
repo_root = sys.argv[2]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

print(live_insert.memory_db_cache_path(db_path))
PY
)"
cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
[ -n "$cache_path" ] && cache_dir="$(dirname "$cache_path")"

echo "=== three-layer memory health ==="
echo "db_path=$db_path"
echo "cache_path=${cache_path:-unknown}"

echo "■ cache容量チェック"
if [ -d "$cache_dir" ]; then
    cache_bytes="$(du -sb "$cache_dir" 2>/dev/null | awk '{print $1+0}')"
else
    cache_bytes=0
fi
echo "cache_dir=$cache_dir bytes=$cache_bytes warn_bytes=$warn_bytes"
if [ "$cache_bytes" -gt "$warn_bytes" ]; then
    echo "WARN: cache容量が閾値を超過。cleanup dry-runで対象を確認せよ。"
    overall="WARN"
else
    echo "OK: cache容量は閾値内"
fi

echo "■ tmp残骸cleanup dry-run"
if [ -x "$cleanup_script" ]; then
    bash "$cleanup_script" --dry-run --cache-dir "$cache_dir"
else
    echo "WARN: cleanup script not executable: $cleanup_script"
    overall="WARN"
fi

echo "STATUS: $overall"
[ "$overall" = "PASS" ] && exit 0
exit 2
