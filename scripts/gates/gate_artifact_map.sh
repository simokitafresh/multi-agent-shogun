#!/usr/bin/env bash
# gate_artifact_map.sh — 成果物所在マッピング健全度チェック
# なぜなぜ7回(2026-04-12)の対策: 完了ブロックに成果物所在がないとWARN
#
# 対象: context/l2-okugi-progress.md の56ブロック表
# チェック: GS列が✅なのに成果物所在列が「—」→ WARN
# 用途: 将軍起動ゲートに組み込み or 手動実行

set -euo pipefail

PROGRESS_FILE="${1:-context/l2-okugi-progress.md}"
WARN_COUNT=0
TOTAL_DONE=0
TOTAL_BLOCKS=0

if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "ERROR: $PROGRESS_FILE not found"
    exit 1
fi

echo "=== 成果物マッピング健全度チェック ==="
echo "対象: $PROGRESS_FILE"
echo ""

# Parse block rows in one awk pass (avoids per-row subshell spawns)
# Column layout: | # | 忍法 | GS | 選出 | 成果物所在 | 完了日 |
while IFS=$'\t' read -r block_id ninjutsu gs_status artifact; do
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))

    # Check if GS is done (contains ✅)
    if [[ "$gs_status" == *"✅"* ]]; then
        TOTAL_DONE=$((TOTAL_DONE + 1))

        # Check if artifact is missing
        if [[ "$artifact" == "—" || -z "$artifact" ]]; then
            echo "  WARN: [$block_id] $ninjutsu — GS完了だが成果物所在が未記入"
            WARN_COUNT=$((WARN_COUNT + 1))
        else
            # If artifact mentions a file path, verify it exists
            if [[ "$artifact" == *"GS:"* ]]; then
                # Pure bash extraction (no subshell): strip prefix up to "GS: ", then suffix from " ("
                gs_path="${artifact#*GS: }"
                gs_path="${gs_path%% (*}"
                # Resolve relative to DM-Signal
                full_path="/mnt/c/Python_app/DM-signal/outputs/grid_search/$gs_path"
                if [[ ! -f "$full_path" ]]; then
                    echo "  WARN: [$block_id] $ninjutsu — 成果物ファイル不在: $gs_path"
                    WARN_COUNT=$((WARN_COUNT + 1))
                fi
            fi
        fi
    fi
done < <(awk -F'|' '/^\|[[:space:]]*[0-9]-[0-9][[:space:]]*\|/ {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6)
    print $2"\t"$3"\t"$4"\t"$6
}' "$PROGRESS_FILE")

echo ""
echo "--- 結果 ---"
echo "総ブロック: $TOTAL_BLOCKS"
echo "GS完了ブロック: $TOTAL_DONE"
echo "WARN: $WARN_COUNT"

if [[ $WARN_COUNT -gt 0 ]]; then
    echo ""
    echo "判定: BLOCK — 成果物所在が欠落しているブロックあり"
    exit 1
else
    echo ""
    echo "判定: OK — 全完了ブロックに成果物所在あり"
    exit 0
fi
