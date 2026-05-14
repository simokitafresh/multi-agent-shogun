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
    } else if ($0 ~ /^[[:space:]]*cs_checklist:/) {
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
cold_category_missing=""
skill_usage_missing=""
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

cold_category_missing=$(python3 - "$LOG_FILE" <<'PY' 2>/dev/null || true
import re
import sys

path = sys.argv[1]
catalog = [
    ("assumptions", 10, [r"assumption", r"前提"]),
    ("numbers", 10, [r"number", r"数値", r"再計算", r"分母", r"分子"]),
    ("simulation", 10, [r"simulation", r"時系列", r"依存", r"並列", r"衝突"]),
    ("premortem", 10, [r"premortem", r"失敗", r"failure", r"リスク", r"silent fallback"]),
    ("north_star", 10, [r"north.?star", r"複利", r"品質向上", r"消火"]),
    ("ambiguity", 10, [r"ambiguity", r"曖昧", r"不明瞭"]),
    ("adversarial", 10, [r"adversarial", r"red.?team", r"chaos", r"攻撃"]),
]

entries = []
current = None
capture_categories = False

def clean(value):
    return value.strip().strip("\"'")

def flush():
    global current
    if current:
        entries.append(current)
    current = None

with open(path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if re.match(r"^- (cmd_id|id):", line):
            flush()
            current = {"id": "?", "review_type": "", "finding_categories": [], "text": []}
            value = re.sub(r"^- (cmd_id|id):\s*", "", line)
            current["id"] = clean(value) or "?"
            capture_categories = False
        if current is None:
            continue
        current["text"].append(line)
        if re.match(r"^\s{2}review_type:\s*", line):
            current["review_type"] = clean(re.sub(r"^\s{2}review_type:\s*", "", line))
            capture_categories = False
            continue
        if re.match(r"^\s{2}finding_categories:\s*\[", line):
            values = re.sub(r"^\s{2}finding_categories:\s*\[|\]\s*$", "", line).strip()
            if values:
                current["finding_categories"].extend(clean(v) for v in values.split(",") if clean(v))
            capture_categories = False
            continue
        if re.match(r"^\s{2}finding_categories:\s*$", line):
            capture_categories = True
            continue
        if capture_categories:
            if re.match(r"^\s{4}-\s*", line):
                current["finding_categories"].append(clean(re.sub(r"^\s{4}-\s*", "", line)))
                continue
            capture_categories = False

flush()
reviews = [e for e in entries if e["review_type"] in ("draft", "report")]
start = max(0, len(reviews) - 20)
warnings = []
for idx in range(start, len(reviews)):
    entry = reviews[idx]
    entry_categories = {c.lower() for c in entry["finding_categories"]}
    previous = reviews[max(0, idx - 10):idx]
    if len(previous) < 10:
        continue
    missing = []
    for name, threshold, patterns in catalog:
        cold = True
        for prev in previous[-threshold:]:
            categories = {c.lower() for c in prev["finding_categories"]}
            haystack = "\n".join(prev["text"]).lower()
            if name in categories or any(re.search(pattern, haystack) for pattern in patterns):
                cold = False
                break
        if cold and name not in entry_categories:
            missing.append(name)
    if missing:
        warnings.append(f"{entry['id']}:{','.join(missing)}")

print("\n".join(warnings))
PY
)

skill_usage_missing=$(python3 - "$REPO_ROOT" "$LOG_FILE" <<'PY' 2>/dev/null || true
import os
import sys

import yaml

root = sys.argv[1]
review_log_path = sys.argv[2]

def load_yaml(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return {}
    except yaml.YAMLError:
        return {}

def as_list(value):
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip().lstrip("/") for item in value if str(item).strip()]
    if isinstance(value, dict):
        return [str(item).strip().lstrip("/") for item in value.values() if str(item).strip()]
    text = str(value).strip()
    if not text:
        return []
    if "," in text:
        return [part.strip().lstrip("/") for part in text.split(",") if part.strip()]
    return [text.lstrip("/")]

def normalize_path(path):
    if not path:
        return ""
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(root, path))

def source_matches(source, report_path):
    if not source or not report_path:
        return False
    source_text = str(source).strip()
    report_abs = normalize_path(report_path)
    source_abs = normalize_path(source_text)
    return (
        source_text == report_path
        or source_abs == report_abs
        or os.path.basename(source_text) == os.path.basename(report_path)
    )

review_data = load_yaml(review_log_path)
if isinstance(review_data, dict):
    reviews = review_data.get("reviews") or []
elif isinstance(review_data, list):
    reviews = review_data
else:
    reviews = []

skill_log = load_yaml(os.path.join(root, "logs", "skill_execution_log.yaml"))
if isinstance(skill_log, dict):
    skill_entries = skill_log.get("executions") or []
elif isinstance(skill_log, list):
    skill_entries = skill_log
else:
    skill_entries = []

warnings = []
for entry in [item for item in reviews if isinstance(item, dict) and item.get("review_type") == "report"][-20:]:
    ninja = str(entry.get("report_ninja") or "").strip()
    report_task_id = str(entry.get("report_task_id") or "").strip()
    if not ninja or not report_task_id:
        continue

    task_path = os.path.join(root, "queue", "tasks", f"{ninja}.yaml")
    task_data = load_yaml(task_path)
    task = task_data.get("task") if isinstance(task_data, dict) else None
    if not isinstance(task, dict):
        continue
    if str(task.get("task_id") or "").strip() != report_task_id:
        continue

    recommended = set(as_list(task.get("recommended_skills")))
    if not recommended:
        continue

    report_path = str(task.get("report_path") or "").strip()
    if not report_path:
        report_path = os.path.join("queue", "reports", f"{ninja}_report_{entry.get('cmd_id')}.yaml")

    used = set()
    report_data = load_yaml(normalize_path(report_path))
    if isinstance(report_data, dict):
        for key in ("used_skills", "skills_used", "skill_usage"):
            value = report_data.get(key)
            if isinstance(value, dict):
                used.update(as_list(value.get("used") or value.get("skills") or value))
            else:
                used.update(as_list(value))

    for skill_entry in skill_entries:
        if not isinstance(skill_entry, dict):
            continue
        if str(skill_entry.get("used", "true")).strip().lower() == "false":
            continue
        if not source_matches(skill_entry.get("source"), report_path):
            continue
        skill_name = str(skill_entry.get("skill") or "").strip().lstrip("/")
        if skill_name:
            used.add(skill_name)

    missing = sorted(recommended - used)
    if missing:
        warnings.append(f"{entry.get('cmd_id', '?')}:{','.join(missing)}")

print("\n".join(warnings))
PY
)

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

if (( all_pass > 0 )) && (( fm_pass > 0 )) && [ -z "$ambiguity_missing" ] && [ -z "$single_scenario" ] && [ -z "$adversarial_missing" ] && [ -z "$cold_category_missing" ] && [ -z "$skill_usage_missing" ]; then
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
if [ -n "$cold_category_missing" ]; then
    cold_count=$(printf '%s\n' "$cold_category_missing" | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${cold_count}件のdraft/reportで冷え観点がfinding_categoriesに未反映:"
    printf '%s\n' "$cold_category_missing" | while IFS=: read -r id categories; do
        [ -n "$id" ] && echo "  - $id: cold_categories=${categories}"
    done
    warn=1
fi
if [ -n "$skill_usage_missing" ]; then
    skill_usage_count=$(printf '%s\n' "$skill_usage_missing" | awk 'NF{c++} END{print c+0}')
    echo "WARN: ${skill_usage_count}件のreportでrecommended_skills未使用:"
    printf '%s\n' "$skill_usage_missing" | while IFS=: read -r id skills; do
        [ -n "$id" ] && echo "  - $id: missing_skills=${skills}。REQ_CHANGESを検討せよ"
    done
    warn=1
fi

# --- LG034: 低ROI/対応不要の言語検出 ---
_lg034_hits=$(grep -n '低ROI\|対応不要\|コスト>効果で見送り\|効果が薄い\|優先度低' "$REVIEW_LOG" 2>/dev/null | grep -v '^#' | head -5)
if [ -n "$_lg034_hits" ]; then
    echo "WARN(LG034): 「低ROI/対応不要」表現検出。全件対応が前提、順番を付けて全部やれ:"
    printf '%s\n' "$_lg034_hits" | head -3
    warn=1
fi

# --- LG010: GP提案のdefense_level < 4 検出 ---
_lg010_weak=$(grep -B2 'defense_level: [123]$' "$REVIEW_LOG" 2>/dev/null | grep 'id: GP-' | head -5)
if [ -n "$_lg010_weak" ]; then
    echo "WARN(LG010): defense_level<4のGP提案あり。Level4(フロー内BLOCK)以上を目指せ:"
    printf '%s\n' "$_lg010_weak" | sed 's/.*id: /  /' | head -3
    warn=1
fi

# --- LG033: GP提案前の既存実装grep確認 ---
# proposalsにGP-xxxがあるのに、同エントリのobservationsにgrep/git show/find等の確認証跡がないケースを検出
_lg033_gp_entries=$(grep -n 'id: GP-' "$REVIEW_LOG" 2>/dev/null | grep -v '^#' | tail -5)
if [ -n "$_lg033_gp_entries" ]; then
    while IFS=: read -r _line_no _rest; do
        _gp_id=$(echo "$_rest" | sed 's/.*GP-/GP-/;s/[^0-9a-zA-Z_-].*//')
        # 前後20行内にgrep/git show/findの証跡があるか
        _evidence=$(sed -n "$((_line_no-10)),$((_line_no+10))p" "$REVIEW_LOG" 2>/dev/null | grep -ic 'grep\|git show\|find.*-name\|既存.*確認\|existing.*check' || true)
        if [ "${_evidence:-0}" -eq 0 ]; then
            echo "WARN(LG033): ${_gp_id}に既存実装の確認証跡なし。grep/git showで既存を確認してからGP提案せよ"
            warn=1
        fi
    done <<< "$_lg033_gp_entries"
fi

exit $warn
