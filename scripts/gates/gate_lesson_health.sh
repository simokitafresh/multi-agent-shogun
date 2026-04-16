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
ALERT_THRESHOLD=5
EXIT_CODE=0
LESSON_IMPACT_FILE="$SCRIPT_DIR/logs/lesson_impact.tsv"
LESSON_EFFECT_WINDOW_CMDS=30
LESSON_EFFECT_WARN_THRESHOLD=50
LESSON_EFFECT_ALERT_THRESHOLD=30
LESSON_EFFECT_STATUS_FILE="${LESSON_EFFECT_STATUS_FILE:-$SCRIPT_DIR/queue/lesson_effectiveness_status.txt}"
LESSON_EFFECT_NOTIFY_STATE="${LESSON_EFFECT_NOTIFY_STATE:-$SCRIPT_DIR/queue/lesson_effectiveness_notify_state.txt}"
LESSON_EFFECT_NTFY_ENABLED="${LESSON_EFFECT_NTFY_ENABLED:-1}"
INJECTION_WARN_THRESHOLD=10
ACCUMULATION_THRESHOLD=10
UNSORTED_THRESHOLD=10
CHECKPOINT_FILE="$SCRIPT_DIR/queue/lesson_deprecation_checkpoint.txt"

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "action: $action"
}

# ─── 高速化: lessons.yaml を1回だけ読んで全統計を計算 ───
# 出力1行目: active_count|max_id|deprecated_count|unsynced_count|new_since_checkpoint
# 追加行: PROBLEM:L番号: injection=N, helpful=0 [pid]
_compute_lesson_stats() {
    local file="$1"
    local synced_num="${2:-0}"
    local checkpoint="${3:-0}"
    local inject_thr="${4:-10}"
    local pid="${5:-}"

    awk -v synced="$synced_num" -v chk="$checkpoint" \
        -v thr="$inject_thr" -v pid="$pid" '
    function flush_current(    n) {
        if (current_id == "") return
        n = current_id + 0
        if (is_deprecated) {
            dep++
        } else {
            active_nc++
            if (n > max_id) max_id = n
            if (n > synced + 0) unsynced++
            if (n > chk + 0) new_since++
            if (ic + 0 >= thr + 0 && hc + 0 == 0) {
                problems[active_nc] = "L" current_id ": injection=" ic+0 ", helpful=0 [" pid "]"
            }
        }
    }
    /^- id: L/ {
        flush_current()
        current_id = $3; sub(/^L/, "", current_id)
        is_deprecated = 0; ic = 0; hc = 0
    }
    /[[:space:]]+status:[[:space:]]+deprecated/ { is_deprecated = 1 }
    /[[:space:]]+deprecated:[[:space:]]+true/ { is_deprecated = 1 }
    /[[:space:]]+injection_count:[[:space:]]/ {
        gsub(/.*injection_count:[[:space:]]*/,""); ic = $1 + 0
    }
    /[[:space:]]+helpful_count:[[:space:]]/ {
        gsub(/.*helpful_count:[[:space:]]*/,""); hc = $1 + 0
    }
    END {
        flush_current()
        printf "%d|%d|%d|%d|%d\n", active_nc+0, max_id+0, dep+0, unsynced+0, new_since+0
        for (i in problems) printf "PROBLEM:%s\n", problems[i]
    }
    ' "$file"
}

write_lesson_effect_status() {
    local status="$1" rate="$2" window_cmds="$3" referenced="$4" injected="$5" scope="$6"
    local useful="${7:-0}" total_feedback="${8:-0}" useful_rate="${9:-0.0}"
    cat > "$LESSON_EFFECT_STATUS_FILE" <<EOF
updated_at=$_now
status=${status}
rate=${rate}
window_cmds=${window_cmds}
referenced=${referenced}
injected=${injected}
scope=${scope}
useful=${useful}
total_feedback=${total_feedback}
useful_rate=${useful_rate}
EOF
}

notify_lesson_effect_if_needed() {
    local status="$1" rate="$2" scope="$3"
    local prev_status="" prev_scope=""

    # 高速化: 2回のawk呼び出しを1回に統合
    if [ -f "$LESSON_EFFECT_NOTIFY_STATE" ]; then
        local _ns
        _ns=$(awk -F= '/^last_status=/{s=$2} /^scope=/{sc=$2} END{print s "|" sc}' \
            "$LESSON_EFFECT_NOTIFY_STATE" 2>/dev/null || true)
        prev_status="${_ns%%|*}"
        prev_scope="${_ns##*|}"
    fi

    [ "$scope" != "$prev_scope" ] && prev_status=""

    if [ "$status" = "WARN" ] || [ "$status" = "ALERT" ]; then
        if [ "$prev_status" != "$status" ] && [ "$LESSON_EFFECT_NTFY_ENABLED" = "1" ]; then
            bash "$SCRIPT_DIR/scripts/ntfy.sh" "教訓効果率${status}: ${rate}%"
        fi
    fi

    cat > "$LESSON_EFFECT_NOTIFY_STATE" <<EOF
updated_at=$_now
last_status=${status}
last_rate=${rate}
scope=${scope}
EOF
}

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

    # 高速化: reversed_file tempファイルを排除 (tac→awk直結)
    # 高速化: cmd_fileを$$固定パスに (mktemp呼び出し削減)
    local cmd_file="/tmp/_glh_cmds_$$"

    tac "$LESSON_IMPACT_FILE" | awk -F'\t' -v limit="$LESSON_EFFECT_WINDOW_CMDS" \
        -v project="$target_project" '
        $1 == "timestamp" { next }
        {
            cmd = $2; proj = $8
            gsub(/\r$/, "", cmd); gsub(/\r$/, "", proj)
            if (cmd !~ /^cmd_/) next
            if (cmd ~ /^cmd_test/) next
            if (project != "" && proj != project) next
            if (!(cmd in seen)) {
                seen[cmd] = 1; print cmd; n++
                if (n >= limit) exit
            }
        }
    ' > "$cmd_file"

    local window_cmds
    window_cmds=$(awk 'END{print NR}' "$cmd_file")
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
            cmd=$2; action=$5; result=$6; ref=tolower($7); proj=$8
            gsub(/\r$/, "", cmd); gsub(/\r$/, "", action)
            gsub(/\r$/, "", result); gsub(/\r$/, "", ref); gsub(/\r$/, "", proj)
            if (cmd !~ /^cmd_/) next
            if (!(cmd in selected)) next
            if (project != "" && proj != project) next
            if (action == "injected") {
                injected++
                if (ref == "yes" || ref == "true" || ref == "1") referenced++
            } else if (action == "feedback") {
                total_feedback++
                if (toupper(result) == "USEFUL") useful++
            }
        }
        END { printf "%d\t%d\t%d\t%d\n", referenced+0, injected+0, useful+0, total_feedback+0 }
    ' "$LESSON_IMPACT_FILE")
    rm -f "$cmd_file"

    local referenced_count=0 injected_count=0 useful_count=0 total_feedback_count=0
    IFS=$'\t' read -r referenced_count injected_count useful_count total_feedback_count <<< "$metric"

    # 高速化: float比較4回のawk呼び出しを1回に統合
    local threshold_status rate useful_rate
    IFS='|' read -r threshold_status rate useful_rate <<< "$(awk \
        -v ref="$referenced_count" -v inj="$injected_count" \
        -v uf="$useful_count" -v tf="$total_feedback_count" \
        -v wa="$LESSON_EFFECT_WARN_THRESHOLD" -v al="$LESSON_EFFECT_ALERT_THRESHOLD" '
    BEGIN {
        r  = (inj > 0) ? (ref / inj) * 100 : 0.0
        ur = (tf  > 0) ? (uf  / tf)  * 100 : 0.0
        s  = "OK"
        if (inj > 0 && r < al)                   s = "ALERT"
        else if (inj > 0 && r < wa)               s = "WARN"
        if (tf > 0 && ur < al)                    s = "ALERT"
        else if (tf > 0 && s == "OK" && ur < wa)  s = "WARN"
        printf "%s|%.1f|%.1f\n", s, r, ur
    }')"

    echo "INFO: 教訓効果率(直近${window_cmds}cmd): ${referenced_count}/${injected_count} = ${rate}%"
    echo "INFO: useful率(直近${window_cmds}cmd): ${useful_count}/${total_feedback_count} = ${useful_rate}%"
    echo "METRIC: lesson_effectiveness_threshold status=${threshold_status} rate=${rate}% useful_rate=${useful_rate}% window_cmds=${window_cmds} referenced=${referenced_count} injected=${injected_count} useful=${useful_count} total_feedback=${total_feedback_count} scope=${scope}"

    write_lesson_effect_status "$threshold_status" "$rate" "$window_cmds" \
        "$referenced_count" "$injected_count" "$scope" \
        "$useful_count" "$total_feedback_count" "$useful_rate"
    notify_lesson_effect_if_needed "$threshold_status" "$rate" "$scope"
    return 0
}

# ─── メイン処理 ───

# 高速化: date を1回だけ呼ぶ
_now=$(date '+%Y-%m-%dT%H:%M:%S%z')

# 高速化: checkpoint を1回だけ読む (bash param展開でgrep置換)
_checkpoint=0
if [ -f "$CHECKPOINT_FILE" ]; then
    _raw_chk=$(awk 'match($0, /L([0-9]+)/, a) {found=1; r=a[1]+0; exit} END{print (found ? r : 0)}' \
        "$CHECKPOINT_FILE" 2>/dev/null || echo 0)
    _checkpoint="${_raw_chk:-0}"
fi

# 処理対象projectリストを決定
if [ $# -ge 1 ]; then
    _target_pids=("$1")
    # 単一PJ指定時: context_fileをawk1回で取得
    _cf_raw=$(awk -v pid="$1" '
        /^  - id:/ { cur_id=$3 }
        cur_id == pid && /context_file:/ {
            cf=$2; gsub(/["'"'"']/, "", cf); gsub(/[[:space:]]/, "", cf); print cf; exit
        }
    ' "$CONFIG_FILE" 2>/dev/null || true)
    declare -A _context_map
    if [ -n "$_cf_raw" ]; then
        _context_map["$1"]="$_cf_raw"
    else
        _context_map["$1"]="context/$1.md"
    fi
else
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "ERROR: config/projects.yaml not found"
        exit 1
    fi

    # 高速化: active projects + context_files を1回のawk passで取得
    _target_pids=()
    declare -A _context_map
    while IFS='=' read -r _k _v; do
        if [ "$_k" = "PID" ]; then
            _target_pids+=("$_v")
        else
            _context_map["$_k"]="$_v"
        fi
    done < <(awk '
        /^  - id:/ {
            if (cur_id != "" && is_active) {
                print "PID=" cur_id
                print cur_id "=" (cf != "" ? cf : "context/" cur_id ".md")
            }
            cur_id = $3; is_active = 0; cf = ""
        }
        /status:[[:space:]]+active/ { is_active = 1 }
        /^[[:space:]]+context_file:/ {
            v = $2; gsub(/["'"'"']/, "", v); gsub(/[[:space:]]/, "", v)
            if (v != "") cf = v
        }
        END {
            if (cur_id != "" && is_active) {
                print "PID=" cur_id
                print cur_id "=" (cf != "" ? cf : "context/" cur_id ".md")
            }
        }
    ' "$CONFIG_FILE")

    if [ ${#_target_pids[@]} -eq 0 ]; then
        emit_actionable \
            "WARN: active projectが見つかりません" \
            "config/projects.yaml の active project 設定を確認し、対象projectを有効化せよ。"
        exit 0
    fi
fi

# 蓄積チェック用グローバル集計
_global_max_id=0
_global_new_count=0

for _pid in "${_target_pids[@]}"; do
    _lessons_file="$SCRIPT_DIR/projects/${_pid}/lessons.yaml"

    if [ ! -f "$_lessons_file" ]; then
        echo "OK: ${_pid} lessons.yaml不在(lesson 0件)"
        continue
    fi

    # context_file パスを取得 (awk1回のキャッシュから)
    _cf="${_context_map[$_pid]:-}"
    [ -z "$_cf" ] && _cf="context/${_pid}.md"
    _context_path="$SCRIPT_DIR/$_cf"

    # 高速化: context fileを1回のawk passでsynced_num+unsorted_countを取得
    _synced_num=0
    _unsorted=0
    if [ -f "$_context_path" ]; then
        _ctx_data=$(awk '
            /<!-- last_synced_lesson: L[0-9]+ -->/ {
                match($0, /L([0-9]+)/, arr); synced = arr[1]+0
            }
            /^## 教訓索引（自動追記）/ { in_sec=1; next }
            in_sec && /^## / { in_sec=0 }
            in_sec && /^- L/ { c++ }
            END { printf "%d|%d\n", synced+0, c+0 }
        ' "$_context_path")
        _synced_num="${_ctx_data%%|*}"
        _unsorted="${_ctx_data##*|}"
    fi

    # ─── 1回のawk passで全統計を取得 ───
    _stats_output=$(_compute_lesson_stats "$_lessons_file" "$_synced_num" "$_checkpoint" \
        "$INJECTION_WARN_THRESHOLD" "$_pid")

    _stats_line="${_stats_output%%$'\n'*}"
    IFS='|' read -r _total_lessons _max_id _deprecated_count _unsynced _new_count <<< "$_stats_line"
    _injection_problems=$(printf '%s\n' "$_stats_output" | grep '^PROBLEM:' | sed 's/^PROBLEM://' || true)

    # ─── check_project 相当 ───
    if [ "${_total_lessons:-0}" -eq 0 ]; then
        if [ "${_deprecated_count:-0}" -gt 0 ]; then
            echo "OK: ${_pid} lesson 0件(deprecated除外後)"
        else
            echo "OK: ${_pid} lesson 0件"
        fi
        continue
    fi

    [ "${_deprecated_count:-0}" -gt 0 ] && echo "INFO: ${_pid} deprecated除外: ${_deprecated_count}件"

    if [ "${_unsynced:-0}" -gt "$ALERT_THRESHOLD" ]; then
        emit_actionable \
            "ALERT: ${_pid}のlesson→context未合流${_unsynced}件(total:${_total_lessons},synced:L${_synced_num},max:L${_max_id})" \
            "context 側へ未合流教訓を反映し、last_synced_lesson を更新せよ。"
        EXIT_CODE=1
    else
        echo "OK: ${_pid}のlesson統合状況は健全(未合流${_unsynced}件,total:${_total_lessons},synced:L${_synced_num})"
    fi

    # ─── check_unsorted_lessons 相当 ───
    if [ "${_unsorted:-0}" -gt "$UNSORTED_THRESHOLD" ]; then
        emit_actionable \
            "ALERT: ${_pid}の未振り分け教訓${_unsorted}件 → /lesson-sort推奨" \
            "/lesson-sort を実行し、未振り分け教訓を適切なcontextセクションへ移動せよ。"
        EXIT_CODE=1
    elif [ "${_unsorted:-0}" -gt 0 ]; then
        echo "OK: ${_pid}の未振り分け教訓${_unsorted}件(閾値${UNSORTED_THRESHOLD}以下)"
    fi

    # ─── injection_count チェック相当 ───
    if [ -n "$_injection_problems" ]; then
        local_problem_count=$(printf '%s\n' "$_injection_problems" | wc -l)
        while IFS= read -r _prob_line; do echo "  - $_prob_line"; done <<< "$_injection_problems"
        emit_actionable \
            "WARN: 注入${INJECTION_WARN_THRESHOLD}回以上で効果報告0件の教訓: ${local_problem_count}件" \
            "helpful_count=0 の教訓を見直し、改善するか deprecated 候補として審査せよ。"
    fi

    # 蓄積チェック用に集計
    [ "${_max_id:-0}" -gt "$_global_max_id" ] && _global_max_id="${_max_id}"
    _global_new_count=$((_global_new_count + _new_count))

done

# ─── check_accumulation 相当 ───
if [ "$_global_max_id" -gt 0 ]; then
    if [ "$_global_new_count" -ge "$ACCUMULATION_THRESHOLD" ]; then
        emit_actionable \
            "WARN: 新規教訓+${_global_new_count}件(前回審査: L${_checkpoint}, 現在最新: L${_global_max_id})。" \
            "bash scripts/lesson_deprecation_scan.sh を実行し、新規教訓を審査せよ。"
        EXIT_CODE=1
    else
        echo "OK: 蓄積チェック(新規${_global_new_count}件, 前回審査: L${_checkpoint}, 閾値${ACCUMULATION_THRESHOLD})"
    fi
fi

# ─── check_lesson_effectiveness ───
if [ $# -ge 1 ]; then
    check_lesson_effectiveness "$1"
else
    check_lesson_effectiveness
fi

exit $EXIT_CODE
