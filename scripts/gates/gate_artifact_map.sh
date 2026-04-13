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

# Parse block rows: lines matching "| N-N |"
while IFS= read -r line; do
    # Match block rows like "| 1-1 | bunshin | ✅ | ✅ | DB: ... | 2026-... |"
    if [[ "$line" =~ ^\|[[:space:]]*([0-9]-[0-9])[[:space:]]*\| ]]; then
        block_id="${BASH_REMATCH[1]}"
        TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))

        # Extract columns by splitting on |
        # Column layout: | # | 忍法 | GS | 選出 | 成果物所在 | 完了日 |
        ninjutsu=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')
        gs_status=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4}')
        artifact=$(echo "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $6); print $6}')

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
                    # Extract path after "GS: "
                    gs_path=$(echo "$artifact" | sed 's/.*GS: //' | sed 's/ (.*//')
                    # Resolve relative to DM-Signal
                    full_path="/mnt/c/Python_app/DM-signal/outputs/grid_search/$gs_path"
                    if [[ ! -f "$full_path" ]]; then
                        echo "  WARN: [$block_id] $ninjutsu — 成果物ファイル不在: $gs_path"
                        WARN_COUNT=$((WARN_COUNT + 1))
                    fi
                fi
            fi
        fi
    fi
done < "$PROGRESS_FILE"

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
