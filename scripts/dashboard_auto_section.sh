#!/usr/bin/env bash
# ============================================================
# dashboard_auto_section.sh
# ダッシュボードの機械的セクション(リアルタイム状況)を自動生成
#
# Usage: bash scripts/dashboard_auto_section.sh [--dry-run]
#   --dry-run: 標準出力に出力(dashboard.md未変更)
#
# Input:
#   queue/karo_snapshot.txt  → 忍者配備状況
#   queue/shogun_to_karo.yaml → パイプライン(active cmd一覧)
#   logs/gate_metrics.log    → 連勝数・CLEAR率・総cmd数
#   queue/tasks/*.yaml       → 各忍者の現タスク詳細
#   config/settings.yaml     → モデル名
#
# Output:
#   dashboard.md の DASHBOARD_AUTO_START ～ DASHBOARD_AUTO_END 間を上書き
#   マーカー外(家老記入セクション)は一切変更しない
#
# Exit:
#   0: 成功
#   1: 失敗
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ─── Paths ───
DASHBOARD="$PROJECT_DIR/dashboard.md"
SNAPSHOT="$PROJECT_DIR/queue/karo_snapshot.txt"
STK="$PROJECT_DIR/queue/shogun_to_karo.yaml"
GATE_LOG="$PROJECT_DIR/logs/gate_metrics.log"
TASKS_DIR="$PROJECT_DIR/queue/tasks"
SETTINGS="$PROJECT_DIR/config/settings.yaml"
ARCHIVE_CMD_DIR="$PROJECT_DIR/queue/archive/cmds"
LESSON_EFFECT_STATUS_FILE="$PROJECT_DIR/queue/lesson_effectiveness_status.txt"
GATE_FIRE_LOG="$PROJECT_DIR/logs/gate_fire_log.yaml"

# ─── 初回CLEAR率 (gate_fire_logから計算。累積CLEAR率の隣に表示) ───
compute_first_fire_rate() {
    [[ ! -f "$GATE_FIRE_LOG" ]] && { echo "—"; return; }
    # /tmp/を除外し、実報告のPASS/FAILを集計
    local pass_count fail_count
    pass_count=$(grep -v '/tmp/' "$GATE_FIRE_LOG" | grep -c 'result: PASS' 2>/dev/null || echo 0)
    fail_count=$(grep -v '/tmp/' "$GATE_FIRE_LOG" | grep -c 'result: FAIL' 2>/dev/null || echo 0)
    local total=$((pass_count + fail_count))
    if [[ $total -eq 0 ]]; then
        echo "—"
    else
        awk "BEGIN { printf \"%.1f%%\", ($pass_count / $total) * 100 }"
    fi
}
FIRST_FIRE_RATE=$(compute_first_fire_rate)
KM_JSON_CACHE="/tmp/dashboard_km_json_cache.txt"
KM_MODEL_CACHE="/tmp/dashboard_km_model_cache.txt"
KM_CACHE_LINES="/tmp/dashboard_km_cache_lines.txt"

MARKER_START="<!-- DASHBOARD_AUTO_START -->"
MARKER_END="<!-- DASHBOARD_AUTO_END -->"

TMPFILE=$(mktemp)
TMP_METRICS=$(mktemp)
TMP_PIPELINE=$(mktemp)
TMP_RESULTS=$(mktemp)
TMP_TITLES=$(mktemp)
TMP_RECENT=$(mktemp)
trap 'rm -f "$TMPFILE" "$TMP_METRICS" "$TMP_PIPELINE" "$TMP_RESULTS" "$TMP_TITLES" "$TMP_RECENT"' EXIT

NOW=$(TZ=Asia/Tokyo date '+%H:%M')

# shellcheck source=/dev/null
source "$(dirname "$SCRIPT_DIR")/scripts/lib/agent_config.sh"
ALL_NINJAS=$(get_ninja_names)

# ─── Helper: Japanese name (settings.yamlから動的取得) ───
name_jp() {
    get_japanese_name "$1"
}

# ─── Helper: Extract parent_cmd from task YAML ───
get_task_parent_cmd() {
    local tf="$1"
    [[ ! -f "$tf" ]] && return
    grep -E '^\s*parent_cmd:' "$tf" | head -1 | sed 's/.*parent_cmd:[[:space:]]*//' | sed "s/['\"]//g" | tr -d '[:space:]'
}

# ─── GP-081: Pre-compute all ninja models (cmd_1392: python3→gawk) ───
declare -A _MODEL_CACHE=()
_profiles_yaml="$PROJECT_DIR/config/cli_profiles.yaml"
if [[ -f "$SETTINGS" && -f "$_profiles_yaml" ]]; then
    _model_tmp=$(mktemp)
    # shellcheck disable=SC2086
    # GP-081 + cmd_1392: Python→gawk化 (YAML flat parse)
    gawk -v all_ninjas="$ALL_NINJAS" '
BEGIN {
    n = split(all_ninjas, ninja_list, " ")
    for (i = 1; i <= n; i++) ninja_set[ninja_list[i]] = 1
    default_cli = "claude"; effort = ""; cur = ""; cur_profile = ""
    file_num = 0
}
FNR == 1 { file_num++; cur = ""; cur_profile = "" }
file_num == 1 {
    if (/^effort:/) {
        v = $0; sub(/.*effort:[ \t]*/, "", v); sub(/#.*/, "", v)
        gsub(/["\047\t \r]/, "", v); effort = v; next
    }
    if (/^  default:/) {
        v = $0; sub(/.*default:[ \t]*/, "", v); sub(/#.*/, "", v)
        gsub(/["\047\t \r]/, "", v); if (v != "") default_cli = v; next
    }
    if (/^    [a-z][a-z_0-9]*:[ \t]*$/) {
        cur = $0; sub(/^[ \t]+/, "", cur); sub(/:.*/, "", cur)
        if (!(cur in ninja_set)) cur = ""; next
    }
    if (cur != "" && /^      type:/) {
        v = $0; sub(/.*type:[ \t]*/, "", v); sub(/#.*/, "", v)
        gsub(/["\047\t \r]/, "", v); if (v != "") type_of[cur] = v; next
    }
    if (cur != "" && /^      model_name:/) {
        v = $0; sub(/.*model_name:[ \t]*/, "", v); sub(/#.*/, "", v)
        gsub(/["\047\t \r]/, "", v); if (v != "") model_of[cur] = v; next
    }
    if (cur != "" && !/^      / && !/^[ \t]*$/) cur = ""
}
file_num == 2 {
    if (/^  [a-z][a-z_0-9]*:[ \t]*$/) {
        cur_profile = $0; sub(/^[ \t]+/, "", cur_profile); sub(/:.*/, "", cur_profile); next
    }
    if (cur_profile != "" && /display_name:/) {
        v = $0; sub(/.*display_name:[ \t]*/, "", v)
        gsub(/["\047]/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (v != "") dn[cur_profile] = v; next
    }
}
END {
    for (i = 1; i <= n; i++) {
        name = ninja_list[i]; model = ""; has_explicit = 0
        if (name in model_of && model_of[name] != "") { model = model_of[name]; has_explicit = 1 }
        if (!has_explicit) { t = (name in type_of) ? type_of[name] : default_cli; model = (t in dn) ? dn[t] : t }
        result = model
        if (has_explicit && effort != "") {
            m_cnt = split(model, mparts, " "); found = 0
            for (j = 1; j <= m_cnt; j++) if (mparts[j] == effort) found = 1
            if (!found) result = model " " effort
        }
        if (result == "") result = "unknown"
        print name "|" result
    }
}' "$SETTINGS" "$_profiles_yaml" > "$_model_tmp"
    while IFS='|' read -r _mn _mv; do
        _MODEL_CACHE["$_mn"]="$_mv"
    done < "$_model_tmp"
    rm -f "$_model_tmp"
fi
get_model() {
    echo "${_MODEL_CACHE[$1]:-unknown}"
}

# ─── Build cmd→ninjas mapping (from task YAMLs) ───
declare -A CMD_NINJAS=()
for n in $ALL_NINJAS; do
    tf="$TASKS_DIR/${n}.yaml"
    [[ ! -f "$tf" ]] && continue
    pcmd=$(get_task_parent_cmd "$tf" || true)
    [[ -z "$pcmd" ]] && continue
    jp=$(name_jp "$n")
    if [[ -n "${CMD_NINJAS[$pcmd]:-}" ]]; then
        CMD_NINJAS[$pcmd]="${CMD_NINJAS[$pcmd]},${jp}"
    else
        CMD_NINJAS[$pcmd]="$jp"
    fi
done

# ─── Get idle list from snapshot ───
IDLE_LIST=""
[[ -f "$SNAPSHOT" ]] && IDLE_LIST=$(grep '^idle|' "$SNAPSHOT" | head -1 | cut -d'|' -f2 || true)

# ─── Calculate active ninjas from snapshot ───
ACTIVE_COUNT=0
ACTIVE_NAMES=""
for _an in $ALL_NINJAS; do
    if ! echo ",$IDLE_LIST," | grep -q ",${_an}," 2>/dev/null; then
        ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
        _jp_an=$(name_jp "$_an")
        if [[ -n "$ACTIVE_NAMES" ]]; then
            ACTIVE_NAMES="${ACTIVE_NAMES}, ${_jp_an}"
        else
            ACTIVE_NAMES="$_jp_an"
        fi
    fi
done
[[ -z "$ACTIVE_NAMES" ]] && ACTIVE_NAMES="—"

# ─── Parse pipeline commands from STK (pre-compute for subshell access) ───
if [[ -f "$STK" ]] && grep -qE '^  -[[:space:]]*id:' "$STK" 2>/dev/null; then
    # Output tab-delimited: id\ttitle\tstatus
    # Match command-level "- id:" (no indent), not nested AC entries (2-space indent)
    awk '
        /^-[[:space:]]+id:/ {
            if (cid != "") printf "%s\t%s\t%s\n", cid, tit, sta
            sub(/.*id:[[:space:]]*/, "")
            gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
            cid=$0; tit=""; sta=""
        }
        /^  title:/ && cid!="" {
            sub(/.*title:[[:space:]]*/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if (length($0)>50) $0=substr($0,1,47)"..."
            tit=$0
        }
        /^  status:/ && cid!="" {
            sub(/.*status:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, "")
            sta=$0
        }
        END { if (cid!="") printf "%s\t%s\t%s\n", cid, tit, sta }
    ' "$STK" > "$TMP_PIPELINE"
fi

# ─── Calculate gate metrics ───
STREAK=0
STREAK_START=""
STREAK_END=""
TOTAL_CMDS=0

if [[ -f "$GATE_LOG" ]]; then
    # Cmd-latest dedup (exclude test cmds), sorted by timestamp
    awk -F'\t' '
        NF>=3 && $2 !~ /^cmd_test/ {
            cmd=$2; ts[cmd]=$1; st[cmd]=$3
        }
        END {
            for (c in st) printf "%s\t%s\t%s\n", ts[c], c, st[c]
        }
    ' "$GATE_LOG" | sort -t$'\t' -k1,1 > "$TMP_METRICS"

    TOTAL_CMDS=$(wc -l < "$TMP_METRICS" | tr -d ' ')
    CLEAR_COUNT=$(awk -F'\t' '$3=="CLEAR"{c++} END{print c+0}' "$TMP_METRICS")

    if [[ "$TOTAL_CMDS" -gt 0 ]]; then
        : # CLEAR_COUNT/TOTAL_CMDS used directly in output
    fi

    # Streak: consecutive CLEARs from the end (L074: avoid ((var++)))
    STREAK=0
    STREAK_START=""
    STREAK_END=""
    while IFS=$'\t' read -r _ts _cmd result; do
        if [[ "$result" == "CLEAR" ]]; then
            if [[ $STREAK -eq 0 ]]; then
                STREAK_START="$_cmd"
            fi
            STREAK=$((STREAK + 1))
            STREAK_END="$_cmd"
        else
            STREAK=0
            STREAK_START=""
            STREAK_END=""
        fi
    done < "$TMP_METRICS"

    # Last GATE time (informational only, not rendered in dashboard)
fi

# Build CLEAR'd cmd set for pipeline filtering (must be outside subshell blocks)
declare -A CLEARED_CMDS=()
if [[ -s "$TMP_METRICS" ]]; then
    while IFS=$'\t' read -r _ts _cmd _result; do
        [[ "$_result" == "CLEAR" ]] && CLEARED_CMDS[$_cmd]=1
    done < "$TMP_METRICS"
fi

# ─── Knowledge metrics (cached — only re-run when gate_metrics.log changes) ───
KM_INJECT_RATE="—"
KM_LESSON_EFFECT="—"
KM_LESSON_THRESHOLD="—"
KM_PROBLEM_LESSONS="—"
KM_PROJECT_ROWS=""
KM_KNOWLEDGE_MODEL_ROWS=""
KM_TOP_LESSON_ROWS=""
KM_BOTTOM_LESSON_ROWS=""
KM_TASK_TYPE_ROWS=""
MODEL_SCOREBOARD_ROWS=""
# GP-082: Unified gawk archive scan (titles + project/status/date in one pass)
# GP-083: archiveファイル数キャッシュ（不変ファイルの再スキャン防止）
_TMP_CTX_WARN=$(mktemp)
_CFC_CACHE=$(mktemp)
_ARCH_TITLES_CACHE="/tmp/dashboard_arch_titles_cache.txt"
_ARCH_CFC_CACHE="/tmp/dashboard_arch_cfc_cache.txt"
_ARCH_COUNT_CACHE="/tmp/dashboard_arch_count_cache.txt"
trap 'rm -f "$TMPFILE" "$TMP_METRICS" "$TMP_PIPELINE" "$TMP_RESULTS" "$TMP_TITLES" "$TMP_RECENT" "$_TMP_CTX_WARN" "$_CFC_CACHE" "${_TMP_CI_STATUS:-}"' EXIT
if [[ -d "$ARCHIVE_CMD_DIR" ]]; then
    shopt -s nullglob
    _arch_files=("$ARCHIVE_CMD_DIR"/cmd_*.yaml)
    shopt -u nullglob
    _arch_count=${#_arch_files[@]}
    _cached_arch_count=$(cat "$_ARCH_COUNT_CACHE" 2>/dev/null || echo "0")
    if (( _arch_count > 0 )); then
        if [[ "$_arch_count" == "$_cached_arch_count" ]] && [[ -f "$_ARCH_TITLES_CACHE" ]] && [[ -f "$_ARCH_CFC_CACHE" ]]; then
            # キャッシュヒット: アーカイブファイル数未変更
            cat "$_ARCH_TITLES_CACHE" >> "$TMP_TITLES"
            cat "$_ARCH_CFC_CACHE" > "$_CFC_CACHE"
        else
            # キャッシュミス: フルスキャン+キャッシュ更新
            gawk -v titles_out="$TMP_TITLES" -v cfc_out="$_CFC_CACHE" '
                BEGINFILE {
                    fname = FILENAME; sub(/.*\//, "", fname)
                    cid = ""; tit = ""; proj = ""; st = ""; dt = ""
                }
                /^ *- id: cmd_/ {
                    sub(/.*- id: */, ""); gsub(/["\047[:space:]]/, "")
                    cid = $0
                }
                /^    title:/ && cid != "" {
                    sub(/.*title: */, "")
                    gsub(/^["\047]|["\047]$/, "")
                    if (length($0) > 50) $0 = substr($0, 1, 47) "..."
                    tit = $0
                }
                /project:/ {
                    v = $0; sub(/.*project: */, "", v); gsub(/["\047\t ]/, "", v)
                    if (v != "" && proj == "") proj = v
                }
                /status:/ {
                    v = $0; sub(/.*status: */, "", v); gsub(/["\047\t ]/, "", v)
                    if (v != "") st = v
                }
                dt == "" && /_(at|date):/ {
                    if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}/))
                        dt = substr($0, RSTART, RLENGTH)
                }
                ENDFILE {
                    if (cid != "" && tit != "") print cid "\t" tit > titles_out
                    if (proj != "") print fname "|" proj "|" st "|" dt > cfc_out
                }
            ' "${_arch_files[@]}" 2>/dev/null
            # キャッシュ保存
            cp "$TMP_TITLES" "$_ARCH_TITLES_CACHE" 2>/dev/null || true
            cp "$_CFC_CACHE" "$_ARCH_CFC_CACHE" 2>/dev/null || true
            echo "$_arch_count" > "$_ARCH_COUNT_CACHE"
        fi
    fi
fi
# Launch context_freshness_check with pre-computed cache (zero archive I/O)
CFC_ARCHIVE_CACHE="$_CFC_CACHE" bash "$SCRIPT_DIR/context_freshness_check.sh" --dashboard-warnings > "$_TMP_CTX_WARN" 2>/dev/null &
_PID_CTX=$!
# GP-083: ci_status_check.sh parallel launch (2.3s network call)
_TMP_CI_STATUS=$(mktemp)
bash "$SCRIPT_DIR/ci_status_check.sh" --status > "$_TMP_CI_STATUS" 2>/dev/null &
_PID_CI=$!

_gate_signature="missing"
if [[ -f "$GATE_LOG" ]]; then
    _gate_signature=$(cksum "$GATE_LOG" | awk '{print $1 ":" $2}')
fi
_cached_signature=""
[[ -f "$KM_CACHE_LINES" ]] && _cached_signature=$(tr -d '[:space:]' < "$KM_CACHE_LINES" 2>/dev/null)

if [[ "$_gate_signature" != "$_cached_signature" ]] || [[ ! -f "$KM_JSON_CACHE" ]] || ! grep -q '^model_row=' "$KM_MODEL_CACHE" 2>/dev/null; then
    bash "$SCRIPT_DIR/knowledge_metrics.sh" --json --by-project --by-model > "$KM_JSON_CACHE" 2>/dev/null &
    _PID_KM=$!
    bash "$SCRIPT_DIR/model_analysis.sh" --summary > "$KM_MODEL_CACHE" 2>/dev/null &
    _PID_MA=$!
    wait "$_PID_KM" 2>/dev/null || true
    wait "$_PID_MA" 2>/dev/null || true
    echo "$_gate_signature" > "$KM_CACHE_LINES"
fi

wait "$_PID_CTX" 2>/dev/null || true
CONTEXT_WARNINGS="$(cat "$_TMP_CTX_WARN" 2>/dev/null || true)"

# Parse JSON cache (inject_rate, ref_rate, normalized_delta.delta_pp + knowledge breakdown rows)
if [[ -f "$KM_JSON_CACHE" ]] && [[ -s "$KM_JSON_CACHE" ]]; then
    # cmd_1392: Python→jq化 (JSON parse)
    _km_parsed=$(jq -r '
def fmt1: . * 10 | round | . / 10 | tostring | if test("[.]") then . else . + ".0" end;
def fmt_pct: if . == null then "—" elif type == "number" then "\(fmt1)%" else "—" end;
def safe_text: if . == null then "—" else tostring | gsub("\\|"; "/") | gsub("\n"; " ") | gsub("^\\s+|\\s+$"; "") | if . == "" then "—" else . end end;
def fmt_delta: if . == null then "—" elif type == "number" then (if . >= 0 then "+\(fmt1)pp" else "\(fmt1)pp" end) else "—" end;
"summary=\(.inject_rate | fmt_pct)\t\(.ref_rate | fmt_pct)\t\(.normalized_delta.delta_pp | fmt_delta)\t\(.lesson_effectiveness | fmt_pct)\t\(.problem_lessons // 0)",
(.by_project // [] | .[] | "project_row=| \(.project | safe_text) | \(.inject_rate | fmt_pct) | \(.effectiveness_rate | fmt_pct) | \(.n // "—") |"),
(.by_model // [] | .[] | "knowledge_model_row=| \((.display_name // .model // "unknown") | safe_text) | \(.ref_rate | fmt_pct) | \(.effectiveness_rate | fmt_pct) | \(.n // "—") |"),
(.top_helpful // [] | .[] | "top_lesson_row=| \(.id | safe_text) | \(.project | safe_text) | \(.reference_count // 0) | \(.injection_count // 0) | \(.effectiveness_rate | fmt_pct) |"),
(.bottom_lessons // [] | .[] | "bottom_lesson_row=| \(.id | safe_text) | \(.project | safe_text) | \(.reference_count // 0) | \(.injection_count // 0) | \(.effectiveness_rate | fmt_pct) |")
' < "$KM_JSON_CACHE" 2>/dev/null || echo "summary=—	—	—	—	0")
    while IFS= read -r _line; do
        case "$_line" in
            summary=*)
                _payload=${_line#summary=}
                IFS=$'\t' read -r KM_INJECT_RATE _km_ref_rate _km_delta_pp KM_LESSON_EFFECT KM_PROBLEM_LESSONS <<< "$_payload"
                ;;
            project_row=*)
                KM_PROJECT_ROWS="${KM_PROJECT_ROWS}${_line#project_row=}"$'\n'
                ;;
            knowledge_model_row=*)
                KM_KNOWLEDGE_MODEL_ROWS="${KM_KNOWLEDGE_MODEL_ROWS}${_line#knowledge_model_row=}"$'\n'
                ;;
            top_lesson_row=*)
                KM_TOP_LESSON_ROWS="${KM_TOP_LESSON_ROWS}${_line#top_lesson_row=}"$'\n'
                ;;
            bottom_lesson_row=*)
                KM_BOTTOM_LESSON_ROWS="${KM_BOTTOM_LESSON_ROWS}${_line#bottom_lesson_row=}"$'\n'
                ;;
        esac
    done <<< "$_km_parsed"
fi

# Parse model cache (model_analysis.sh --summary: model_row=<slug>\t<label>\t<clear>\t<impl>\t<trend>\t<n>)
if [[ -f "$KM_MODEL_CACHE" ]] && [[ -s "$KM_MODEL_CACHE" ]]; then
    while IFS= read -r _line; do
        [[ "$_line" == model_row=* ]] || continue
        _payload=${_line#model_row=}
        IFS=$'\t' read -r _slug _label _clear _impl _trend _n <<< "$_payload"
        [[ -z "$_label" ]] && continue
        _label=${_label//_/ }

        _clear_display="—"
        [[ -n "$_clear" && "$_clear" != "—" ]] && _clear_display="${_clear}%"

        _impl_display="—"
        [[ -n "$_impl" && "$_impl" != "—" ]] && _impl_display="${_impl}%"

        _trend_display="→"
        case "$_trend" in
            up) _trend_display="↑" ;;
            down) _trend_display="↓" ;;
        esac

        MODEL_SCOREBOARD_ROWS="${MODEL_SCOREBOARD_ROWS}| ${_label} | ${_clear_display} | ${_impl_display} | ${_trend_display} | ${_n:-—} |
"
    done < "$KM_MODEL_CACHE"
fi

# Parse lesson effectiveness threshold snapshot (from gate_lesson_health.sh)
if [[ -f "$LESSON_EFFECT_STATUS_FILE" ]] && [[ -s "$LESSON_EFFECT_STATUS_FILE" ]]; then
    _threshold_status=$(awk -F= '/^status=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_rate=$(awk -F= '/^rate=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_window=$(awk -F= '/^window_cmds=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_ref=$(awk -F= '/^referenced=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    _threshold_inj=$(awk -F= '/^injected=/{print $2; exit}' "$LESSON_EFFECT_STATUS_FILE" 2>/dev/null || true)
    if [[ -n "$_threshold_status" ]]; then
        case "$_threshold_status" in
            ALERT|WARN|OK)
                KM_LESSON_THRESHOLD="${_threshold_status} (${_threshold_rate}%, ${_threshold_ref}/${_threshold_inj}, ${_threshold_window}cmd)"
                ;;
            NODATA)
                KM_LESSON_THRESHOLD="NODATA"
                ;;
            *)
                KM_LESSON_THRESHOLD="${_threshold_status}"
                ;;
        esac
    fi
fi

# ─── Task type injection breakdown (from lesson_impact.tsv) ───
LESSON_IMPACT_FILE="$PROJECT_DIR/logs/lesson_impact.tsv"
if [[ -f "$LESSON_IMPACT_FILE" ]] && [[ -s "$LESSON_IMPACT_FILE" ]]; then
    KM_TASK_TYPE_ROWS=$(awk -F'\t' '
        NR > 1 && $5 != "" && $9 != "" && ($5 == "injected" || $5 == "skipped") {
            if ($5 == "injected") inj[$9]++
            if ($5 == "skipped") skip[$9]++
        }
        END {
            for (t in inj) { if (!(t in skip)) skip[t] = 0 }
            for (t in skip) { if (!(t in inj)) inj[t] = 0 }
            for (t in inj) {
                n = inj[t] + skip[t]
                if (n > 0) rate = sprintf("%.0f%%", inj[t] / n * 100)
                else rate = "—"
                printf "| %s | %d | %d | %s | %d |\n", t, inj[t], skip[t], rate, n
            }
        }
    ' "$LESSON_IMPACT_FILE" | sort -t'|' -k6 -rn)
fi

# ─── Recent 30 cmd metrics (from lesson_impact.tsv) ───
declare -A RECENT_PJ_IR=() RECENT_PJ_ER=() RECENT_PJ_WARN=()
declare -A RECENT_TT_INJ=() RECENT_TT_SKIP=() RECENT_TT_RATE=() RECENT_TT_WARN=()
declare -A RECENT_MDL_RR=() RECENT_MDL_ER=() RECENT_MDL_WARN=()

if [[ -f "$LESSON_IMPACT_FILE" ]] && [[ -s "$LESSON_IMPACT_FILE" ]]; then
    # cmd_1392: Python→gawk化 (TSV集計: Recent 30 cmd metrics)
    gawk -v gate_path="$GATE_LOG" '
BEGIN { FS="\t"; OFS="\t" }
FILENAME == gate_path { if (NF >= 6) cmd_model[$2] = $6; next }
FNR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
{
    if (NF < 9) next
    result = toupper($col["result"]); gsub(/^[ \t]+|[ \t]+$/, "", result)
    if (result == "PENDING") next
    action = $col["action"]; gsub(/^[ \t]+|[ \t]+$/, "", action)
    if (action != "injected" && action != "skipped") next
    row_n++
    row_cmd[row_n] = $col["cmd_id"]; row_action[row_n] = action
    row_project[row_n] = $col["project"]; row_tasktype[row_n] = $col["task_type"]
    row_referenced[row_n] = $col["referenced"]
}
END {
    rc = 0
    for (i = row_n; i >= 1 && rc < 30; i--) {
        cid = row_cmd[i]
        if (!(cid in recent_seen)) { recent_seen[cid] = 1; rc++ }
    }
    for (i = 1; i <= row_n; i++) {
        p = row_project[i]; gsub(/^[ \t]+|[ \t]+$/, "", p); if (p == "") p = "unknown"
        t = row_tasktype[i]; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t == "") t = "unknown"
        cid = row_cmd[i]; ref = row_referenced[i]; gsub(/^[ \t]+|[ \t]+$/, "", ref)
        is_recent = (cid in recent_seen) ? 1 : 0
        mdl = (cid in cmd_model) ? cmd_model[cid] : "unknown"
        mn = split(mdl, mdl_arr, ",")
        for (mi = 1; mi <= mn; mi++) {
            m = mdl_arr[mi]; gsub(/^[ \t]+|[ \t]+$/, "", m); if (m == "") continue
            low = tolower(m); gsub(/[-_]/, " ", low); fam = "unknown"
            if (index(low, "opus") && (index(low, "4.6") || index(low, "4 6"))) fam = "opus_4_6"
            else if (index(low, "gpt") && (index(low, "5.4") || index(low, "5 4"))) fam = "gpt_5_4"
            else if (index(low, "codex") && (index(low, "5.4") || index(low, "5 4"))) fam = "gpt_5_4"
            else { fam = low; gsub(/[^a-z0-9]+/, "_", fam); gsub(/^_|_$/, "", fam); if (fam == "") fam = "unknown" }
            if (row_action[i] == "injected") {
                o_mdl_inj[fam]++; o_mdl_total[fam]++
                if (ref == "yes") o_mdl_ref[fam]++
                if (is_recent) { r_mdl_inj[fam]++; r_mdl_total[fam]++; if (ref == "yes") r_mdl_ref[fam]++ }
            } else {
                o_mdl_total[fam]++; if (is_recent) r_mdl_total[fam]++
            }
            if (o_mdl_total[fam] > o_mdl_maxn[fam]+0) { o_mdl_maxn[fam] = o_mdl_total[fam]; o_mdl_label[fam] = m }
            if (is_recent && r_mdl_total[fam] > r_mdl_maxn[fam]+0) { r_mdl_maxn[fam] = r_mdl_total[fam]; r_mdl_label[fam] = m }
            if (fam != "unknown") all_fam[fam] = 1
        }
        if (row_action[i] == "injected") {
            o_pj_inj[p]++; if (ref == "yes") o_pj_ref[p]++; o_tt_inj[t]++
            if (is_recent) { r_pj_inj[p]++; if (ref == "yes") r_pj_ref[p]++; r_tt_inj[t]++ }
        } else {
            o_pj_skip[p]++; o_tt_skip[t]++
            if (is_recent) { r_pj_skip[p]++; r_tt_skip[t]++ }
        }
        all_pj[p] = 1; all_tt[t] = 1
    }
    n_pj = asorti(all_pj, sorted_pj)
    for (i = 1; i <= n_pj; i++) {
        p = sorted_pj[i]
        oi = o_pj_inj[p]+0; os = o_pj_skip[p]+0; or_ = o_pj_ref[p]+0
        ri = r_pj_inj[p]+0; rs = r_pj_skip[p]+0; rr = r_pj_ref[p]+0
        o_ir = (oi+os > 0) ? oi/(oi+os)*100 : -1; o_er = (oi > 0) ? or_/oi*100 : -1
        r_ir = (ri+rs > 0) ? ri/(ri+rs)*100 : -1; r_er = (ri > 0) ? rr/ri*100 : -1
        w = "N"
        if (o_ir >= 0 && r_ir >= 0 && (o_ir-r_ir > 10 || r_ir-o_ir > 10)) w = "Y"
        if (o_er >= 0 && r_er >= 0 && (o_er-r_er > 10 || r_er-o_er > 10)) w = "Y"
        r_ir_s = (r_ir >= 0) ? sprintf("%.1f%%", r_ir) : "\xe2\x80\x94"
        r_er_s = (r_er >= 0) ? sprintf("%.1f%%", r_er) : "\xe2\x80\x94"
        printf "PJ\t%s\t%s\t%s\t%d\t%s\n", p, r_ir_s, r_er_s, ri+rs, w
    }
    n_tt = asorti(all_tt, sorted_tt)
    for (i = 1; i <= n_tt; i++) {
        t = sorted_tt[i]
        oi = o_tt_inj[t]+0; os = o_tt_skip[t]+0; ri = r_tt_inj[t]+0; rs = r_tt_skip[t]+0
        o_rate = (oi+os > 0) ? oi/(oi+os)*100 : -1; r_rate = (ri+rs > 0) ? ri/(ri+rs)*100 : -1
        w = "N"
        if (o_rate >= 0 && r_rate >= 0 && (o_rate-r_rate > 10 || r_rate-o_rate > 10)) w = "Y"
        r_rate_s = (r_rate >= 0) ? sprintf("%.1f%%", r_rate) : "\xe2\x80\x94"
        printf "TT\t%s\t%d\t%d\t%s\t%d\t%s\n", t, ri, rs, r_rate_s, ri+rs, w
    }
    n_fam = asorti(all_fam, sorted_fam)
    for (i = 1; i <= n_fam; i++) {
        fam = sorted_fam[i]
        label = r_mdl_label[fam]; if (label == "") label = o_mdl_label[fam]; if (label == "") label = fam
        display = tolower(label); gsub(/_/, " ", display); gsub(/^[ \t]+|[ \t]+$/, "", display)
        o_rr_val = (o_mdl_inj[fam]+0 > 0) ? (o_mdl_ref[fam]+0)/o_mdl_inj[fam]*100 : -1
        r_rr_val = (r_mdl_inj[fam]+0 > 0) ? (r_mdl_ref[fam]+0)/r_mdl_inj[fam]*100 : -1
        w = "N"
        if (o_rr_val >= 0 && r_rr_val >= 0 && (o_rr_val-r_rr_val > 10 || r_rr_val-o_rr_val > 10)) w = "Y"
        r_rr_s = (r_rr_val >= 0) ? sprintf("%.1f%%", r_rr_val) : "\xe2\x80\x94"
        printf "MODEL\t%s\t%s\t%s\t%d\t%s\n", display, r_rr_s, r_rr_s, r_mdl_total[fam]+0, w
    }
}' "$GATE_LOG" "$LESSON_IMPACT_FILE" > "$TMP_RECENT" 2>/dev/null

    while IFS=$'\t' read -r _rtype _rkey _rv1 _rv2 _rv3 _rv4 _rv5; do
        case "$_rtype" in
            PJ)
                RECENT_PJ_IR[$_rkey]="$_rv1"
                RECENT_PJ_ER[$_rkey]="$_rv2"
                # _rv3=N (not displayed), _rv4=warn
                RECENT_PJ_WARN[$_rkey]="$_rv4"
                ;;
            TT)
                RECENT_TT_INJ[$_rkey]="$_rv1"
                RECENT_TT_SKIP[$_rkey]="$_rv2"
                RECENT_TT_RATE[$_rkey]="$_rv3"
                # _rv4=N (not displayed), _rv5=warn
                RECENT_TT_WARN[$_rkey]="$_rv5"
                ;;
            MODEL)
                RECENT_MDL_RR[$_rkey]="$_rv1"
                RECENT_MDL_ER[$_rkey]="$_rv2"
                # _rv3=N (not displayed), _rv4=warn
                RECENT_MDL_WARN[$_rkey]="$_rv4"
                ;;
        esac
    done < "$TMP_RECENT"
fi

# ─── Build cmd→title map (for 戦果 section) ───
# Priority: gate_metrics.log(9列目) > active STK > archive STK done
if [[ -f "$GATE_LOG" ]]; then
    awk -F'\t' '
        NF >= 9 {
            cmd = $2
            title = $9
            gsub(/\r/, "", title)
            gsub(/\t/, " ", title)
            if (title == "") {
                next
            }
            if (length(title) > 50) {
                title = substr(title, 1, 47) "..."
            }
            latest_title[cmd] = title  # 同一cmdは最後の行を採用
        }
        END {
            for (cmd in latest_title) {
                print cmd "\t" latest_title[cmd]
            }
        }
    ' "$GATE_LOG" >> "$TMP_TITLES"
fi
if [[ -s "$TMP_PIPELINE" ]]; then
    awk -F'\t' '{print $1"\t"$2}' "$TMP_PIPELINE" >> "$TMP_TITLES"
fi
# GP-082: archive titles already written to TMP_TITLES by unified gawk pass above

# ─── Get last 5 CLEAR cmds for battle results ───
if [[ -s "$TMP_METRICS" ]]; then
    awk -F'\t' '$3=="CLEAR"' "$TMP_METRICS" | tail -5 > "$TMP_RESULTS"
fi

# ═══════════════════════════════════════════════════════
# Generate auto section content
# ═══════════════════════════════════════════════════════
{
    echo "$MARKER_START"
    echo "## 📊 リアルタイム状況 (${NOW} 自動更新)"
    echo ""

    # ─── 忍者配備 ───
    echo "### 忍者配備"
    echo "| 忍者 | モデル | 状態 | cmd | 内容 |"
    echo "|------|--------|------|-----|------|"

    for ninja in $ALL_NINJAS; do
        jp=$(name_jp "$ninja")
        model=$(get_model "$ninja")

        # Status from idle list
        status="稼働中"
        if echo ",$IDLE_LIST," | grep -q ",${ninja}," 2>/dev/null; then
            status="idle"
        fi

        # Status from snapshot (done override)
        if [[ -f "$SNAPSHOT" ]]; then
            snap_line=$(grep "^ninja|${ninja}|" "$SNAPSHOT" | head -1 || true)
            if [[ -n "$snap_line" ]]; then
                snap_status=$(echo "$snap_line" | cut -d'|' -f4)
                [[ "$snap_status" == "done" || "$snap_status" == "completed" ]] && status="done"
            fi
        fi

        # parent_cmd from task YAML
        cmd="—"
        tf="$TASKS_DIR/${ninja}.yaml"
        if [[ -f "$tf" ]]; then
            _cmd=$(get_task_parent_cmd "$tf" || true)
            [[ -n "$_cmd" ]] && cmd="$_cmd"
        fi

        # cmd title from TMP_TITLES (50 char limit already applied)
        title="—"
        if [[ "$cmd" != "—" ]] && [[ -s "$TMP_TITLES" ]]; then
            _title=$(grep "^${cmd}"$'\t' "$TMP_TITLES" | head -1 | cut -f2 || true)
            [[ -n "$_title" ]] && title="$_title"
        fi

        echo "| ${jp} | ${model} | ${status} | ${cmd} | ${title} |"
    done

    echo ""

    # ─── CI Status (cmd_715) ───
    # GP-083: collect pre-launched background result
    wait "$_PID_CI" 2>/dev/null || true
    _ci_status=$(cat "$_TMP_CI_STATUS" 2>/dev/null || echo "UNKNOWN")
    [[ -z "$_ci_status" ]] && _ci_status="UNKNOWN"
    case "$_ci_status" in
        GREEN)
            echo "### CI Status"
            echo "CI GREEN"
            echo ""
            ;;
        RED:*)
            _ci_run_id=$(echo "$_ci_status" | cut -d: -f2)
            _ci_failed=$(echo "$_ci_status" | cut -d: -f3-)
            echo "### CI Status"
            echo "**CI RED: run ${_ci_run_id} — ${_ci_failed}**"
            echo ""
            ;;
        *)
            echo "### CI Status"
            echo "CI status: check failed"
            echo ""
            ;;
    esac

    # ─── Unpushed Commits WARN (cmd_1267) ───
    _unpushed_count=$(cd "$PROJECT_DIR" && git rev-list origin/main..HEAD --count 2>/dev/null || echo 0)
    if [[ "$_unpushed_count" -ge 10 ]]; then
        echo "**WARN: ${_unpushed_count}件のcommit未push。\`git push\`を検討せよ**"
        echo ""
    fi

    # ─── パイプライン ───
    echo "### パイプライン"

    if [[ ! -s "$TMP_PIPELINE" ]]; then
        echo "パイプライン空 — 次cmd待ち"
    else
        echo "| cmd | タイトル | status | 配備忍者 |"
        echo "|-----|---------|--------|----------|"

        shown=0
        while IFS=$'\t' read -r cid tit sta; do
            # Skip completed commands and already GATE CLEAR'd commands.
            [[ "$sta" == "completed" ]] && continue
            [[ -n "${CLEARED_CMDS[$cid]:-}" ]] && continue
            ninjas="${CMD_NINJAS[$cid]:-—}"
            echo "| ${cid} | ${tit} | ${sta} | ${ninjas} |"
            shown=$((shown + 1))
        done < "$TMP_PIPELINE"

        if [[ $shown -eq 0 ]]; then
            echo "パイプライン空 — 次cmd待ち"
        fi
    fi

    echo ""

    # ─── 戦況メトリクス ───
    echo "### 戦況メトリクス"
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| cmd完了(GATE CLEAR) | ${CLEAR_COUNT:-0}/${TOTAL_CMDS} |"
    echo "| 稼働忍者 | ${ACTIVE_COUNT}/8 (${ACTIVE_NAMES}) |"
    echo "| 初回CLEAR率(gate_fire) | ${FIRST_FIRE_RATE} |"
    if [[ -n "$STREAK_START" ]] && [[ -n "$STREAK_END" ]]; then
        echo "| 連勝(CLEAR streak) | ${STREAK} (${STREAK_START}〜${STREAK_END}) |"
    else
        echo "| 連勝(CLEAR streak) | ${STREAK} |"
    fi

    echo ""

    # ─── モデル別スコアボード ───
    echo "### モデル別スコアボード"
    echo "| モデル | CLEAR率 | impl率 | 傾向 | N |"
    echo "|--------|---------|--------|------|---|"
    if [[ -n "$MODEL_SCOREBOARD_ROWS" ]]; then
        printf "%s" "$MODEL_SCOREBOARD_ROWS"
    else
        echo "| — | — | — | — | — |"
    fi

    echo ""

    # ─── 知識サイクル健全度 ───
    echo "### 知識サイクル健全度"
    echo "| 項目 | 値 |"
    echo "|------|-----|"
    echo "| 教訓注入率 | ${KM_INJECT_RATE} |"
    echo "| 教訓活用率(helpful>0) | ${KM_LESSON_EFFECT} |"
    echo "| 効果率閾値 | ${KM_LESSON_THRESHOLD} |"
    echo "| 問題教訓 | ${KM_PROBLEM_LESSONS}件 |"

    echo ""
    echo "#### PJ別"
    echo "| PJ | 注入率 | 注入CLEAR率 | N | 直近30cmd注入率 | 直近30cmd注入CLEAR率 |"
    echo "|----|--------|--------|---|----------------|----------------|"
    if [[ -n "$KM_PROJECT_ROWS" ]]; then
        while IFS= read -r _row; do
            [[ -z "$_row" ]] && continue
            _pj=$(echo "$_row" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')
            _ri="${RECENT_PJ_IR[$_pj]:-—}"
            _re="${RECENT_PJ_ER[$_pj]:-—}"
            _warn="${RECENT_PJ_WARN[$_pj]:-N}"
            if [[ "$_warn" == "Y" ]]; then
                _row="${_row/| ${_pj} |/| ⚠ ${_pj} |}"
            fi
            echo "${_row% |} | ${_ri} | ${_re} |"
        done <<< "$KM_PROJECT_ROWS"
    else
        echo "| — | — | — | — | — | — |"
    fi

    echo ""
    echo "#### タスク種別別"
    echo "| task_type | 注入 | スキップ | 注入率 | N | 直近30cmd注入 | 直近30cmdスキップ | 直近30cmd注入率 |"
    echo "|-----------|------|---------|--------|---|--------------|------------------|----------------|"
    if [[ -n "$KM_TASK_TYPE_ROWS" ]]; then
        while IFS= read -r _row; do
            [[ -z "$_row" ]] && continue
            _tt=$(echo "$_row" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')
            _tinj="${RECENT_TT_INJ[$_tt]:-0}"
            _tskip="${RECENT_TT_SKIP[$_tt]:-0}"
            _trate="${RECENT_TT_RATE[$_tt]:-—}"
            _twarn="${RECENT_TT_WARN[$_tt]:-N}"
            if [[ "$_twarn" == "Y" ]]; then
                _row="${_row/| ${_tt} |/| ⚠ ${_tt} |}"
            fi
            echo "${_row% |} | ${_tinj} | ${_tskip} | ${_trate} |"
        done <<< "$KM_TASK_TYPE_ROWS"
    else
        echo "| — | — | — | — | — | — | — | — |"
    fi

    echo ""
    echo "#### モデル別"
    echo "| モデル | 参照率 | 効果率 | N | 直近30cmd参照率 | 直近30cmd効果率 |"
    echo "|--------|--------|--------|---|----------------|----------------|"
    if [[ -n "$KM_KNOWLEDGE_MODEL_ROWS" ]]; then
        while IFS= read -r _row; do
            [[ -z "$_row" ]] && continue
            _mdl=$(echo "$_row" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')
            _mdl_key=$(echo "$_mdl" | tr '[:upper:]' '[:lower:]' | tr -s ' ')
            _mrr="${RECENT_MDL_RR[$_mdl_key]:-—}"
            _mer="${RECENT_MDL_ER[$_mdl_key]:-—}"
            _mwarn="${RECENT_MDL_WARN[$_mdl_key]:-N}"
            if [[ "$_mwarn" == "Y" ]]; then
                _row="${_row/| ${_mdl} |/| ⚠ ${_mdl} |}"
            fi
            echo "${_row% |} | ${_mrr} | ${_mer} |"
        done <<< "$KM_KNOWLEDGE_MODEL_ROWS"
    else
        echo "| — | — | — | — | — | — |"
    fi

    echo ""
    echo "#### 教訓ランキング"
    echo "Top 5 有効教訓"
    echo "| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |"
    echo "|------|----|----------|----------|--------|"
    if [[ -n "$KM_TOP_LESSON_ROWS" ]]; then
        printf "%s" "$KM_TOP_LESSON_ROWS"
    else
        echo "| — | — | — | — | — |"
    fi

    echo ""
    echo "Bottom 5 低効果教訓"
    echo "| 教訓 | PJ | 参照回数 | 注入回数 | 効果率 |"
    echo "|------|----|----------|----------|--------|"
    if [[ -n "$KM_BOTTOM_LESSON_ROWS" ]]; then
        printf "%s" "$KM_BOTTOM_LESSON_ROWS"
    else
        echo "| — | — | — | — | — |"
    fi

    echo ""

    # ─── Context freshness warnings (cmd_778 A-layer) ───
    echo "### Context鮮度警告"
    if [[ -n "$CONTEXT_WARNINGS" ]]; then
        printf "%s\n" "$CONTEXT_WARNINGS"
    else
        echo "なし"
    fi

    echo ""

    # ─── 戦果（直近5件） ───
    echo "### 戦果（直近5件）"
    if [[ -s "$TMP_RESULTS" ]]; then
        echo "| cmd | 内容 | 結果 | 完了日時 |"
        echo "|-----|------|------|----------|"
        # Reverse order (newest first)
        tac "$TMP_RESULTS" | while IFS=$'\t' read -r _ts _cmd _result; do
            # Look up title
            _title=$(grep "^${_cmd}"$'\t' "$TMP_TITLES" | head -1 | cut -f2 || true)
            [[ -z "$_title" ]] && _title="—"
            # Format timestamp (2026-02-27T12:26:56 → 02-27 12:26)
            _date="—"
            if [[ "$_ts" =~ ([0-9]{4}-([0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2})) ]]; then
                _date="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
            fi
            echo "| ${_cmd} | ${_title} | GATE CLEAR | ${_date} |"
        done
    else
        echo "(戦果データなし)"
    fi

    echo ""
    echo "> 過去の戦果は archive/dashboard/ を参照"

    echo "$MARKER_END"
} > "$TMPFILE"

# ═══════════════════════════════════════════════════════
# Output or update dashboard.md
# ═══════════════════════════════════════════════════════
if [[ "$DRY_RUN" == true ]]; then
    cat "$TMPFILE"
    # Report strikethrough entries that would be removed from 将軍宛報告
    if [[ -f "$DASHBOARD" ]] && grep -q '^## 将軍宛報告' "$DASHBOARD"; then
        _strike_count=$(awk '
            /^## 将軍宛報告/ { in_section=1; next }
            in_section && /^#/ { in_section=0 }
            in_section && /^- ~~/ { c++ }
            END { print c+0 }
        ' "$DASHBOARD")
        if [[ "$_strike_count" -gt 0 ]]; then
            echo "DRY-RUN: Would remove ${_strike_count} strikethrough entries from 将軍宛報告"
        fi
    fi
    exit 0
fi

if [[ ! -f "$DASHBOARD" ]]; then
    echo "ERROR: dashboard.md not found: $DASHBOARD" >&2
    exit 1
fi

if ! grep -qF "$MARKER_START" "$DASHBOARD"; then
    echo "ERROR: $MARKER_START not found in dashboard.md" >&2
    exit 1
fi

if ! grep -qF "$MARKER_END" "$DASHBOARD"; then
    echo "ERROR: $MARKER_END not found in dashboard.md" >&2
    exit 1
fi

# Replace content between markers (inclusive)
{
    # Lines before start marker
    awk -v m="$MARKER_START" '$0==m{exit} {print}' "$DASHBOARD"
    # New content (includes markers)
    cat "$TMPFILE"
    # Lines after end marker
    awk -v m="$MARKER_END" 'f{print} $0==m{f=1}' "$DASHBOARD"
} > "${DASHBOARD}.tmp"

mv "${DASHBOARD}.tmp" "$DASHBOARD"
echo "OK: dashboard.md auto section updated (${NOW})"

# ─── ntfy notification (cmd_1359) ───
if [[ "$DRY_RUN" == "false" ]]; then
    if [[ "${TOTAL_CMDS:-0}" -gt 0 ]]; then
        _ntfy_clear_pct=$((CLEAR_COUNT * 100 / TOTAL_CMDS))
    else
        _ntfy_clear_pct=0
    fi
    _ntfy_summary="📊 Dashboard更新: 稼働${ACTIVE_COUNT}名 CLEAR率${_ntfy_clear_pct}% 連勝${STREAK}"

    # AC2: Dedup — only send when CLEAR_COUNT increases (= new cmd completed)
    # Old logic checked exact string match, but active ninja count changes
    # caused 72 sends/day. Now tracks CLEAR_COUNT only.
    _ntfy_last_file="/tmp/mas-dashboard-ntfy-last-clear.txt"
    _ntfy_skip=false
    _last_clear_count=0
    if [[ -f "$_ntfy_last_file" ]]; then
        _last_clear_count=$(cat "$_ntfy_last_file" 2>/dev/null || echo 0)
    fi
    if [[ "${CLEAR_COUNT:-0}" -le "$_last_clear_count" ]]; then
        _ntfy_skip=true
    fi

    if [[ "$_ntfy_skip" == "false" ]]; then
        # AC3: Non-blocking — || true ensures dashboard update is not interrupted
        bash "$SCRIPT_DIR/ntfy.sh" "$_ntfy_summary" || true
        echo "${CLEAR_COUNT:-0}" > "$_ntfy_last_file"
    fi
fi

# ─── Remove strikethrough entries from 将軍宛報告 section ───
if grep -q '^## 将軍宛報告' "$DASHBOARD"; then
    TMP_STRIKE=$(mktemp)
    awk '
        /^## 将軍宛報告/ { in_section=1; print; next }
        in_section && /^#/ { in_section=0 }
        in_section && /^- ~~/ { next }
        { print }
    ' "$DASHBOARD" > "$TMP_STRIKE"

    _orig_lines=$(wc -l < "$DASHBOARD")
    _new_lines=$(wc -l < "$TMP_STRIKE")
    _removed=$((_orig_lines - _new_lines))

    if [[ "$_removed" -gt 0 ]]; then
        mv "$TMP_STRIKE" "$DASHBOARD"
        echo "OK: removed ${_removed} strikethrough entries from 将軍宛報告"
    else
        rm -f "$TMP_STRIKE"
    fi
fi
