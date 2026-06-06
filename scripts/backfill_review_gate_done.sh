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

strip_yaml_scalar() {
    local value="$1"
    value="${value//\"/}"
    value="${value//\'/}"
    value="${value//[[:space:]]/}"
    printf '%s' "$value"
}

# Pass 1: gate dirs with archive.done or training/cycle/selfimprovement
while IFS= read -r dir; do
    [ -f "$dir/review_gate.done" ] && continue
    dname="${dir##*/}"
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
done < <(find "$GATES_DIR" -maxdepth 1 -mindepth 1 -type d)

# Pass 2: completed reports whose gate dir lacks review_gate.done
# Create gate dir + review_gate.done so archive_completed.sh can process them
for report_file in "$REPORTS_DIR"/*.yaml; do
    [ -f "$report_file" ] || continue
    pcmd=""
    status=""
    while IFS= read -r line; do
        case "$line" in
            parent_cmd:*)
                pcmd="$(strip_yaml_scalar "${line#parent_cmd:}")"
                ;;
            status:*)
                status="$(strip_yaml_scalar "${line#status:}")"
                ;;
        esac
        [ -n "$pcmd" ] && [ -n "$status" ] && break
    done < "$report_file"

    [ -z "$pcmd" ] && continue
    gate_dir="$GATES_DIR/$pcmd"
    [ -f "$gate_dir/review_gate.done" ] && continue
    case "$status" in
        done|completed|complete|success|failed)
            mkdir -p "$gate_dir"
            touch "$gate_dir/review_gate.done"
            count=$((count + 1))
            ;;
    esac
done

echo "backfill_review_gate_done: ${count} directories processed"
