#!/usr/bin/env bash
# ============================================================
# archive_completed.sh
# 完了cmdと古い戦果をアーカイブし、ファイルを軽量化する
# 家老がcmd完了判定後に呼び出す
#
# Usage: bash scripts/archive_completed.sh [keep_results] [cmd_id]
#   keep_results: ダッシュボードに残す戦果数（デフォルト: 3）
#   cmd_id: 指定時にqueue/gates/{cmd_id}/archive.doneフラグを出力
# ============================================================
set -euo pipefail

# tmpファイルの後始末
cleanup() { rm -f /tmp/stk_active_$$.yaml /tmp/stk_done_$$.yaml /tmp/dash_trim_$$.md /tmp/dash_karo_trim_$$.md /tmp/lord_conv_trim_$$.yaml; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/scripts/lib/field_get.sh"

QUEUE_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive"
ARCHIVE_CMD="$ARCHIVE_DIR/shogun_to_karo_done.yaml"
ARCHIVE_CMD_DIR="$ARCHIVE_DIR/cmds"
DASHBOARD="$PROJECT_DIR/dashboard.md"
DASH_ARCHIVE="$ARCHIVE_DIR/dashboard_archive.md"
REPORTS_DIR="$PROJECT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$ARCHIVE_DIR/reports"
usage_error() {
    echo "Usage: archive_completed.sh [keep_results] [cmd_id]" >&2
    echo "  keep_results: 正の整数（省略時3）" >&2
    echo "  cmd_id: cmd_XXX形式（任意）" >&2
    echo "受け取った引数: $*" >&2
}

# 引数パース: $1がcmd_で始まる場合はCMD_IDとして扱う
if [[ "${1:-}" == cmd_* ]]; then
    CMD_ID="$1"
    KEEP_RESULTS=${2:-3}
else
    KEEP_RESULTS=${1:-3}
    CMD_ID=${2:-""}
fi

if [[ ! "$KEEP_RESULTS" =~ ^[0-9]+$ ]]; then
    echo "ERROR: keep_results は正の整数で指定せよ。" >&2
    usage_error "$@"
    exit 1
fi

if [ -n "$CMD_ID" ] && [[ "$CMD_ID" != cmd_* ]]; then
    echo "ERROR: cmd_id は cmd_XXX 形式で指定せよ。" >&2
    usage_error "$@"
    exit 1
fi

mkdir -p "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_CMD_DIR"
mkdir -p "$ARCHIVE_REPORT_DIR"

# postcondition用グローバル変数（archive_cmdsが設定）
_POSTCOND_COMPLETED=0
_POSTCOND_ARCHIVED=0

# ============================================================
# 1. shogun_to_karo.yaml — 完了cmdをアーカイブに退避
# ============================================================
archive_cmds() {
    [ -f "$QUEUE_FILE" ] || return 0

    local tmp_active="/tmp/stk_active_$$.yaml"
    local tmp_done="/tmp/stk_done_$$.yaml"
    local archived=0 kept=0
    local date_stamp
    date_stamp="$(date '+%Y%m%d')"

    echo "commands:" > "$tmp_active"
    : > "$tmp_done"

    # エントリ境界を行番号で特定
    local -a starts
    mapfile -t starts < <(grep -n '^ *- id: cmd_' "$QUEUE_FILE" | cut -d: -f1)

    if [ ${#starts[@]} -eq 0 ]; then
        # 空振り検出: エントリ境界が0件でも完了ステータスが存在するならパターン不一致
        local pre_check
        pre_check=$(awk '/^ *status: *(completed|cancelled|absorbed|halted|superseded|done)/{c++} END{print c+0}' "$QUEUE_FILE")
        if [ "$pre_check" -gt 0 ]; then
            echo "[archive] WARN: $pre_check completed cmds found but 0 archived — grep pattern mismatch?" >&2
        fi
        _POSTCOND_COMPLETED=$pre_check
        echo "[archive] cmds: no entries found"
        rm -f "$tmp_active" "$tmp_done"
        return 0
    fi

    local total_lines
    total_lines=$(wc -l < "$QUEUE_FILE")

    for i in "${!starts[@]}"; do
        local s=${starts[$i]}
        local e
        if [ $((i + 1)) -lt ${#starts[@]} ]; then
            e=$(( ${starts[$((i + 1))]} - 1 ))
        else
            e=$total_lines
        fi

        local entry
        entry="$(sed -n "${s},${e}p" "$QUEUE_FILE")"

        # statusフィールドを取得（L070対策: field_getでインデント変動に追従）
        local status_val
        local entry_tmp="/tmp/stk_entry_${$}_${i}.yaml"
        printf '%s\n' "$entry" > "$entry_tmp"
        status_val=$(FIELD_GET_NO_LOG=1 field_get "$entry_tmp" "status" "" 2>/dev/null | tr -d '[:space:]')
        rm -f "$entry_tmp"

        # cmd_idを取得（退避先ファイル名に利用）
        local cmd_id
        cmd_id=$(printf '%s\n' "$entry" \
            | grep '^ *- id: cmd_' | head -1 \
            | sed 's/^ *- id: //')

        if [[ "$status_val" =~ ^(completed|cancelled|absorbed|halted|superseded|done) ]]; then
            local archive_status="${BASH_REMATCH[1]}"
            printf '%s\n' "$entry" >> "$tmp_done"

            if [ -n "$cmd_id" ]; then
                local cmd_archive_file="$ARCHIVE_CMD_DIR/${cmd_id}_${archive_status}_${date_stamp}.yaml"
                {
                    echo "commands:"
                    printf '%s\n' "$entry"
                } > "$cmd_archive_file"
            else
                echo "[archive] WARN: failed to parse cmd_id at lines ${s}-${e}" >&2
            fi

            ((archived++)) || true
        else
            printf '%s\n' "$entry" >> "$tmp_active"
            ((kept++)) || true
        fi
    done

    # 空振り検出: 完了ステータスのcmdが存在するのにarchived=0の場合WARN
    local completed_count
    completed_count=$(awk '/^ *status: *(completed|cancelled|absorbed|halted|superseded|done)/{c++} END{print c+0}' "$QUEUE_FILE")
    # postcondition用グローバル変数を設定
    _POSTCOND_COMPLETED=$completed_count
    _POSTCOND_ARCHIVED=$archived

    if [ "$completed_count" -gt 0 ] && [ "$archived" -eq 0 ]; then
        echo "[archive] WARN: $completed_count completed cmds found but 0 archived — grep pattern mismatch?" >&2
    fi

    if [ "$archived" -gt 0 ] && [ -s "$tmp_done" ]; then
        # flockでYAMLファイルへの書き込みを排他制御
        (
            flock -w 10 200 || { echo "[archive] WARN: flock timeout on QUEUE_FILE"; return 1; }
            cat "$tmp_done" >> "$ARCHIVE_CMD"
            mv "$tmp_active" "$QUEUE_FILE"
        ) 200>"$QUEUE_FILE.lock"
        echo "[archive] cmds: archived=$archived kept=$kept"
    else
        rm -f "$tmp_active"
        echo "[archive] cmds: nothing to archive (kept=$kept)"
    fi
    rm -f "$tmp_done"
}

# ============================================================
# 1.5 queue/reports — 完了報告をアーカイブ
#   - 新形式: {ninja}_report_{cmd}.yaml
#   - 旧形式: {ninja}_report.yaml（後方互換）
# ============================================================
archive_reports() {
    [ -d "$REPORTS_DIR" ] || return 0

    local archived=0 kept=0 skipped=0 junk=0
    local date_stamp
    date_stamp="$(date '+%Y%m%d')"

    # --- 非YAMLファイルの掃除 (忍者の成果物混入防止) ---
    shopt -s nullglob
    local all_files=("$REPORTS_DIR"/*)
    shopt -u nullglob
    for f in "${all_files[@]}"; do
        [ -f "$f" ] || continue
        case "$f" in *.yaml) continue ;; esac
        mv "$f" "$ARCHIVE_REPORT_DIR/"
        junk=$((junk + 1))
    done

    # --- YAML報告のアーカイブ ---
    shopt -s nullglob
    local report_files=("$REPORTS_DIR"/*_report*.yaml "$REPORTS_DIR"/subtask_*.yaml)
    shopt -u nullglob

    if [ ${#report_files[@]} -eq 0 ] && [ "$junk" -eq 0 ]; then
        echo "[archive] reports: none"
        return 0
    fi

    for report_file in "${report_files[@]}"; do
        [ -f "$report_file" ] || continue

        local status_val parent_cmd base_name target_name dest_path
        status_val=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "status" "" 2>/dev/null | tr -d '[:space:]')
        parent_cmd=$(FIELD_GET_NO_LOG=1 field_get "$report_file" "parent_cmd" "" 2>/dev/null | tr -d '[:space:]')

        # cmd指定時は該当cmdの報告のみを対象化
        if [ -n "$CMD_ID" ] && [ -n "$parent_cmd" ] && [ "$parent_cmd" != "$CMD_ID" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        # CMD_ID指定なし(sweep mode): 完了報告のみ。CMD_ID指定あり: status不問で全archive
        if [ -z "$CMD_ID" ]; then
            case "$status_val" in
                done|completed|complete|success|failed) ;;
                *)
                    kept=$((kept + 1))
                    continue
                    ;;
            esac
        fi

        base_name="$(basename "$report_file")"
        target_name="$base_name"

        # 旧形式はアーカイブ時にcmdサフィックスを付与（識別性向上）
        if [[ "$base_name" =~ _report\.yaml$ ]] && [[ "$parent_cmd" == cmd_* ]]; then
            target_name="${base_name%.yaml}_${parent_cmd}.yaml"
        fi

        dest_path="$ARCHIVE_REPORT_DIR/${target_name%.yaml}_${date_stamp}.yaml"
        if [ -e "$dest_path" ]; then
            dest_path="$ARCHIVE_REPORT_DIR/${target_name%.yaml}_$(date '+%H%M%S').yaml"
        fi

        mv "$report_file" "$dest_path"
        archived=$((archived + 1))
    done

    echo "[archive] reports: archived=$archived kept=$kept skipped=$skipped junk=$junk"
}

# ============================================================
# 1.6 dashboard.md KARO_SECTION 最新更新 — 古い更新をアーカイブ（直近3件を残す）
# ============================================================
archive_karo_section() {
    [ -f "$DASHBOARD" ] || return 0

    local karo_archive="$ARCHIVE_DIR/dashboard_karo_archive.md"
    local update_start update_end
    update_start=$(grep -n '^## 最新更新' "$DASHBOARD" | head -1 | cut -d: -f1 || true)

    if [[ -z "$update_start" ]]; then
        echo "[archive] karo_section: '## 最新更新' not found, skip"
        return 0
    fi

    # 次の ## ヘッダ直前までを最新更新セクションとみなす
    update_end=$(awk -v s="$update_start" '
        NR > s && /^## / { print NR - 1; found=1; exit }
        END { if (!found) print NR }
    ' "$DASHBOARD")

    local -a update_lines
    mapfile -t update_lines < <(
        awk -v s="$update_start" -v e="$update_end" '
            NR > s && NR <= e && /^- \*\*cmd_[^*]*\*\*:/ { print NR }
        ' "$DASHBOARD"
    )
    local total_updates=${#update_lines[@]}

    if [[ $total_updates -le 3 ]]; then
        echo "[archive] karo_updates: $total_updates entries <= 3, skip"
        return 0
    fi

    local -a delete_lines=("${update_lines[@]:3}")
    local archived_count=${#delete_lines[@]}
    local delete_csv
    delete_csv=$(IFS=,; echo "${delete_lines[*]}")

    {
        echo ""
        echo "# Archived KARO updates $(date '+%Y-%m-%d %H:%M')"
        for line_no in "${delete_lines[@]}"; do
            sed -n "${line_no}p" "$DASHBOARD"
        done
    } >> "$karo_archive"

    # dashboard.mdから退避済み行を削除（flock排他）
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; return 1; }
        awk -v csv="$delete_csv" '
            BEGIN {
                n = split(csv, arr, ",")
                for (i = 1; i <= n; i++) {
                    if (arr[i] != "") del[arr[i]] = 1
                }
            }
            !(NR in del) { print }
        ' "$DASHBOARD" > "/tmp/dash_karo_trim_$$.md"
        mv "/tmp/dash_karo_trim_$$.md" "$DASHBOARD"
    ) 200>"$DASHBOARD.lock"

    echo "[archive] karo_updates: archived=$archived_count kept=3"
}

# ============================================================
# 2. dashboard.md — 古い戦果をアーカイブ（直近N件を残す）
# ============================================================
archive_dashboard() {
    [ -f "$DASHBOARD" ] || return 0

    # 戦果セクションのデータ行を取得（ヘッダ・区切り行を除外）
    local -a result_lines
    mapfile -t result_lines < <(grep -n '^| [0-9]' "$DASHBOARD" | cut -d: -f1)

    local total=${#result_lines[@]}
    if [ "$total" -le "$KEEP_RESULTS" ]; then
        echo "[archive] dashboard: $total results <= keep=$KEEP_RESULTS, skip"
        return 0
    fi

    # KEEP_RESULTS件目の次のデータ行からアーカイブ対象
    local archive_first_line=${result_lines[$KEEP_RESULTS]}
    local last_data_line=${result_lines[$((total - 1))]}
    local archived_count=$((total - KEEP_RESULTS))

    # アーカイブに追記（データ行のみ）
    {
        echo ""
        echo "# Archived $(date '+%Y-%m-%d %H:%M')"
        sed -n "${archive_first_line},${last_data_line}p" "$DASHBOARD"
    } >> "$DASH_ARCHIVE"

    # ダッシュボードからアーカイブ済みデータ行を削除（flock排他）
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; return 1; }
        sed "${archive_first_line},${last_data_line}d" "$DASHBOARD" > "/tmp/dash_trim_$$.md"
        mv "/tmp/dash_trim_$$.md" "$DASHBOARD"
    ) 200>"$DASHBOARD.lock"

    echo "[archive] dashboard: archived=$archived_count kept=$KEEP_RESULTS"
}

# ============================================================
# Main
# ============================================================
echo "[archive_completed] $(date '+%Y-%m-%d %H:%M:%S') start"
archive_cmds
archive_reports
archive_karo_section

# ============================================================
# postcondition: archive_cmds結果の事後検証
# L074対策: 算術式は$((var+1))形式。postcondition失敗でもスクリプトを止めない。
# ============================================================
postcondition_archive() {
    local input=$_POSTCOND_COMPLETED
    local output=$_POSTCOND_ARCHIVED

    if [ "$input" -eq 0 ]; then
        echo "[archive] postcondition: OK (no completed cmds)"
        return 0
    fi

    if [ "$output" -eq 0 ]; then
        echo "[archive] ALERT: completed存在するがアーカイブ0件 (expected=$input actual=0)" >&2
        bash "$PROJECT_DIR/scripts/ntfy.sh" "[archive] ALERT: completed存在するがアーカイブ0件 (expected=${input} actual=0)" || true
        return 0
    fi

    if [ "$output" -lt "$input" ]; then
        echo "[archive] WARN: アーカイブ不完全 (expected=$input actual=$output)" >&2
        return 0
    fi

    echo "[archive] postcondition: OK (archived=$output/$input)"
}
postcondition_archive || true

archive_dashboard

# ============================================================
# 3. lord_conversation.yaml — 100件超→直近50件に刈り込み
# ============================================================
rotate_lord_conversation() {
    local lord_conv="$PROJECT_DIR/queue/lord_conversation.yaml"
    [ -f "$lord_conv" ] || { echo "[archive] lord_conversation: not found, skip"; return 0; }

    local lord_archive_dir="$ARCHIVE_DIR/lord_conversation"
    mkdir -p "$lord_archive_dir"

    # エントリ数を計算（"- timestamp:" 行をカウント）
    local entry_count
    entry_count=$(grep -c '^ *- timestamp:' "$lord_conv" 2>/dev/null || echo 0)

    if [ "$entry_count" -le 100 ]; then
        echo "[archive] lord_conversation: $entry_count entries <= 100, skip"
        return 0
    fi

    local keep=50
    local archive_count=$((entry_count - keep))
    local date_stamp
    date_stamp="$(date '+%Y%m%d_%H%M%S')"

    # エントリ境界の行番号を取得
    local -a entry_starts
    mapfile -t entry_starts < <(grep -n '^ *- timestamp:' "$lord_conv" | cut -d: -f1)

    # keep件目（=archive_count+1番目）のエントリ開始行
    local keep_start_line=${entry_starts[$archive_count]}

    # アーカイブ対象（先頭〜keep_start_line-1行目）を退避
    local archive_file="$lord_archive_dir/lord_conversation_${date_stamp}.yaml"

    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on lord_conversation"; return 1; }
        head -n $((keep_start_line - 1)) "$lord_conv" > "$archive_file"
        # 直近keep件を残す（ヘッダ行がある場合に備えてtailではなくsedで切り出し）
        sed -n "${keep_start_line},\$p" "$lord_conv" > "/tmp/lord_conv_trim_$$.yaml"
        mv "/tmp/lord_conv_trim_$$.yaml" "$lord_conv"
    ) 200>"$lord_conv.lock"

    echo "[archive] lord_conversation: archived=$archive_count kept=$keep"
}
rotate_lord_conversation

# archive.doneフラグ出力（CMD_ID指定時のみ）
if [ -n "$CMD_ID" ]; then
    mkdir -p "$PROJECT_DIR/queue/gates/${CMD_ID}"
    touch "$PROJECT_DIR/queue/gates/${CMD_ID}/archive.done"
    echo "[archive_completed] gate flag: queue/gates/${CMD_ID}/archive.done"
fi

echo "[archive_completed] done"
