#!/bin/bash
# gate_gunshi_cs_checklist.sh — consultation/self_studyエントリのCS観点チェックリスト強制
# @source: cmd_1494 (CoDD分析4サイクルで自己検出率0%→CS観点プロトコル定義)
# 知性の外部化: CS観点を軍師の意志に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_gunshi_cs_checklist.sh
# Exit: 0=PASS(全エントリにcs_checklist), 1=WARN(欠落あり)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/gunshi_review_log.yaml"

if [ ! -f "$LOG_FILE" ]; then
    echo "ALERT: gunshi_review_log.yaml not found — レビューログ不在は異常"
    exit 1
fi

RESULT=$(awk '
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function emit_list(prefix, arr, count,    i, out) {
    if (count <= 0) return
    out = ""
    for (i = 1; i <= count; i++) out = out (i > 1 ? "," : "") arr[i]
    print prefix out
}
function flush_record(    is_ss, has_fm, has_tolerance, idx) {
    if (!in_record) return

    is_ss = (review_type == "self_study" || review_type == "consultation")
    if (is_ss) {
        ss_count++
        ss_id[ss_count] = (entry_id != "" ? entry_id : "?")
        ss_has_cs[ss_count] = has_cs
        ss_has_causal[ss_count] = has_causal
    }

    if (review_type == "draft") {
        draft_count++
        draft_id[draft_count] = (entry_id != "" ? entry_id : "?")
        draft_obs[draft_count] = obs_text
        draft_verdict[draft_count] = verdict
    }

    in_record = 0
    entry_id = ""
    review_type = ""
    verdict = ""
    has_cs = 0
    has_causal = 0
    in_obs = 0
    obs_text = ""
}
BEGIN {
    fm_pat = "FM|failure|リスク|穴|通過する|偽陽性|偽陰性"
    tol_pat = "許容|後追い|v1で|TBD|shallow|最小実装"
}
/^- (cmd_id|id):/ {
    flush_record()
    in_record = 1
    line = $0
    sub(/^- (cmd_id|id):[[:space:]]*/, "", line)
    gsub(/["'\''"]/, "", line)
    entry_id = trim(line)
    next
}
{
    if (!in_record) next

    if ($0 ~ /^[[:space:]]*review_type:[[:space:]]*/) {
        line = $0
        sub(/^[[:space:]]*review_type:[[:space:]]*/, "", line)
        gsub(/["'\''"]/, "", line)
        review_type = trim(line)
    } else if ($0 ~ /^[[:space:]]*verdict:[[:space:]]*/) {
        line = $0
        sub(/^[[:space:]]*verdict:[[:space:]]*/, "", line)
        gsub(/["'\''"]/, "", line)
        verdict = trim(line)
    } else if ($0 ~ /^[[:space:]]*cs_checklist:[[:space:]]*$/) {
        has_cs = 1
    } else if ($0 ~ /^[[:space:]]*causal_chain:[[:space:]]*/) {
        has_causal = 1
    }

    if ($0 ~ /^[[:space:]]*observations:[[:space:]]*$/) {
        in_obs = 1
        next
    }
    if (in_obs) {
        if ($0 ~ /^[[:space:]]{4,}- /) {
            obs_text = obs_text "\n" $0
            next
        }
        if ($0 ~ /^[[:space:]]{2}[a-z_]+:/ || $0 ~ /^- (cmd_id|id):/) {
            in_obs = 0
        }
    }
}
END {
    flush_record()

    start_ss = (ss_count > 10) ? ss_count - 9 : 1
    cs_missing_count = 0
    causal_missing_count = 0
    for (i = start_ss; i <= ss_count; i++) {
        if (!ss_has_cs[i]) cs_missing[++cs_missing_count] = ss_id[i]
        if (!ss_has_causal[i]) causal_missing[++causal_missing_count] = ss_id[i]
    }

    start_draft = (draft_count > 20) ? draft_count - 19 : 1
    fm_flagged_count = 0
    for (i = start_draft; i <= draft_count; i++) {
        has_fm = (draft_obs[i] ~ fm_pat)
        has_tolerance = (draft_obs[i] ~ tol_pat)
        if (draft_verdict[i] == "APPROVE" && has_fm && has_tolerance) {
            fm_flagged[++fm_flagged_count] = draft_id[i]
        }
    }

    emit_list("CS_MISSING:", cs_missing, cs_missing_count)
    emit_list("CAUSAL_MISSING:", causal_missing, causal_missing_count)
    emit_list("FM_TOLERANCE:", fm_flagged, fm_flagged_count)
    if (cs_missing_count == 0 && causal_missing_count == 0) print "ALL_PASS"
    if (fm_flagged_count == 0) print "FM_PASS"
}
' "$LOG_FILE" 2>/dev/null)

cs_missing=""
causal_missing=""
fm_flagged=""
all_pass=0
fm_pass=0
while IFS= read -r line; do
    case "$line" in
        CS_MISSING:*)
            cs_missing="${line#CS_MISSING:}"
            ;;
        CAUSAL_MISSING:*)
            causal_missing="${line#CAUSAL_MISSING:}"
            ;;
        FM_TOLERANCE:*)
            fm_flagged="${line#FM_TOLERANCE:}"
            ;;
        ALL_PASS)
            all_pass=1
            ;;
        FM_PASS)
            fm_pass=1
            ;;
    esac
done <<< "$RESULT"

if (( all_pass > 0 )); then
    echo "PASS: 直近self_study/consultationエントリ全てにcs_checklist+causal_chain確認"
fi

if [ -n "$fm_flagged" ]; then
    echo "WARN: APPROVE+FM許容パターン検出(発見≠解決):"
    printf '%s\n' "$fm_flagged" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id: FMを発見しながらmitigationが許容/TBD。REQUEST_CHANGESの再検討を"
    done
    warn=1
elif (( fm_pass > 0 )); then
    echo "PASS: APPROVE+FM許容パターンなし"
fi

warn=0
if [ -n "$fm_flagged" ]; then
    warn=1
fi

if (( all_pass > 0 )) && (( fm_pass > 0 )); then
    exit 0
fi
if [ -n "$cs_missing" ]; then
    cs_count=$(printf '%s\n' "$cs_missing" | tr ',' '\n' | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${cs_count}件のエントリにcs_checklistなし:"
    printf '%s\n' "$cs_missing" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id"
    done
    warn=1
fi
if [ -n "$causal_missing" ]; then
    causal_count=$(printf '%s\n' "$causal_missing" | tr ',' '\n' | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${causal_count}件のエントリにcausal_chainなし:"
    printf '%s\n' "$causal_missing" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id"
    done
    warn=1
fi

exit $warn
