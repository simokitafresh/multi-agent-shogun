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
        draft_obs_count[draft_count] = obs_count
        draft_verdict[draft_count] = verdict
        draft_has_ambiguity[draft_count] = has_ambiguity
        draft_ambiguity[draft_count] = ambiguity_text
        draft_changed_lines[draft_count] = changed_lines + 0
        draft_has_adv[draft_count] = has_adversarial
        draft_adv_required[draft_count] = adversarial_required
    }

    in_record = 0
    entry_id = ""
    review_type = ""
    verdict = ""
    has_cs = 0
    has_causal = 0
    has_ambiguity = 0
    ambiguity_text = ""
    changed_lines = 0
    has_adversarial = 0
    adversarial_required = 0
    in_obs = 0
    obs_count = 0
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
    } else if ($0 ~ /^[[:space:]]*ambiguity_points:[[:space:]]*/) {
        has_ambiguity = 1
        line = $0
        sub(/^[[:space:]]*ambiguity_points:[[:space:]]*/, "", line)
        gsub(/["'\''"]/, "", line)
        ambiguity_text = trim(line)
    } else if ($0 ~ /^[[:space:]]*changed_lines:[[:space:]]*[0-9]+/) {
        line = $0
        sub(/^[[:space:]]*changed_lines:[[:space:]]*/, "", line)
        gsub(/[^0-9]/, "", line)
        changed_lines = line + 0
    } else if ($0 ~ /^[[:space:]]*adversarial_review:[[:space:]]*$/) {
        has_adversarial = 1
    } else if ($0 ~ /^[[:space:]]*required:[[:space:]]*(true|yes)/) {
        adversarial_required = 1
    }

    if ($0 ~ /^[[:space:]]*observations:[[:space:]]*$/) {
        in_obs = 1
        next
    }
    if (in_obs) {
        if ($0 ~ /^[[:space:]]{4,}- /) {
            obs_text = obs_text "\n" $0
            obs_count++
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
    ambiguity_missing_count = 0
    single_scenario_count = 0
    convergence_once_count = 0
    adversarial_missing_count = 0
    for (i = 1; i <= draft_count; i++) {
        has_fm = (draft_obs[i] ~ fm_pat)
        has_tolerance = (draft_obs[i] ~ tol_pat)
        zero_ambiguity = (tolower(draft_ambiguity[i]) ~ /^(none|なし|0|\[\]|\{\})$/)
        if (i >= start_draft && draft_verdict[i] == "APPROVE" && has_fm && has_tolerance) {
            fm_flagged[++fm_flagged_count] = draft_id[i]
        }
        if (i >= start_draft && !draft_has_ambiguity[i]) {
            ambiguity_missing[++ambiguity_missing_count] = draft_id[i]
        }
        if (i >= start_draft && draft_obs_count[i] <= 1) {
            single_scenario[++single_scenario_count] = draft_id[i]
        }
        if (i >= start_draft && zero_ambiguity && zero_ambiguity_seen[draft_id[i]] == 0) {
            convergence_once[++convergence_once_count] = draft_id[i]
        }
        if (i >= start_draft && draft_changed_lines[i] >= 200 && !draft_has_adv[i]) {
            adversarial_missing[++adversarial_missing_count] = draft_id[i] "(changed_lines=" draft_changed_lines[i] ")"
        }
        if (i >= start_draft && draft_adv_required[i] && !draft_has_adv[i]) {
            adversarial_missing[++adversarial_missing_count] = draft_id[i] "(required=true)"
        }
        if (zero_ambiguity) {
            zero_ambiguity_seen[draft_id[i]]++
        }
    }

    emit_list("CS_MISSING:", cs_missing, cs_missing_count)
    emit_list("CAUSAL_MISSING:", causal_missing, causal_missing_count)
    emit_list("FM_TOLERANCE:", fm_flagged, fm_flagged_count)
    emit_list("AMBIGUITY_MISSING:", ambiguity_missing, ambiguity_missing_count)
    emit_list("SINGLE_SCENARIO:", single_scenario, single_scenario_count)
    emit_list("CONVERGENCE_ONCE:", convergence_once, convergence_once_count)
    emit_list("ADVERSARIAL_MISSING:", adversarial_missing, adversarial_missing_count)
    if (cs_missing_count == 0 && causal_missing_count == 0) print "ALL_PASS"
    if (fm_flagged_count == 0) print "FM_PASS"
}
' "$LOG_FILE" 2>/dev/null)

cs_missing=""
causal_missing=""
fm_flagged=""
ambiguity_missing=""
single_scenario=""
convergence_once=""
adversarial_missing=""
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
        AMBIGUITY_MISSING:*)
            ambiguity_missing="${line#AMBIGUITY_MISSING:}"
            ;;
        SINGLE_SCENARIO:*)
            single_scenario="${line#SINGLE_SCENARIO:}"
            ;;
        CONVERGENCE_ONCE:*)
            convergence_once="${line#CONVERGENCE_ONCE:}"
            ;;
        ADVERSARIAL_MISSING:*)
            adversarial_missing="${line#ADVERSARIAL_MISSING:}"
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

if [ -n "$convergence_once" ]; then
    echo "INFO: ambiguity_points=0 が1回だけのdraftを検出。mizchi Red flag『不明瞭点0が1回出たから終わり』を避け、連続ゼロ収束を確認せよ:"
    printf '%s\n' "$convergence_once" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id"
    done
fi

if (( all_pass > 0 )) && (( fm_pass > 0 )) && [ -z "$ambiguity_missing" ] && [ -z "$single_scenario" ] && [ -z "$adversarial_missing" ]; then
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
if [ -n "$ambiguity_missing" ]; then
    ambiguity_count=$(printf '%s\n' "$ambiguity_missing" | tr ',' '\n' | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${ambiguity_count}件のdraftエントリにambiguity_pointsなし:"
    printf '%s\n' "$ambiguity_missing" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id"
    done
    warn=1
fi
if [ -n "$single_scenario" ]; then
    single_scenario_count=$(printf '%s\n' "$single_scenario" | tr ',' '\n' | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${single_scenario_count}件のdraftエントリが1シナリオ観測のみ:"
    printf '%s\n' "$single_scenario" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id: 観測が1件のみ。mizchi Red flag『1シナリオで充分』の可能性"
    done
    warn=1
fi
if [ -n "$adversarial_missing" ]; then
    adversarial_count=$(printf '%s\n' "$adversarial_missing" | tr ',' '\n' | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${adversarial_count}件のdraftエントリでAdversarial review欠落:"
    printf '%s\n' "$adversarial_missing" | tr ',' '\n' | while read -r id; do
        [ -n "$id" ] && echo "  - $id: changed_lines>=200 なのに adversarial_review 記録なし"
    done
    warn=1
fi

exit $warn
