#!/bin/bash
# auto_failure_lesson.sh — 失敗タスクの報告YAMLから自動でdraft教訓を生成
# Usage: bash scripts/auto_failure_lesson.sh <report_yaml_path>
# - status: failed → lesson_write.sh --status draft で登録
# - status: done/その他 → 何もしない (exit 0)
# - failure_analysis.root_cause があれば抽出、なければ result.summary から要約
# - タイトルに「[自動生成]」プレフィックスを付与
# - projectは report YAMLの parent_cmd → shogun_to_karo.yaml から取得

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${1:-}"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "[auto_failure] Usage: auto_failure_lesson.sh <report_yaml_path>" >&2
    exit 1
fi

# Extract failure info from report YAML
export REPORT_PATH SCRIPT_DIR
extract_result=$(python3 << 'PYEOF'
import yaml, os, sys, json, re

report_path = os.environ["REPORT_PATH"]
script_dir = os.environ["SCRIPT_DIR"]

with open(report_path, encoding='utf-8') as f:
    data = yaml.safe_load(f)

if not data:
    print(json.dumps({"action": "skip", "reason": "no_data"}))
    sys.exit(0)

# L010: status check — use top-level status only (safe_load handles this)
status = data.get("status", "")
if status != "failed":
    print(json.dumps({"action": "skip", "reason": f"status_not_failed ({status})"}))
    sys.exit(0)

task_id = data.get("task_id", "unknown")
parent_cmd = data.get("parent_cmd", "")
worker_id = data.get("worker_id", "auto_failure")
result = data.get("result", {}) or {}
summary = result.get("summary", "").strip()
notes = result.get("notes", "").strip()
failure_analysis = data.get("failure_analysis", {}) or {}
root_cause = failure_analysis.get("root_cause", "").strip()
what_would_prevent = failure_analysis.get("what_would_prevent", "").strip()

# Get project from parent_cmd → shogun_to_karo.yaml
project = ""
if parent_cmd:
    stk_path = os.path.join(script_dir, "queue", "shogun_to_karo.yaml")
    if os.path.exists(stk_path):
        with open(stk_path, encoding='utf-8') as f:
            stk = yaml.safe_load(f)
        for cmd in stk.get("commands", []):
            if cmd.get("id") == parent_cmd:
                project = cmd.get("project", "")
                break

# Fallback: no project found
if not project:
    print(json.dumps({"action": "skip", "reason": "no_project_found"}))
    sys.exit(0)

# Build lesson title using failure category templates
title_prefix = "[自動生成]"

# Detect failure category from summary/notes/root_cause
combined_text = f"{summary} {notes} {root_cause}".lower()

if any(kw in combined_text for kw in ["timeout", "タイムアウト", "timed out", "time out"]):
    title = f"{title_prefix} タイムアウト失敗: {task_id}"
elif any(kw in combined_text for kw in ["syntax", "構文", "syntaxerror", "parse error", "実行エラー"]):
    title = f"{title_prefix} 構文/実行エラー: {task_id}"
elif any(kw in combined_text for kw in ["ac未達", "acceptance", "未達", "未完了", "not met"]):
    # Extract brief AC summary if possible
    ac_brief = summary[:50] if summary else notes[:50] if notes else ""
    title = f"{title_prefix} AC未達: {task_id} — {ac_brief}" if ac_brief else f"{title_prefix} AC未達: {task_id}"
else:
    brief = summary[:50] if summary else notes[:50] if notes else "詳細不明"
    title = f"{title_prefix} タスク失敗: {task_id} — {brief}"

# Build lesson detail
if root_cause and what_would_prevent:
    detail = f"根本原因: {root_cause}。防止策: {what_would_prevent}"
elif root_cause:
    detail = f"根本原因: {root_cause}。失敗summary: {summary}" if summary else f"根本原因: {root_cause}"
elif summary:
    detail = f"失敗報告: {summary}"
    if notes:
        detail += f"。備考: {notes}"
else:
    detail = f"タスク{task_id}が失敗。詳細な分析情報なし"

# Ensure detail is at least 10 chars (lesson_write.sh quality gate)
if len(detail) < 10:
    detail = detail + f" (task_id: {task_id})"

print(json.dumps({
    "action": "register",
    "project": project,
    "title": title,
    "detail": detail,
    "source_cmd": parent_cmd,
    "author": worker_id,
    "task_id": task_id
}))
PYEOF
)

# Parse JSON result
action=$(echo "$extract_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('action','skip'))")

if [ "$action" = "skip" ]; then
    reason=$(echo "$extract_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason',''))")
    echo "[auto_failure] Skipped: ${reason} (${REPORT_PATH})"
    exit 0
fi

# Extract fields
PROJECT=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['project'])")
TITLE=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['title'])")
DETAIL=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['detail'])")
SOURCE_CMD=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['source_cmd'])")
AUTHOR=$(echo "$extract_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['author'])")

# Call lesson_write.sh with --status draft
echo "[auto_failure] Registering draft lesson: project=$PROJECT title=$TITLE source=$SOURCE_CMD"
bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$PROJECT" "$TITLE" "$DETAIL" "$SOURCE_CMD" "$AUTHOR" "" --status draft

echo "[auto_failure] Draft lesson registered successfully"
