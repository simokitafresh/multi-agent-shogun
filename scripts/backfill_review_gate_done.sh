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
GATES_DIR="${BACKFILL_REVIEW_GATES_DIR:-$PROJECT_DIR/queue/gates}"
REPORTS_DIR="${BACKFILL_REVIEW_REPORTS_DIR:-$PROJECT_DIR/queue/reports}"
count=0

[ -d "$GATES_DIR" ] || { echo "backfill_review_gate_done: gates directory missing: $GATES_DIR" >&2; exit 1; }
[ -d "$REPORTS_DIR" ] || { echo "backfill_review_gate_done: reports directory missing: $REPORTS_DIR" >&2; exit 1; }

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

# Pass 2: parse all reports in one awk process instead of one Bash read loop
# per YAML line. Only the same top-level parent_cmd/status scalars are emitted.
shopt -s nullglob
report_files=("$REPORTS_DIR"/*.yaml)
if [ "${#report_files[@]}" -gt 0 ]; then
while IFS=$'\t' read -r pcmd status; do
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
done < <(awk '
    function clean(value) {
        gsub(/["'\''[:space:]]/, "", value)
        return value
    }
    FNR == 1 { pcmd = ""; status = ""; emitted = 0 }
    /^parent_cmd:/ && pcmd == "" { pcmd = clean(substr($0, index($0, ":") + 1)) }
    /^status:/ && status == "" { status = clean(substr($0, index($0, ":") + 1)) }
    pcmd != "" && status != "" && !emitted {
        print pcmd "\t" status
        emitted = 1
        nextfile
    }
' "${report_files[@]}")
fi

echo "backfill_review_gate_done: ${count} directories processed"
