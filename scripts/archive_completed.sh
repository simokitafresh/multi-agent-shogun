#!/usr/bin/env bash
# ============================================================
# archive_completed.sh
# 完了cmdと古い戦果をアーカイブし、ファイルを軽量化する
# 家老がcmd完了判定後に呼び出す
#
# Usage: bash scripts/archive_completed.sh [keep_results]
#   keep_results: ダッシュボードに残す戦果数（デフォルト: 3）
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
DASHBOARD="$PROJECT_DIR/dashboard.md"
DASH_ARCHIVE="$ARCHIVE_DIR/dashboard_archive.md"
KEEP_RESULTS=${1:-3}

mkdir -p "$ARCHIVE_DIR"

# ============================================================
# 1. shogun_to_karo.yaml — 完了cmdをアーカイブに退避
# ============================================================
archive_cmds() {
    [ -f "$QUEUE_FILE" ] || return 0

    local tmp_active="/tmp/stk_active_$$.yaml"
    local tmp_done="/tmp/stk_done_$$.yaml"
    local archived=0 kept=0

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

        # statusフィールドを取得（インデント4スペースの行のみ）
        local status_val
        status_val=$(sed -n "${s},${e}p" "$QUEUE_FILE" \
            | grep '^    status: ' | head -1 \
            | sed 's/^    status: //' | tr -d '[:space:]')

        if [[ "$status_val" =~ ^done ]]; then
            sed -n "${s},${e}p" "$QUEUE_FILE" >> "$tmp_done"
            ((archived++)) || true
        else
            sed -n "${s},${e}p" "$QUEUE_FILE" >> "$tmp_active"
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

    local -a result_lines
    mapfile -t result_lines < <(grep -n '^### 🏁 cmd_' "$DASHBOARD" | cut -d: -f1)

    local total=${#result_lines[@]}
    if [ "$total" -le "$KEEP_RESULTS" ]; then
        echo "[archive] dashboard: $total results <= keep=$KEEP_RESULTS, skip"
        return 0
    fi

    # KEEP_RESULTS番目の次のエントリ開始行
    local cut_from=${result_lines[$KEEP_RESULTS]}

    # その直前の---区切り行を探す
    local sep_line
    sep_line=$(awk -v cut="$cut_from" \
        'NR < cut && /^---$/ { line=NR } END { print line+0 }' "$DASHBOARD")

    if [ "$sep_line" -eq 0 ]; then
        sep_line=$((cut_from - 1))
    fi

    local total_lines archived_count
    total_lines=$(wc -l < "$DASHBOARD")
    archived_count=$((total - KEEP_RESULTS))

    # アーカイブに追記
    {
        echo ""
        echo "# Archived $(date '+%Y-%m-%d %H:%M')"
        tail -n +$((sep_line + 1)) "$DASHBOARD"
    } >> "$DASH_ARCHIVE"

    # ダッシュボードをトリム（flock排他）
    (
        flock -w 10 200 || { echo "[archive] WARN: flock timeout on DASHBOARD"; return 1; }
        head -n "$sep_line" "$DASHBOARD" > "/tmp/dash_trim_$$.md"
        mv "/tmp/dash_trim_$$.md" "$DASHBOARD"
    ) 200>"$DASHBOARD.lock"

    echo "[archive] dashboard: archived=$archived_count kept=$KEEP_RESULTS (cut at L$sep_line)"
}

# ============================================================
# Main
# ============================================================
echo "[archive_completed] $(date '+%Y-%m-%d %H:%M:%S') start"
archive_cmds
archive_dashboard
echo "[archive_completed] done"
