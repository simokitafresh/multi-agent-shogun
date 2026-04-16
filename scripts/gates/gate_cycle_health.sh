#!/usr/bin/env bash
# gate_cycle_health.sh — サイクル停滞検知heartbeat
# 「気づきを止めた瞬間に進化が止まる」を自動化×強制
# Usage: bash scripts/gates/gate_cycle_health.sh
#   /loop対応: /loop 30m bash scripts/gates/gate_cycle_health.sh
# @source: cmd_1494セッション(CoDD→なぜなぜ→L-CycleNeverStop)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

ALERTS=()
INFOS=()
INSIGHT_COUNT=0
IDLE_COUNT=0
IDLE_NAMES=""
PI_RATIO="?"

# --- 1. 未消化insights aging check (resolved除外) ---
if [ -f queue/insights.yaml ]; then
    TOTAL_INSIGHTS=$(grep -c "^- " queue/insights.yaml 2>/dev/null) || TOTAL_INSIGHTS=0
    RESOLVED=$(grep -c "status: resolved" queue/insights.yaml 2>/dev/null) || RESOLVED=0
    INSIGHT_COUNT=$((TOTAL_INSIGHTS - RESOLVED))
    if [ "$INSIGHT_COUNT" -gt 15 ]; then
        ALERTS+=("insights: ${INSIGHT_COUNT}件未消化(閾値15, resolved除外)。気づきが行動に変わっていない")
    elif [ "$INSIGHT_COUNT" -gt 5 ]; then
        INFOS+=("insights: ${INSIGHT_COUNT}件(正常範囲, resolved除外)")
    fi
fi

# --- 2. idle忍者 check (稼働可能な手が遊んでいる) ---
if [ -f queue/karo_snapshot.txt ]; then
    IDLE_LINE=$(grep "^idle|" queue/karo_snapshot.txt 2>/dev/null || echo "")
    if [ -n "$IDLE_LINE" ]; then
        IDLE_NAMES=$(echo "$IDLE_LINE" | cut -d'|' -f2)
        IDLE_COUNT=$(echo "$IDLE_NAMES" | tr ',' '\n' | grep -c . 2>/dev/null) || IDLE_COUNT=0
        if [ "$IDLE_COUNT" -ge 4 ]; then
            ALERTS+=("idle忍者: ${IDLE_COUNT}名(${IDLE_NAMES})。手が遊んでいる=進化が止まっている")
        elif [ "$IDLE_COUNT" -ge 2 ]; then
            INFOS+=("idle忍者: ${IDLE_COUNT}名(${IDLE_NAMES})")
        fi
    fi
fi

# --- 3. 完了報告GATE未処理 check (24h以内, CLEAR済み除外) ---
PENDING_REPORTS=0
NOW=$(date +%s)
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
# Optimized: glob+stat一括+awk単一パス(getline) (cmd_1982)
# find(10ms)+xargs stat 25files(28ms)+xargs grep-l(25ms) → glob stat(8ms)+awk+getline(5ms)
_CUTOFF=$((NOW - 86400))
_CLEARED_IDS=""
if [ -f "$GATE_LOG" ]; then
    # B2: grep+grep-oE+sort 1パイプライン (echo subshell廃止)
    _CLEARED_IDS=$(grep $'\tCLEAR' "$GATE_LOG" 2>/dev/null | grep -oE 'cmd_[a-zA-Z0-9_]+' | sort -u || true)
fi
# B1: bash glob + stat一括 + awk単一パス(cleared/cutoff/status check with getline)
shopt -s nullglob
_REPORT_FILES=( queue/reports/*_report_*.yaml )
shopt -u nullglob
if [ ${#_REPORT_FILES[@]} -gt 0 ]; then
    PENDING_REPORTS=$(stat -c '%Y %n' "${_REPORT_FILES[@]}" 2>/dev/null \
        | awk -v cids="$_CLEARED_IDS" -v cutoff="$_CUTOFF" '
            BEGIN{n=split(cids,c,"\n");for(i=1;i<=n;i++)clr[c[i]]=1}
            {
                mtime=$1; path=$2
                fname=path; sub(".*/","",fname)
                sub(".*_report_","",fname); sub("\\.yaml$","",fname); sub("_[a-z]*$","",fname)
                if(clr[fname]) next
                if(mtime+0 <= cutoff+0) next
                while ((getline line < path) > 0) {
                    if(line ~ /^status: completed/) { count++; break }
                }
                close(path)
            }
            END{print count+0}
        ')
fi
if [ "$PENDING_REPORTS" -gt 3 ]; then
    ALERTS+=("GATE未処理報告: ${PENDING_REPORTS}件(24h以内)。成果が還流されていない")
elif [ "$PENDING_REPORTS" -gt 0 ]; then
    INFOS+=("GATE未処理報告: ${PENDING_REPORTS}件(24h以内)")
fi

# --- 4. PI原理率 check ---
if [ -f projects/dm-signal.yaml ]; then
    # Optimized: python3(80ms) → awk(6ms) cmd_1955
    PI_RATIO=$(awk '
    /^  entries:/{in_pi=1; next}
    in_pi && /^    - /{found++}
    in_pi && /implication:/ && /全て|原理|適用される|信頼境界|任意の/{principle++}
    /^[^ ]/{if(in_pi) in_pi=0}
    END{
        if(found>0) printf "%d\n", 100*principle/found
        else print "0"
    }
    ' projects/dm-signal.yaml 2>/dev/null || echo "?")
    if [ "$PI_RATIO" != "?" ] && [ "$PI_RATIO" -lt 20 ]; then
        ALERTS+=("PI原理率: ${PI_RATIO}%。個別防御に偏っている(原理=1対N防御)")
    else
        INFOS+=("PI原理率: ${PI_RATIO}%")
    fi
fi

# --- 5. 自動強制アクション(意志依存排除) ---
# クールダウン: 同一nudgeは30分以内に再送しない
COOLDOWN_FILE="/tmp/cycle_health_cooldown"
COOLDOWN_SEC=1800
can_nudge() {
    local key="$1"
    if [ -f "$COOLDOWN_FILE" ]; then
        local last
        last=$(grep "^${key}:" "$COOLDOWN_FILE" 2>/dev/null | cut -d: -f2 || echo 0)
        if [ -n "$last" ] && [ $((NOW - last)) -lt $COOLDOWN_SEC ]; then
            return 1
        fi
    fi
    return 0
}
mark_nudge() {
    local key="$1"
    if [ -f "$COOLDOWN_FILE" ]; then
        grep -v "^${key}:" "$COOLDOWN_FILE" > "${COOLDOWN_FILE}.tmp" 2>/dev/null || true
        mv "${COOLDOWN_FILE}.tmp" "$COOLDOWN_FILE"
    fi
    echo "${key}:${NOW}" >> "$COOLDOWN_FILE"
}

FORCED=()
MANUAL=()

# 強制: idle忍者+GATE未処理 → 家老に自動nudge(クールダウン付き)
if [ "$IDLE_COUNT" -ge 4 ] && [ "$PENDING_REPORTS" -gt 3 ]; then
    if can_nudge "karo_idle_gate"; then
        if bash scripts/inbox_write.sh karo \
            "【自動】heartbeat ALERT: idle忍者${IDLE_COUNT}名+GATE未処理${PENDING_REPORTS}件。報告処理→配備を急げ。" \
            cycle_health shogun 2>/dev/null; then
            mark_nudge "karo_idle_gate"
            FORCED+=("家老にnudge自動送信済み(idle${IDLE_COUNT}+GATE${PENDING_REPORTS})")
        fi
    else
        FORCED+=("家老nudge: クールダウン中(30分間隔)")
    fi
fi

# 強制: ntfy通知(殿に状況を伝える)
if [ ${#ALERTS[@]} -ge 3 ]; then
    if can_nudge "ntfy_alert"; then
        if bash scripts/ntfy.sh "heartbeat: ${#ALERTS[@]}件ALERT(idle${IDLE_COUNT}/insights${INSIGHT_COUNT}/reports${PENDING_REPORTS}/PI${PI_RATIO}%)" 2>/dev/null; then
            mark_nudge "ntfy_alert"
            FORCED+=("ntfy通知送信済み")
        fi
    fi
fi

# 将軍判断が必要なもの(0が目標。0でない限り表示し続ける=閾値で満足させない)
if [ "$INSIGHT_COUNT" -gt 0 ]; then
    MANUAL+=("insights ${INSIGHT_COUNT}→0へ: queue/insights.yamlの未解決を処理 or cmd起票")
fi
if [ "$IDLE_COUNT" -gt 0 ]; then
    MANUAL+=("idle忍者 ${IDLE_COUNT}→0へ: cmdを起票して全員稼働させろ")
fi
if [ "$PENDING_REPORTS" -gt 0 ]; then
    MANUAL+=("GATE未処理 ${PENDING_REPORTS}→0へ: 家老の処理を加速させろ")
fi
if [ "$PI_RATIO" != "?" ] && [ "$PI_RATIO" -lt 100 ] 2>/dev/null; then
    MANUAL+=("PI原理率 ${PI_RATIO}→100%へ: 個別PIを原理PIに昇華せよ")
fi

# --- Output ---
echo "=== Cycle Health Check ==="
date '+%Y-%m-%dT%H:%M:%S'

if [ ${#ALERTS[@]} -eq 0 ]; then
    echo "STATUS: OK — サイクル稼働中"
else
    echo "STATUS: ALERT — サイクル停滞検知"
    for a in "${ALERTS[@]}"; do
        echo "  🔴 $a"
    done
fi

for i in "${INFOS[@]}"; do
    echo "  ℹ️  $i"
done

if [ ${#FORCED[@]} -gt 0 ]; then
    echo "--- 自動実行済み(強制) ---"
    for f in "${FORCED[@]}"; do
        echo "  ⚡ $f"
    done
fi

if [ ${#MANUAL[@]} -gt 0 ]; then
    echo "--- 将軍が即実行せよ(逃げるな) ---"
    for m in "${MANUAL[@]}"; do
        echo "  → $m"
    done
fi

echo "--- 行動したら即再実行: bash scripts/gates/gate_cycle_health.sh ---"
