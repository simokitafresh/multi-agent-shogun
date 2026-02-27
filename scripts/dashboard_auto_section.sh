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

MARKER_START="<!-- DASHBOARD_AUTO_START -->"
MARKER_END="<!-- DASHBOARD_AUTO_END -->"

TMPFILE=$(mktemp)
TMP_METRICS=$(mktemp)
TMP_PIPELINE=$(mktemp)
trap 'rm -f "$TMPFILE" "$TMP_METRICS" "$TMP_PIPELINE"' EXIT

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
    while IFS=$'\t' read -r _ts _cmd result; do
        if [[ "$result" == "CLEAR" ]]; then
            STREAK=$((STREAK + 1))
        else
            STREAK=0
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

        while IFS=$'\t' read -r cid tit sta; do
            ninjas="${CMD_NINJAS[$cid]:-—}"
            echo "| ${cid} | ${tit} | ${sta} | ${ninjas} |"
        done < "$TMP_PIPELINE"
    fi

    echo ""

    # ─── メトリクス ───
    echo "### メトリクス"
    echo "| 連勝 | CLEAR率 | 総cmd完了 | 最終GATE |"
    echo "|------|---------|----------|----------|"
    echo "| ${STREAK} | ${CLEAR_RATE} | ${TOTAL_CMDS} | ${LAST_GATE} |"

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
