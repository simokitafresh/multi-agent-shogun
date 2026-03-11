#!/usr/bin/env bash
# normalize_report.sh — lesson/decision/skill_candidate旧形式(リスト)→dict形式変換
# 3層防御(C/B/A)の共通関数。全層がこのスクリプトを呼ぶ。
#
# Usage: normalize_report.sh <report_yaml_path>
# Returns: 0 = 修正した(stdout: 修正箇所), 1 = 修正不要
# Note: 冪等。既にdict形式なら何もしない。

set -euo pipefail

REPORT_FILE="${1:-}"

if [ -z "$REPORT_FILE" ]; then
    echo "Usage: normalize_report.sh <report_yaml_path>" >&2
    exit 2
fi

if [ ! -f "$REPORT_FILE" ]; then
    echo "File not found: $REPORT_FILE" >&2
    exit 2
fi

# Python3でYAML操作（既存コードベースと同一手法）
python3 - "$REPORT_FILE" <<'PYEOF'
import yaml, sys, os, tempfile

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

# Atomic write（書き込み中の破損防止）
dir_path = os.path.dirname(os.path.abspath(report_file))
fd, tmp_path = tempfile.mkstemp(dir=dir_path, suffix='.tmp')
try:
    with os.fdopen(fd, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    os.replace(tmp_path, report_file)
except Exception:
    os.unlink(tmp_path)
    raise

for m in modified:
    print(m)

sys.exit(0)
PYEOF
