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
cleanup() { rm -f /tmp/stk_active_$$.yaml /tmp/stk_done_$$.yaml /tmp/dash_karo_trim_$$.md /tmp/lord_conv_trim_$$.yaml; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/scripts/lib/field_get.sh"

QUEUE_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"
CHANGELOG_FILE="$PROJECT_DIR/queue/completed_changelog.yaml"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive"
ARCHIVE_CMD="$ARCHIVE_DIR/shogun_to_karo_done.yaml"
ARCHIVE_CMD_DIR="$ARCHIVE_DIR/cmds"
DASHBOARD="$PROJECT_DIR/dashboard.md"
DASH_ARCHIVE="$ARCHIVE_DIR/dashboard_archive.md"
REPORTS_DIR="$PROJECT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$ARCHIVE_DIR/reports"
CHRONICLE_FILE="$PROJECT_DIR/context/cmd-chronicle.md"
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
# 0.5 CMD年代記への追記
# ============================================================
append_to_chronicle() {
    local cmd_id="$1"
    local entry="$2"

    # Extract purpose/title from entry
    local title
    title=$(printf '%s\n' "$entry" | grep -m1 '^ *purpose:' | sed 's/^ *purpose: *//; s/^"//; s/"$//')
    if [ -z "$title" ]; then
        title=$(printf '%s\n' "$entry" | grep -m1 '^ *title:' | sed 's/^ *title: *//; s/^"//; s/"$//')
    fi

    # Extract project from entry
    local project
    project=$(printf '%s\n' "$entry" | grep -m1 '^ *project:' | sed 's/^ *project: *//; s/^"//; s/"$//')

    # Report summary (30 chars) — reports not yet archived at this point
    local key_result=""
    shopt -s nullglob
    local rfiles=("$REPORTS_DIR"/*_report_"${cmd_id}".yaml)
    shopt -u nullglob
    for rf in "${rfiles[@]}"; do
        [ -f "$rf" ] || continue
        key_result=$(FIELD_GET_NO_LOG=1 field_get "$rf" "summary" "" 2>/dev/null | cut -c1-30)
        [ -n "$key_result" ] && break
    done

    local date_mm_dd year_month
    date_mm_dd="$(date '+%m-%d')"
    year_month="$(date '+%Y-%m')"

    local chronicle_line="| ${cmd_id} | ${title:-—} | ${project:-—} | ${date_mm_dd} | ${key_result:-—} |"

    (
        flock -w 10 200 || { echo "[chronicle] WARN: flock timeout on chronicle" >&2; return 1; }

        # Create file if not exists
        if [ ! -f "$CHRONICLE_FILE" ]; then
            printf '# CMD年代記\n<!-- last_updated: %s -->\n' "$(date '+%Y-%m-%d')" > "$CHRONICLE_FILE"
        fi

        # Add month section if missing
        if ! grep -q "^## ${year_month}$" "$CHRONICLE_FILE"; then
            printf '\n## %s\n\n| cmd | title | project | date | key_result |\n|-----|-------|---------|------|------------|\n' "$year_month" >> "$CHRONICLE_FILE"
        fi

        # Append data line
        printf '%s\n' "$chronicle_line" >> "$CHRONICLE_FILE"

        # Update last_updated
        sed -i "s/<!-- last_updated: .* -->/<!-- last_updated: $(date '+%Y-%m-%d') -->/" "$CHRONICLE_FILE"
    ) 200>"$CHRONICLE_FILE.lock"

    echo "[chronicle] appended: $cmd_id"
}

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

        # status欠損時のみ、completed_changelog照合でcompleted扱いにする。
        # 完全一致(anchor)で cmd_51 が cmd_515 に誤マッチしないようにする。
        if [ -z "$status_val" ] && [ -n "$cmd_id" ] && [ -f "$CHANGELOG_FILE" ]; then
            local cmd_id_re
            cmd_id_re=$(printf '%s' "$cmd_id" | sed 's/[][(){}.^$*+?|\\-]/\\&/g')
            if grep -Eq "^[[:space:]]*(-[[:space:]]*)?(id|cmd_id):[[:space:]]*${cmd_id_re}[[:space:]]*$" "$CHANGELOG_FILE"; then
                status_val="completed"
            fi
        fi

        if [[ "$status_val" =~ ^(completed|cancelled|absorbed|halted|superseded|done) ]]; then
            local archive_status="${BASH_REMATCH[1]}"
            printf '%s\n' "$entry" >> "$tmp_done"

            if [ -n "$cmd_id" ]; then
                local cmd_archive_file="$ARCHIVE_CMD_DIR/${cmd_id}_${archive_status}_${date_stamp}.yaml"
                {
                    echo "commands:"
                    printf '%s\n' "$entry"
                } > "$cmd_archive_file"
                append_to_chronicle "$cmd_id" "$entry" || true
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
            # S06修正: mv前にtmpファイル存在確認
            [ -f "$tmp_active" ] || { echo "[archive] FATAL: tmp_active not found: $tmp_active" >&2; exit 1; }
            mv "$tmp_active" "$QUEUE_FILE" || { echo "[archive] FATAL: mv failed: $tmp_active → $QUEUE_FILE" >&2; exit 1; }
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
        mv "$f" "$ARCHIVE_REPORT_DIR/" || { echo "[archive] WARN: mv failed: $f" >&2; continue; }
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

            # sweep mode安全弁: 親cmdが進行中なら報告を退避しない
            # 取得失敗(空文字)は安全側(keep)へ倒す。
            if [ -n "$parent_cmd" ]; then
                local cmd_status
                if [ ! -f "$QUEUE_FILE" ]; then
                    kept=$((kept + 1))
                    continue
                fi

                # exact matchでparent_cmdブロックのstatusを抽出（部分一致防止）
                cmd_status=$(
                    awk -v target="$parent_cmd" '
                        BEGIN { in_target = 0 }
                        /^[[:space:]]*-[[:space:]]id:[[:space:]]*cmd_/ {
                            id = $0
                            sub(/^[[:space:]]*-[[:space:]]id:[[:space:]]*/, "", id)
                            gsub(/[[:space:]]+$/, "", id)
                            if (in_target == 1) { exit }
                            in_target = (id == target)
                            next
                        }
                        in_target == 1 && /^[[:space:]]*status:[[:space:]]*/ {
                            st = $0
                            sub(/^[[:space:]]*status:[[:space:]]*/, "", st)
                            gsub(/[[:space:]]+$/, "", st)
                            print st
                            exit
                        }
                    ' "$QUEUE_FILE"
                )

                case "$cmd_status" in
                    pending|in_progress|acknowledged)
                        kept=$((kept + 1))
                        continue
                        ;;
                    "")
                        # parent cmd not in QUEUE_FILE — check child tasks
                        local has_active_child=false
                        local task_file_check
                        for task_file_check in "$PROJECT_DIR/queue/tasks"/*.yaml; do
                            [ -f "$task_file_check" ] || continue
                            local t_parent t_status
                            t_parent=$(FIELD_GET_NO_LOG=1 field_get "$task_file_check" "parent_cmd" "" 2>/dev/null | tr -d '[:space:]')
                            [ "$t_parent" = "$parent_cmd" ] || continue
                            t_status=$(FIELD_GET_NO_LOG=1 field_get "$task_file_check" "status" "" 2>/dev/null | tr -d '[:space:]')
                            case "$t_status" in
                                done|completed|complete|success|failed|"") ;;
                                *)
                                    has_active_child=true
                                    break
                                    ;;
                            esac
                        done
                        if $has_active_child; then
                            kept=$((kept + 1))
                            continue
                        fi
                        # No active children — safe to archive
                        ;;
                esac
            fi
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

        mv "$report_file" "$dest_path" || { echo "[archive] WARN: mv failed: $report_file → $dest_path" >&2; continue; }
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
        mv "/tmp/dash_karo_trim_$$.md" "$DASHBOARD" || { echo "[archive] FATAL: mv failed: karo trim → $DASHBOARD" >&2; exit 1; }
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
        # S07修正: mktempで安全なtmp生成 + sed成功確認後にmv
        local tmp_dash
        tmp_dash=$(mktemp /tmp/dash_trim_XXXXXXXX.md)
        if ! sed "${archive_first_line},${last_data_line}d" "$DASHBOARD" > "$tmp_dash"; then
            echo "[archive] FATAL: sed failed for dashboard trim" >&2
            rm -f "$tmp_dash"
            exit 1
        fi
        mv "$tmp_dash" "$DASHBOARD" || { echo "[archive] FATAL: mv failed: $tmp_dash → $DASHBOARD" >&2; exit 1; }
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

# cmd_579: 会話保持はJSONL専用 `scripts/conversation_retention.sh` に移管。
# archive_completed.sh から旧YAMLローテーションは撤去する。

# archive.doneフラグ出力（CMD_ID指定時のみ）
if [ -n "$CMD_ID" ]; then
    mkdir -p "$PROJECT_DIR/queue/gates/${CMD_ID}"
    touch "$PROJECT_DIR/queue/gates/${CMD_ID}/archive.done"
    echo "[archive_completed] gate flag: queue/gates/${CMD_ID}/archive.done"
fi

echo "[archive_completed] done"
