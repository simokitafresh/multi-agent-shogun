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
FIRE_LOG="${GATE_FIRE_LOG_FILE:-$SCRIPT_DIR/../logs/gate_fire_log.yaml}"

if [ ! -f "$FIRE_LOG" ]; then
    printf 'healed=0 fail_total=0 fail_live=0\n'
    exit 0
fi

# --- mtimeキャッシュ: 同一ファイルの2回目以降はほぼゼロms ---
mtime=$(stat -c '%Y' "$FIRE_LOG" 2>/dev/null || printf '0')
cache_file="/tmp/gate_fire_log_stats_${mtime}"

if [ -f "$cache_file" ]; then
    cat "$cache_file"
    exit 0
fi

# --- awk 1パス: fail_total + healed + /mnt/c FAILパスを同時計算 ---
# 出力形式: 1行目="<fail_total> <healed>", 残行=FAILファイルパス
tmp_awk=$(mktemp /tmp/gate_fire_log_awk.XXXXXX)
awk '
/result: FAIL/ { fail_total++ }
match($0, /file: "([^"]*)"/, f) {
    fname = f[1]
    if (match($0, /result: (FAIL|PASS)/, r)) {
        if (r[1] == "FAIL") {
            fails[fname] = 1
            if (fname ~ /^\/mnt\/c/) { live_paths[fname] = 1 }
        } else if (r[1] == "PASS" && fname in fails) {
            healed++
        }
    }
}
END {
    printf "%d %d\n", fail_total+0, healed+0
    for (p in live_paths) { print p }
}
' "$FIRE_LOG" > "$tmp_awk"

# 1行目から fail_total, healed を取得
read -r fail_total healed < "$tmp_awk"
fail_total="${fail_total:-0}"
healed="${healed:-0}"

# 残行: FAILファイルパス → 存在チェック
fail_live=0
while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ -f "$path" ]; then (( fail_live++ )) || true; fi
done < <(tail -n +2 "$tmp_awk")
rm -f "$tmp_awk" 2>/dev/null || true

output="healed=${healed} fail_total=${fail_total} fail_live=${fail_live}"
printf '%s\n' "$output"

# --- キャッシュ保存 ---
rm -f /tmp/gate_fire_log_stats_* 2>/dev/null || true
printf '%s\n' "$output" > "$cache_file"
