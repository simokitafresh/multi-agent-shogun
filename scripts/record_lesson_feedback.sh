#!/usr/bin/env bash
# record_lesson_feedback.sh — 報告YAMLのlessons_usefulをlesson_impact.tsvにフィードバック記録
# Usage: bash scripts/record_lesson_feedback.sh <report_yaml_path>
# 目的: deploy_task.shのcompute_useful_rates()が実フィードバックを使えるようにする
# 設計: 冪等（同一taskのfeedback集合を最新reportで置換する）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMPACT_TSV="$SCRIPT_DIR/logs/lesson_impact.tsv"
IMPACT_HEADER=$'timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level\tscore\ttraversal_depth'

report_file="${1:-}"
if [[ -z "$report_file" || ! -f "$report_file" ]]; then
    echo "[feedback] ERROR: report file not found: $report_file" >&2
    exit 1
fi

# ヘッダ確認（lesson_impact.tsvが存在しない場合は作成）
if [[ ! -f "$IMPACT_TSV" ]]; then
    printf '%s\n' "$IMPACT_HEADER" > "$IMPACT_TSV"
else
    # Backward compatibility: add trailing score/traversal_depth columns to old logs.
    # Fast-path: skip flock+subshell entirely if header is already up-to-date.
    _existing_header="$(head -n 1 "$IMPACT_TSV" 2>/dev/null || true)"
    if [[ "$_existing_header" != *$'\ttraversal_depth' ]]; then
        (
            flock -w 10 200 || { echo "[feedback] WARN: flock timeout during header upgrade" >&2; exit 0; }
            current_header="$(head -n 1 "$IMPACT_TSV" 2>/dev/null || true)"
            if [[ "$current_header" != *$'\ttraversal_depth' ]]; then
                tmp_file="${IMPACT_TSV}.tmp.$$"
                if [[ "$current_header" == *$'\tscore' ]]; then
                    awk -F'\t' -v OFS='\t' -v header="$IMPACT_HEADER" '
                        NR == 1 { print header; next }
                        { print $0, "" }
                    ' "$IMPACT_TSV" > "$tmp_file"
                else
                    awk -F'\t' -v OFS='\t' -v header="$IMPACT_HEADER" '
                        NR == 1 { print header; next }
                        { print $0, "", "" }
                    ' "$IMPACT_TSV" > "$tmp_file"
                fi
                mv "$tmp_file" "$IMPACT_TSV"
            fi
        ) 200>"${IMPACT_TSV}.lock"
    fi
fi

# 報告YAMLからメタデータとlessons_usefulを1回の走査で抽出する。
cmd_id=""
ninja=""
task_id=""
project=""
task_type=""
lesson_records=()
while IFS=$'\t' read -r record_type field value; do
    case "$record_type" in
        META)
            case "$field" in
                parent_cmd) cmd_id="$value" ;;
                worker_id) ninja="$value" ;;
                task_id) task_id="$value" ;;
                project) project="$value" ;;
                task_type) task_type="$value" ;;
            esac
            ;;
        LESSON)
            lesson_records+=("${field}"$'\t'"${value}")
            ;;
    esac
done < <(
    awk '
        function clean(line) {
            sub(/^[^:]*:[[:space:]]*/, "", line)
            gsub(/\047|"/, "", line)
            return line
        }
        /^parent_cmd:/ { print "META\tparent_cmd\t" clean($0); next }
        /^worker_id:/ { print "META\tworker_id\t" clean($0); next }
        /^task_id:/ { print "META\ttask_id\t" clean($0); next }
        /^project:/ { print "META\tproject\t" clean($0); next }
        /^task_type:/ { print "META\ttask_type\t" clean($0); next }
        /^lessons_useful:/ { in_lessons = 1; next }
        in_lessons && /^[a-z_]+:/ { exit }
        in_lessons && /id:/ { current_id = clean($0); next }
        in_lessons && /useful:/ {
            useful_val = tolower(clean($0))
            if (current_id != "") {
                print "LESSON\t" current_id "\t" useful_val
                current_id = ""
            }
        }
    ' "$report_file"
)

# projectフィールド: 報告YAML → task YAMLフォールバック
if [[ -z "$project" && -n "$ninja" ]]; then
    task_yaml="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    if [[ -f "$task_yaml" ]]; then
        project=$(awk '/project:/ { sub(/.*project:[[:space:]]*/, ""); gsub(/\047|"/, ""); print; exit }' "$task_yaml")
    fi
fi

# task_typeフィールド: 報告YAML → task YAMLフォールバック
if [[ -z "$task_type" && -n "$ninja" ]]; then
    task_yaml="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    if [[ -f "$task_yaml" ]]; then
        task_type=$(awk '/task_type:/ { sub(/.*task_type:[[:space:]]*/, ""); gsub(/\047|"/, ""); print; exit }' "$task_yaml")
    fi
fi

# cmd_idフォールバック: task_idからparent_cmd推定
if [[ -z "$cmd_id" && -n "$task_id" ]]; then
    cmd_id=$(echo "$task_id" | sed 's/_impl$//' | sed 's/_recon$//')
fi

timestamp=$(date "+%Y-%m-%dT%H:%M:%S")

dedup_key="${task_id:-${cmd_id}}"

# lesson-reflux等が明示した評価集合はreportより強い契約である。
# 現在taskが既に再配備済みの場合の台帳修復に限り、環境変数で同じ集合を渡せる。
strict_assigned_set=false
assigned_ids=()
task_yaml="${LESSON_FEEDBACK_TASK_FILE:-$SCRIPT_DIR/queue/tasks/${ninja}.yaml}"
assigned_override="${LESSON_FEEDBACK_ASSIGNED_IDS:-}"
if [[ -n "$assigned_override" ]]; then
    strict_assigned_set=true
    IFS=',' read -r -a assigned_ids <<< "$assigned_override"
elif [[ -n "$ninja" && -f "$task_yaml" ]]; then
    while IFS=$'\t' read -r record_type value; do
        case "$record_type" in
            STRICT) strict_assigned_set=true ;;
            ID) assigned_ids+=("$value") ;;
        esac
    done < <(python3 - "$task_yaml" "$task_id" "$cmd_id" <<'PY'
import sys, yaml

path, report_task_id, report_cmd_id = sys.argv[1:]
try:
    data = yaml.safe_load(open(path, encoding="utf-8")) or {}
except Exception:
    raise SystemExit(0)
task = data.get("task", data) if isinstance(data, dict) else {}
if not isinstance(task, dict):
    raise SystemExit(0)
task_id = str(task.get("task_id", "")).strip()
parent_cmd = str(task.get("parent_cmd", "")).strip()
if report_task_id and task_id != report_task_id:
    raise SystemExit(0)
if report_cmd_id and parent_cmd != report_cmd_id:
    raise SystemExit(0)
if "assigned_lesson_ids" not in task:
    raise SystemExit(0)
print("STRICT\t1")
values = task.get("assigned_lesson_ids")
if isinstance(values, list):
    for value in values:
        value = str(value).strip()
        if value:
            print(f"ID\t{value}")
PY
    )
fi

# lessons_usefulセクションからid+usefulを抽出
# フォーマット:
# lessons_useful:
# - id: L074
#   useful: false
#   reason: "..."
feedback_count=0
auto_feedback_count=0
reported_ids=()

has_reported_id() {
    local lesson_id="$1"
    local existing
    for existing in "${reported_ids[@]}"; do
        if [[ "$existing" == "$lesson_id" ]]; then
            return 0
        fi
    done
    return 1
}

has_assigned_id() {
    local lesson_id="$1"
    local existing
    for existing in "${assigned_ids[@]}"; do
        existing="${existing#"${existing%%[![:space:]]*}"}"
        existing="${existing%"${existing##*[![:space:]]}"}"
        if [[ "$existing" == "$lesson_id" ]]; then
            return 0
        fi
    done
    return 1
}

# Collect all feedback lines in memory, then write in one flock to reduce lock overhead.
_batch_lines=()

make_feedback_line() {
    local lesson_id="$1"
    local result="$2"
    local ref="$3"
    # feedback行は注入時scoreを持たないためscoreは空欄。
    printf '%s\t%s\t%s\t%s\tfeedback\t%s\t%s\t%s\t%s\tNone\t\t\n' \
        "$timestamp" "${task_id:-${cmd_id}}" "${ninja:-unknown}" \
        "$lesson_id" "$result" "$ref" "${project:-unknown}" "${task_type:-impl}"
}

for lesson_record in "${lesson_records[@]}"; do
    IFS=$'\t' read -r current_id useful_val <<< "$lesson_record"
    if [[ -n "$current_id" ]]; then
        if [[ "$strict_assigned_set" == true ]] && ! has_assigned_id "$current_id"; then
            continue
        fi
        if [[ "$useful_val" == "true" ]]; then
            result="USEFUL"
            ref="yes"
        else
            result="NOT_USEFUL"
            ref="no"
        fi
        _batch_lines+=("$(make_feedback_line "$current_id" "$result" "$ref")")
        reported_ids+=("$current_id")
        feedback_count=$((feedback_count + 1))
    fi
done

if [[ -n "$dedup_key" && "$strict_assigned_set" != true ]]; then
    while IFS= read -r injected_id; do
        [[ -n "$injected_id" ]] || continue
        if ! has_reported_id "$injected_id"; then
            _batch_lines+=("$(make_feedback_line "$injected_id" "NOT_USEFUL" "no")")
            auto_feedback_count=$((auto_feedback_count + 1))
        fi
    done < <(
        awk -F'\t' -v key="$dedup_key" '
            NR > 1 && $2 == key && tolower($5) == "injected" && $4 != "" { seen[$4] = 1 }
            END { for (id in seen) print id }
        ' "$IMPACT_TSV" | sort
    )
fi

# Single flock reconciliation: replace prior feedback for the task instead of
# skipping it, so a corrected report can remove false negative rows.
if [[ -n "$dedup_key" || ${#_batch_lines[@]} -gt 0 ]]; then
    (
        flock -w 10 200 || { echo "[feedback] WARN: flock timeout" >&2; exit 0; }
        tmp_file=$(mktemp "${IMPACT_TSV}.tmp.XXXXXX")
        awk -F'\t' -v OFS='\t' -v key="$dedup_key" -v strict="$strict_assigned_set" \
            -v assigned_csv="$(IFS=,; echo "${assigned_ids[*]}")" '
            BEGIN {
                n=split(assigned_csv, ids, ",")
                for (i=1; i<=n; i++) if (ids[i] != "") assigned[ids[i]]=1
            }
            NR == 1 { print; next }
            $2 == key && tolower($5) == "feedback" { next }
            $2 == key && strict == "true" && tolower($5) == "injected" && !($4 in assigned) {
                $6="pending"; $7="pending"
            }
            { print }
        ' "$IMPACT_TSV" > "$tmp_file"
        if [[ ${#_batch_lines[@]} -gt 0 ]]; then
            printf '%s\n' "${_batch_lines[@]}" >> "$tmp_file"
        fi
        mv "$tmp_file" "$IMPACT_TSV"
    ) 200>"${IMPACT_TSV}.lock"
fi

if [[ $feedback_count -gt 0 ]]; then
    echo "[feedback] Recorded $feedback_count lesson feedback entries for ${cmd_id:-unknown}" >&2
else
    echo "[feedback] No lessons_useful found in $report_file" >&2
fi

if [[ $auto_feedback_count -gt 0 ]]; then
    echo "[feedback] Auto-recorded $auto_feedback_count missing injected lessons as NOT_USEFUL for ${cmd_id:-unknown}" >&2
fi
