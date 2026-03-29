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
LESSON_IMPACT_FILE="$SCRIPT_DIR/logs/lesson_impact.tsv"
LESSON_EFFECT_WINDOW_CMDS=30
LESSON_EFFECT_WARN_THRESHOLD=50
LESSON_EFFECT_ALERT_THRESHOLD=30
LESSON_EFFECT_STATUS_FILE="${LESSON_EFFECT_STATUS_FILE:-$SCRIPT_DIR/queue/lesson_effectiveness_status.txt}"
LESSON_EFFECT_NOTIFY_STATE="${LESSON_EFFECT_NOTIFY_STATE:-$SCRIPT_DIR/queue/lesson_effectiveness_notify_state.txt}"
LESSON_EFFECT_NTFY_ENABLED="${LESSON_EFFECT_NTFY_ENABLED:-1}"

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "action: $action"
}

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
        emit_actionable \
            "ALERT: ${project_id}のlesson→context未合流${unsynced}件(total:${total_lessons},synced:L${synced_num},max:L${max_id})" \
            "context 側へ未合流教訓を反映し、last_synced_lesson を更新せよ。"
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
        emit_actionable \
            "WARN: 新規教訓+${new_count}件(前回審査: L${checkpoint}, 現在最新: L${max_id})。" \
            "bash scripts/lesson_deprecation_scan.sh を実行し、新規教訓を審査せよ。"
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
        emit_actionable \
            "ALERT: ${project_id}の未振り分け教訓${count}件 → /lesson-sort推奨" \
            "/lesson-sort を実行し、未振り分け教訓を適切なcontextセクションへ移動せよ。"
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
        emit_actionable \
            "WARN: active projectが見つかりません" \
            "config/projects.yaml の active project 設定を確認し、対象projectを有効化せよ。"
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
        emit_actionable \
            "WARN: 注入${INJECTION_WARN_THRESHOLD}回以上で効果報告0件の教訓: ${problem_count}件" \
            "helpful_count=0 の教訓を見直し、改善するか deprecated 候補として審査せよ。"
    fi
}

# 教訓効果率ステータスをダッシュボードが拾える形式で保存
write_lesson_effect_status() {
    local status="$1"
    local rate="$2"
    local window_cmds="$3"
    local referenced="$4"
    local injected="$5"
    local scope="$6"
    cat > "$LESSON_EFFECT_STATUS_FILE" <<EOF
updated_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
status=${status}
rate=${rate}
window_cmds=${window_cmds}
referenced=${referenced}
injected=${injected}
scope=${scope}
EOF
}

notify_lesson_effect_if_needed() {
    local status="$1"
    local rate="$2"
    local scope="$3"

    local prev_status=""
    local prev_scope=""
    if [ -f "$LESSON_EFFECT_NOTIFY_STATE" ]; then
        prev_status=$(awk -F= '/^last_status=/{print $2; exit}' "$LESSON_EFFECT_NOTIFY_STATE" 2>/dev/null || true)
        prev_scope=$(awk -F= '/^scope=/{print $2; exit}' "$LESSON_EFFECT_NOTIFY_STATE" 2>/dev/null || true)
    fi

    if [ "$scope" != "$prev_scope" ]; then
        prev_status=""
    fi

    if [ "$status" = "WARN" ] || [ "$status" = "ALERT" ]; then
        if [ "$prev_status" != "$status" ]; then
            if [ "$LESSON_EFFECT_NTFY_ENABLED" = "1" ]; then
                bash "$SCRIPT_DIR/scripts/ntfy.sh" "教訓効果率${status}: ${rate}%"
            fi
        fi
    fi

    cat > "$LESSON_EFFECT_NOTIFY_STATE" <<EOF
updated_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
last_status=${status}
last_rate=${rate}
scope=${scope}
EOF
}

# --- 教訓効果サマリ (cmd_531: lesson_impact.tsv 直近30cmdで評価) ---
check_lesson_effectiveness() {
    local target_project="${1:-}"
    local scope="${target_project:-all}"

    if [ ! -f "$LESSON_IMPACT_FILE" ] || [ ! -s "$LESSON_IMPACT_FILE" ]; then
        emit_actionable \
            "WARN: 教訓効果率計算データなし(lesson_impact.tsv)" \
            "logs/lesson_impact.tsv の生成経路を確認し、メトリクス収集を有効化せよ。"
        write_lesson_effect_status "NODATA" "0.0" "0" "0" "0" "$scope"
        notify_lesson_effect_if_needed "NODATA" "0.0" "$scope"
        return 0
    fi

    local cmd_file
    cmd_file="$(mktemp)"
    local reversed_file
    reversed_file="$(mktemp)"

    tail -2000 "$LESSON_IMPACT_FILE" | tac > "$reversed_file"

    awk -F'\t' -v limit="$LESSON_EFFECT_WINDOW_CMDS" -v project="$target_project" '
        $1 == "timestamp" { next }
        {
            cmd = $2
            proj = $8
            gsub(/\r$/, "", cmd)
            gsub(/\r$/, "", proj)
            if (cmd !~ /^cmd_/) next
            if (cmd ~ /^cmd_test/) next
            if (project != "" && proj != project) next
            if (!(cmd in seen)) {
                seen[cmd] = 1
                print cmd
                n++
                if (n >= limit) exit
            }
        }
    ' "$reversed_file" > "$cmd_file"
    rm -f "$reversed_file"

    local window_cmds
    window_cmds=$(wc -l < "$cmd_file" | tr -d ' ')
    if [ "$window_cmds" -eq 0 ]; then
        rm -f "$cmd_file"
        emit_actionable \
            "WARN: 教訓効果率計算対象cmdなし(scope:${scope})" \
            "scope 設定と logs/lesson_impact.tsv の project 列を確認せよ。"
        write_lesson_effect_status "NODATA" "0.0" "0" "0" "0" "$scope"
        notify_lesson_effect_if_needed "NODATA" "0.0" "$scope"
        return 0
    fi

    local metric
    metric=$(awk -F'\t' -v cmd_file="$cmd_file" -v project="$target_project" '
        BEGIN {
            while ((getline line < cmd_file) > 0) {
                gsub(/\r$/, "", line)
                if (line != "") selected[line] = 1
            }
            close(cmd_file)
        }
        $1 == "timestamp" { next }
        {
            cmd = $2
            action = $5
            ref = tolower($7)
            proj = $8
            gsub(/\r$/, "", cmd)
            gsub(/\r$/, "", action)
            gsub(/\r$/, "", ref)
            gsub(/\r$/, "", proj)
            if (cmd !~ /^cmd_/) next
            if (!(cmd in selected)) next
            if (project != "" && proj != project) next
            if (action == "injected") {
                injected++
                if (ref == "yes" || ref == "true" || ref == "1") {
                    referenced++
                }
            }
        }
        END {
            printf "%d\t%d\n", referenced + 0, injected + 0
        }
    ' "$LESSON_IMPACT_FILE")
    rm -f "$cmd_file"

    local referenced_count=0
    local injected_count=0
    IFS=$'\t' read -r referenced_count injected_count <<< "$metric"

    local rate
    rate=$(awk -v ref="$referenced_count" -v inj="$injected_count" 'BEGIN{
        if (inj > 0) printf "%.1f", (ref / inj) * 100
        else printf "0.0"
    }')

    local threshold_status="OK"
    if [ "$injected_count" -gt 0 ]; then
        if awk -v v="$rate" -v thr="$LESSON_EFFECT_ALERT_THRESHOLD" 'BEGIN{exit !(v < thr)}'; then
            threshold_status="ALERT"
        elif awk -v v="$rate" -v thr="$LESSON_EFFECT_WARN_THRESHOLD" 'BEGIN{exit !(v < thr)}'; then
            threshold_status="WARN"
        fi
    fi

    echo "INFO: 教訓効果率(直近${window_cmds}cmd): ${referenced_count}/${injected_count} = ${rate}%"
    echo "METRIC: lesson_effectiveness_threshold status=${threshold_status} rate=${rate}% window_cmds=${window_cmds} referenced=${referenced_count} injected=${injected_count} scope=${scope}"

    write_lesson_effect_status "$threshold_status" "$rate" "$window_cmds" "$referenced_count" "$injected_count" "$scope"
    notify_lesson_effect_if_needed "$threshold_status" "$rate" "$scope"

    # injection_count >= 10 かつ helpful_count == 0 の精密チェック (cmd_470)
    if [ -n "$target_project" ]; then
        check_injection_count_threshold "$target_project"
    else
        check_injection_count_threshold
    fi
    return 0
}

if [ $# -ge 1 ]; then
    check_lesson_effectiveness "$1"
else
    check_lesson_effectiveness
fi

exit $EXIT_CODE
