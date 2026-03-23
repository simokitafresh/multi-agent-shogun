#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMPACT_FILE="$SCRIPT_DIR/logs/lesson_impact.tsv"
METRICS_FILE="$SCRIPT_DIR/logs/gate_metrics.log"
REPORT_DIR="$SCRIPT_DIR/queue/reports"
ARCHIVE_REPORT_DIR="$SCRIPT_DIR/queue/archive/reports"

if [[ ! -f "$IMPACT_FILE" ]]; then
    echo "[ERROR] lesson_impact.tsv not found: $IMPACT_FILE" >&2
    exit 1
fi
if [[ ! -f "$METRICS_FILE" ]]; then
    echo "[ERROR] gate_metrics.log not found: $METRICS_FILE" >&2
    exit 1
fi

python3 - "$IMPACT_FILE" "$METRICS_FILE" "$REPORT_DIR" "$ARCHIVE_REPORT_DIR" <<'PY'
import csv
import os
import re
import sys
import tempfile

impact_file = sys.argv[1]
metrics_file = sys.argv[2]
report_dir = sys.argv[3]
archive_report_dir = sys.argv[4]

# --- Step 1: Build cmd -> final result map from gate_metrics.log ---
# gate_metrics.log format: timestamp\tcmd_id\tresult\tdetails\t...
# Multiple entries per cmd possible; last one wins (final result)
cmd_results = {}
with open(metrics_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        cmd_id = parts[1].strip()
        result = parts[2].strip()
        if result in ("CLEAR", "BLOCK"):
            cmd_results[cmd_id] = result

# --- Step 2: Build report file existence set ---
# Scan both current and archive report dirs
# Extract cmd_NNN from filenames to build a set of cmds with reports
report_cmds = set()
for d in [report_dir, archive_report_dir]:
    if not os.path.isdir(d):
        continue
    for fname in os.listdir(d):
        m = re.search(r"(cmd_\d+)", fname)
        if m:
            report_cmds.add(m.group(1))

# --- Step 3: Read, count, and update ---
rows = []
header = None
pending_before = 0
ref_pending_before = 0
updated_clear = 0
updated_block = 0
updated_skipped = 0
ref_updated_yes = 0
ref_updated_no = 0

with open(impact_file, "r", encoding="utf-8", newline="") as f:
    reader = csv.reader(f, delimiter="\t")
    header = next(reader)
    for row in reader:
        # Pad short rows
        while len(row) < len(header):
            row.append("")

        cmd_id_full = row[1].strip()
        result_val = row[5].strip()
        referenced_val = row[6].strip()

        # Extract base cmd_id (cmd_NNN) for prefix matching
        m = re.match(r"(cmd_\d+)", cmd_id_full)
        base_cmd = m.group(1) if m else cmd_id_full

        # Update result column for pending rows
        if result_val == "pending":
            pending_before = pending_before + 1
            if base_cmd in cmd_results:
                row[5] = cmd_results[base_cmd]
                if cmd_results[base_cmd] == "CLEAR":
                    updated_clear = updated_clear + 1
                else:
                    updated_block = updated_block + 1
            else:
                row[5] = "skipped"
                updated_skipped = updated_skipped + 1

        # Update referenced column for pending rows
        if referenced_val == "pending":
            ref_pending_before = ref_pending_before + 1
            if base_cmd in report_cmds:
                row[6] = "yes"
                ref_updated_yes = ref_updated_yes + 1
            else:
                row[6] = "no"
                ref_updated_no = ref_updated_no + 1

        rows.append(row)

# --- Pre-update counts ---
total_rows = len(rows)
print(f"=== backfill_lesson_impact.sh ===")
print(f"total rows (excl header): {total_rows}")
print(f"gate_metrics unique cmds: {len(cmd_results)}")
print(f"report files found (unique cmds): {len(report_cmds)}")
print()
print(f"--- result column ---")
print(f"pending before: {pending_before}")
print(f"  -> CLEAR:   {updated_clear}")
print(f"  -> BLOCK:   {updated_block}")
print(f"  -> skipped: {updated_skipped}")
pending_after = sum(1 for r in rows if r[5].strip() == "pending")
print(f"pending after:  {pending_after}")
print()
print(f"--- referenced column ---")
print(f"pending before: {ref_pending_before}")
print(f"  -> yes: {ref_updated_yes}")
print(f"  -> no:  {ref_updated_no}")
ref_pending_after = sum(1 for r in rows if r[6].strip() == "pending")
print(f"pending after:  {ref_pending_after}")

# --- Step 4: Write back atomically ---
dir_name = os.path.dirname(impact_file)
with tempfile.NamedTemporaryFile(
    mode="w", encoding="utf-8", newline="",
    dir=dir_name, suffix=".tmp", delete=False
) as tmp:
    writer = csv.writer(tmp, delimiter="\t", lineterminator="\n")
    writer.writerow(header)
    for row in rows:
        writer.writerow(row)
    tmp_path = tmp.name

os.replace(tmp_path, impact_file)
print()
print(f"[OK] {impact_file} updated.")
PY
