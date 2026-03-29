#!/usr/bin/env bash
# backfill_review_gate_done.sh
# queue/gates/配下でarchive.doneありかつreview_gate.doneなしの
# ディレクトリにreview_gate.doneプレースホルダーを生成する。
# training/cycle/selfimprovement系ディレクトリも対象。
#
# Usage: bash scripts/backfill_review_gate_done.sh
# Output: 処理件数を標準出力に表示
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GATES_DIR="$PROJECT_DIR/queue/gates"

REPORTS_DIR="$PROJECT_DIR/queue/reports"
count=0

# Pass 1: gate dirs with archive.done or training/cycle/selfimprovement
while IFS= read -r dir; do
    [ -f "$dir/review_gate.done" ] && continue
    dname=$(basename "$dir")
    should_backfill=false
    if [ -f "$dir/archive.done" ]; then
        should_backfill=true
    fi
    case "$dname" in
        cmd_training_*|cmd_cycle_*|cmd_selfimprovement_*) should_backfill=true ;;
    esac
    if [ "$should_backfill" = "true" ]; then
        touch "$dir/review_gate.done"
        count=$((count + 1))
    fi
done < <(find "$GATES_DIR" -maxdepth 1 -mindepth 1 -type d | sort)

# Pass 2: completed reports whose gate dir lacks review_gate.done
# Create gate dir + review_gate.done so archive_completed.sh can process them
for report_file in "$REPORTS_DIR"/*.yaml; do
    [ -f "$report_file" ] || continue
    pcmd=$(grep -m1 "^parent_cmd:" "$report_file" | sed 's/^parent_cmd: *//' | tr -d '"'"'" | tr -d ' ' || true)
    [ -z "$pcmd" ] && continue
    gate_dir="$GATES_DIR/$pcmd"
    [ -f "$gate_dir/review_gate.done" ] && continue
    status=$(grep -m1 "^status:" "$report_file" | sed 's/^status: *//' | tr -d '"'"'" | tr -d ' ' || true)
    case "$status" in
        done|completed|complete|success|failed)
            mkdir -p "$gate_dir"
            touch "$gate_dir/review_gate.done"
            count=$((count + 1))
            ;;
    esac
done

echo "backfill_review_gate_done: ${count} directories processed"
