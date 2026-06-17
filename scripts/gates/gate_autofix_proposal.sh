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
FIX_SINCE="${GATE_AUTOFIX_FIX_SINCE:-120 days ago}"

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
    row_ts = $1
    n = split($4, reasons, "|")
    for (i = 1; i <= n; i++) {
        r = normalize(reasons[i])
        if (r) {
            cnt[r]++
            ts_arr[r] = (ts_arr[r] == "") ? row_ts : (ts_arr[r] "|" row_ts)
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
    for (p in cnt) printf "PAT\t%d\t%s\t%s\t%s\n", cnt[p], p, examples[p], ts_arr[p]
}' "$_tmp_recent")"

# Parse awk output into bash associative arrays
_rows=0
declare -A _pat_counts=()
declare -A _pat_examples=()
declare -A _pat_timestamps=()
while IFS=$'\t' read -r _tag _f1 _f2 _f3 _f4; do
    case "$_tag" in
        ROWS) _rows="$_f1" ;;
        PAT)
            _pat_counts["$_f2"]="$_f1"
            _pat_examples["$_f2"]="${_f3:-}"
            _pat_timestamps["$_f2"]="${_f4:-}"
            ;;
    esac
done <<< "$_awk_data"

# Sort patterns by count descending
mapfile -t _sorted_patterns < <(
    for _p in "${!_pat_counts[@]}"; do
        printf '%s\t%s\n' "${_pat_counts[$_p]}" "$_p"
    done | sort -rn | cut -f2
)

# FP修正commitログ取得（GATE_AUTOFIX_FIX_LOG環境変数はテスト用オーバーライド）
if [[ -n "${GATE_AUTOFIX_FIX_LOG:-}" ]]; then
    _fix_log_data="$GATE_AUTOFIX_FIX_LOG"
else
    _fix_log_data="$(git -C "$REPO_ROOT" log --format="%aI %s" --since="$FIX_SINCE" 2>/dev/null || true)"
fi

# パターンに関連するFP修正commitを検索し修正前/後のBLOCK件数を分離する
# 出力: "fix_ts|before|after" または空文字（修正commitなし）
_split_by_fix_commit() {
    local pattern="$1" ts_list="$2"
    if [[ -z "$_fix_log_data" || -z "$ts_list" ]]; then echo ""; return; fi
    local fix_line
    fix_line="$(printf '%s\n' "$_fix_log_data" | grep -iF -- "$pattern" | head -1)"
    if [[ -z "$fix_line" ]]; then echo ""; return; fi
    local fix_ts fix_epoch
    fix_ts="$(printf '%s\n' "$fix_line" | awk '{print $1}')"
    fix_epoch="$(date -d "$fix_ts" +%s 2>/dev/null)" || { echo ""; return; }
    local before=0 after=0
    IFS='|' read -ra _sba_ts_arr <<< "$ts_list"
    local _bts _bts_epoch
    for _bts in "${_sba_ts_arr[@]}"; do
        [[ -z "$_bts" ]] && continue
        _bts_epoch="$(date -d "$_bts" +%s 2>/dev/null)" || continue
        if (( _bts_epoch < fix_epoch )); then (( before++ )); else (( after++ )); fi
    done
    printf '%s|%d|%d\n' "$fix_ts" "$before" "$after"
}

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
        # FP修正commit境界の検出と分離表示
        _split_info=""
        if [[ -n "${_pat_timestamps[$_p]:-}" ]]; then
            _split_info="$(_split_by_fix_commit "$_p" "${_pat_timestamps[$_p]}")"
        fi
        if [[ -n "$_split_info" ]]; then
            IFS='|' read -r _fix_ts _before _after <<< "$_split_info"
            echo "  [$_cnt] $_p :: $_cat :: $_ex  [イベント境界:${_fix_ts%%T*} 修正前=${_before}件/修正後=${_after}件]"
        else
            echo "  [$_cnt] $_p :: $_cat :: $_ex"
        fi
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
