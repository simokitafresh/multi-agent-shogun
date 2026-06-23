#!/usr/bin/env bash
# semantic-links: [[学習ループ]], [[免疫系]], [[三層学習ループ]]
# gate_immunity_depth.sh — 免疫系の深度計測(6観点)
# 殿指示(2026-06-23): 既存計測で見えない穴を計測する
# 観点: (1)免疫多様性 (2)免疫速度 (3)初見対応力 (4)成長加速度 (5)因果到達距離 (6)第二層往復
# Usage: bash scripts/gates/gate_immunity_depth.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$SCRIPT_DIR"

echo "=== 免疫系深度計測 ($(date +%Y-%m-%dT%H:%M:%S)) ==="

# --- 観点1: 免疫多様性 (gate種別ごとのFAIL→PASS内訳) ---
echo ""
echo "■ 観点1: 免疫多様性 (gate種別FAIL内訳)"
GATE_LOG="logs/gate_metrics.log"
if [ -f "$GATE_LOG" ]; then
    echo "  gate種別BLOCK件数 (上位10):"
    awk -F'\t' '$3 == "BLOCK" {
        reason=$4; gsub(/\|.*/, "", reason)
        counts[reason]++
    } END {
        for (r in counts) printf "    %4d  %s\n", counts[r], r
    }' "$GATE_LOG" | sort -rn | head -10
    TOTAL_GATE=$(wc -l < "$GATE_LOG")
    FAIL_GATE=$(awk -F'\t' '$3 == "BLOCK"' "$GATE_LOG" | wc -l)
    UNIQUE_FAIL=$(awk -F'\t' '$3 == "BLOCK" {
        reason=$4; gsub(/\|.*/, "", reason)
        seen[reason]=1
    } END { print length(seen) }' "$GATE_LOG")
    echo "  総gate: ${TOTAL_GATE} / FAIL: ${FAIL_GATE} / 種類: ${UNIQUE_FAIL}"
    if [ "$UNIQUE_FAIL" -le 3 ]; then
        echo "  ★ WARN: FAIL種類${UNIQUE_FAIL}種のみ。免疫が偏っている"
    else
        echo "  OK: ${UNIQUE_FAIL}種類の多様な免疫"
    fi
else
    echo "  SKIP: gate_metrics.logなし"
fi

# --- 観点2: 免疫速度 (FAIL→同一cmd LGTM到達時間) ---
echo ""
echo "■ 観点2: 免疫速度 (FAIL→LGTM回復時間)"
if [ -f logs/gunshi_review_log.yaml ]; then
    # FAIL cmdごとに最初のFAIL timestamp と最初のLGTM timestampの差分を計算
    awk '
    /^- cmd_id:/ { cmd=$3 }
    /verdict: FAIL/ && cmd { fail_ts[cmd] = last_ts }
    /verdict: LGTM/ && cmd && (cmd in fail_ts) && !(cmd in recovered) {
        recovered[cmd] = last_ts
    }
    /timestamp:/ { gsub(/"/, "", $2); last_ts = $2 }
    END {
        n = 0
        for (c in recovered) {
            printf "    %s: FAIL→LGTM\n", c
            n++
        }
        printf "  FAIL→LGTM回復: %d件 / 未回復FAIL: %d件\n", n, length(fail_ts) - n
    }
    ' logs/gunshi_review_log.yaml
fi

# --- 観点3: 初見対応力 (gate種別の初回FAIL月) ---
echo ""
echo "■ 観点3: 初見対応力 (新種FAIL出現の時系列)"
if [ -f "$GATE_LOG" ]; then
    echo "  新種FAIL初出月:"
    awk -F'\t' '$3 == "BLOCK" {
        reason=$4; gsub(/\|.*/, "", reason)
        month=substr($1,1,7)
        if (!(reason in first)) first[reason] = month
    } END {
        for (r in first) printf "    %s  %s\n", first[r], r
    }' "$GATE_LOG" | sort | tail -10
fi

# --- 観点4: 成長加速度 (月別FAIL発火数推移) ---
echo ""
echo "■ 観点4: 成長加速度 (月別FAIL発火数)"
if [ -f "$GATE_LOG" ]; then
    awk -F'\t' '$3 == "BLOCK" {
        month=substr($1,1,7); counts[month]++
    } END {
        for (m in counts) printf "    %s: %d件\n", m, counts[m]
    }' "$GATE_LOG" | sort
fi

# --- 観点5: 教訓→FAIL防止の因果到達 ---
echo ""
echo "■ 観点5: 教訓因果到達 (教訓数 vs 自動化enforcement有無)"
if [ -f projects/infra/lessons_gunshi.yaml ]; then
    TOTAL_L=$(grep -c '^- id: LG' projects/infra/lessons_gunshi.yaml 2>/dev/null || echo 0)
    AUTO_L=$(grep -c 'automated: true' projects/infra/lessons_gunshi.yaml 2>/dev/null || echo 0)
    ENFORCE_L=$(grep -c 'enforcement:' projects/infra/lessons_gunshi.yaml 2>/dev/null || echo 0)
    echo "  軍師教訓: ${TOTAL_L}件 / automated: ${AUTO_L}件 / enforcement記載: ${ENFORCE_L}件"
    if [ "$AUTO_L" -eq "$TOTAL_L" ] && [ "$TOTAL_L" -gt 0 ]; then
        echo "  OK: 全教訓automated"
    else
        echo "  WARN: automated未完 $((TOTAL_L - AUTO_L))件"
    fi
fi

# --- 観点6: 第二層往復 (RC→同一cmdのverify/APPROVE対応付け) ---
echo ""
echo "■ 観点6: 第二層往復 (RC→解決の対応付け)"
if [ -f logs/gunshi_review_log.yaml ]; then
    # cmd_idごとにRC→その後のverify/APPROVEを対応付け
    awk '
    /^- cmd_id:/ { cmd=$3 }
    /verdict: REQUEST_CHANGES/ && cmd { rc[cmd]++ }
    /verdict: APPROVE/ && cmd && (cmd in rc) && !(cmd in resolved) { resolved[cmd] = "APPROVE" }
    /review_type: verify/ && cmd && (cmd in rc) && !(cmd in resolved) { resolved[cmd] = "VERIFY" }
    END {
        rc_total = length(rc)
        resolved_total = length(resolved)
        printf "  RC発行cmd: %d件\n", rc_total
        for (c in rc) {
            status = (c in resolved) ? resolved[c] : "UNRESOLVED"
            printf "    %s: RC→%s\n", c, status
        }
        if (rc_total > 0) {
            printf "  RC解決率: %d/%d (%d%%)\n", resolved_total, rc_total, (resolved_total * 100 / rc_total)
        }
    }
    ' logs/gunshi_review_log.yaml
fi

echo ""
echo "=== 深度計測完了 ==="
