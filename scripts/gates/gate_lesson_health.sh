#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]]
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
LESSON_EFFECT_WINDOW_CMDS=10
LESSON_EFFECT_WARN_THRESHOLD=50
LESSON_EFFECT_ALERT_THRESHOLD=30
LESSON_EFFECT_STATUS_FILE="${LESSON_EFFECT_STATUS_FILE:-$SCRIPT_DIR/queue/lesson_effectiveness_status.txt}"
LESSON_EFFECT_NOTIFY_STATE="${LESSON_EFFECT_NOTIFY_STATE:-$SCRIPT_DIR/queue/lesson_effectiveness_notify_state.txt}"
LESSON_EFFECT_NTFY_ENABLED="${LESSON_EFFECT_NTFY_ENABLED:-1}"
LESSON_EFFECT_MIN_SAMPLES="${LESSON_EFFECT_MIN_SAMPLES:-5}"  # 退役スキャン確定閾値と揃え、少数feedbackノイズでBLOCKしない
LESSON_EFFECT_USEFUL_MIN="${LESSON_EFFECT_USEFUL_MIN:-2}"   # health計測用の最小サンプル数。退役(5)より低く設定(30cmd窓で各教訓が5件に達しない計測バグ修正)
INJECTION_WARN_THRESHOLD=10
ACCUMULATION_THRESHOLD=10
UNSORTED_THRESHOLD=10
UNSORTED_WARN_THRESHOLD=5
CHECKPOINT_FILE="$SCRIPT_DIR/queue/lesson_deprecation_checkpoint.txt"

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "action: $action"
}

check_ssot_conflict_markers() {
    local pid="$1"
    local lessons_file="$2"
    local ssot_path=""
    local conflict_hits=""

    ssot_path=$(awk '
        /^ssot_path:[[:space:]]*/ {
            sub(/^ssot_path:[[:space:]]*/, "", $0)
            gsub(/^["'"'"']|["'"'"']$/, "", $0)
            print
            exit
        }
    ' "$lessons_file" 2>/dev/null || true)

    if [ -z "$ssot_path" ]; then
        emit_actionable \
            "WARN: ${pid} ssot_path未設定のため conflict markers を確認できません" \
            "projects/${pid}/lessons.yaml の ssot_path を設定し、SSOT lessons.md を参照可能にせよ。"
        return 1
    fi

    if [ ! -f "$ssot_path" ]; then
        emit_actionable \
            "WARN: ${pid} SSOT file not found: ${ssot_path}" \
            "projects/${pid}/lessons.yaml の ssot_path を正しい lessons.md に修正せよ。"
        return 1
    fi

    conflict_hits=$(grep -nE '^[[:space:]]*(<<<<<<<|[|]{7}|=======|>>>>>>>)' "$ssot_path" || true)
    if [ -z "$conflict_hits" ]; then
        echo "OK: ${pid} SSOT conflict markersなし"
        return 0
    fi

    echo "$conflict_hits" | while IFS= read -r line; do
        [ -n "$line" ] && echo "  - ${ssot_path}:${line}"
    done
    emit_actionable \
        "ALERT: ${pid} SSOTにgit conflict markers検出" \
        "SSOT lessons.md の conflict markers(<<<<<<< / ||||||| / ======= / >>>>>>>)を解消せよ。"
    return 1
}

# ─── 高速化: lessons.yaml を1回だけ読んで全統計を計算 ───
# 出力1行目: active_count|max_id|deprecated_count|unsynced_count|new_since_checkpoint|when_count|how_count|origin_count
# 追加行: PROBLEM:L番号: injection=N, helpful=0 [pid]
_compute_lesson_stats() {
    local file="$1"
    local synced_num="${2:-0}"
    local checkpoint="${3:-0}"
    local inject_thr="${4:-10}"
    local pid="${5:-}"

    awk -v synced="$synced_num" -v chk="$checkpoint" \
        -v thr="$inject_thr" -v pid="$pid" '
    function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
    function inline_value(line, field,    pat,m,v) {
        pat = "(^|[,][[:space:]]*)" field ":[[:space:]]*([^,}]+)"
        if (match(line, pat, m)) {
            v = trim(m[2])
            gsub(/^['\''"]|['\''"]$/, "", v)
            return trim(v)
        }
        return ""
    }
    function is_set_value(v) {
        v = trim(v)
        return (v != "")
    }
    function flush_current(    n) {
        if (current_id == "") return
        n = current_id + 0
        if (is_deprecated) {
            dep++
        } else {
            active_nc++
            if (has_when) when_count++
            if (has_how) how_count++
            if (has_origin) origin_count++
            if (n > max_id) max_id = n
            if (n > synced + 0) unsynced++
            if (n > chk + 0) new_since++
            if (ic + 0 >= thr + 0 && hc + 0 == 0) {
                problems[active_nc] = "L" current_id ": injection=" ic+0 ", helpful=0 [" pid "]"
            }
        }
    }
    /^- / && /id:[[:space:]]*['\''"]?L[0-9]+/ {
        flush_current()
        current_id = $0
        sub(/^.*id:[[:space:]]*['\''"]?L/, "", current_id)
        sub(/[^0-9].*$/, "", current_id)
        is_deprecated = 0; ic = 0; hc = 0; has_when = 0; has_how = 0; has_origin = 0
        if (is_set_value(inline_value($0, "when"))) has_when = 1
        if (is_set_value(inline_value($0, "how"))) has_how = 1
        if (is_set_value(inline_value($0, "origin"))) has_origin = 1
    }
    /[[:space:]]+status:[[:space:]]+deprecated/ { is_deprecated = 1 }
    /[[:space:]]+deprecated:[[:space:]]+true/ { is_deprecated = 1 }
    /^[[:space:]]+when:[[:space:]]*[^[:space:]]/ {
        v = $0
        sub(/^[[:space:]]+when:[[:space:]]*/, "", v)
        if (is_set_value(v)) has_when = 1
    }
    /^[[:space:]]+how:[[:space:]]*[^[:space:]]/ {
        v = $0
        sub(/^[[:space:]]+how:[[:space:]]*/, "", v)
        if (is_set_value(v)) has_how = 1
    }
    /^[[:space:]]+origin:[[:space:]]*[^[:space:]]/ {
        v = $0
        sub(/^[[:space:]]+origin:[[:space:]]*/, "", v)
        if (is_set_value(v)) has_origin = 1
    }
    /[[:space:]]+injection_count:[[:space:]]/ {
        gsub(/.*injection_count:[[:space:]]*/,""); ic = $1 + 0
    }
    /[[:space:]]+helpful_count:[[:space:]]/ {
        gsub(/.*helpful_count:[[:space:]]*/,""); hc = $1 + 0
    }
    END {
        flush_current()
        printf "%d|%d|%d|%d|%d|%d|%d|%d\n", active_nc+0, max_id+0, dep+0, unsynced+0, new_since+0, when_count+0, how_count+0, origin_count+0
        for (i in problems) printf "PROBLEM:%s\n", problems[i]
    }
    ' "$file"
}

# §3.3: 3ファイル×awk 3回→1回のawk+BEGINFILE/ENDFILE統合(cmd_3632)
check_role_lesson_origins_batch() {
    local _origin_files=()
    for _lf in "$SCRIPT_DIR"/projects/infra/lessons_shogun.yaml \
               "$SCRIPT_DIR"/projects/infra/lessons_gunshi.yaml \
               "$SCRIPT_DIR"/projects/infra/lessons_karo.yaml; do
        [ -f "$_lf" ] && _origin_files+=("$_lf")
    done
    [ ${#_origin_files[@]} -eq 0 ] && return 0
    awk '
        function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
        function first5(arr,    i,out) {
            out = ""
            for (i = 1; i <= arr[0] && i <= 5; i++) out = out (out ? "," : "") arr[i]
            return out
        }
        function flush_current(    origin_text) {
            if (id == "") return
            ftotal++
            if (!origin_seen) {
                fmissing[++fmissing[0]] = id
            } else {
                origin_text = trim(origin_value)
                gsub(/^["'\''"]|["'\''"]$/, "", origin_text)
                if (origin_text == "") fempty[++fempty[0]] = id
                else if (origin_text !~ /\[\[[^]\n]+\]\]/) fno_links[++fno_links[0]] = id
            }
        }
        function emit_file_result() {
            bad = fmissing[0] + fempty[0] + fno_links[0]
            if (bad) {
                printf "WARN: %s origin因果リンク不備 %d/%d件\n", flabel, bad, ftotal
                if (fmissing[0]) printf "  origin欠落: %s\n", first5(fmissing)
                if (fempty[0]) printf "  origin空: %s\n", first5(fempty)
                if (fno_links[0]) printf "  リンク0件: %s\n", first5(fno_links)
            } else {
                printf "OK: %s origin因果リンク (%d件)\n", flabel, ftotal
            }
        }
        BEGINFILE {
            if (id != "") flush_current()
            if (ftotal > 0) emit_file_result()
            flabel = FILENAME; sub(/.*\//, "", flabel)
            ftotal = 0; id = ""; delete fmissing; delete fempty; delete fno_links
            fmissing[0] = 0; fempty[0] = 0; fno_links[0] = 0
        }
        /^- id:[[:space:]]*/ {
            flush_current()
            id = $0
            sub(/^- id:[[:space:]]*["'\''"]?/, "", id)
            sub(/["'\''"]?[[:space:]]*$/, "", id)
            origin_seen = 0; origin_value = ""
            next
        }
        /^[[:space:]]+origin:[[:space:]]*/ {
            origin_seen = 1
            origin_value = $0
            sub(/^[[:space:]]+origin:[[:space:]]*/, "", origin_value)
            next
        }
        ENDFILE {
            flush_current()
            emit_file_result()
            id = ""; ftotal = 0; delete fmissing; delete fempty; delete fno_links
            fmissing[0] = 0; fempty[0] = 0; fno_links[0] = 0
        }
    ' "${_origin_files[@]}" 2>/dev/null || echo "WARN: origin検査に失敗。YAML構文または形式を確認せよ"
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
    local active_file="/tmp/_glh_active_lessons_$$"
    local presence_file="/tmp/_glh_lesson_presence_$$"

    : > "$active_file"
    : > "$presence_file"
    local _active_pid _active_lessons_file
    local _active_pids=()
    if [ -n "$target_project" ]; then
        _active_pids=("$target_project")
    else
        _active_pids=("${_target_pids[@]}")
    fi
    # §3.2: 14PJ×awk→1回のawk+複数ファイル引数(ファイルI/O削減)
    local _lesson_files=()
    for _active_pid in "${_active_pids[@]}"; do
        _active_lessons_file="$SCRIPT_DIR/projects/${_active_pid}/lessons.yaml"
        [ -f "$_active_lessons_file" ] && _lesson_files+=("$_active_lessons_file")
    done
    if [ ${#_lesson_files[@]} -gt 0 ]; then
        awk '
            BEGINFILE {
                # ファイルパスからPJ IDを抽出: projects/{id}/lessons.yaml
                pid = FILENAME
                sub(/.*\/projects\//, "", pid)
                sub(/\/lessons.*/, "", pid)
            }
            function flush_current() {
                if (id != "" && !deprecated) print pid "\t" id
            }
            /^- / && /id:[[:space:]]*['\''"]?L[0-9]+/ {
                flush_current()
                id = $0
                sub(/^.*id:[[:space:]]*['\''"]?/, "", id)
                sub(/[^L0-9].*$/, "", id)
                deprecated = 0
                if ($0 ~ /deprecated:[[:space:]]*true/ || $0 ~ /status:[[:space:]]*deprecated/) deprecated = 1
                next
            }
            /^[[:space:]]+deprecated:[[:space:]]*true/ { deprecated = 1 }
            /^[[:space:]]+status:[[:space:]]*deprecated/ { deprecated = 1 }
            ENDFILE { flush_current(); id = "" }
        ' "${_lesson_files[@]}" > "$active_file"
        awk '
            BEGINFILE {
                pid = FILENAME
                sub(/.*\/projects\//, "", pid)
                sub(/\/lessons.*/, "", pid)
            }
            /^- / && /id:[[:space:]]*['\''"]?L[0-9]+/ {
                id = $0
                sub(/^.*id:[[:space:]]*['\''"]?/, "", id)
                sub(/[^L0-9].*$/, "", id)
                if (id != "") print pid "\t" id
            }
        ' "${_lesson_files[@]}" > "$presence_file"
    fi

    tac "$LESSON_IMPACT_FILE" | awk -F'\t' -v limit="$LESSON_EFFECT_WINDOW_CMDS" \
        -v project="$target_project" '
        $1 == "timestamp" { next }
        {
            cmd = $2; result = tolower($6); ref = tolower($7); proj = $8
            gsub(/\r$/, "", cmd); gsub(/\r$/, "", result); gsub(/\r$/, "", ref); gsub(/\r$/, "", proj)
            if (cmd !~ /^cmd_/) next
            if (cmd ~ /^cmd_test/) next
            if (cmd ~ /^cmd_training/) next
            if (result == "pending" || ref == "pending") next
            if (project != "" && proj != project) next
            if (!(cmd in seen)) {
                seen[cmd] = 1
                if (n < limit) {
                    print cmd
                    n++
                }
            }
        }
    ' > "$cmd_file"

    local window_cmds
    window_cmds=$(awk 'END{print NR}' "$cmd_file")
    if [ "$window_cmds" -eq 0 ]; then
        rm -f "$cmd_file" "$active_file" "$presence_file"
        emit_actionable \
            "WARN: 教訓効果率計算対象cmdなし(scope:${scope})" \
            "scope 設定と logs/lesson_impact.tsv の project 列を確認せよ。"
        write_lesson_effect_status "NODATA" "0.0" "0" "0" "0" "$scope"
        notify_lesson_effect_if_needed "NODATA" "0.0" "$scope"
        return 0
    fi

    # Pass 0: Build mature lesson list (all-time feedback >= useful_min).
    # Bootstrap教訓(全期間で1回しかfeedbackがない)を直近窓の集計から除外する。
    local mature_file
    mature_file=$(mktemp)
    awk -F'\t' -v useful_min="$LESSON_EFFECT_USEFUL_MIN" -v active_file="$active_file" -v presence_file="$presence_file" '
        BEGIN {
            while ((getline line < active_file) > 0) {
                split(line, parts, "\t")
                if (parts[1] != "" && parts[2] != "") active[parts[1] SUBSEP parts[2]] = 1
            }
            close(active_file)
            while ((getline line < presence_file) > 0) {
                split(line, parts, "\t")
                if (parts[1] != "" && parts[2] != "") present[parts[1] SUBSEP parts[2]] = 1
            }
            close(presence_file)
        }
        $1 == "timestamp" { next }
        {
            action=$5; lid=$4; proj=$8
            gsub(/\r$/, "", action); gsub(/\r$/, "", lid); gsub(/\r$/, "", proj)
            if (tolower(action) != "feedback" || lid == "") next
            lesson_key = ""
            if ((proj SUBSEP lid) in active) lesson_key = proj SUBSEP lid
            else if (!((proj SUBSEP lid) in present) && (("infra" SUBSEP lid) in active)) lesson_key = proj SUBSEP "infra:" lid
            if (lesson_key != "") all_total[lesson_key]++
        }
        END {
            for (lesson_key in all_total) {
                if (all_total[lesson_key] >= useful_min) print lesson_key
            }
        }
    ' "$LESSON_IMPACT_FILE" > "$mature_file"

    local metric
    metric=$(awk -F'\t' -v cmd_file="$cmd_file" -v active_file="$active_file" -v presence_file="$presence_file" -v project="$target_project" \
        -v min_samples="$LESSON_EFFECT_MIN_SAMPLES" \
        -v useful_min="$LESSON_EFFECT_USEFUL_MIN" \
        -v mature_file="$mature_file" '
        BEGIN {
            while ((getline line < cmd_file) > 0) {
                gsub(/\r$/, "", line)
                if (line != "") selected[line] = 1
            }
            close(cmd_file)
            while ((getline line < active_file) > 0) {
                split(line, parts, "\t")
                if (parts[1] != "" && parts[2] != "") active[parts[1] SUBSEP parts[2]] = 1
            }
            close(active_file)
            while ((getline line < presence_file) > 0) {
                split(line, parts, "\t")
                if (parts[1] != "" && parts[2] != "") present[parts[1] SUBSEP parts[2]] = 1
            }
            close(presence_file)
            # Load mature lesson list (all-time feedback >= useful_min)
            while ((getline line < mature_file) > 0) {
                gsub(/\r$/, "", line)
                if (line != "") mature[line] = 1
            }
            close(mature_file)
        }
        $1 == "timestamp" { next }
        {
            cmd=$2; action=$5; result=$6; ref=tolower($7); proj=$8; task_type=$9; lid=$4
            gsub(/\r$/, "", cmd); gsub(/\r$/, "", action)
            gsub(/\r$/, "", result); gsub(/\r$/, "", ref); gsub(/\r$/, "", proj); gsub(/\r$/, "", task_type); gsub(/\r$/, "", lid)
            if (cmd !~ /^cmd_/) next
            if (!(cmd in selected)) next
            if (project != "" && proj != project) next
            lesson_key = ""
            if ((proj SUBSEP lid) in active) lesson_key = proj SUBSEP lid
            else if (!((proj SUBSEP lid) in present) && (("infra" SUBSEP lid) in active)) lesson_key = proj SUBSEP "infra:" lid
            if (lesson_key == "") next
            if (result == "pending" || ref == "pending") next
            # hotfix feedback is dominated by self-healing tasks and is too bursty
            # for the long-window lesson usefulness health signal.
            if (task_type == "hotfix") next
            if (action == "injected") {
                injected++
                if (ref == "yes" || ref == "true" || ref == "1") referenced++
            } else if (action == "feedback") {
                # Only count feedback for mature lessons (all-time feedback >= useful_min)
                # to exclude Bootstrap noise (first-time NOT_USEFUL from untested lessons).
                if (!(lesson_key in mature)) next
                lesson_total[lesson_key]++
                if (toupper(result) == "USEFUL") lesson_useful[lesson_key]++
            }
        }
        END {
            for (lid in lesson_total) {
                total_feedback += lesson_total[lid]
                useful += (lid in lesson_useful) ? lesson_useful[lid] : 0
            }
            printf "%d\t%d\t%d\t%d\n", referenced+0, injected+0, useful+0, total_feedback+0
        }
    ' "$LESSON_IMPACT_FILE")
    rm -f "$mature_file"
    rm -f "$cmd_file" "$active_file" "$presence_file"

    local referenced_count=0 injected_count=0 useful_count=0 total_feedback_count=0
    IFS=$'\t' read -r referenced_count injected_count useful_count total_feedback_count <<< "$metric"

    # 高速化: float比較4回のawk呼び出しを1回に統合
    local threshold_status rate useful_rate
    IFS='|' read -r threshold_status rate useful_rate <<< "$(awk \
        -v ref="$referenced_count" -v inj="$injected_count" \
        -v uf="$useful_count" -v tf="$total_feedback_count" \
        -v ms="$LESSON_EFFECT_MIN_SAMPLES" \
        -v wa="$LESSON_EFFECT_WARN_THRESHOLD" -v al="$LESSON_EFFECT_ALERT_THRESHOLD" '
    BEGIN {
        r  = (inj > 0) ? (ref / inj) * 100 : 0.0
        ur = (tf  > 0) ? (uf  / tf)  * 100 : 0.0
        s  = "OK"
        if (inj >= ms && r < al)                  s = "ALERT"
        else if (inj >= ms && r < wa)              s = "WARN"
        if (tf >= ms && ur < al)                    s = "ALERT"
        else if (tf >= ms && s == "OK" && ur < wa)  s = "WARN"
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

    # 高速化: context fileを1回のawk passでsynced_num+unsorted_count+unsorted_idsを取得
    _synced_num=0
    _unsorted=0
    _unsorted_ids=""
    if [ -f "$_context_path" ]; then
        _ctx_data=$(awk '
            /<!-- last_synced_lesson: L[0-9]+ -->/ {
                match($0, /L([0-9]+)/, arr); synced = arr[1]+0
            }
            /^## 教訓索引（自動追記）/ { in_sec=1; next }
            in_sec && /^## / { in_sec=0 }
            in_sec && /^- L/ {
                c++
                if (match($0, /L[0-9]+/)) {
                    ids = ids (ids ? "," : "") substr($0, RSTART, RLENGTH)
                }
            }
            END { printf "%d|%d|%s\n", synced+0, c+0, ids }
        ' "$_context_path")
        _synced_num="${_ctx_data%%|*}"
        _rest="${_ctx_data#*|}"
        _unsorted="${_rest%%|*}"
        _unsorted_ids="${_rest#*|}"
    fi

    # ─── 1回のawk passで全統計を取得 ───
    _stats_output=$(_compute_lesson_stats "$_lessons_file" "$_synced_num" "$_checkpoint" \
        "$INJECTION_WARN_THRESHOLD" "$_pid")

    _stats_line="${_stats_output%%$'\n'*}"
    IFS='|' read -r _total_lessons _max_id _deprecated_count _unsynced _new_count _when_count _how_count _origin_count <<< "$_stats_line"
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

    if ! check_ssot_conflict_markers "$_pid" "$_lessons_file"; then
        EXIT_CODE=1
    fi

    [ "${_deprecated_count:-0}" -gt 0 ] && echo "INFO: ${_pid} deprecated除外: ${_deprecated_count}件"

    _when_missing=$((_total_lessons - ${_when_count:-0}))
    _how_missing=$((_total_lessons - ${_how_count:-0}))
    # 高速化: awk 3回→1回で when/how/origin rate を一括計算
    IFS='|' read -r _when_rate _how_rate _origin_rate <<< "$(awk \
        -v wk="${_when_count:-0}" -v hk="${_how_count:-0}" -v ok="${_origin_count:-0}" \
        -v total="${_total_lessons:-0}" \
        'BEGIN{printf "%.1f|%.1f|%.1f\n", \
            total?wk/total*100:100.0, \
            total?hk/total*100:100.0, \
            total?ok/total*100:100.0}')"
    echo "INFO: ${_pid} when/how充足率: when=${_when_count:-0}/${_total_lessons}(${_when_rate}%) how=${_how_count:-0}/${_total_lessons}(${_how_rate}%)"
    if [ "$_when_missing" -gt 0 ] || [ "$_how_missing" -gt 0 ]; then
        emit_actionable \
            "WARN: ${_pid} when/how欠落教訓あり(when欠落:${_when_missing}, how欠落:${_how_missing}, total:${_total_lessons})" \
            "lesson_write.sh の新テンプレートに沿って既存教訓へ when/how を補完せよ。"
    fi

    _origin_missing=$((_total_lessons - ${_origin_count:-0}))
    echo "INFO: ${_pid} origin充足率: origin=${_origin_count:-0}/${_total_lessons}(${_origin_rate}%)"
    if [ "$_origin_missing" -gt 0 ]; then
        emit_actionable \
            "WARN: ${_pid} origin欠落教訓あり(origin欠落:${_origin_missing}, total:${_total_lessons})" \
            "lesson_write.sh の --origin または source_cmd 由来の [[cmd_XXX]] origin を既存教訓へ補完せよ。"
    fi

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
            "ALERT: ${_pid}の未振り分け教訓${_unsorted}件 → /lesson-sort推奨 (ids: ${_unsorted_ids:-unknown})" \
            "/lesson-sort を実行し、未振り分け教訓を適切なcontextセクションへ移動せよ。"
        EXIT_CODE=1
    elif [ "${_unsorted:-0}" -ge "$UNSORTED_WARN_THRESHOLD" ]; then
        # Level5早期導線(GA-166 L934 / GA-182 / GA-183 L971): ALERT閾値到達前に
        # project+ids+推奨アクションを事前提示し、将軍/lesson-sortの早期着手を促す。
        emit_actionable \
            "WARN: ${_pid}の未振り分け教訓${_unsorted}件(早期導線, ALERT閾値${UNSORTED_THRESHOLD}未満, ids: ${_unsorted_ids:-unknown})" \
            "ALERT閾値(${UNSORTED_THRESHOLD}件)に達する前に /lesson-sort を実行し、${_pid}の未振り分け教訓の蓄積を防げ。"
    elif [ "${_unsorted:-0}" -gt 0 ]; then
        echo "OK: ${_pid}の未振り分け教訓${_unsorted}件(閾値${UNSORTED_THRESHOLD}以下, ids: ${_unsorted_ids:-unknown})"
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

# ─── enforcement phantom検出 (deepdive 2026-05-16: 自己申告vs他覚的検証) ───
# §3.3: bash while+grep per entryをawk一括処理に統合(cmd_3632)
_phantom_count=0
_find_scripts=$(find "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/.claude/hooks" -name "*.sh" -printf '%f\n' 2>/dev/null || true)

_phantom_output=""
_phantom_files=()
for _lf in "$SCRIPT_DIR"/projects/infra/lessons_gunshi.yaml "$SCRIPT_DIR"/projects/infra/lessons_karo.yaml; do
    [ -f "$_lf" ] && _phantom_files+=("$_lf")
done
if [ ${#_phantom_files[@]} -gt 0 ]; then
    _phantom_output=$(awk -v scripts="$_find_scripts" '
        BEGIN {
            n = split(scripts, arr, "\n")
            for (i = 1; i <= n; i++) if (arr[i] != "") exists[arr[i]] = 1
        }
        /^- id:/ { id = $3; automated = 0; next }
        /^  automated:[[:space:]]*true/ { automated = 1; next }
        /^  enforcement:[[:space:]]*/ {
            if (!automated) next
            enf = $0; sub(/^  enforcement:[[:space:]]*/, "", enf)
            missing = ""
            while (match(enf, /[A-Za-z0-9_-]+\.sh/)) {
                s = substr(enf, RSTART, RLENGTH)
                if (!(s in exists)) missing = missing (missing ? " " : "") s
                enf = substr(enf, RSTART + RLENGTH)
            }
            if (missing != "") print "WARN: PHANTOM教訓 " id " — enforcement参照スクリプト不在: " missing
        }
    ' "${_phantom_files[@]}" 2>/dev/null) || true
fi
if [ -n "$_phantom_output" ]; then
    echo "$_phantom_output"
    _phantom_count=$(printf '%s\n' "$_phantom_output" | wc -l)
fi
if [ "$_phantom_count" -gt 0 ]; then
    echo "WARN: PHANTOM教訓${_phantom_count}件。enforcement参照スクリプトが存在しない。enforcementフィールドを更新せよ"
    EXIT_CODE=1
else
    echo "OK: enforcement phantom検出: 0件"
fi

# ─── role別lesson origin因果リンク検出 ───
check_role_lesson_origins_batch

# ─── check_lesson_effectiveness ───
if [ $# -ge 1 ]; then
    check_lesson_effectiveness "$1"
else
    check_lesson_effectiveness
fi

exit $EXIT_CODE
