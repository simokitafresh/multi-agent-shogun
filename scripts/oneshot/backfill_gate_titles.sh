#!/bin/bash
# backfill_gate_titles.sh — gate_metrics.log の既存8列行にタイトル(9列目)を追記
# Usage: bash scripts/oneshot/backfill_gate_titles.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
ACTIVE_STK="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
ARCHIVE_STK="$SCRIPT_DIR/queue/archive/shogun_to_karo_done.yaml"

if [ ! -f "$GATE_LOG" ]; then
    echo "ERROR: gate log not found: $GATE_LOG" >&2
    exit 1
fi

tmp_map=$(mktemp)
tmp_out=$(mktemp)
trap 'rm -f "$tmp_map" "$tmp_out"' EXIT

extract_cmd_titles() {
    local yaml_file="$1"
    [ -f "$yaml_file" ] || return 0

    awk '
        /^[[:space:]]*-[[:space:]]*id:[[:space:]]*cmd_[0-9]+/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            gsub(/["[:space:]]/, "", line)
            cid = line
            in_cmd = 1
            next
        }
        in_cmd && /^[[:space:]]*title:[[:space:]]*/ {
            title = $0
            sub(/^[[:space:]]*title:[[:space:]]*/, "", title)
            sub(/[[:space:]]+#.*$/, "", title)
            gsub(/^["\047]|["\047]$/, "", title)
            gsub(/\t/, " ", title)
            if (length(title) > 50) {
                title = substr(title, 1, 47) "..."
            }
            print cid "\t" title
            cid = ""
            in_cmd = 0
        }
    ' "$yaml_file"
}

{
    extract_cmd_titles "$ARCHIVE_STK"
    extract_cmd_titles "$ACTIVE_STK"
} | awk -F'\t' '
    $1 != "" {
        title = ""
        if (index($0, "\t") > 0) {
            title = substr($0, index($0, "\t") + 1)
        }
        cmd_to_title[$1] = title
    }
    END {
        for (cmd in cmd_to_title) {
            print cmd "\t" cmd_to_title[cmd]
        }
    }
' > "$tmp_map"

before_nf8=$(awk -F'\t' 'NF==8{c++} END{print c+0}' "$GATE_LOG")

awk -F'\t' -v OFS='\t' -v map_file="$tmp_map" '
    BEGIN {
        while ((getline line < map_file) > 0) {
            if (line == "") {
                continue
            }
            split(line, parts, "\t")
            cmd = parts[1]
            title = ""
            if (index(line, "\t") > 0) {
                title = substr(line, index(line, "\t") + 1)
            }
            cmd_to_title[cmd] = title
        }
        close(map_file)
    }
    NF == 8 {
        cmd = $2
        title = (cmd in cmd_to_title) ? cmd_to_title[cmd] : ""
        gsub(/\t/, " ", title)
        if (length(title) > 50) {
            title = substr(title, 1, 47) "..."
        }
        print $0, title
        next
    }
    {
        print $0
    }
' "$GATE_LOG" > "$tmp_out"

mv "$tmp_out" "$GATE_LOG"

after_nf8=$(awk -F'\t' 'NF==8{c++} END{print c+0}' "$GATE_LOG")
after_nf9=$(awk -F'\t' 'NF==9{c++} END{print c+0}' "$GATE_LOG")

echo "OK: backfill complete"
echo "  updated_rows (8->9): $before_nf8"
echo "  remaining_nf8: $after_nf8"
echo "  nf9_rows: $after_nf9"
