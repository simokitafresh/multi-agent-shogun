#!/usr/bin/env bash
# record_lesson_feedback.sh — 報告YAMLのlessons_usefulをlesson_impact.tsvにフィードバック記録
# Usage: bash scripts/record_lesson_feedback.sh <report_yaml_path>
# 目的: deploy_task.shのcompute_useful_rates()が実フィードバックを使えるようにする
# 設計: 冪等（同一report+lesson_idの重複書込みを防止）

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

# 報告YAMLからメタデータ抽出（フィールド不在時は空文字でOK）
cmd_id=$(grep -m1 "^parent_cmd:" "$report_file" | sed 's/parent_cmd:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)
ninja=$(grep -m1 "^worker_id:" "$report_file" | sed 's/worker_id:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)
task_id=$(grep -m1 "^task_id:" "$report_file" | sed 's/task_id:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)

# projectフィールド: 報告YAML → task YAMLフォールバック
project=$(grep -m1 "^project:" "$report_file" | sed 's/project:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)
if [[ -z "$project" && -n "$ninja" ]]; then
    task_yaml="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    if [[ -f "$task_yaml" ]]; then
        project=$(grep -m1 "project:" "$task_yaml" | sed 's/.*project:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)
    fi
fi

# task_typeフィールド: 報告YAML → task YAMLフォールバック
task_type=$(grep -m1 "^task_type:" "$report_file" | sed 's/task_type:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)
if [[ -z "$task_type" && -n "$ninja" ]]; then
    task_yaml="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    if [[ -f "$task_yaml" ]]; then
        task_type=$(grep -m1 "task_type:" "$task_yaml" | sed 's/.*task_type:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)
    fi
fi

# cmd_idフォールバック: task_idからparent_cmd推定
if [[ -z "$cmd_id" && -n "$task_id" ]]; then
    cmd_id=$(echo "$task_id" | sed 's/_impl$//' | sed 's/_recon$//')
fi

timestamp=$(date "+%Y-%m-%dT%H:%M:%S")

# 重複チェック用: 既にfeedbackが記録されているか（task_idで照合）
dedup_key="${task_id:-${cmd_id}}"
if [[ -n "$dedup_key" ]] && grep -q "	${dedup_key}	.*	feedback	" "$IMPACT_TSV" 2>/dev/null; then
    echo "[feedback] SKIP: feedback already recorded for $dedup_key" >&2
    exit 0
fi

# lessons_usefulセクションからid+usefulを抽出
# フォーマット:
# lessons_useful:
# - id: L074
#   useful: false
#   reason: "..."
feedback_count=0
auto_feedback_count=0
in_lessons=0
current_id=""
reported_ids=()

record_feedback() {
    local lesson_id="$1"
    local result="$2"
    local ref="$3"

    # flockで排他書込み。feedback行は注入時scoreを持たないためscoreは空欄。
    (
        flock -w 10 200 || { echo "[feedback] WARN: flock timeout" >&2; exit 0; }
        echo -e "${timestamp}\t${task_id:-${cmd_id}}\t${ninja:-unknown}\t${lesson_id}\tfeedback\t${result}\t${ref}\t${project:-unknown}\t${task_type:-impl}\tNone\t\t" >> "$IMPACT_TSV"
    ) 200>"${IMPACT_TSV}.lock"
}

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

while IFS= read -r line; do
    # lessons_usefulセクション開始
    if echo "$line" | grep -q "^lessons_useful:"; then
        in_lessons=1
        continue
    fi
    # セクション終了（次のトップレベルキー）
    if [[ $in_lessons -eq 1 ]] && echo "$line" | grep -qE "^[a-z_]+:"; then
        break
    fi
    if [[ $in_lessons -eq 1 ]]; then
        # id行
        if echo "$line" | grep -q "id:"; then
            current_id=$(echo "$line" | sed 's/.*id:[[:space:]]*//' | tr -d "'" | tr -d '"')
        fi
        # useful行
        if echo "$line" | grep -q "useful:"; then
            useful_val=$(echo "$line" | sed 's/.*useful:[[:space:]]*//' | tr -d "'" | tr -d '"' | tr '[:upper:]' '[:lower:]')
            if [[ -n "$current_id" ]]; then
                if [[ "$useful_val" == "true" ]]; then
                    result="USEFUL"
                    ref="yes"
                else
                    result="NOT_USEFUL"
                    ref="no"
                fi
                record_feedback "$current_id" "$result" "$ref"
                reported_ids+=("$current_id")
                feedback_count=$((feedback_count + 1))
                current_id=""
            fi
        fi
    fi
done < "$report_file"

if [[ -n "$dedup_key" ]]; then
    while IFS= read -r injected_id; do
        [[ -n "$injected_id" ]] || continue
        if ! has_reported_id "$injected_id"; then
            record_feedback "$injected_id" "NOT_USEFUL" "no"
            auto_feedback_count=$((auto_feedback_count + 1))
        fi
    done < <(
        awk -F'\t' -v key="$dedup_key" '
            NR > 1 && $2 == key && tolower($5) == "injected" && $4 != "" { seen[$4] = 1 }
            END { for (id in seen) print id }
        ' "$IMPACT_TSV" | sort
    )
fi

if [[ $feedback_count -gt 0 ]]; then
    echo "[feedback] Recorded $feedback_count lesson feedback entries for ${cmd_id:-unknown}" >&2
else
    echo "[feedback] No lessons_useful found in $report_file" >&2
fi

if [[ $auto_feedback_count -gt 0 ]]; then
    echo "[feedback] Auto-recorded $auto_feedback_count missing injected lessons as NOT_USEFUL for ${cmd_id:-unknown}" >&2
fi
