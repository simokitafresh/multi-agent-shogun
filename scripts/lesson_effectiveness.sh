#!/usr/bin/env bash
# ============================================================
# lesson_effectiveness.sh
# 教訓別効果メトリクス集計スクリプト
#
# Usage:
#   bash scripts/lesson_effectiveness.sh
#   bash scripts/lesson_effectiveness.sh --project infra
#
# データソース:
#   1. logs/gate_metrics.log — injected_lessons列(8列目)からinject_count
#   2. queue/reports/*_report_*.yaml — lessons_useful/lesson_referenced
#   3. (将来) preventable_by from report YAMLs
#
# 出力: TSV (lesson_id, inject_count, useful_count, preventable_count, effectiveness)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GATE_METRICS_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
REPORTS_DIR="$SCRIPT_DIR/queue/reports"

# Parse --project option
PROJECT_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) PROJECT_FILTER="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

declare -A inject_count
declare -A useful_count
declare -A preventable_count
declare -A all_lessons

# --- 1. gate_metrics.log: injected_lessons (8th column) ---
if [[ -f "$GATE_METRICS_LOG" ]]; then
    while IFS=$'\t' read -r _ts _cmd_id _result _detail _task_type _model _bloom_level injected_lessons _rest; do
        [[ -z "${injected_lessons:-}" || "$injected_lessons" == "none" ]] && continue
        # injected_lessons format: L001,L002,L003
        IFS=',' read -ra lessons <<< "$injected_lessons"
        for lid in "${lessons[@]}"; do
            lid="${lid// /}"
            [[ -z "$lid" || ! "$lid" =~ ^L[0-9]+ ]] && continue
            inject_count[$lid]=$((${inject_count[$lid]:-0} + 1))
            all_lessons[$lid]=1
        done
    done < "$GATE_METRICS_LOG"
fi

# --- 2. Report YAMLs: lessons_useful / lesson_referenced ---
parse_lesson_list() {
    local report="$1"
    local in_section=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^lessons_useful: ]] || [[ "$line" =~ ^lesson_referenced: ]]; then
            # lessons_useful: [] → empty, skip
            [[ "$line" =~ \[\] ]] && continue
            # lessons_useful: false → skip
            [[ "$line" =~ false ]] && continue
            in_section="yes"
            continue
        fi
        if [[ "$in_section" == "yes" ]]; then
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(L[0-9]+) ]]; then
                local lid="${BASH_REMATCH[1]}"
                useful_count[$lid]=$((${useful_count[$lid]:-0} + 1))
                all_lessons[$lid]=1
            elif [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                in_section=""
            fi
        fi
    done < "$report"
}

for report in "$REPORTS_DIR"/*_report_*.yaml; do
    [[ -f "$report" ]] || continue
    # Project filtering
    if [[ -n "$PROJECT_FILTER" ]]; then
        local_project=$(awk '/^[[:space:]]*project:/{print $2; exit}' "$report")
        [[ "${local_project:-}" != "$PROJECT_FILTER" ]] && continue
    fi
    parse_lesson_list "$report"
done

# --- 3. preventable_by from report YAMLs (future manual tag) ---
parse_preventable_by() {
    local report="$1"
    local in_section=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*preventable_by: ]]; then
            [[ "$line" =~ \[\] ]] && continue
            in_section="yes"
            continue
        fi
        if [[ "$in_section" == "yes" ]]; then
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(L[0-9]+) ]]; then
                local lid="${BASH_REMATCH[1]}"
                preventable_count[$lid]=$((${preventable_count[$lid]:-0} + 1))
                all_lessons[$lid]=1
            elif [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                in_section=""
            fi
        fi
    done < "$report"
}

for report in "$REPORTS_DIR"/*_report_*.yaml; do
    [[ -f "$report" ]] || continue
    if [[ -n "$PROJECT_FILTER" ]]; then
        local_project=$(awk '/^[[:space:]]*project:/{print $2; exit}' "$report")
        [[ "${local_project:-}" != "$PROJECT_FILTER" ]] && continue
    fi
    parse_preventable_by "$report"
done

# --- Output ---
if [[ ${#all_lessons[@]} -eq 0 ]]; then
    echo -e "lesson_id\tinject_count\tuseful_count\tpreventable_count\teffectiveness"
    exit 0
fi

echo -e "lesson_id\tinject_count\tuseful_count\tpreventable_count\teffectiveness"

{
    for lid in "${!all_lessons[@]}"; do
        ic=${inject_count[$lid]:-0}
        uc=${useful_count[$lid]:-0}
        pc=${preventable_count[$lid]:-0}
        if [[ "$ic" -gt 0 ]]; then
            eff=$(awk "BEGIN{printf \"%.1f%%\", ($uc/$ic)*100}")
        else
            eff="N/A"
        fi
        echo -e "${lid}\t${ic}\t${uc}\t${pc}\t${eff}"
    done
} | sort -t$'\t' -k2 -rn
