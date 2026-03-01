#!/usr/bin/env bash
# ============================================================
# dashboard_auto_section.sh
# ダッシュボードの機械的セクション(リアルタイム状況)を自動生成
#
# Usage: bash scripts/dashboard_auto_section.sh [--dry-run]
#   --dry-run: 標準出力に出力(dashboard.md未変更)
#
# Input:
#   queue/karo_snapshot.txt  → 忍者配備状況
#   queue/shogun_to_karo.yaml → パイプライン(active cmd一覧)
#   logs/gate_metrics.log    → 連勝数・CLEAR率・総cmd数
#   queue/tasks/*.yaml       → 各忍者の現タスク詳細
#   config/settings.yaml     → モデル名
#
# Output:
#   dashboard.md の DASHBOARD_AUTO_START ～ DASHBOARD_AUTO_END 間を上書き
#   マーカー外(家老記入セクション)は一切変更しない
#
# Exit:
#   0: 成功
#   1: 失敗
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ─── Paths ───
DASHBOARD="$PROJECT_DIR/dashboard.md"
SNAPSHOT="$PROJECT_DIR/queue/karo_snapshot.txt"
STK="$PROJECT_DIR/queue/shogun_to_karo.yaml"
GATE_LOG="$PROJECT_DIR/logs/gate_metrics.log"
TASKS_DIR="$PROJECT_DIR/queue/tasks"
SETTINGS="$PROJECT_DIR/config/settings.yaml"
ARCHIVE_STK_DONE="$PROJECT_DIR/queue/archive/shogun_to_karo_done.yaml"
KM_JSON_CACHE="/tmp/dashboard_km_json_cache.txt"
KM_MODEL_CACHE="/tmp/dashboard_km_model_cache.txt"
KM_CACHE_LINES="/tmp/dashboard_km_cache_lines.txt"

MARKER_START="<!-- DASHBOARD_AUTO_START -->"
MARKER_END="<!-- DASHBOARD_AUTO_END -->"

TMPFILE=$(mktemp)
TMP_METRICS=$(mktemp)
TMP_PIPELINE=$(mktemp)
TMP_RESULTS=$(mktemp)
TMP_TITLES=$(mktemp)
trap 'rm -f "$TMPFILE" "$TMP_METRICS" "$TMP_PIPELINE" "$TMP_RESULTS" "$TMP_TITLES"' EXIT

NOW=$(TZ=Asia/Tokyo date '+%H:%M')

ALL_NINJAS="sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru"

# ─── Helper: Japanese name ───
name_jp() {
    case "$1" in
        sasuke)   echo "佐助" ;;
        kirimaru) echo "霧丸" ;;
        hayate)   echo "疾風" ;;
        kagemaru) echo "影丸" ;;
        hanzo)    echo "半蔵" ;;
        saizo)    echo "才蔵" ;;
        kotaro)   echo "小太郎" ;;
        tobisaru) echo "飛猿" ;;
        *)        echo "$1" ;;
    esac
}

# ─── Helper: Get model for a ninja from settings.yaml ───
# Parse without yq/python — simple awk state machine
get_model() {
    local ninja="$1"
    [[ ! -f "$SETTINGS" ]] && { echo "Opus"; return; }
    awk -v agent="$ninja" '
        BEGIN { at=""; am="" }
        /^[[:space:]]*agents:/ { in_a=1; next }
        in_a && /^[^[:space:]]/ { in_a=0 }
        in_a && /^    [a-z]/ {
            gsub(/:.*/, ""); gsub(/^[[:space:]]+/, "")
            cur=$0
        }
        in_a && cur==agent && /type:[[:space:]]*codex/ { at="codex" }
        in_a && cur==agent && /model_name:/ {
            sub(/.*model_name:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
            am=$0
        }
        END {
            if (at=="codex") { print "Codex"; exit }
            if (am ~ /sonnet/) { print "Sonnet"; exit }
            if (am ~ /haiku/) { print "Haiku"; exit }
            print "Opus"
        }
    ' "$SETTINGS"
}

# ─── Build cmd→ninjas mapping (from task YAMLs) ───
declare -A CMD_NINJAS=()
for n in $ALL_NINJAS; do
    tf="$TASKS_DIR/${n}.yaml"
    [[ ! -f "$tf" ]] && continue
    pcmd=$(grep -E '^\s*parent_cmd:' "$tf" | head -1 | sed 's/.*parent_cmd:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
    [[ -z "$pcmd" ]] && continue
    jp=$(name_jp "$n")
    if [[ -n "${CMD_NINJAS[$pcmd]:-}" ]]; then
        CMD_NINJAS[$pcmd]="${CMD_NINJAS[$pcmd]},${jp}"
    else
        CMD_NINJAS[$pcmd]="$jp"
    fi
done

# ─── Get idle list from snapshot ───
IDLE_LIST=""
[[ -f "$SNAPSHOT" ]] && IDLE_LIST=$(grep '^idle|' "$SNAPSHOT" | head -1 | cut -d'|' -f2 || true)

# ─── Calculate active ninjas from snapshot ───
ACTIVE_COUNT=0
ACTIVE_NAMES=""
for _an in $ALL_NINJAS; do
    if ! echo ",$IDLE_LIST," | grep -q ",${_an}," 2>/dev/null; then
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        _jp_an=$(name_jp "$_an")
        if [[ -n "$ACTIVE_NAMES" ]]; then
            ACTIVE_NAMES="${ACTIVE_NAMES}, ${_jp_an}"
        else
            ACTIVE_NAMES="$_jp_an"
        fi
    fi
done
[[ -z "$ACTIVE_NAMES" ]] && ACTIVE_NAMES="—"

# ─── Parse pipeline commands from STK (pre-compute for subshell access) ───
if [[ -f "$STK" ]] && grep -qE '^  -[[:space:]]*id:' "$STK" 2>/dev/null; then
    # Output tab-delimited: id\ttitle\tstatus
    # Only match command-level "- id:" (2-space indent), not nested AC entries (6+)
    awk '
        /^  -[[:space:]]*id:/ {
            if (cid != "") printf "%s\t%s\t%s\n", cid, tit, sta
            sub(/.*-[[:space:]]*id:[[:space:]]*/, "")
            gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
            cid=$0; tit=""; sta=""
        }
        /^    title:/ && cid!="" {
            sub(/.*title:[[:space:]]*/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if (length($0)>50) $0=substr($0,1,47)"..."
            tit=$0
        }
        /^    status:/ && cid!="" {
            sub(/.*status:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
            sta=$0
        }
        END { if (cid!="") printf "%s\t%s\t%s\n", cid, tit, sta }
    ' "$STK" > "$TMP_PIPELINE"
fi

# ─── Calculate gate metrics ───
STREAK=0
CLEAR_RATE="0.0%"
TOTAL_CMDS=0
LAST_GATE="—"

if [[ -f "$GATE_LOG" ]]; then
    # Cmd-latest dedup (exclude test cmds), sorted by timestamp
    awk -F'\t' '
        NF>=3 && $2 !~ /^cmd_test/ {
            cmd=$2; ts[cmd]=$1; st[cmd]=$3
        }
        END {
            for (c in st) printf "%s\t%s\t%s\n", ts[c], c, st[c]
        }
    ' "$GATE_LOG" | sort -t$'\t' -k1,1 > "$TMP_METRICS"

    TOTAL_CMDS=$(wc -l < "$TMP_METRICS" | tr -d ' ')
    CLEAR_COUNT=$(awk -F'\t' '$3=="CLEAR"{c++} END{print c+0}' "$TMP_METRICS")

    if [[ "$TOTAL_CMDS" -gt 0 ]]; then
        CLEAR_RATE=$(awk -v c="$CLEAR_COUNT" -v t="$TOTAL_CMDS" 'BEGIN{printf "%.1f%%", (c/t)*100}')
    fi

    # Streak: consecutive CLEARs from the end (L074: avoid ((var++)))
    STREAK=0
    STREAK_START=""
    STREAK_END=""
    while IFS=$'\t' read -r _ts _cmd result; do
        if [[ "$result" == "CLEAR" ]]; then
            if [[ $STREAK -eq 0 ]]; then
                STREAK_START="$_cmd"
            fi
            STREAK=$((STREAK + 1))
            STREAK_END="$_cmd"
        else
            STREAK=0
            STREAK_START=""
            STREAK_END=""
        fi
    done < "$TMP_METRICS"

    # Last GATE time
    last_line=$(tail -1 "$TMP_METRICS" || true)
    if [[ -n "$last_line" ]]; then
        _last_ts=$(echo "$last_line" | cut -f1)
        if [[ "$_last_ts" =~ T([0-9]{2}:[0-9]{2}) ]]; then
            LAST_GATE="${BASH_REMATCH[1]}"
        fi
    fi
fi

# Build CLEAR'd cmd set for pipeline filtering (must be outside subshell blocks)
declare -A CLEARED_CMDS=()
if [[ -s "$TMP_METRICS" ]]; then
    while IFS=$'\t' read -r _ts _cmd _result; do
        [[ "$_result" == "CLEAR" ]] && CLEARED_CMDS[$_cmd]=1
    done < "$TMP_METRICS"
fi

# ─── Knowledge metrics (cached — only re-run when gate_metrics.log changes) ───
KM_INJECT_RATE="—"
KM_REF_RATE="—"
KM_DELTA_PP="—"
KM_LESSON_EFFECT="—"
KM_PROBLEM_LESSONS="—"
KM_MODEL_OPUS="—"
KM_MODEL_SONNET="—"
KM_MODEL_CODEX="—"
KM_N_OPUS="—"
KM_N_SONNET="—"
KM_N_CODEX="—"

_gate_lines=0
[[ -f "$GATE_LOG" ]] && _gate_lines=$(wc -l < "$GATE_LOG" | tr -d ' ')
_cached_lines=0
[[ -f "$KM_CACHE_LINES" ]] && _cached_lines=$(cat "$KM_CACHE_LINES" 2>/dev/null | tr -d '[:space:]')

if [[ "$_gate_lines" != "$_cached_lines" ]] || [[ ! -f "$KM_JSON_CACHE" ]]; then
    bash "$SCRIPT_DIR/knowledge_metrics.sh" --json > "$KM_JSON_CACHE" 2>/dev/null || true
    bash "$SCRIPT_DIR/model_analysis.sh" --summary > "$KM_MODEL_CACHE" 2>/dev/null || true
    echo "$_gate_lines" > "$KM_CACHE_LINES"
fi

# Parse JSON cache (inject_rate, ref_rate, normalized_delta.delta_pp)
if [[ -f "$KM_JSON_CACHE" ]] && [[ -s "$KM_JSON_CACHE" ]]; then
    _km_parsed=$(python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    ir = data.get('inject_rate')
    rr = data.get('ref_rate')
    nd = data.get('normalized_delta', {})
    dp = nd.get('delta_pp')
    le = data.get('lesson_effectiveness')
    pl = data.get('problem_lessons', 0)
    ir_s = f'{ir:.1f}%' if ir is not None else '—'
    rr_s = f'{rr:.1f}%' if rr is not None else '—'
    dp_s = f'{dp:+.1f}pp' if dp is not None else '—'
    le_s = f'{le:.1f}%' if le is not None else '—'
    pl_s = str(pl) if pl is not None else '0'
    print(f'{ir_s}\t{rr_s}\t{dp_s}\t{le_s}\t{pl_s}')
except Exception:
    print('—\t—\t—\t—\t0')
" < "$KM_JSON_CACHE" 2>/dev/null || echo "—	—	—	—	0")
    IFS=$'\t' read -r KM_INJECT_RATE KM_REF_RATE KM_DELTA_PP KM_LESSON_EFFECT KM_PROBLEM_LESSONS <<< "$_km_parsed"
fi

# Parse model cache (model_analysis.sh --summary: key=value format)
if [[ -f "$KM_MODEL_CACHE" ]] && [[ -s "$KM_MODEL_CACHE" ]]; then
    _get_model_val() {
        local key="$1"
        grep "^${key}=" "$KM_MODEL_CACHE" | head -1 | cut -d= -f2 || true
    }
    _rate=$(_get_model_val opus_clear_rate)
    [[ -n "$_rate" ]] && KM_MODEL_OPUS="${_rate}%"
    _n=$(_get_model_val opus_n)
    [[ -n "$_n" ]] && KM_N_OPUS="$_n"

    _rate=$(_get_model_val sonnet_clear_rate)
    [[ -n "$_rate" ]] && KM_MODEL_SONNET="${_rate}%"
    _n=$(_get_model_val sonnet_n)
    [[ -n "$_n" ]] && KM_N_SONNET="$_n"

    _rate=$(_get_model_val codex_clear_rate)
    [[ -n "$_rate" ]] && KM_MODEL_CODEX="${_rate}%"
    _n=$(_get_model_val codex_n)
    [[ -n "$_n" ]] && KM_N_CODEX="$_n"
fi

# ─── Build cmd→title map (for 戦果 section) ───
# From active STK
if [[ -s "$TMP_PIPELINE" ]]; then
    awk -F'\t' '{print $1"\t"$2}' "$TMP_PIPELINE" >> "$TMP_TITLES"
fi
# From archive done YAML
if [[ -f "$ARCHIVE_STK_DONE" ]]; then
    awk '
        /^ *- id: cmd_/ {
            sub(/.*- id: */, ""); gsub(/["\047[:space:]]/, "")
            cid=$0; tit=""
        }
        /^    title:/ && cid!="" {
            sub(/.*title: */, "")
            gsub(/^["\047]|["\047]$/, "")
            if (length($0)>50) $0=substr($0,1,47)"..."
            tit=$0
            print cid"\t"tit
            cid=""
        }
    ' "$ARCHIVE_STK_DONE" >> "$TMP_TITLES"
fi

# ─── Get last 5 CLEAR cmds for battle results ───
if [[ -s "$TMP_METRICS" ]]; then
    awk -F'\t' '$3=="CLEAR"' "$TMP_METRICS" | tail -5 > "$TMP_RESULTS"
fi

# ═══════════════════════════════════════════════════════
# Generate auto section content
# ═══════════════════════════════════════════════════════
{
    echo "$MARKER_START"
    echo "## 📊 リアルタイム状況 (${NOW} 自動更新)"
    echo ""

    # ─── 忍者配備 ───
    echo "### 忍者配備"
    echo "| 忍者 | モデル | 状態 | 現タスク | cmd | 種別 |"
    echo "|------|--------|------|----------|-----|------|"

    for ninja in $ALL_NINJAS; do
        jp=$(name_jp "$ninja")
        model=$(get_model "$ninja")

        # Status from idle list
        status="稼働中"
        if echo ",$IDLE_LIST," | grep -q ",${ninja}," 2>/dev/null; then
            status="idle"
        fi

        # Task info from snapshot
        task_id="—"
        if [[ -f "$SNAPSHOT" ]]; then
            snap_line=$(grep "^ninja|${ninja}|" "$SNAPSHOT" | head -1 || true)
            if [[ -n "$snap_line" ]]; then
                task_id=$(echo "$snap_line" | cut -d'|' -f3)
                snap_status=$(echo "$snap_line" | cut -d'|' -f4)
                [[ "$snap_status" == "done" ]] && status="done"
            fi
        fi

        # parent_cmd and task_type from task YAML (L034: flexible matching)
        cmd="—"
        task_type="—"
        tf="$TASKS_DIR/${ninja}.yaml"
        if [[ -f "$tf" ]]; then
            _cmd=$(grep -E '^\s*parent_cmd:' "$tf" | head -1 | sed 's/.*parent_cmd:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
            _type=$(grep -E '^\s*task_type:' "$tf" | head -1 | sed 's/.*task_type:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]' || true)
            [[ -n "$_cmd" ]] && cmd="$_cmd"
            [[ -n "$_type" ]] && task_type="$_type"
        fi

        echo "| ${jp} | ${model} | ${status} | ${task_id} | ${cmd} | ${task_type} |"
    done

    echo ""

    # ─── パイプライン ───
    echo "### パイプライン"

    if [[ ! -s "$TMP_PIPELINE" ]]; then
        echo "パイプライン空 — 次cmd待ち"
    else
        echo "| cmd | タイトル | status | 配備忍者 |"
        echo "|-----|---------|--------|----------|"

        shown=0
        while IFS=$'\t' read -r cid tit sta; do
            # Skip completed commands and already GATE CLEAR'd commands.
            [[ "$sta" == "completed" ]] && continue
            [[ -n "${CLEARED_CMDS[$cid]:-}" ]] && continue
            ninjas="${CMD_NINJAS[$cid]:-—}"
            echo "| ${cid} | ${tit} | ${sta} | ${ninjas} |"
            shown=$((shown + 1))
        done < "$TMP_PIPELINE"

        if [[ $shown -eq 0 ]]; then
            echo "パイプライン空 — 次cmd待ち"
        fi
    fi

    echo ""

    # ─── 戦況メトリクス ───
    echo "### 戦況メトリクス"
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| cmd完了(GATE CLEAR) | ${CLEAR_COUNT:-0}/${TOTAL_CMDS} |"
    echo "| 稼働忍者 | ${ACTIVE_COUNT}/8 (${ACTIVE_NAMES}) |"
    if [[ -n "$STREAK_START" ]] && [[ -n "$STREAK_END" ]]; then
        echo "| 連勝(CLEAR streak) | ${STREAK} (${STREAK_START}〜${STREAK_END}) |"
    else
        echo "| 連勝(CLEAR streak) | ${STREAK} |"
    fi

    echo ""

    # ─── モデル別スコアボード ───
    echo "### モデル別スコアボード"
    echo "| モデル | CLEAR率 | サンプル数 |"
    echo "|--------|---------|-----------|"
    echo "| Opus | ${KM_MODEL_OPUS} | ${KM_N_OPUS} |"
    echo "| Sonnet | ${KM_MODEL_SONNET} | ${KM_N_SONNET} |"
    echo "| Codex | ${KM_MODEL_CODEX} | ${KM_N_CODEX} |"

    echo ""

    # ─── 知識サイクル健全度 ───
    echo "### 知識サイクル健全度"
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| 教訓注入率 | ${KM_INJECT_RATE} |"
    echo "| 教訓効果率 | ${KM_LESSON_EFFECT} |"
    echo "| 問題教訓 | ${KM_PROBLEM_LESSONS}件 |"

    echo ""

    # ─── 戦果（直近5件） ───
    echo "### 戦果（直近5件）"
    if [[ -s "$TMP_RESULTS" ]]; then
        echo "| cmd | 内容 | 結果 | 完了日時 |"
        echo "|-----|------|------|----------|"
        # Reverse order (newest first)
        tac "$TMP_RESULTS" | while IFS=$'\t' read -r _ts _cmd _result; do
            # Look up title
            _title=$(grep "^${_cmd}"$'\t' "$TMP_TITLES" | head -1 | cut -f2 || true)
            [[ -z "$_title" ]] && _title="—"
            # Format timestamp (2026-02-27T12:26:56 → 02-27 12:26)
            _date="—"
            if [[ "$_ts" =~ ([0-9]{4}-([0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2})) ]]; then
                _date="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
            fi
            echo "| ${_cmd} | ${_title} | GATE CLEAR | ${_date} |"
        done
    else
        echo "(戦果データなし)"
    fi

    echo ""
    echo "> 過去の戦果は archive/dashboard/ を参照"

    echo "$MARKER_END"
} > "$TMPFILE"

# ═══════════════════════════════════════════════════════
# Output or update dashboard.md
# ═══════════════════════════════════════════════════════
if [[ "$DRY_RUN" == true ]]; then
    cat "$TMPFILE"
    exit 0
fi

if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: dashboard.md not found: $DASHBOARD" >&2
    exit 1
fi

if ! grep -qF "$MARKER_START" "$DASHBOARD"; then
    echo "ERROR: $MARKER_START not found in dashboard.md" >&2
    exit 1
fi

if ! grep -qF "$MARKER_END" "$DASHBOARD"; then
    echo "ERROR: $MARKER_END not found in dashboard.md" >&2
    exit 1
fi

# Replace content between markers (inclusive)
{
    # Lines before start marker
    awk -v m="$MARKER_START" '$0==m{exit} {print}' "$DASHBOARD"
    # New content (includes markers)
    cat "$TMPFILE"
    # Lines after end marker
    awk -v m="$MARKER_END" 'f{print} $0==m{f=1}' "$DASHBOARD"
} > "${DASHBOARD}.tmp"

mv "${DASHBOARD}.tmp" "$DASHBOARD"
echo "OK: dashboard.md auto section updated (${NOW})"
