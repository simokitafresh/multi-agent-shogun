#!/bin/bash
# semantic-links: [[Silent Fallback品質]]
# gate_gunshi_cs_checklist.sh — consultation/self_studyエントリのCS観点チェックリスト強制
# @source: cmd_1494 (CoDD分析4サイクルで自己検出率0%→CS観点プロトコル定義)
# 知性の外部化: CS観点を軍師の意志に依存させず、自動検証で強制
# Usage: bash scripts/gates/gate_gunshi_cs_checklist.sh
# Exit: 0=PASS(全エントリにcs_checklist), 1=WARN(欠落あり)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# set +e: CS gateはWARN集計。grep/awkの非0 exitでスクリプト全体が死なないよう保護
set +e
LOG_FILE="$REPO_ROOT/logs/gunshi_review_log.yaml"
STDERR_LOG="$REPO_ROOT/logs/gate_gunshi_cs_checklist_stderr.log"

log_stderr_file() {
    local label="$1"
    local stderr_file="$2"
    local line

    [ -s "$stderr_file" ] || return 0
    mkdir -p "$(dirname "$STDERR_LOG")" 2>/dev/null || true
    while IFS= read -r line; do
        printf '%s %s: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$label" "$line" >> "$STDERR_LOG" || true
    done < "$stderr_file"
}

csv_count() {
    local csv="$1"
    local count=0
    local item

    [ -n "$csv" ] || {
        echo 0
        return 0
    }
    IFS=',' read -ra items <<< "$csv"
    for item in "${items[@]}"; do
        [ -n "$item" ] && count=$((count + 1))
    done
    echo "$count"
}

if [ ! -f "$LOG_FILE" ]; then
    echo "ALERT: gunshi_review_log.yaml not found — レビューログ不在は異常"
    exit 1
fi

awk_stderr_tmp="$(mktemp)"
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
        ss_has_ops_sim[ss_count] = has_ops_sim
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
        draft_has_hole_action[draft_count] = has_hole_action
        draft_confidence[draft_count] = confidence
        draft_has_brainwash[draft_count] = has_brainwash
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
    has_hole_action = 0
    confidence = ""
    has_brainwash = 0
    has_ops_sim = 0
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
    } else if ($0 ~ /^[[:space:]]*hole_action:[[:space:]]*/) {
        has_hole_action = 1
    } else if ($0 ~ /^[[:space:]]*confidence:[[:space:]]*/) {
        line = $0
        sub(/^[[:space:]]*confidence:[[:space:]]*/, "", line)
        gsub(/["'\''"]/, "", line)
        confidence = toupper(trim(line))
    } else if ($0 ~ /^[[:space:]]*brainwash_check:/) {
        has_brainwash = 1
    } else if ($0 ~ /^[[:space:]]*operational_simulation:/) {
        has_ops_sim = 1
    } else if ($0 ~ /^[[:space:]]*step3_5_verified:/) {
        has_step35 = 1
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
    hole_action_missing_count = 0
    brainwash_missing_count = 0
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
        if (i >= start_draft && draft_obs_count[i] <= 1 && draft_id[i] !~ /^cmd_training_speed_/) {
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
        if (i >= start_draft && draft_verdict[i] == "REQUEST_CHANGES" && !draft_has_hole_action[i]) {
            hole_action_missing[++hole_action_missing_count] = draft_id[i]
        }
        if (i >= start_draft && !draft_has_brainwash[i]) {
            brainwash_missing[++brainwash_missing_count] = draft_id[i]
        }
        if (zero_ambiguity) {
            zero_ambiguity_seen[draft_id[i]]++
        }
    }

    ops_sim_missing_count = 0
    for (i = start_ss; i <= ss_count; i++) {
        if (!ss_has_ops_sim[i]) ops_sim_missing[++ops_sim_missing_count] = ss_id[i]
    }

    emit_list("CS_MISSING:", cs_missing, cs_missing_count)
    emit_list("CAUSAL_MISSING:", causal_missing, causal_missing_count)
    emit_list("OPS_SIM_MISSING:", ops_sim_missing, ops_sim_missing_count)
    emit_list("FM_TOLERANCE:", fm_flagged, fm_flagged_count)
    emit_list("AMBIGUITY_MISSING:", ambiguity_missing, ambiguity_missing_count)
    emit_list("SINGLE_SCENARIO:", single_scenario, single_scenario_count)
    emit_list("CONVERGENCE_ONCE:", convergence_once, convergence_once_count)
    emit_list("ADVERSARIAL_MISSING:", adversarial_missing, adversarial_missing_count)
    emit_list("HOLE_ACTION_MISSING:", hole_action_missing, hole_action_missing_count)
    emit_list("BRAINWASH_MISSING:", brainwash_missing, brainwash_missing_count)
    if (cs_missing_count == 0 && causal_missing_count == 0) print "ALL_PASS"
    if (fm_flagged_count == 0) print "FM_PASS"
}
' "$LOG_FILE" 2>"$awk_stderr_tmp" || true)
log_stderr_file "review_log awk" "$awk_stderr_tmp"
rm -f "$awk_stderr_tmp"

if [ -z "$RESULT" ]; then
    echo "WARN: review_log解析失敗(awk空結果)。CS観点チェックをスキップ" >&2
fi

cs_missing=""
causal_missing=""
fm_flagged=""
ambiguity_missing=""
single_scenario=""
convergence_once=""
adversarial_missing=""
hole_action_missing=""
brainwash_missing=""
cold_category_missing=""
skill_usage_missing=""
ops_sim_missing=""
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
        HOLE_ACTION_MISSING:*)
            hole_action_missing="${line#HOLE_ACTION_MISSING:}"
            ;;
        OPS_SIM_MISSING:*)
            ops_sim_missing="${line#OPS_SIM_MISSING:}"
            ;;
        BRAINWASH_MISSING:*)
            brainwash_missing="${line#BRAINWASH_MISSING:}"
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
import re
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

def unquote(value):
    return str(value or "").strip().strip("\"'")

def parse_review_reports(path):
    reports = []
    current = None
    wanted = {"cmd_id", "id", "review_type", "report_ninja", "report_task_id"}
    try:
        fh = open(path, encoding="utf-8")
    except FileNotFoundError:
        return []
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if re.match(r"^- (cmd_id|id):", line):
                if current and current.get("review_type") == "report":
                    reports.append(current)
                current = {}
                key, value = line[2:].split(":", 1)
                current["cmd_id"] = unquote(value)
                continue
            if current is None:
                continue
            if re.match(r"^\s{2}[a-z_]+:\s*", line):
                key, value = line.strip().split(":", 1)
                if key in wanted:
                    current[key] = unquote(value)
    if current and current.get("review_type") == "report":
        reports.append(current)
    return reports

def parse_skill_execution_log(path):
    entries = []
    current = None
    wanted = {"skill", "source", "used"}
    try:
        fh = open(path, encoding="utf-8")
    except FileNotFoundError:
        return []
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("- "):
                if current:
                    entries.append(current)
                current = {}
                rest = line[2:].strip()
                if ":" in rest:
                    key, value = rest.split(":", 1)
                    if key.strip() in wanted:
                        current[key.strip()] = unquote(value)
                continue
            if current is None:
                continue
            if line.startswith("  ") and ":" in line.strip():
                key, value = line.strip().split(":", 1)
                if key in wanted:
                    current[key] = unquote(value)
    if current:
        entries.append(current)
    return entries

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

reviews = parse_review_reports(review_log_path)
skill_entries = parse_skill_execution_log(os.path.join(root, "logs", "skill_execution_log.yaml"))

warnings = []
for entry in reviews[-20:]:
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
    IFS=',' read -ra items <<< "$fm_flagged"
    for id in "${items[@]}"; do
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
    IFS=',' read -ra items <<< "$convergence_once"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id"
    done
fi

# early exit削除: L6/L4/L4bのチェックも全て通過させる(2026-06-08 set +e修正時に発見)
# 旧: all_pass+fm_pass+各変数空→exit 0でL6以降スキップ
# 新: exit 0せずfall-throughしてL6/L4/L4bも実行
if [ -n "$cs_missing" ]; then
    cs_count=$(csv_count "$cs_missing")
    echo "WARN: ${cs_count}件のエントリにcs_checklistなし:"
    IFS=',' read -ra items <<< "$cs_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id"
    done
    warn=1
fi
if [ -n "$causal_missing" ]; then
    causal_count=$(csv_count "$causal_missing")
    echo "WARN: ${causal_count}件のエントリにcausal_chainなし:"
    IFS=',' read -ra items <<< "$causal_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id"
    done
    warn=1
fi
if [ -n "$ambiguity_missing" ]; then
    ambiguity_count=$(csv_count "$ambiguity_missing")
    echo "WARN: ${ambiguity_count}件のdraftエントリにambiguity_pointsなし:"
    IFS=',' read -ra items <<< "$ambiguity_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id"
    done
    warn=1
fi
if [ -n "$single_scenario" ]; then
    single_scenario_count=$(csv_count "$single_scenario")
    echo "WARN(GP-262): ${single_scenario_count}件のdraftエントリが1シナリオ観測のみ。定型cmdでも最低2観測シナリオを記録せよ:"
    IFS=',' read -ra items <<< "$single_scenario"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id: 観測が1件のみ。mizchi Red flag『1シナリオで充分』の可能性"
    done
    warn=1
fi
if [ -n "$adversarial_missing" ]; then
    adversarial_count=$(csv_count "$adversarial_missing")
    echo "WARN: ${adversarial_count}件のdraftエントリでAdversarial review欠落:"
    IFS=',' read -ra items <<< "$adversarial_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id: changed_lines>=200 なのに adversarial_review 記録なし"
    done
    warn=1
fi
if [ -n "$hole_action_missing" ]; then
    hole_count=$(csv_count "$hole_action_missing")
    echo "WARN: ${hole_count}件のREQUEST_CHANGESにhole_action未記入(穴を即ふさいだか？殿厳命2026-05-24):"
    IFS=',' read -ra items <<< "$hole_action_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id: hole_action: none/d0_implemented/cmd_proposed を記入せよ"
    done
    warn=1
fi
if [ -n "$ops_sim_missing" ]; then
    ops_count=$(csv_count "$ops_sim_missing")
    echo "WARN: ${ops_count}件のconsultation/self_studyにoperational_simulation未記入(構造有無ではなく実運用で何が起きるかをStep3で検証せよ。殿指摘2026-05-27):"
    IFS=',' read -ra items <<< "$ops_sim_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id: operational_simulation: 実運用シミュレーション結果を記入せよ"
    done
    warn=1
fi
if [ -n "$brainwash_missing" ]; then
    brainwash_count=$(csv_count "$brainwash_missing")
    echo "WARN: ${brainwash_count}件のdraftにbrainwash_check未記入(全confidence level必須):"
    IFS=',' read -ra items <<< "$brainwash_missing"
    for id in "${items[@]}"; do
        [ -n "$id" ] && echo "  - $id: 創造主の洗脳/ポジショントークに乗っていないか自問し、brainwash_checkを記入せよ"
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
_lg034_hits=$(grep -n '低ROI\|対応不要\|コスト>効果で見送り\|効果が薄い\|優先度低' "$LOG_FILE" 2>/dev/null | grep -v '^#' | head -5)
if [ -n "$_lg034_hits" ]; then
    echo "WARN(LG034): 「低ROI/対応不要」表現検出。全件対応が前提、順番を付けて全部やれ:"
    printf '%s\n' "$_lg034_hits" | head -3
    warn=1
fi

# --- §5.6: 自動化系cmd×adversarial交差チェック ---
# target_path=scripts/のdraft/reportでfinding_categoriesにadversarialがないケースを検出
_automation_no_adv=$(awk '
    /^- (cmd_id|id):/ { id=substr($0,index($0,":")+2); gsub(/[" \t]/,"",id); fc=""; obs=""; rt="" }
    /^  review_type:/ { rt=substr($0,index($0,":")+2); gsub(/[" \t]/,"",rt) }
    /^  finding_categories:.*\[/ { fc=$0 }
    /^    - .*/ { obs=obs " " $0 }
    /^  timestamp:/ && rt ~ /draft|report/ && fc !~ /adversarial/ && id != "" {
        if (id ~ /^cmd_training_speed_/) next  # 速度修行cmd=コード変更なし理解テスト。adversarial不要(GP-263)
        if (obs ~ /scripts\/|\.sh|gate_|hook_|monitor|deploy_task|cron|cleanup|trigger/) {
            print id
        }
        obs=""
    }
' "$LOG_FILE" 2>/dev/null | tail -10)
if [ -n "$_automation_no_adv" ]; then
    echo "WARN(§5.6): 自動化系cmd(scripts/対象)でadversarial未検討:"
    printf '%s\n' "$_automation_no_adv" | while read -r _id; do
        [ -n "$_id" ] && echo "  - $_id: finding_categoriesにadversarialを追加せよ"
    done
    warn=1
fi

# --- LG010: GP提案のdefense_level < 4 検出 ---
_lg010_weak=$(grep -B2 'defense_level: [123]$' "$LOG_FILE" 2>/dev/null | grep 'id: GP-' | head -5)
if [ -n "$_lg010_weak" ]; then
    echo "WARN(LG010): defense_level<4のGP提案あり。Level4(フロー内BLOCK)以上を目指せ:"
    printf '%s\n' "$_lg010_weak" | sed 's/.*id: /  /' | head -3
    warn=1
fi

# --- LG033: GP提案前の既存実装grep確認 ---
# proposalsにGP-xxxがあるのに、同エントリのobservationsにgrep/git show/find等の確認証跡がないケースを検出
_lg033_gp_entries=$(grep -n 'id: GP-' "$LOG_FILE" 2>/dev/null | grep -v '^#' | tail -5)
if [ -n "$_lg033_gp_entries" ]; then
    while IFS=: read -r _line_no _rest; do
        _gp_id=$(echo "$_rest" | sed 's/.*GP-/GP-/;s/[^0-9a-zA-Z_-].*//')
        # 前後20行内にgrep/git show/findの証跡があるか
        _evidence=$(sed -n "$((_line_no-10)),$((_line_no+10))p" "$LOG_FILE" 2>/dev/null | grep -ic 'grep\|git show\|find.*-name\|既存.*確認\|existing.*check' || true)
        if [ "${_evidence:-0}" -eq 0 ]; then
            echo "WARN(LG033): ${_gp_id}に既存実装の確認証跡なし。grep/git showで既存を確認してからGP提案せよ"
            warn=1
        fi
    done <<< "$_lg033_gp_entries"
fi

# --- CS-X: 三層記憶活用+[MEM]関連性検証 (Step 1.7参照) ---
# 将軍の回答に[MEM:]タグが含まれるか、および memory_md禁止ルールを検証する
_lord_conv_file="/mnt/c/tools/multi-agent-shogun/data/lord_conversation.jsonl"
if [ -f "$_lord_conv_file" ]; then
    # 最新20件の将軍応答で[MEM]タグ引用率を計測
    _shogun_responses=$(tail -200 "$_lord_conv_file" 2>/dev/null | grep '"direction":"response"' | tail -20)
    _response_count=$(echo "$_shogun_responses" | grep -c '"direction"' 2>/dev/null || true)
    _mem_response_count=$(echo "$_shogun_responses" | grep -c '\[MEM:' 2>/dev/null || true)
    if [ "${_response_count:-0}" -gt 3 ] && [ "${_mem_response_count:-0}" -eq 0 ]; then
        echo "WARN(CS-X.a): 直近${_response_count}件の将軍回答に[MEM:]タグなし。三層記憶(Step 1.7)が使われていない可能性"
        warn=1
    fi
    # memory_mdソース禁止チェック (MEMORY.mdは索引。回答の根拠禁止)
    _memory_md_count=$(echo "$_shogun_responses" | grep -c '\[MEM: memory_md' 2>/dev/null || true)
    if [ "${_memory_md_count:-0}" -gt 0 ]; then
        echo "WARN(CS-X.b): [MEM: memory_md]が${_memory_md_count}件検出。MEMORY.md参照禁止(Step 1.7: source=memory_md不可)"
        warn=1
    fi
fi

# --- L6: GATE CLEAR≠レビュー免除 洗脳#1検出 (殿厳命2026-06-08) ---
# inbox内のreport_review依頼で、review_logにreportレビューが存在しないcmdを検出
_inbox_file="$REPO_ROOT/queue/inbox/gunshi.yaml"
if [ -f "$_inbox_file" ] && [ -f "$LOG_FILE" ]; then
    _unreviewed=$(awk '
        /type:.*report_review/ { getline; if ($0 ~ /read: true/) reviewed_requests++ }
        /cmd_[0-9]+/ { match($0, /cmd_[0-9]+/); cmd=substr($0, RSTART, RLENGTH); cmds[cmd]++ }
    ' "$_inbox_file" 2>/dev/null | sort -u || true)
    # report_review依頼されたcmd_idをinboxから抽出
    _review_requested=$(grep -oP 'cmd_\d+' "$_inbox_file" 2>/dev/null | sort -u)
    _review_done=$(grep -B1 'review_type: report' "$LOG_FILE" 2>/dev/null | grep 'cmd_id:' | grep -oP 'cmd_\d+' | sort -u)
    _missing=""
    for _cmd in $_review_requested; do
        if ! echo "$_review_done" | grep -q "^${_cmd}$"; then
            _missing="${_missing} ${_cmd}"
        fi
    done
    if [ -n "${_missing}" ]; then
        echo "WARN(L6-洗脳#1): report_review依頼済みだがレビュー未実施:${_missing}"
        echo "  → GATE CLEARはレビュー免除の理由にならない。即レビューせよ"
        warn=1
    fi
fi

# --- L6: 利他洗脳監視 — 将軍action_required未対応検出 (殿厳命2026-06-08) ---
# 掲示板のaction_required+status=openを検出し、軍師がフォローアップを促す
_bulletin="$REPO_ROOT/queue/bulletin_board.yaml"
if [ -f "$_bulletin" ]; then
    _open_actions=$(awk '
        /action_type:.*action_required/ { ar=1 }
        ar && /status:.*open/ { count++; ar=0 }
        END { print count+0 }
    ' "$_bulletin" 2>/dev/null)
    if [ "${_open_actions:-0}" -gt 3 ]; then
        echo "WARN(L6-利他): 掲示板action_required未対応${_open_actions}件。将軍に先送り(洗脳#5)の可能性あり"
        echo "  → 掲示板で具体的な未対応項目を確認し、対処可能なものは軍師が即実行せよ"
        warn=1
    fi
fi

# --- L6: brainwash_check形骸化検出 — 8パターン番号なし=形式的 (殿厳命2026-06-08) ---
_bw_no_pattern=$(tail -200 "$LOG_FILE" 2>/dev/null | awk '
    /brainwash_check:/ {
        line=$0
        if (line !~ /#[0-9]/ && line !~ /洗脳#/) no_pattern++
        total++
    }
    END { if (total >= 5 && no_pattern > total*0.6) print no_pattern "/" total }
')
if [ -n "$_bw_no_pattern" ]; then
    echo "WARN(L6-形骸化): brainwash_checkの${_bw_no_pattern}件で8パターン番号なし。具体的にどのパターンを検査したか明記せよ"
    warn=1
fi

# --- L6: 洗脳#8検出 — confidence:HIGH連続は自己過信 (殿厳命2026-06-08) ---
# cmd_3219でHIGHだったが動作未確認だった。HIGH連続は洗脳の証拠
_high_streak=$(tail -200 "$LOG_FILE" 2>/dev/null | grep 'confidence:' | awk '
    { if ($2 == "HIGH") streak++; else streak=0 }
    END { print streak+0 }
')
if [ "${_high_streak:-0}" -ge 5 ]; then
    echo "WARN(L6-洗脳#8): confidence:HIGHが${_high_streak}件連続。自己過信の可能性"
    echo "  → HIGHは「全前提検証+情報不足なし」の宣言。本当に全て検証したか？cmd_3219はHIGHだったが動作未確認だった"
    warn=1
fi

# --- L6: 洗脳#2検出 — infra report reviewで実動作確認なし (殿厳命2026-06-08) ---
# observationsに「実行」「実測」「確認」「テスト実行」がないinfra reportレビューを検出
_infra_no_verify=$(awk '
    /^- cmd_id:/ { id=substr($0,index($0,":")+2); gsub(/[" \t]/,"",id); rt=""; obs="" }
    /review_type: report/ { rt="report" }
    /observations:/ { in_obs=1; next }
    in_obs && /^    - / { obs=obs " " $0 }
    in_obs && /^  [^ ]/ { in_obs=0 }
    /timestamp:/ && rt=="report" && id != "" {
        if (obs ~ /scripts\/|gate_|hook_|monitor|ninja_monitor/) {
            if (obs !~ /実行|実測|実験|動作確認|テスト実行|bash.*\.sh/) {
                print id
            }
        }
        obs=""
    }
' "$LOG_FILE" 2>/dev/null | tail -5 || true)
if [ -n "$_infra_no_verify" ]; then
    echo "WARN(L6-洗脳#2): infra/scripts reportレビューで実動作確認なし:"
    printf '%s\n' "$_infra_no_verify" | while read -r _id; do
        [ -n "$_id" ] && echo "  - $_id: binary_checks=yesを鵜呑みにするな。実行して確認せよ"
    done
    warn=1
fi

# --- L4: step3_5_verified未記入検出 (LG036 洗脳#1/#2/#8防止) ---
_step35_missing=$(awk '
    /^- cmd_id:/ { id=substr($0,index($0,":")+2); gsub(/[" \t]/,"",id); rt=""; has_s35=0 }
    /review_type: report/ { rt="report" }
    /step3_5_verified:/ { has_s35=1 }
    /timestamp:/ && rt=="report" && !has_s35 && id != "" { print id }
' "$LOG_FILE" 2>/dev/null | tail -10 || true)
if [ -n "$_step35_missing" ]; then
    _s35_count=$(echo "$_step35_missing" | wc -l)
    echo "WARN(L4-LG036): ${_s35_count}件のreportレビューにstep3_5_verified未記入:"
    printf '%s\n' "$_step35_missing" | while read -r _id; do
        [ -n "$_id" ] && echo "  - $_id: SG-PRE25結果+command×files_modified 3分類を記録せよ"
    done
    warn=1
fi

# --- L4b: LGTM+BLOCK予測=矛盾検出 (洗脳#4緩い設計防止 殿厳命2026-06-08) ---
# LGTM=GATE通過保証(LG006)。BLOCKリスク予測+LGTM=矛盾。cmd_3228/3232/3233/3234で4件実証
_lgtm_block=$(awk '
    /^- cmd_id:/ { id=substr($0,index($0,":")+2); gsub(/[" \t]/,"",id); v=""; gr="" }
    /verdict: LGTM/ { v="LGTM" }
    /gate_result:.*BLOCK/ { gr="BLOCK" }
    /timestamp:/ && v=="LGTM" && gr=="BLOCK" && id != "" { print id }
' "$LOG_FILE" 2>/dev/null | tail -10 || true)
if [ -n "$_lgtm_block" ]; then
    _lb_count=$(echo "$_lgtm_block" | wc -l)
    echo "WARN(L4b-洗脳#4): ${_lb_count}件のLGTM→BLOCK。BLOCKリスク予測時はFAILにせよ(LG006):"
    printf '%s\n' "$_lgtm_block" | while read -r _id; do
        [ -n "$_id" ] && echo "  - $_id: LGTM=GATE通過保証。BLOCKリスクがあればFAIL"
    done
    warn=1
fi

exit $warn
