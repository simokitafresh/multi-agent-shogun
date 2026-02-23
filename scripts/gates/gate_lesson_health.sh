#!/usr/bin/env bash
# ============================================================
# gate_lesson_health.sh
# 教訓(lessons) → context合流状態の健全性チェック
#
# Usage:
#   bash scripts/gates/gate_lesson_health.sh <project_id>
#   bash scripts/gates/gate_lesson_health.sh              # 全project走査
#
# 動作:
#   (a) projects/{project_id}/lessons.yaml の総lesson数を取得
#   (b) context/{project_id}.md の last_synced_lesson マーカーを取得
#       マーカー形式: <!-- last_synced_lesson: L115 -->
#       マーカーなし → L000(全件未合流扱い)
#   (c) 差分(未合流lesson数)を計算
#   (d) 未合流10件超 → ALERT
#   (e) 未合流10件以下 → OK
#
# Exit code: 0=OK(全project健全), 1=ALERT(1つ以上のprojectで未合流過多)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/projects.yaml"
ALERT_THRESHOLD=10
EXIT_CODE=0

# 単一projectの健全性チェック
# $1: project_id
check_project() {
    local project_id="$1"
    local lessons_file="$SCRIPT_DIR/projects/${project_id}/lessons.yaml"
    local context_file

    # context_fileをconfig/projects.yamlから取得
    context_file=$(grep -A5 "id: ${project_id}" "$CONFIG_FILE" 2>/dev/null \
        | grep 'context_file:' | head -1 \
        | sed 's/.*context_file:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')

    if [ -z "$context_file" ]; then
        # フォールバック: context/{project_id}.md
        context_file="context/${project_id}.md"
    fi
    local context_path="$SCRIPT_DIR/$context_file"

    # (a) lessons.yamlの総lesson数
    if [ ! -f "$lessons_file" ]; then
        echo "OK: ${project_id} lessons.yaml不在(lesson 0件)"
        return 0
    fi

    local total_lessons
    total_lessons=$(grep -c '^- id: L' "$lessons_file" 2>/dev/null || echo "0")

    if [ "$total_lessons" -eq 0 ]; then
        echo "OK: ${project_id} lesson 0件"
        return 0
    fi

    # 全lesson IDの数値部分を取得(降順)
    local -a all_ids
    mapfile -t all_ids < <(grep '^- id: L' "$lessons_file" | sed 's/^- id: L//' | sort -rn)

    local max_id="${all_ids[0]}"

    # (b) context fileの last_synced_lesson マーカーを取得
    local synced_num=0
    if [ -f "$context_path" ]; then
        local marker
        marker=$(grep -oE '<!-- last_synced_lesson: L[0-9]+ -->' "$context_path" 2>/dev/null | tail -1)
        if [ -n "$marker" ]; then
            synced_num=$(echo "$marker" | grep -oE '[0-9]+')
        fi
    fi

    # (c) 未合流lesson数を計算(IDの数値 > synced_num のものをカウント)
    local unsynced=0
    for id_num in "${all_ids[@]}"; do
        if [ "$id_num" -gt "$synced_num" ] 2>/dev/null; then
            ((unsynced++))
        fi
    done

    # (d)(e) 判定と出力
    if [ "$unsynced" -gt "$ALERT_THRESHOLD" ]; then
        echo "ALERT: ${project_id}のlesson→context未合流${unsynced}件(total:${total_lessons},synced:L${synced_num},max:L${max_id})"
        return 1
    else
        echo "OK: ${project_id}のlesson統合状況は健全(未合流${unsynced}件,total:${total_lessons},synced:L${synced_num})"
        return 0
    fi
}

# メイン処理
if [ $# -ge 1 ]; then
    # 引数あり: 指定projectのみチェック
    check_project "$1" || EXIT_CODE=1
else
    # 引数なし: 全projectを走査
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "ERROR: config/projects.yaml not found"
        exit 1
    fi

    # active projectのIDを取得
    local_ids=()
    while IFS= read -r line; do
        local_ids+=("$line")
    done < <(awk '/^  - id:/{id=$3} /status: active/{print id}' "$CONFIG_FILE")

    if [ ${#local_ids[@]} -eq 0 ]; then
        echo "WARN: active projectが見つかりません"
        exit 0
    fi

    for pid in "${local_ids[@]}"; do
        check_project "$pid" || EXIT_CODE=1
    done
fi

exit $EXIT_CODE
