#!/usr/bin/env bash
# record_lesson_feedback.sh — 報告YAMLのlessons_usefulをlesson_impact.tsvにフィードバック記録
# Usage: bash scripts/record_lesson_feedback.sh <report_yaml_path>
# 目的: deploy_task.shのcompute_useful_rates()が実フィードバックを使えるようにする
# 設計: 冪等（同一report+lesson_idの重複書込みを防止）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMPACT_TSV="$SCRIPT_DIR/logs/lesson_impact.tsv"

report_file="${1:-}"
if [[ -z "$report_file" || ! -f "$report_file" ]]; then
    echo "[feedback] ERROR: report file not found: $report_file" >&2
    exit 1
fi

# ヘッダ確認（lesson_impact.tsvが存在しない場合は作成）
if [[ ! -f "$IMPACT_TSV" ]]; then
    echo -e "timestamp\tcmd_id\tninja\tlesson_id\taction\tresult\treferenced\tproject\ttask_type\tbloom_level" > "$IMPACT_TSV"
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

# task_typeフィールド
task_type=$(grep -m1 "^task_type:" "$report_file" | sed 's/task_type:[[:space:]]*//' | tr -d "'" | tr -d '"' || true)

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
in_lessons=0

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
                # flockで排他書込み
                (
                    flock -w 10 200 || { echo "[feedback] WARN: flock timeout" >&2; exit 0; }
                    echo -e "${timestamp}\t${task_id:-${cmd_id}}\t${ninja:-unknown}\t${current_id}\tfeedback\t${result}\t${ref}\t${project:-unknown}\t${task_type:-impl}\tNone" >> "$IMPACT_TSV"
                ) 200>"${IMPACT_TSV}.lock"
                feedback_count=$((feedback_count + 1))
                current_id=""
            fi
        fi
    fi
done < "$report_file"

if [[ $feedback_count -gt 0 ]]; then
    echo "[feedback] Recorded $feedback_count lesson feedback entries for ${cmd_id:-unknown}" >&2
else
    echo "[feedback] No lessons_useful found in $report_file" >&2
fi
