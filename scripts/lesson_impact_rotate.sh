#!/usr/bin/env bash
# ============================================================
# lesson_impact_rotate.sh
# lesson_impact.tsv のローテーション
#
# 直近2000行を保持し、残りを logs/archive/lesson_impact_archive.tsv に追記退避。
# ヘッダー行は保持。
#
# Usage:
#   bash scripts/lesson_impact_rotate.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TSV_FILE="$SCRIPT_DIR/logs/lesson_impact.tsv"
ARCHIVE_FILE="$SCRIPT_DIR/logs/archive/lesson_impact_archive.tsv"
KEEP_LINES=2000

if [ ! -f "$TSV_FILE" ]; then
    exit 0
fi

total_lines=$(wc -l < "$TSV_FILE" | tr -d ' ')

# ヘッダー(1行) + データ行で KEEP_LINES+1 以下なら何もしない
if [ "$total_lines" -le $((KEEP_LINES + 1)) ]; then
    exit 0
fi

# アーカイブディレクトリ確保
mkdir -p "$(dirname "$ARCHIVE_FILE")"

# アーカイブファイルにヘッダーがなければ追加
if [ ! -f "$ARCHIVE_FILE" ] || [ ! -s "$ARCHIVE_FILE" ]; then
    head -1 "$TSV_FILE" > "$ARCHIVE_FILE"
fi

# 退避対象: ヘッダーの次行 〜 (total - KEEP_LINES)行目
archive_end=$((total_lines - KEEP_LINES))
sed -n "2,${archive_end}p" "$TSV_FILE" >> "$ARCHIVE_FILE"

# 保持: ヘッダー + 末尾KEEP_LINES行
tmpfile=$(mktemp)
head -1 "$TSV_FILE" > "$tmpfile"
tail -"$KEEP_LINES" "$TSV_FILE" >> "$tmpfile"
mv "$tmpfile" "$TSV_FILE"

archived=$((archive_end - 1))
echo "[lesson_impact_rotate] archived=${archived} lines, kept=${KEEP_LINES} lines"
