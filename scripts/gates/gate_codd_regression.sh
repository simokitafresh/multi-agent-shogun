#!/usr/bin/env bash
# gate_codd_regression.sh — CoDD refactor registry regression check
# Usage: bash scripts/gates/gate_codd_regression.sh [registry_path]
# Exit 0: OK/WARN/SKIP (WARN-only, never BLOCK)
# Stdout: OK / WARN messages
#
# After > Before を台帳の最新エントリで検知し WARN を表示する。
# 5%の計測ノイズ許容閾値: after_ms > before_ms * 1.05 でのみ WARN。

set -euo pipefail

_self="${BASH_SOURCE[0]}"
SCRIPT_DIR="${_self%/*}"
[[ "$SCRIPT_DIR" != /* ]] && SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts/gates}"

REGISTRY="${1:-$REPO_ROOT/docs/research/codd_refactor_registry.md}"
LAST_N=10  # 最新N件をチェック

if [ ! -f "$REGISTRY" ]; then
    echo "SKIP: registry not found: $REGISTRY"
    exit 0
fi

# REGISTRY内の "→" を ASCII SOH (0x01) に変換してからawk処理
# (UTF-8の→を安全にフィールド分割するため)
LC_ALL=C sed 's/\xe2\x86\x92/\x01/g' "$REGISTRY" | awk -v last_n="$LAST_N" '

# タイミング文字列から最初の数値をms単位に変換
# 対応形式: Nms, N.Nms, Ns, N.Ns (先頭のバッククォート・チルダ・スペースは無視)
function first_ms(s,    tmp) {
    tmp = s
    gsub(/[`~( \t]/, " ", tmp)

    # まず Nms / N.Nms を探す
    if (match(tmp, /[0-9]+\.[0-9]+ms/)) {
        return substr(tmp, RSTART, RLENGTH - 2) + 0
    }
    if (match(tmp, /[0-9]+ms/)) {
        return substr(tmp, RSTART, RLENGTH - 2) + 0
    }
    # 次に N.Ns / Ns を探す
    if (match(tmp, /[0-9]+\.[0-9]+s/)) {
        return substr(tmp, RSTART, RLENGTH - 1) * 1000
    }
    if (match(tmp, /[0-9]+s/)) {
        return substr(tmp, RSTART, RLENGTH - 1) * 1000
    }
    return -1
}

# データ行: 日付列が YYYY- 形式で始まる行
/^\|[[:space:]]*[0-9][0-9][0-9][0-9]-/ {
    cols_n = split($0, cols, "|")
    if (cols_n < 7) next

    # col[4] = 対象スクリプト, col[6] = Before→After (→はSOHに置換済み)
    col4 = cols[4]; col6 = cols[6]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", col4)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", col6)

    # SOH (\x01) で分割
    n_parts = split(col6, parts, "\001")
    if (n_parts < 2) next

    before_str = parts[1]
    after_str  = parts[2]

    before_ms = first_ms(before_str)
    after_ms  = first_ms(after_str)

    if (before_ms <= 0 || after_ms < 0) next

    rows[++cnt] = col4 "\t" before_ms "\t" after_ms
}

END {
    warn_count = 0
    ok_count   = 0
    start = (cnt - last_n + 1 > 1) ? cnt - last_n + 1 : 1

    for (i = start; i <= cnt; i++) {
        split(rows[i], r, "\t")
        col4 = r[1]; bms = r[2] + 0; ams = r[3] + 0
        ok_count++
        # 5%の計測ノイズ許容: 5%超の悪化のみWARN
        if (ams > bms * 1.05) {
            pct = int((ams - bms) / bms * 100 + 0.5)
            printf "WARN: CoDD悪化検出 — %s: %.0fms → %.0fms (+%d%%)\n", col4, bms, ams, pct
            warn_count++
        }
    }

    if (warn_count > 0) {
        print "      revertして再改善。After > Beforeのエントリを台帳から修正/削除せよ"
    } else if (ok_count > 0) {
        printf "OK: 最新%d件 悪化なし (%d件チェック済み)\n", last_n, ok_count
    } else {
        print "SKIP: Before\001After形式のエントリなし (Before→After列が不明)"
    }
}
'
