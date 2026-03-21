#!/usr/bin/env bash
# gunshi_review_stats.sh — 軍師レビューログのヘッダ統計を自動計算・更新
# 対象: logs/gunshi_review_log.yaml + logs/archive/gunshi_review_log_*.yaml
# 計算項目: 累計件数/accuracy/verdict分布/忍者別品質/品質Flag頻出
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAIN_LOG="$REPO_ROOT/logs/gunshi_review_log.yaml"
ARCHIVE_DIR="$REPO_ROOT/logs/archive"

if [[ ! -f "$MAIN_LOG" ]]; then
    echo "[gunshi_review_stats] ERROR: $MAIN_LOG not found" >&2
    exit 1
fi

# --- Step 1: Combine all data (archive + main, excluding comments/empty lines) ---
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

for f in "$ARCHIVE_DIR"/gunshi_review_log_*.yaml; do
    [[ -f "$f" ]] && cat "$f" >> "$tmpfile"
done
# Main log: exclude comment lines
grep -v '^#' "$MAIN_LOG" | grep -v '^[[:space:]]*$' >> "$tmpfile" || true

# --- Step 2: Compute stats with awk ---
STATS=$(awk '
BEGIN {
    total=0; drafts=0; reports=0
    approve=0; lgtm_count=0; req_changes=0; fail_count=0
    gate_clear=0; gate_fail=0; gate_null=0
    bc_flag=0
    in_entry=0
    earliest=""
}

/^- cmd_id:/ {
    if (in_entry) process()
    in_entry=1
    review_type=""; verdict=""; gate_result=""; report_ninja=""; lesson_quality=""
    findings=""; ts=""
    next
}

/^[[:space:]]*$/ { next }

in_entry && /^[[:space:]]+review_type:/ {
    v=$0; sub(/.*review_type:[[:space:]]*/, "", v); gsub(/"/, "", v)
    review_type=v; next
}
in_entry && /^[[:space:]]+verdict:/ && !/report_verdict/ {
    v=$0; sub(/.*verdict:[[:space:]]*/, "", v); gsub(/"/, "", v)
    sub(/[[:space:]]*#.*/, "", v)
    verdict=v; next
}
in_entry && /^[[:space:]]+gate_result:/ {
    v=$0; sub(/.*gate_result:[[:space:]]*/, "", v); gsub(/"/, "", v)
    sub(/[[:space:]]*#.*/, "", v)
    gate_result=v; next
}
in_entry && /^[[:space:]]+report_ninja:/ {
    v=$0; sub(/.*report_ninja:[[:space:]]*/, "", v); gsub(/"/, "", v)
    report_ninja=v; next
}
in_entry && /^[[:space:]]+lesson_quality:/ {
    v=$0; sub(/.*lesson_quality:[[:space:]]*/, "", v); gsub(/"/, "", v)
    lesson_quality=v; next
}
in_entry && /^[[:space:]]+findings_summary:/ {
    v=$0; sub(/.*findings_summary:[[:space:]]*/, "", v); gsub(/"/, "", v)
    findings=v; next
}
in_entry && /^[[:space:]]+timestamp:/ {
    v=$0; sub(/.*timestamp:[[:space:]]*/, "", v); gsub(/"/, "", v)
    sub(/T.*/, "", v)
    ts=v; next
}

END {
    if (in_entry) process()

    gate_known = gate_clear + gate_fail
    if (gate_known > 0) {
        accuracy = int(gate_clear * 100 / gate_known + 0.5)
    } else {
        accuracy = -1
    }
    if (total > 0) {
        gate_null_pct = int(gate_null * 100 / total + 0.5)
    } else {
        gate_null_pct = 0
    }

    # Output key=value pairs (safe: all values are numbers or simple strings)
    printf "TOTAL=%d\n", total
    printf "DRAFTS=%d\n", drafts
    printf "REPORTS=%d\n", reports
    printf "APPROVE=%d\n", approve
    printf "LGTM=%d\n", lgtm_count
    printf "REQ_CHANGES=%d\n", req_changes
    printf "FAIL=%d\n", fail_count
    printf "GATE_CLEAR=%d\n", gate_clear
    printf "GATE_FAIL=%d\n", gate_fail
    printf "GATE_NULL=%d\n", gate_null
    printf "GATE_KNOWN=%d\n", gate_known
    printf "ACCURACY=%d\n", accuracy
    printf "GATE_NULL_PCT=%d\n", gate_null_pct
    printf "BC_FLAG=%d\n", bc_flag
    printf "EARLIEST=%s\n", earliest

    # Ninja quality: WEAK
    weak_str=""
    for (n in ninja_weak) {
        jp = get_jp(n)
        if (weak_str != "") weak_str = weak_str ","
        weak_str = weak_str jp ninja_weak[n] "回"
    }
    printf "NINJA_WEAK=%s\n", weak_str

    # Ninja quality: HIGH
    high_str=""
    for (n in ninja_high) {
        jp = get_jp(n)
        if (high_str != "") high_str = high_str ","
        high_str = high_str jp ninja_high[n]
    }
    printf "NINJA_HIGH=%s\n", high_str
}

function process() {
    total = total + 1

    # Classify draft/report
    if (review_type == "draft") {
        drafts = drafts + 1
    } else if (review_type == "report") {
        reports = reports + 1
    } else if (verdict == "APPROVE" || verdict == "REQUEST_CHANGES") {
        drafts = drafts + 1
    } else {
        reports = reports + 1
    }

    # Verdict distribution
    if (verdict == "APPROVE") approve = approve + 1
    else if (verdict == "LGTM") lgtm_count = lgtm_count + 1
    else if (verdict == "REQUEST_CHANGES") req_changes = req_changes + 1
    else if (verdict == "FAIL") fail_count = fail_count + 1

    # Gate result
    if (gate_result == "CLEAR") gate_clear = gate_clear + 1
    else if (gate_result == "FAIL") gate_fail = gate_fail + 1
    else gate_null = gate_null + 1

    # Ninja quality (report entries only)
    if (report_ninja != "" && lesson_quality != "") {
        if (lesson_quality == "HIGH") ninja_high[report_ninja] = ninja_high[report_ninja] + 1
        else if (lesson_quality == "WEAK") ninja_weak[report_ninja] = ninja_weak[report_ninja] + 1
    }

    # Quality flags: binary_checks issues (exclude positive mentions)
    if (index(findings, "binary_checks") > 0) {
        is_positive = 0
        # Positive patterns: 全yes, 全PASS, 全true, 正規YAML, 全明示PASS, PASS alone
        if ((index(findings, "全yes") > 0 || index(findings, "全PASS") > 0 || \
             index(findings, "全true") > 0 || index(findings, "正規YAML") > 0 || \
             index(findings, "全明示") > 0 || index(findings, "binary_checks PASS") > 0) && \
            index(findings, "欠落") == 0 && index(findings, "非独立") == 0 && \
            index(findings, "非標準") == 0 && index(findings, "未記入") == 0 && \
            index(findings, "文字列") == 0 && index(findings, "内包") == 0 && \
            index(findings, "JSON") == 0) {
            is_positive = 1
        }
        # Template changes (adding binary_checks to templates)
        if (index(findings, "binary_checks/verdict追加") > 0 && index(findings, "欠落") == 0) {
            is_positive = 1
        }
        # Existence verification
        if (index(findings, "binary_checks存在検証") > 0 && index(findings, "欠落") == 0) {
            is_positive = 1
        }
        if (!is_positive) bc_flag = bc_flag + 1
    }

    # Earliest date
    if (ts != "" && (earliest == "" || ts < earliest)) earliest = ts
}

function get_jp(name) {
    if (name == "hayate") return "疾風"
    if (name == "kagemaru") return "影丸"
    if (name == "hanzo") return "半蔵"
    if (name == "saizo") return "才蔵"
    if (name == "kotaro") return "小太郎"
    if (name == "tobisaru") return "飛猿"
    return name
}
' "$tmpfile")

# --- Step 3: Parse stats into shell variables ---
eval "$STATS"

# --- Step 4: Build replacement header lines ---
total_line="# 累計: ${TOTAL}件 (draft:${DRAFTS}, report:${REPORTS}) | ${EARLIEST}〜"

if [[ $ACCURACY -ge 0 ]]; then
    accuracy_line="# accuracy: gate_result判明分 ${ACCURACY}% (${GATE_CLEAR}/${GATE_KNOWN} CLEAR, ${GATE_FAIL} FAIL)"
else
    accuracy_line="# accuracy: gate_result判明分 N/A (判明0件)"
fi
null_line="#   未判明: ${GATE_NULL}件(${GATE_NULL_PCT}%)"

verdict_line="# verdict分布: APPROVE:${APPROVE} LGTM:${LGTM} REQ_CHANGES:${REQ_CHANGES} FAIL:${FAIL}"

flag_line="# 品質Flag頻出: binary_checks関連(${BC_FLAG}回)"

# Ninja quality
ninja_line="# 忍者別品質:"
if [[ -n "${NINJA_WEAK:-}" ]]; then
    ninja_line="${ninja_line} WEAK=${NINJA_WEAK}"
fi
if [[ -n "${NINJA_HIGH:-}" ]]; then
    [[ -n "${NINJA_WEAK:-}" ]] && ninja_line="${ninja_line} /"
    ninja_line="${ninja_line} HIGH=${NINJA_HIGH}"
fi
if [[ -z "${NINJA_WEAK:-}" && -z "${NINJA_HIGH:-}" ]]; then
    ninja_line="${ninja_line} (特記なし)"
fi

# --- Step 5: Replace auto-computed lines in the header ---
awk -v total_line="$total_line" \
    -v accuracy_line="$accuracy_line" \
    -v null_line="$null_line" \
    -v verdict_line="$verdict_line" \
    -v flag_line="$flag_line" \
    -v ninja_line="$ninja_line" \
'
/^# 累計:/ { print total_line; next }
/^# accuracy:/ { print accuracy_line; next }
/^#[[:space:]]+未判明:/ { print null_line; next }
/^# verdict分布:/ { print verdict_line; next }
/^# 品質Flag頻出:/ { print flag_line; next }
/^# 忍者別品質:/ { print ninja_line; next }
{ print }
' "$MAIN_LOG" > "${MAIN_LOG}.tmp"

mv "${MAIN_LOG}.tmp" "$MAIN_LOG"

echo "[gunshi_review_stats] ヘッダ更新完了: ${TOTAL}件 (draft:${DRAFTS}, report:${REPORTS}), accuracy:${ACCURACY}%, verdict:A${APPROVE}/L${LGTM}/R${REQ_CHANGES}/F${FAIL}"
