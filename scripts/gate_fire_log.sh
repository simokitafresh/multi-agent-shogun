#!/bin/bash
# gate_fire_log.sh — gate_fire_log.yaml 高速クエリユーティリティ
# Usage: bash scripts/gate_fire_log.sh
# 出力:  "healed=N fail_total=N fail_live=N"
# 最適化:
#   Before: Python起動+ファイル読込 + grep×2 + シェルループ = 3回読込
#   After:  awk 1パス(3統計同時計算) + mtimeキャッシュ(2回目以降<5ms)
# 呼出元: gate_gunshi_startup.sh Check 11

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${GATE_FIRE_LOG_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FIRE_LOG="${GATE_FIRE_LOG_FILE:-$SCRIPT_DIR/../logs/gate_fire_log.yaml}"
LIVE_REPORT_DIR="${GATE_FIRE_LOG_LIVE_REPORT_DIR:-$REPO_ROOT/queue/reports}"

if [ ! -f "$FIRE_LOG" ]; then
    printf 'healed=0 fail_total=0 fail_live=0\n'
    exit 0
fi

# --- mtimeキャッシュ: 同一ファイルの2回目以降はほぼゼロms ---
# 秒単位mtimeでは同一秒・同サイズ更新を見逃すため、ナノ秒mtime+path+sizeを署名に含める。
cache_sig=$(stat -c '%n:%y:%s' "$FIRE_LOG" 2>/dev/null || printf 'missing')
cache_key="${FIRE_LOG}_${cache_sig}"
cache_key="${cache_key//[^A-Za-z0-9_.-]/_}"
cache_tail="$cache_key"
if [ "${#cache_tail}" -gt 100 ]; then
    cache_tail="${cache_tail: -100}"
fi
cache_key="${#FIRE_LOG}_${cache_tail}"
cache_file="${GATE_FIRE_LOG_CACHE_DIR:-/tmp}/gate_fire_log_stats_${cache_key}"

if [ -f "$cache_file" ]; then
    cat "$cache_file"
    exit 0
fi

# --- awk 1パス: fail_total + healed + /mnt/c FAILパスを同時計算 ---
# 出力形式: 1行目="<fail_total> <healed>", 残行=FAILファイルパス
mapfile -t awk_lines < <(awk -v repo_root="$REPO_ROOT" -v live_report_dir="$LIVE_REPORT_DIR" '
function normalize_path(path) {
    if (path ~ /^\//) return path
    return repo_root "/" path
}
/result: FAIL/ { fail_total++ }
match($0, /file: "([^"]*)"/, f) {
    fname = normalize_path(f[1])
    if (match($0, /result: (FAIL|PASS)/, r)) {
        if (r[1] == "FAIL") {
            fails[fname] = 1
            pending_fail[fname] = 1
            if (index(fname, live_report_dir "/") == 1) { live_paths[fname] = 1 }
        } else if (r[1] == "PASS" && fname in pending_fail) {
            healed++
            delete pending_fail[fname]
            delete live_paths[fname]
        }
    }
}
END {
    printf "%d %d\n", fail_total+0, healed+0
    for (p in live_paths) { print p }
}
' "$FIRE_LOG")

# 1行目から fail_total, healed を取得
read -r fail_total healed <<< "${awk_lines[0]:-0 0}"
fail_total="${fail_total:-0}"
healed="${healed:-0}"

# 残行: FAILファイルパス → 存在チェック
fail_live=0
for path in "${awk_lines[@]:1}"; do
    [ -z "$path" ] && continue
    if [ -f "$path" ]; then (( fail_live++ )) || true; fi
done

output="healed=${healed} fail_total=${fail_total} fail_live=${fail_live}"
printf '%s\n' "$output"

# --- キャッシュ保存 ---
printf '%s\n' "$output" > "$cache_file"
