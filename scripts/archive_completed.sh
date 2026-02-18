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
cleanup() { rm -f /tmp/stk_active_$$.yaml /tmp/stk_done_$$.yaml /tmp/dash_trim_$$.md; }
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

QUEUE_FILE="$PROJECT_DIR/queue/shogun_to_karo.yaml"
ARCHIVE_DIR="$PROJECT_DIR/queue/archive"
ARCHIVE_CMD="$ARCHIVE_DIR/shogun_to_karo_done.yaml"
ARCHIVE_CMD_DIR="$ARCHIVE_DIR/cmds"
DASHBOARD="$PROJECT_DIR/dashboard.md"
DASH_ARCHIVE="$ARCHIVE_DIR/dashboard_archive.md"
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
    mapfile -t starts < <(grep -n '^  - id: cmd_' "$QUEUE_FILE" | cut -d: -f1)

    if [ ${#starts[@]} -eq 0 ]; then
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

        # statusフィールドを取得（インデント4スペースの行のみ）
        local status_val
        status_val=$(printf '%s\n' "$entry" \
            | grep '^    status: ' | head -1 \
            | sed 's/^    status: //' | tr -d '[:space:]')

        # cmd_idを取得（退避先ファイル名に利用）
        local cmd_id
        cmd_id=$(printf '%s\n' "$entry" \
            | grep '^  - id: cmd_' | head -1 \
            | sed 's/^  - id: //')

        if [[ "$status_val" =~ ^(completed|cancelled|absorbed) ]]; then
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
archive_dashboard

# archive.doneフラグ出力（CMD_ID指定時のみ）
if [ -n "$CMD_ID" ]; then
    mkdir -p "$PROJECT_DIR/queue/gates/${CMD_ID}"
    touch "$PROJECT_DIR/queue/gates/${CMD_ID}/archive.done"
    echo "[archive_completed] gate flag: queue/gates/${CMD_ID}/archive.done"
fi

echo "[archive_completed] done"
