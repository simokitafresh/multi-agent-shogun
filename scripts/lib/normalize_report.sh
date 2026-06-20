#!/usr/bin/env bash
# normalize_report.sh — lesson/decision/skill_candidate旧形式(リスト)→dict形式変換
# 3層防御(C/B/A)の共通関数。全層がこのスクリプトを呼ぶ。
#
# Usage: normalize_report.sh <report_yaml_path>
# Returns: 0 = 修正した(stdout: 修正箇所), 1 = 修正不要
# Note: 冪等。既にdict形式なら何もしない。

set -euo pipefail

_NR_SELF="${BASH_SOURCE[0]}"
[[ "$_NR_SELF" != /* ]] && _NR_SELF="$PWD/$_NR_SELF"
SCRIPT_DIR="${_NR_SELF%/scripts/lib/normalize_report.sh}"

REPORT_FILE="${1:-}"

if [ -z "$REPORT_FILE" ]; then
    echo "Usage: normalize_report.sh <report_yaml_path>" >&2
    exit 2
fi

if [ ! -f "$REPORT_FILE" ]; then
    echo "File not found: $REPORT_FILE" >&2
    exit 2
fi

# 純bash高速pre-check: 全3候補フィールドがdict形式ならPython不要で即exit 1
# WSL2でPython3起動コスト~100msを回避(フォーク+exec排除)
_nr_fields_found=0
_nr_needs_python=false
_nr_in_candidate=false

while IFS= read -r _nr_line; do
    if [[ "$_nr_line" =~ ^(lesson_candidate|decision_candidate|skill_candidate): ]]; then
        _nr_fields_found=$(( _nr_fields_found + 1 ))
        _nr_in_candidate=true
    elif [[ "$_nr_in_candidate" == "true" ]]; then
        if [[ "$_nr_line" =~ ^[[:space:]]+-[[:space:]] || "$_nr_line" =~ ^-[[:space:]] ]]; then
            # リスト形式発見 → Pythonが必要
            _nr_needs_python=true
            break
        elif [[ -n "$_nr_line" && ! "$_nr_line" =~ ^[[:space:]] && ! "$_nr_line" =~ ^# ]]; then
            # インデントなし行 = フィールド終了
            _nr_in_candidate=false
        fi
    fi
done < "$REPORT_FILE"

# 3フィールド全て存在かつリスト形式なし → 修正不要
if [[ "$_nr_needs_python" == "false" && "$_nr_fields_found" -eq 3 ]]; then
    exit 1
fi

# Python3でYAML操作（既存コードベースと同一手法）
PYTHONPATH="$SCRIPT_DIR" python3 - "$REPORT_FILE" <<'PYEOF'
import yaml, sys, os
from scripts.lib.yaml_atomic import atomic_yaml_write

report_file = sys.argv[1]

try:
    with open(report_file) as f:
        data = yaml.safe_load(f)
except Exception as e:
    print(f"YAML parse error: {e}", file=sys.stderr)
    sys.exit(2)

if not isinstance(data, dict):
    print("Not a valid report YAML (top-level is not dict)", file=sys.stderr)
    sys.exit(2)

CANDIDATE_FIELDS = ["lesson_candidate", "decision_candidate", "skill_candidate"]
modified = []

for field in CANDIDATE_FIELDS:
    value = data.get(field)

    if value is None:
        # フィールド欠落 → dict形式で補完
        data[field] = {"found": False, "title": "", "detail": "", "project": ""}
        modified.append(f"{field}: missing → dict(found=false)")
        continue

    if isinstance(value, list):
        # リスト形式 → dict形式に変換
        if len(value) == 0:
            data[field] = {"found": False, "title": "", "detail": "", "project": ""}
            modified.append(f"{field}: empty list → dict(found=false)")
        else:
            # リストに内容がある場合、found=trueとして内容を保持
            items_text = "\n".join(str(item) for item in value)
            first_item = str(value[0])
            title = first_item[:100] if len(first_item) > 100 else first_item
            data[field] = {
                "found": True,
                "title": title,
                "detail": items_text,
                "project": ""
            }
            modified.append(f"{field}: list({len(value)} items) → dict(found=true)")
        continue

    if isinstance(value, dict):
        # 既にdict形式 → 何もしない（冪等）
        continue

    # str等の不正型 → dict形式に変換
    data[field] = {"found": False, "title": "", "detail": str(value), "project": ""}
    modified.append(f"{field}: {type(value).__name__} → dict(found=false)")

if not modified:
    sys.exit(1)  # 修正不要

atomic_yaml_write(report_file, data, sort_keys=False)

for m in modified:
    print(m)

sys.exit(0)
PYEOF
