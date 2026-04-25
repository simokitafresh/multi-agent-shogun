#!/usr/bin/env bash
# gate_autofix_proposal.sh — 直近BLOCKパターンから instructions 修正提案を自動起票
# 目的: idle時に「頻出BLOCKをどの指示で潰すべきか」を queue/insights.yaml へ還流する
# Usage: bash scripts/gates/gate_autofix_proposal.sh

set -euo pipefail

REPO_ROOT="${SHOGUN_STARTUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_FILE="$REPO_ROOT/logs/gate_metrics.log"
INSIGHT_SCRIPT="$REPO_ROOT/scripts/insight_write.sh"
WINDOW="${GATE_AUTOFIX_WINDOW:-50}"
MIN_COUNT="${GATE_AUTOFIX_MIN_COUNT:-3}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "SKIP: gate_metrics.log not found"
    exit 0
fi

_tmp_recent="$(mktemp)"
trap 'rm -f "$_tmp_recent"' EXIT

awk -F'\t' -v limit="$WINDOW" '
    $3 == "BLOCK" {
        print
        c++
        if (c >= limit) {
            exit
        }
    }
' < <(tac "$LOG_FILE") > "$_tmp_recent"

if [[ ! -s "$_tmp_recent" ]]; then
    echo "NO DATA: recent BLOCK rows not found"
    exit 0
fi

python3 - "$REPO_ROOT" "$INSIGHT_SCRIPT" "$MIN_COUNT" "$WINDOW" "$_tmp_recent" <<'PY'
import os
import subprocess
import sys
from collections import Counter, defaultdict

repo_root = sys.argv[1]
insight_script = sys.argv[2]
min_count = int(sys.argv[3])
window = int(sys.argv[4])
recent_path = sys.argv[5]

PROPOSAL_MAP = {
    "report_format": {
        "category": "report_yaml",
        "target": "instructions/ashigaru-procedures.md",
        "action": "report_field_set.sh再実行手順と提出前gate再確認を先頭へ固定化",
    },
    "fill_this_remaining": {
        "category": "report_yaml",
        "target": "instructions/ashigaru-procedures.md",
        "action": "FILL_THIS全置換と提出前grep確認を報告手順へ追記",
    },
    "binary_checks_fail": {
        "category": "report_yaml",
        "target": "instructions/ashigaru.md",
        "action": "binary_checksは全AC yes/no必須を記入例付きで強調",
    },
    "purpose_validation_fit_false": {
        "category": "scope_alignment",
        "target": "instructions/ashigaru.md",
        "action": "purpose_validation記入前にcmd目的との差分確認を必須化",
    },
    "draft_lessons": {
        "category": "lesson_flow",
        "target": "instructions/karo.md",
        "action": "draft lessons解消手順と完了条件をレビュー工程に追記",
    },
    "ac_version_mismatch": {
        "category": "task_sync",
        "target": "instructions/ashigaru.md",
        "action": "復帰時のtask再読込とac_version_read同期確認を提出前必須化",
    },
}


def normalize_reason(raw):
    raw = raw.strip()
    if not raw:
        return None

    tokens = [token.strip() for token in raw.split(":") if token.strip()]
    if not tokens:
        return None

    if tokens[0] == "report_format":
        return "report_format"
    if "fill_this_remaining" in tokens:
        return "fill_this_remaining"
    if "binary_checks_fail" in tokens:
        return "binary_checks_fail"
    if "purpose_validation_fit_false" in tokens:
        return "purpose_validation_fit_false"
    if tokens[0] == "draft_lessons":
        return "draft_lessons"
    if "ac_version_mismatch" in tokens:
        return "ac_version_mismatch"
    return raw


pattern_counts = Counter()
pattern_examples = defaultdict(list)
rows = []

with open(recent_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        rows.append(line)
        cols = line.split("\t")
        if len(cols) < 4:
            continue
        reason_text = cols[3].strip()
        if not reason_text:
            continue
        for raw_reason in reason_text.split("|"):
            normalized = normalize_reason(raw_reason)
            if not normalized:
                continue
            pattern_counts[normalized] += 1
            bucket = pattern_examples[normalized]
            example = raw_reason.strip()
            if example and example not in bucket and len(bucket) < 3:
                bucket.append(example)

print("=== Auto-Fix Proposal Scan ===")
print(f"Recent BLOCK window: {window}")
print(f"Analyzed BLOCK rows: {len(rows)}")
print("Recurring patterns:")
for pattern, count in pattern_counts.most_common():
    category = PROPOSAL_MAP.get(pattern, {}).get("category", "other")
    examples = " ; ".join(pattern_examples.get(pattern, [])[:2]) or "-"
    print(f"  [{count}] {pattern} :: {category} :: {examples}")

print(f"Proposal threshold: {min_count}")
created = 0

if not os.path.isfile(insight_script):
    print("Proposals:")
    print("  SKIP: insight_write.sh not found")
    sys.exit(0)

print("Proposals:")
for pattern, count in pattern_counts.most_common():
    spec = PROPOSAL_MAP.get(pattern)
    if spec is None or count < min_count:
        continue

    examples = " ; ".join(pattern_examples.get(pattern, [])[:2])
    message = (
        f"AUTOFIX-PROPOSAL: {pattern} -> {spec['target']} :: {spec['action']} "
        f"(recent{window}={count}; category={spec['category']}; examples={examples})"
    )
    try:
        result = subprocess.run(
            ["bash", insight_script, message, "high", "gate_autofix_proposal"],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
            cwd=repo_root,
        )
        output = (result.stdout or result.stderr).strip() or "NO_OUTPUT"
        print(f"  {pattern}: {output}")
        created += 1
    except Exception as exc:
        print(f"  {pattern}: ERROR:{exc}")

if created == 0:
    print("  none")
PY
