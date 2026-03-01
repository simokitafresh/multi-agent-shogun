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

    local total_lessons_raw
    total_lessons_raw=$(awk '/^- id: L/{c++} END{print c+0}' "$lessons_file")

    if [ "$total_lessons_raw" -eq 0 ]; then
        echo "OK: ${project_id} lesson 0件"
        return 0
    fi

    # deprecated教訓を除外してIDを収集 (L034: 固定インデント非依存)
    # deprecated: true AND status: deprecated 両方を除外 (cmd_414)
    local -a all_ids
    mapfile -t all_ids < <(awk '
        /^- id: L/ {
            if (current_id != "" && !is_deprecated) print current_id
            current_id = $3; sub(/^L/, "", current_id)
            is_deprecated = 0
        }
        /[[:space:]]+status:[[:space:]]+deprecated/ { is_deprecated = 1 }
        /[[:space:]]+deprecated:[[:space:]]+true/ { is_deprecated = 1 }
        END { if (current_id != "" && !is_deprecated) print current_id }
    ' "$lessons_file" | sort -rn)

    # deprecated件数をログ出力 (status: deprecated OR deprecated: true, per-lesson)
    local deprecated_count
    deprecated_count=$(awk '
        /^- id: L/ {
            if (current_id != "" && is_deprecated) c++
            current_id = $3; is_deprecated = 0
        }
        /[[:space:]]+status:[[:space:]]+deprecated/ { is_deprecated = 1 }
        /[[:space:]]+deprecated:[[:space:]]+true/ { is_deprecated = 1 }
        END { if (current_id != "" && is_deprecated) c++; print c+0 }
    ' "$lessons_file")
    if [ "$deprecated_count" -gt 0 ]; then
        echo "INFO: ${project_id} deprecated除外: ${deprecated_count}件"
    fi

    local total_lessons="${#all_ids[@]}"

    if [ "$total_lessons" -eq 0 ]; then
        echo "OK: ${project_id} lesson 0件(deprecated除外後)"
        return 0
    fi

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

# 蓄積トリガーチェック (cmd_414)
# 前回審査時点から新規教訓が10件以上増えたらWARN
# checkpoint: queue/lesson_deprecation_checkpoint.txt (L番号1つだけ記録)
ACCUMULATION_THRESHOLD=10
CHECKPOINT_FILE="$SCRIPT_DIR/queue/lesson_deprecation_checkpoint.txt"

check_accumulation() {
    # 全projectの最新L番号(deprecated除外)を取得
    local max_id=0
    local total_active=0

    for pid in "$@"; do
        local lessons_file="$SCRIPT_DIR/projects/${pid}/lessons.yaml"
        [ -f "$lessons_file" ] || continue

        # deprecated: true AND status: deprecated 両方を除外してactive教訓のIDを収集 (L034: 柔軟マッチ)
        while IFS= read -r id_num; do
            [ -z "$id_num" ] && continue
            total_active=$((total_active + 1))
            if [ "$id_num" -gt "$max_id" ] 2>/dev/null; then
                max_id="$id_num"
            fi
        done < <(awk '
            /^- id: L/ {
                if (current_id != "" && !is_deprecated) print current_id
                current_id = $3; sub(/^L/, "", current_id)
                is_deprecated = 0
            }
            /[[:space:]]+status:[[:space:]]+deprecated/ { is_deprecated = 1 }
            /[[:space:]]+deprecated:[[:space:]]+true/ { is_deprecated = 1 }
            END { if (current_id != "" && !is_deprecated) print current_id }
        ' "$lessons_file")
    done

    if [ "$max_id" -eq 0 ]; then
        return 0
    fi

    # checkpoint読取り
    local checkpoint=0
    if [ -f "$CHECKPOINT_FILE" ]; then
        local raw
        raw=$(grep -oE 'L[0-9]+' "$CHECKPOINT_FILE" 2>/dev/null | head -1)
        if [ -n "$raw" ]; then
            checkpoint=$(echo "$raw" | grep -oE '[0-9]+')
        fi
    fi

    # 新規件数計算
    local new_count=0
    for pid in "$@"; do
        local lessons_file="$SCRIPT_DIR/projects/${pid}/lessons.yaml"
        [ -f "$lessons_file" ] || continue

        while IFS= read -r id_num; do
            [ -z "$id_num" ] && continue
            if [ "$id_num" -gt "$checkpoint" ] 2>/dev/null; then
                new_count=$((new_count + 1))
            fi
        done < <(awk '
            /^- id: L/ {
                if (current_id != "" && !is_deprecated) print current_id
                current_id = $3; sub(/^L/, "", current_id)
                is_deprecated = 0
            }
            /[[:space:]]+status:[[:space:]]+deprecated/ { is_deprecated = 1 }
            /[[:space:]]+deprecated:[[:space:]]+true/ { is_deprecated = 1 }
            END { if (current_id != "" && !is_deprecated) print current_id }
        ' "$lessons_file")
    done

    if [ "$new_count" -ge "$ACCUMULATION_THRESHOLD" ]; then
        echo "WARN: 新規教訓+${new_count}件(前回審査: L${checkpoint}, 現在最新: L${max_id})。"
        echo "      lesson_deprecation_scan.sh を実行し審査せよ。"
        return 1
    else
        echo "OK: 蓄積チェック(新規${new_count}件, 前回審査: L${checkpoint}, 閾値${ACCUMULATION_THRESHOLD})"
    fi
    return 0
}

# 未振り分け教訓チェック (cmd_301)
# context fileの「## 教訓索引（自動追記）」セクション内の「- L」行をカウント
# $1: project_id
UNSORTED_THRESHOLD=10

check_unsorted_lessons() {
    local project_id="$1"
    local context_file

    # context_fileをconfig/projects.yamlから取得
    context_file=$(grep -A5 "id: ${project_id}" "$CONFIG_FILE" 2>/dev/null \
        | grep 'context_file:' | head -1 \
        | sed 's/.*context_file:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')

    if [ -z "$context_file" ]; then
        context_file="context/${project_id}.md"
    fi
    local context_path="$SCRIPT_DIR/$context_file"

    if [ ! -f "$context_path" ]; then
        # context fileなし → 0件扱い
        return 0
    fi

    # セクション「## 教訓索引（自動追記）」内の「- L」行をカウント
    local count
    count=$(awk '
        /^## 教訓索引（自動追記）/ { in_section=1; next }
        in_section && /^## / { exit }
        in_section && /^- L/ { c++ }
        END { print c+0 }
    ' "$context_path")

    if [ "$count" -gt "$UNSORTED_THRESHOLD" ]; then
        echo "ALERT: ${project_id}の未振り分け教訓${count}件 → /lesson-sort推奨"
        return 1
    elif [ "$count" -gt 0 ]; then
        echo "OK: ${project_id}の未振り分け教訓${count}件(閾値${UNSORTED_THRESHOLD}以下)"
    fi
    # セクションなし or 0件 → 何も出力しない（0件扱い）
    return 0
}

# メイン処理
if [ $# -ge 1 ]; then
    # 引数あり: 指定projectのみチェック
    check_project "$1" || EXIT_CODE=1
    check_unsorted_lessons "$1" || EXIT_CODE=1
    check_accumulation "$1" || EXIT_CODE=1
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
        check_unsorted_lessons "$pid" || EXIT_CODE=1
    done

    # 蓄積チェックは全project横断で1回実行
    check_accumulation "${local_ids[@]}" || EXIT_CODE=1
fi

# --- injection_count閾値チェック (cmd_470) ---
INJECTION_WARN_THRESHOLD=10
check_injection_count_threshold() {
    local target_pids=("$@")
    if [ ${#target_pids[@]} -eq 0 ]; then
        # 全projectを走査
        while IFS= read -r line; do
            target_pids+=("$line")
        done < <(awk '/^  - id:/{id=$3} /status: active/{print id}' "$CONFIG_FILE" 2>/dev/null)
    fi

    local problem_count=0
    for pid in "${target_pids[@]}"; do
        local lessons_file="$SCRIPT_DIR/projects/${pid}/lessons.yaml"
        [ -f "$lessons_file" ] || continue

        # injection_count >= THRESHOLD かつ helpful_count == 0 の教訓を抽出
        local problems
        problems=$(python3 -c "
import yaml, sys
with open('$lessons_file', encoding='utf-8') as f:
    data = yaml.safe_load(f)
if not data or 'lessons' not in data:
    sys.exit(0)
for l in data['lessons']:
    st = str(l.get('status', 'confirmed')).lower()
    if st == 'deprecated' or l.get('deprecated', False):
        continue
    ic = l.get('injection_count', 0) or 0
    hc = l.get('helpful_count', 0) or 0
    if ic >= $INJECTION_WARN_THRESHOLD and hc == 0:
        print(f\"  - {l['id']}: injection={ic}, helpful={hc} [{pid}]\")
" 2>/dev/null || true)

        if [ -n "$problems" ]; then
            problem_count=$((problem_count + $(echo "$problems" | wc -l)))
            echo "$problems"
        fi
    done

    if [ "$problem_count" -gt 0 ]; then
        echo "WARN: 注入${INJECTION_WARN_THRESHOLD}回以上で効果報告0件の教訓: ${problem_count}件"
    fi
}

# --- 教訓効果サマリ (cmd_473: lessons.yaml直接参照に統一) ---
check_lesson_effectiveness() {
    local target_pids=()
    if [ $# -ge 1 ]; then
        target_pids=("$1")
    else
        while IFS= read -r line; do
            target_pids+=("$line")
        done < <(awk '/^  - id:/{id=$3} /status: active/{print id}' "$CONFIG_FILE" 2>/dev/null)
    fi

    if [ ${#target_pids[@]} -eq 0 ]; then
        echo "OK: 教訓効果データなし(対象project 0件)"
        return 0
    fi

    local result
    result=$(python3 -c "
import yaml, sys, os

base = sys.argv[1]
pids = sys.argv[2:]
total = 0
helpful_positive = 0
warn5 = []

for pid in pids:
    path = os.path.join(base, 'projects', pid, 'lessons.yaml')
    if not os.path.exists(path):
        continue
    with open(path, encoding='utf-8') as f:
        data = yaml.safe_load(f)
    if not data or 'lessons' not in data:
        continue
    for l in data['lessons']:
        st = str(l.get('status', 'confirmed')).lower()
        if st == 'deprecated' or l.get('deprecated', False):
            continue
        total += 1
        hc = l.get('helpful_count', 0) or 0
        ic = l.get('injection_count', 0) or 0
        if hc > 0:
            helpful_positive += 1
        # injection_count >= 5 かつ helpful_count == 0 (injection_count==0は除外)
        if ic >= 5 and hc == 0:
            warn5.append(f'  - {l[\"id\"]}: injection={ic}, helpful={hc} [{pid}]')

if warn5:
    print('WARN: 注入5回以上で効果報告0件の教訓:')
    for w in warn5:
        print(w)

if total > 0:
    pct = round(helpful_positive / total * 100, 1)
    print(f'INFO: 教訓効果率: {helpful_positive}/{total} = {pct}%')
else:
    print('INFO: 教訓効果率: 0/0 (教訓なし)')
" "$SCRIPT_DIR" "${target_pids[@]}" 2>/dev/null) || {
        echo "WARN: 教訓効果率計算失敗"
        return 0
    }

    [ -n "$result" ] && echo "$result"

    # injection_count >= 10 かつ helpful_count == 0 の精密チェック (cmd_470)
    check_injection_count_threshold "${target_pids[@]}"
    return 0
}

if [ $# -ge 1 ]; then
    check_lesson_effectiveness "$1"
else
    check_lesson_effectiveness
fi

exit $EXIT_CODE
