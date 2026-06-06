#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]]
# gate_autofix_proposal.sh — 直近BLOCKパターンから instructions 修正提案を自動起票
# 目的: idle時に「頻出BLOCKをどの指示で潰すべきか」を queue/insights.yaml へ還流する
# Usage: bash scripts/gates/gate_autofix_proposal.sh

set -euo pipefail

REPO_ROOT="${SHOGUN_STARTUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_FILE="$REPO_ROOT/logs/gate_metrics.log"
INSIGHT_SCRIPT="$REPO_ROOT/scripts/insight_write.sh"
WINDOW="${GATE_AUTOFIX_WINDOW:-50}"
MIN_COUNT="${GATE_AUTOFIX_MIN_COUNT:-3}"
CACHE_TTL="${GATE_AUTOFIX_CACHE_TTL:-30}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "SKIP: gate_metrics.log not found"
    exit 0
fi

_cache_file=""
if [[ "${GATE_AUTOFIX_DISABLE_CACHE:-0}" != "1" && "$CACHE_TTL" =~ ^[0-9]+$ && "$CACHE_TTL" -gt 0 ]]; then
    _log_sig="$(stat -c '%Y:%s' "$LOG_FILE" 2>/dev/null || printf 'unknown')"
    _root_key="${REPO_ROOT//[^A-Za-z0-9._-]/_}"
    _cache_file="/tmp/gate_autofix_proposal_${_root_key}_${WINDOW}_${MIN_COUNT}_${_log_sig//[^A-Za-z0-9._-]/_}.cache"
    _now="$(date +%s)"
    if [[ -f "$_cache_file" ]]; then
        _cache_mtime="$(stat -c '%Y' "$_cache_file" 2>/dev/null || printf 0)"
        if (( _now - _cache_mtime < CACHE_TTL )); then
            cat "$_cache_file"
            exit 0
        fi
    fi
fi

_tmp_recent="$(mktemp)"
_tmp_output="$(mktemp)"
trap 'rm -f "$_tmp_recent" "$_tmp_output"' EXIT

awk -F'\t' -v limit="$WINDOW" '
    $3 == "BLOCK" {
        print
        c++
        if (c >= limit) {
            exit
        }
    }
' < <(tac "$LOG_FILE") > "$_tmp_recent"

if [[ ! -s "$_tmp_recent" ]]; then
    echo "NO DATA: recent BLOCK rows not found"
    exit 0
fi

# Count patterns and collect examples with awk (replaces python3 to eliminate startup overhead)
_awk_data="$(awk -F'\t' '
function normalize(raw,    s, t, n, i) {
    s = raw
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    if (!s) return ""
    n = split(s, t, ":")
    for (i = 1; i <= n; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", t[i])
    if (t[1] == "report_format") return "report_format"
    for (i = 1; i <= n; i++) {
        if (t[i] == "fill_this_remaining") return "fill_this_remaining"
        if (t[i] == "binary_checks_fail") return "binary_checks_fail"
        if (t[i] == "purpose_validation_fit_false") return "purpose_validation_fit_false"
        if (t[i] == "ac_version_mismatch") return "ac_version_mismatch"
    }
    if (t[1] == "draft_lessons") return "draft_lessons"
    return s
}
NF > 0 { rows++ }
NF >= 4 && $4 {
    n = split($4, reasons, "|")
    for (i = 1; i <= n; i++) {
        r = normalize(reasons[i])
        if (r) {
            cnt[r]++
            if (ecnt[r] < 2) {
                ex_raw = reasons[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", ex_raw)
                if (ex_raw != "" && !seen[r, ex_raw]) {
                    seen[r, ex_raw] = 1
                    examples[r] = (examples[r] == "") ? ex_raw : (examples[r] " ; " ex_raw)
                    ecnt[r]++
                }
            }
        }
    }
}
END {
    printf "ROWS\t%d\n", rows
    for (p in cnt) printf "PAT\t%d\t%s\t%s\n", cnt[p], p, examples[p]
}' "$_tmp_recent")"

# Parse awk output into bash associative arrays
_rows=0
declare -A _pat_counts=()
declare -A _pat_examples=()
while IFS=$'\t' read -r _tag _f1 _f2 _f3; do
    case "$_tag" in
        ROWS) _rows="$_f1" ;;
        PAT)
            _pat_counts["$_f2"]="$_f1"
            _pat_examples["$_f2"]="${_f3:-}"
            ;;
    esac
done <<< "$_awk_data"

# Sort patterns by count descending
mapfile -t _sorted_patterns < <(
    for _p in "${!_pat_counts[@]}"; do
        printf '%s\t%s\n' "${_pat_counts[$_p]}" "$_p"
    done | sort -rn | cut -f2
)

{
    echo "=== Auto-Fix Proposal Scan ==="
    echo "Recent BLOCK window: $WINDOW"
    echo "Analyzed BLOCK rows: $_rows"
    echo "Recurring patterns:"
    for _p in "${_sorted_patterns[@]}"; do
        _cnt="${_pat_counts[$_p]}"
        case "$_p" in
            report_format|fill_this_remaining|binary_checks_fail) _cat="report_yaml" ;;
            purpose_validation_fit_false) _cat="scope_alignment" ;;
            draft_lessons) _cat="lesson_flow" ;;
            ac_version_mismatch) _cat="task_sync" ;;
            *) _cat="other" ;;
        esac
        _ex="${_pat_examples[$_p]:-}"
        [[ -z "$_ex" ]] && _ex="-"
        echo "  [$_cnt] $_p :: $_cat :: $_ex"
    done

    echo "Proposal threshold: $MIN_COUNT"
    echo "Proposals:"

    if [[ ! -f "$INSIGHT_SCRIPT" ]]; then
        echo "  SKIP: insight_write.sh not found"
    else
        _created=0
        for _p in "${_sorted_patterns[@]}"; do
            _cnt="${_pat_counts[$_p]}"
            [[ "$_cnt" -lt "$MIN_COUNT" ]] && continue

            # Patterns already handled by Level 4+ gates
            case "$_p" in
                report_format|fill_this_remaining|binary_checks_fail|purpose_validation_fit_false|ac_version_mismatch)
                    echo "  $_p: SKIP (Level4 gate handles this; gate_report_format already BLOCKS it)"
                    continue ;;
            esac

            # PROPOSAL_MAP lookup
            case "$_p" in
                report_format)
                    _cat="report_yaml"; _tgt="instructions/ashigaru-procedures.md"
                    _act="report_field_set.sh再実行手順と提出前gate再確認を先頭へ固定化" ;;
                fill_this_remaining)
                    _cat="report_yaml"; _tgt="instructions/ashigaru-procedures.md"
                    _act="FILL_THIS全置換と提出前grep確認を報告手順へ追記" ;;
                binary_checks_fail)
                    _cat="report_yaml"; _tgt="instructions/ashigaru.md"
                    _act="binary_checksは全AC yes/no必須を記入例付きで強調" ;;
                purpose_validation_fit_false)
                    _cat="scope_alignment"; _tgt="instructions/ashigaru.md"
                    _act="purpose_validation記入前にcmd目的との差分確認を必須化" ;;
                draft_lessons)
                    _cat="lesson_flow"; _tgt="instructions/karo.md"
                    _act="draft lessons解消手順と完了条件をレビュー工程に追記" ;;
                ac_version_mismatch)
                    _cat="task_sync"; _tgt="instructions/ashigaru.md"
                    _act="復帰時のtask再読込とac_version_read同期確認を提出前必須化" ;;
                *)
                    continue ;;
            esac

            # Ninja recovery does not read these files after /new — proposals would be unread
            case "$_tgt" in
                "instructions/ashigaru.md"|"instructions/ashigaru-procedures.md")
                    echo "  $_p: SKIP (target file ninja-unread)"
                    continue ;;
            esac

            _ex="${_pat_examples[$_p]:-}"
            _msg="AUTOFIX-PROPOSAL: $_p -> $_tgt :: $_act (recent${WINDOW}=${_cnt}; category=${_cat}; examples=${_ex})"
            _out="$(bash "$INSIGHT_SCRIPT" "$_msg" "high" "gate_autofix_proposal" 2>&1)" || _out="ERROR"
            echo "  $_p: ${_out:-NO_OUTPUT}"
            (( _created++ )) || true
        done

        if [[ "${_created:-0}" -eq 0 ]]; then
            echo "  none"
        fi
    fi
} | tee "$_tmp_output"

if [[ -n "$_cache_file" ]]; then
    cp "$_tmp_output" "$_cache_file"
fi
