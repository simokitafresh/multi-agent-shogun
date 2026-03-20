#!/usr/bin/env bash
# ============================================================
# gate_dc_duplicate.sh
# Decision candidate duplicate check against resolved pending_decisions
#
# Usage:
#   bash scripts/gates/gate_dc_duplicate.sh <report_yaml>
#
# Input: report YAML file path
# Checks: decision_candidate against queue/pending_decisions.yaml resolved entries
# Logic:
#   - decision_candidate missing or found: false → SKIP (exit 0)
#   - Full match (DC title == resolved summary) → BLOCK (exit 1)
#   - Partial match (3+ common keywords) → WARN (exit 0)
#   - No match → OK (exit 0)
#
# Exit code: 0=OK/WARN/SKIP, 1=BLOCK
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PENDING_DECISIONS="$SCRIPT_DIR/queue/pending_decisions.yaml"

REPORT_FILE="${1:-}"

if [ -z "$REPORT_FILE" ]; then
    echo "SKIP: no report file specified"
    exit 0
fi

if [ ! -f "$REPORT_FILE" ]; then
    echo "SKIP: report file not found: $REPORT_FILE"
    exit 0
fi

if [ ! -f "$PENDING_DECISIONS" ]; then
    echo "SKIP: pending_decisions.yaml not found"
    exit 0
fi

# Run python3 for YAML parsing + comparison
REPORT_FILE_ENV="$REPORT_FILE" PD_FILE_ENV="$PENDING_DECISIONS" python3 - <<'PYEOF'
import os
import sys
import re
import yaml

report_file = os.environ["REPORT_FILE_ENV"]
pd_file = os.environ["PD_FILE_ENV"]

def extract_keywords(text):
    """Extract meaningful keywords from text. Splits CJK/ASCII boundaries."""
    if not text:
        return set()
    text = str(text).lower()
    # Insert space at CJK↔ASCII boundaries to split mixed tokens
    text = re.sub(r'([a-z0-9])([^\x00-\x7f])', r'\1 \2', text)
    text = re.sub(r'([^\x00-\x7f])([a-z0-9])', r'\1 \2', text)
    # Split on whitespace + common delimiters + Japanese particles
    tokens = re.split(r'[\s,.:;!?()（）【】「」→←↔+/\\|=<>{}\[\]・、。：；\n\'\"]+|(?:の件|について|のみ|が必要|を殿|か殿|の裁定|で殿|(?<=.)の(?=.)|(?<=.)を(?=.)|(?<=.)が(?=.)|(?<=.)で(?=.)|(?<=.)は(?=.)|(?<=.)に(?=.)|(?<=.)か(?=.)|(?<=.)も(?=.)|(?<=.)と(?=.))', text)
    stop_words = {
        'the', 'and', 'for', 'that', 'this', 'with', 'from',
        'are', 'was', 'has', 'not', 'but', 'can', 'will', 'all',
    }
    return {t for t in tokens if len(t) >= 2 and t not in stop_words}

# Parse report YAML
try:
    with open(report_file, encoding="utf-8") as f:
        report_data = yaml.safe_load(f) or {}
except Exception:
    print("SKIP: report YAML parse error")
    sys.exit(0)

dc = report_data.get("decision_candidate")
if dc is None or not isinstance(dc, dict):
    print("SKIP: decision_candidate not found")
    sys.exit(0)

if dc.get("found") is not True:
    print("SKIP: decision_candidate.found is not true")
    sys.exit(0)

# Extract DC text for comparison
dc_title = str(dc.get("title", "") or "").strip()
dc_detail = str(dc.get("detail", "") or "").strip()
dc_summary = str(dc.get("summary", "") or "").strip()
dc_text = f"{dc_title} {dc_detail} {dc_summary}".strip()

if not dc_text:
    print("SKIP: decision_candidate has no text content")
    sys.exit(0)

dc_keywords = extract_keywords(dc_text)

# Parse pending_decisions YAML
try:
    with open(pd_file, encoding="utf-8") as f:
        pd_data = yaml.safe_load(f) or {}
except Exception:
    print("SKIP: pending_decisions.yaml parse error")
    sys.exit(0)

decisions = pd_data.get("decisions", [])
if not decisions:
    print("OK: no resolved decisions to compare against")
    sys.exit(0)

resolved = [d for d in decisions if isinstance(d, dict) and d.get("status") == "resolved"]
if not resolved:
    print("OK: no resolved decisions to compare against")
    sys.exit(0)

# Check for matches
block_matches = []
warn_matches = []

for rd in resolved:
    rd_id = str(rd.get("id", "?"))
    rd_summary = str(rd.get("summary", "") or "").strip()
    rd_resolution = str(rd.get("resolution", "") or "").strip()
    rd_resolved_content = str(rd.get("resolved_content", "") or "").strip()
    rd_text = f"{rd_summary} {rd_resolution} {rd_resolved_content}"

    # Full match: DC title exactly matches resolved summary
    if dc_title and rd_summary and dc_title == rd_summary:
        block_matches.append(rd_id)
        continue

    # Partial match: 3+ common keywords
    rd_keywords = extract_keywords(rd_text)
    common = dc_keywords & rd_keywords
    if len(common) >= 3:
        warn_matches.append((rd_id, common))

if block_matches:
    print(f"BLOCK: decision_candidate is exact duplicate of resolved: {', '.join(block_matches)}")
    sys.exit(1)

if warn_matches:
    for rd_id, common in warn_matches:
        top_keywords = sorted(common)[:5]
        print(f"WARN: decision_candidate partially overlaps with {rd_id} (common: {', '.join(top_keywords)})")
    sys.exit(0)

print("OK: no duplicate with resolved decisions")
sys.exit(0)
PYEOF
