#!/bin/bash
# gate_workaround_rate.sh — 直近N件のGATE CLEARedcmdsに対するworkaround率を計算
# Usage: bash scripts/gates/gate_workaround_rate.sh [--last N]
# 分母: gate_metrics.logのユニークCLEAR cmd数（直近N件）
# 分子: そのcmd群のうちkaro_workarounds.yamlにworkaround:trueがあるcmd数
# フォールバック: gate_metrics.log不在時はkaro_workarounds.yamlのエントリ数を分母に使用
# Output: OK/WARN/ALERT + WA率 + カテゴリ内訳
# 閾値: OK=<15%, WARN=15-30%, ALERT=>30%
# GATE判定には影響しない（情報表示のみ）
# 最適化(cmd_1970): python3+grep+awk3本 → awk1本に統合(-44%)
# 最適化(cmd_2092): BEGIN内getline from tac → gate_log処理21ms→3ms(-86%) 全体36ms→25ms(-31%)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WA_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
LAST_N=10

# 引数パース
while [ $# -gt 0 ]; do
    case "$1" in
        --last)
            LAST_N="${2:-10}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "■ Workaround率 (直近${LAST_N}件)"

if [ ! -f "$WA_FILE" ]; then
    echo "  SKIP: karo_workarounds.yaml不在"
    exit 0
fi

# gate_metrics.log が存在する場合:
#   BEGIN内でtacコマンドからgetlineし、末尾からN件ユニークCLEARを取得(~3ms)
#   その後karo_workarounds.yamlを1パスで処理(~15ms)
# 不在の場合: fallbackモード(karo_workarounds.yamlのみ処理)
if [ -f "$GATE_LOG" ]; then
    _HAS_GATE="true"
else
    _HAS_GATE="false"
fi

result=$(awk -v has_gate="$_HAS_GATE" -v gate_log="$GATE_LOG" -v last_n="$LAST_N" '
BEGIN {
    cur_cmd = ""; has_wa_field = 0; cur_wa = 0; cur_cat = "uncategorized"
    item_count = 0; clear_count = 0

    # gate_pathの場合: tacでgate_logを末尾から読みlast_n件ユニークCLEARを取得
    # N件見つかり次第breakし、tacにSIGPIPEを送ってI/Oを最小化
    if (has_gate == "true") {
        cmd = "tac \"" gate_log "\""
        while ((cmd | getline line) > 0) {
            n = split(line, f, "\t")
            if (f[3] == "CLEAR" && !seen_cl[f[2]]++) {
                clear_set[f[2]] = 1
                if (++clear_count >= last_n) break
            }
        }
        close(cmd)
    }
}

# karo_workarounds.yaml のエントリ先頭
/^- cmd_id:/ {
    flush_item()
    cur_cmd = $0
    sub(/^- cmd_id:[[:space:]]*/, "", cur_cmd)
    gsub(/["'"'"'[:space:]]/, "", cur_cmd)
    cur_wa = 0; cur_cat = "uncategorized"; has_wa_field = 0
}

/^  workaround:/ {
    val = $0
    sub(/^[[:space:]]*workaround:[[:space:]]*/, "", val)
    gsub(/["'"'"'[:space:]]/, "", val)
    cur_wa = (val == "true" || val == "yes") ? 1 : 0
    has_wa_field = 1
}

/^  category:/ {
    cur_cat = $0
    sub(/^[[:space:]]*category:[[:space:]]*["'"'"']?/, "", cur_cat)
    gsub(/["'"'"']$/, "", cur_cat)
    gsub(/[[:space:]]*$/, "", cur_cat)
    if (cur_cat == "") cur_cat = "uncategorized"
}

END {
    flush_item()

    if (has_gate == "true" && clear_count > 0) {
        # gate_metrics.logベース: 分母=CLEAR cmd数
        # 同一cmdに複数エントリある場合 workaround=trueが優先
        total = clear_count; wa_count = 0
        for (i = 0; i < item_count; i++) {
            cmd = item_cmd[i]
            if (cmd in clear_set && item_wa[i] && !(cmd in wa_seen_true)) {
                wa_seen_true[cmd] = 1
                wa_count++
                cats[item_cat[i]]++
            }
        }
        source = "gate_metrics"
    } else {
        # フォールバック: karo_workarounds.yamlの直近N件を分母に使用
        if (item_count == 0) { print "OK|0|0|0|none|no data"; exit }
        start_i = (item_count > last_n) ? item_count - last_n : 0
        total = item_count - start_i; wa_count = 0
        for (i = start_i; i < item_count; i++) {
            if (item_wa[i]) {
                wa_count++
                cats[item_cat[i]]++
            }
        }
        source = "fallback"
    }

    rate = (total > 0) ? wa_count / total * 100 : 0
    level = (rate < 15) ? "OK" : (rate <= 30) ? "WARN" : "ALERT"

    # カテゴリ内訳文字列を構築
    cat_str = ""
    for (cat in cats) {
        if (cat_str != "") cat_str = cat_str ", "
        cat_str = cat_str cat ":" cats[cat]
    }
    if (cat_str == "") cat_str = "none"

    printf "%s|%.0f|%d|%d|%s|%s\n", level, rate, wa_count, total, cat_str, source
}

function flush_item() {
    if (cur_cmd != "" && has_wa_field) {
        item_cmd[item_count] = cur_cmd
        item_wa[item_count]  = cur_wa
        item_cat[item_count] = cur_cat
        item_count++
    }
    cur_cmd = ""; has_wa_field = 0
}
' "$WA_FILE" 2>/dev/null || echo "ERROR|0|0|0|awk_error|unknown")

IFS='|' read -r LEVEL RATE WA_COUNT TOTAL CATS SOURCE <<< "$result"

echo "  WA率: ${RATE}% (${WA_COUNT}/${TOTAL}件) — ${LEVEL}"
if [ -n "$SOURCE" ] && [ "$SOURCE" = "fallback" ]; then
    echo "  (gate_metrics.log不在のためkaro_workaroundsエントリ数をフォールバック分母に使用)"
fi
if [ "$WA_COUNT" -gt 0 ] && [ -n "$CATS" ] && [ "$CATS" != "none" ]; then
    echo "  カテゴリ内訳: ${CATS}"
fi

if [ "$LEVEL" = "ALERT" ]; then
    echo "  ⚠ ALERT: workaround率が30%超過。構造的問題の可能性"
elif [ "$LEVEL" = "WARN" ]; then
    echo "  注意: workaround率が15-30%。傾向監視を推奨"
fi
