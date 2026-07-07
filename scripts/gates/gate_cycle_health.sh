#!/usr/bin/env bash
# semantic-links: [[学習ループ]]
# gate_cycle_health.sh — サイクル停滞検知heartbeat
# 「気づきを止めた瞬間に進化が止まる」を自動化×強制
# Usage: bash scripts/gates/gate_cycle_health.sh
#   /loop対応: /loop 30m bash scripts/gates/gate_cycle_health.sh
# @source: cmd_1494セッション(CoDD→なぜなぜ→L-CycleNeverStop)

set -euo pipefail
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="${SCRIPT_PATH%/scripts/gates/gate_cycle_health.sh}"
if [ "$SCRIPT_DIR" = "$SCRIPT_PATH" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/../.." && pwd)"
fi
cd "$SCRIPT_DIR"

ALERTS=()
INFOS=()
INSIGHT_COUNT=0
IDLE_COUNT=0
IDLE_NAMES=""
PI_RATIO="?"

# --- 1. 未消化insights aging check (pendingのみ)
if [ -f queue/insights.yaml ]; then
    read -r INSIGHT_COUNT < <(
        awk '
            /status: pending/ { pending++ }
            END { print pending + 0 }
        ' queue/insights.yaml
    )
    if [ "$INSIGHT_COUNT" -gt 15 ]; then
        ALERTS+=("insights: ${INSIGHT_COUNT}件未消化(閾値15, pendingのみ)。気づきが行動に変わっていない")
    elif [ "$INSIGHT_COUNT" -gt 5 ]; then
        INFOS+=("insights: ${INSIGHT_COUNT}件(正常範囲, pendingのみ)")
    fi
fi

# --- 2. idle忍者 check (稼働可能な手が遊んでいる) ---
if [ -f queue/karo_snapshot.txt ]; then
    IDLE_LINE=""
    while IFS= read -r line; do
        case "$line" in
            idle\|*)
                IDLE_LINE="$line"
                break
                ;;
        esac
    done < queue/karo_snapshot.txt
    if [ -n "$IDLE_LINE" ]; then
        IDLE_NAMES="${IDLE_LINE#idle|}"
        IFS=',' read -r -a idle_agents <<< "$IDLE_NAMES"
        for agent in "${idle_agents[@]}"; do
            [ -n "$agent" ] && IDLE_COUNT=$((IDLE_COUNT + 1))
        done
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
CACHE_KEY="${SCRIPT_DIR//[^A-Za-z0-9_.-]/_}"
PENDING_REPORTS_CACHE="/tmp/gate_cycle_health_pending_reports_${CACHE_KEY}.cache"
PENDING_REPORTS_CACHE_TTL="${GATE_CYCLE_HEALTH_CACHE_TTL_SEC:-5}"
REPORT_DIR_MTIME=0
if [ -d queue/reports ]; then
    REPORT_DIR_MTIME=$(stat -c '%Y' queue/reports 2>/dev/null || echo 0)
fi
GATE_LOG_MTIME=0
if [ -f "$GATE_LOG" ]; then
    GATE_LOG_MTIME=$(stat -c '%Y' "$GATE_LOG" 2>/dev/null || echo 0)
fi
PENDING_REPORTS_CACHE_HIT=0
if [ -f "$PENDING_REPORTS_CACHE" ]; then
    read -r _CACHE_REPORT_MTIME _CACHE_GATE_LOG_MTIME _CACHE_TS _CACHE_VALUE < "$PENDING_REPORTS_CACHE" || true
    if [ "${_CACHE_REPORT_MTIME:-}" = "$REPORT_DIR_MTIME" ] \
        && [ "${_CACHE_GATE_LOG_MTIME:-}" = "$GATE_LOG_MTIME" ] \
        && [ -n "${_CACHE_TS:-}" ] \
        && [ -n "${_CACHE_VALUE:-}" ] \
        && [ $((NOW - _CACHE_TS)) -lt "$PENDING_REPORTS_CACHE_TTL" ] 2>/dev/null; then
        PENDING_REPORTS="$_CACHE_VALUE"
        PENDING_REPORTS_CACHE_HIT=1
    fi
fi
# Optimized: glob+stat一括+awk単一パス(getline) (cmd_1982)
# find(10ms)+xargs stat 25files(28ms)+xargs grep-l(25ms) → glob stat(8ms)+awk+getline(5ms)
if [ "$PENDING_REPORTS_CACHE_HIT" -eq 0 ]; then
    _CUTOFF=$((NOW - 86400))
    _CLEARED_IDS=""
    if [ -f "$GATE_LOG" ]; then
        # B2: grep+grep-oE+sort 1パイプライン (echo subshell廃止)
        _CLEARED_IDS=$(grep $'\tCLEAR' "$GATE_LOG" 2>/dev/null | grep -oE 'cmd_[a-zA-Z0-9_]+' | sort -u || true)
    fi
    # B1: bash glob + stat一括 + awk単一パス(cleared/cutoff/status/parent_cmd check with getline)
    shopt -s nullglob
    _REPORT_FILES=( queue/reports/*_report_*.yaml )
    shopt -u nullglob
    if [ ${#_REPORT_FILES[@]} -gt 0 ]; then
        PENDING_REPORTS=$(stat -c '%Y %n' "${_REPORT_FILES[@]}" 2>/dev/null \
            | awk -v cids="$_CLEARED_IDS" -v cutoff="$_CUTOFF" '
            BEGIN{n=split(cids,c,"\n");for(i=1;i<=n;i++)clr[c[i]]=1}
            {
                mtime=$1; path=$2
                if(mtime+0 <= cutoff+0) next
                fname=path; sub(".*/","",fname)
                sub(".*_report_","",fname); sub("\\.yaml$","",fname); sub("_[a-z]*$","",fname)
                status_completed=0
                parent_cmd=""
                while ((getline line < path) > 0) {
                    if(line ~ /^status:[[:space:]]*completed[[:space:]]*$/) status_completed=1
                    if(line ~ /^parent_cmd:/ && parent_cmd == "") {
                        parent_cmd=line
                        sub(/^parent_cmd:[[:space:]]*/, "", parent_cmd)
                        gsub(/["'\''[:space:]]/, "", parent_cmd)
                    }
                    if(status_completed && parent_cmd != "") break
                }
                close(path)
                clear_key=(parent_cmd != "" ? parent_cmd : fname)
                if(status_completed && !clr[clear_key]) count++
            }
            END{print count+0}
        ')
    fi
    PENDING_REPORTS_CACHE_TMP="${PENDING_REPORTS_CACHE}.$$"
    printf '%s %s %s %s\n' "$REPORT_DIR_MTIME" "$GATE_LOG_MTIME" "$NOW" "$PENDING_REPORTS" > "$PENDING_REPORTS_CACHE_TMP"
    mv "$PENDING_REPORTS_CACHE_TMP" "$PENDING_REPORTS_CACHE"
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
    /^production_invariants:/ { in_section=1; next }
    in_section && /^  entries:/ { in_pi=1; next }
    in_section && /^[^ ]/ { in_section=0; in_pi=0 }
    in_pi && /^  [a-zA-Z_]+:/ && $1 != "entries:" { in_pi=0 }
    in_pi && /^    - / {
        found++
        if ($0 ~ /(implication|fact):/ && $0 ~ /全て|原理|適用される|信頼境界|任意の/) principle++
        next
    }
    in_pi && /(implication|fact):/ && /全て|原理|適用される|信頼境界|任意の/ { principle++ }
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

# --- 6. semantic候補alias自動昇格(意志依存排除・cmd_3718) ---
# semantic_stress_testが生成したpending候補は昇格道具(semantic_alias_absorb_pending.sh)が
# 実在するのに呼び出し元が無く滞留していた。このheartbeat(/loop 30m)を自動トリガーとして接続する。
SEMANTIC_PENDING_COUNT=0
if [ -f queue/insights.yaml ]; then
    read -r SEMANTIC_PENDING_COUNT < <(
        awk '
            /^- id:/ {
                if (started && status == "pending" && insight ~ /semantic_stress_test candidate_aliases/) pending++
                started = 1; status = ""; insight = ""
            }
            /^  status:/ { status = $2 }
            /^  insight:/ { insight = $0 }
            END {
                if (started && status == "pending" && insight ~ /semantic_stress_test candidate_aliases/) pending++
                print pending + 0
            }
        ' queue/insights.yaml
    )
fi

SEMANTIC_ABSORB_SCRIPT="$SCRIPT_DIR/scripts/semantic_alias_absorb_pending.sh"
if [ "$SEMANTIC_PENDING_COUNT" -gt 0 ]; then
    if [ -f "$SEMANTIC_ABSORB_SCRIPT" ]; then
        SEMANTIC_ABSORB_OUTPUT="$(bash "$SEMANTIC_ABSORB_SCRIPT" 2>/dev/null || true)"
        SEMANTIC_PENDING_BEFORE="$(printf '%s\n' "$SEMANTIC_ABSORB_OUTPUT" | grep -oE '^pending_before=[0-9]+$' | cut -d= -f2 || true)"
        SEMANTIC_ALIASES_ADDED="$(printf '%s\n' "$SEMANTIC_ABSORB_OUTPUT" | grep -oE '^aliases_added=[0-9]+$' | cut -d= -f2 || true)"
        SEMANTIC_PENDING_AFTER="$(printf '%s\n' "$SEMANTIC_ABSORB_OUTPUT" | grep -oE '^pending_after=[0-9]+$' | cut -d= -f2 || true)"
        SEMANTIC_PENDING_BEFORE="${SEMANTIC_PENDING_BEFORE:-$SEMANTIC_PENDING_COUNT}"
        SEMANTIC_ALIASES_ADDED="${SEMANTIC_ALIASES_ADDED:-0}"
        SEMANTIC_PENDING_AFTER="${SEMANTIC_PENDING_AFTER:-$SEMANTIC_PENDING_COUNT}"
        FORCED+=("semantic候補alias自動昇格: pending${SEMANTIC_PENDING_BEFORE}→${SEMANTIC_PENDING_AFTER}(追加${SEMANTIC_ALIASES_ADDED})")

        # 実行証拠を既存のNO_MATCH計測出力(logs/semantic_stress_test.log)へ還流し追跡可能にする
        SEMANTIC_NO_MATCH_LOG="$SCRIPT_DIR/logs/semantic_stress_test.log"
        SEMANTIC_HIT_RATE_REF="?"
        if [ -f "$SEMANTIC_NO_MATCH_LOG" ]; then
            SEMANTIC_HIT_RATE_REF="$(tail -1 "$SEMANTIC_NO_MATCH_LOG" | grep -oE '"hit_rate": *[0-9.]+' | head -1 | grep -oE '[0-9.]+$' || true)"
            SEMANTIC_HIT_RATE_REF="${SEMANTIC_HIT_RATE_REF:-?}"
        fi
        mkdir -p "$(dirname "$SEMANTIC_NO_MATCH_LOG")"
        printf '{ "timestamp": "%s", "trigger": "gate_cycle_health", "pending_before": %s, "aliases_added": %s, "pending_after": %s, "hit_rate_reference": "%s" }\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            "$SEMANTIC_PENDING_BEFORE" "$SEMANTIC_ALIASES_ADDED" "$SEMANTIC_PENDING_AFTER" "$SEMANTIC_HIT_RATE_REF" \
            >> "$SEMANTIC_NO_MATCH_LOG"
    else
        ALERTS+=("semantic候補alias: pending${SEMANTIC_PENDING_COUNT}件だが昇格スクリプト不在(${SEMANTIC_ABSORB_SCRIPT})")
    fi
else
    INFOS+=("semantic候補alias: pending0件(昇格待ちなし)")
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
