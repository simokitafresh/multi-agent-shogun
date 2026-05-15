#!/bin/bash
# auto_failure_lesson.sh — 失敗タスクの報告YAMLから自動でconfirmed教訓を生成
# Usage: bash scripts/auto_failure_lesson.sh <report_yaml_path>
# - status: failed → lesson_write.sh --status confirmed で登録
# - status: done/その他 → 何もしない (exit 0)
# - failure_analysis.root_cause があれば抽出、なければ result.summary から要約
# - gate_fire_logのFAIL原因がスクリプトバグ系なら将軍へ修正cmd起票を要請
# - タイトルに「[自動生成]」プレフィックスを付与
# - projectは report YAMLの parent_cmd → shogun_to_karo.yaml から取得

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="${1:-}"
BULLETIN_SCRIPT="${AUTO_FAILURE_BULLETIN_SCRIPT:-$SCRIPT_DIR/scripts/bulletin_write.sh}"

if [ -z "$REPORT_PATH" ] || [ ! -f "$REPORT_PATH" ]; then
    echo "[auto_failure] Usage: auto_failure_lesson.sh <report_yaml_path>" >&2
    exit 1
fi

# Extract failure info from report YAML
export REPORT_PATH SCRIPT_DIR
extract_result=$(python3 << 'PYEOF'
import yaml, os, sys, json

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

def _extract_field(line, field):
    marker = f'{field}: "'
    start = line.find(marker)
    if start >= 0:
        start += len(marker)
        end = line.find('"', start)
        return line[start:] if end < 0 else line[start:end]
    marker = f"{field}: "
    start = line.find(marker)
    if start < 0:
        return ""
    start += len(marker)
    end = line.find(",", start)
    value = line[start:] if end < 0 else line[start:end]
    return value.strip().strip('"')

def _norm_path(value):
    if not value:
        return ""
    value = os.path.abspath(value) if value.startswith("/") else os.path.normpath(value)
    return value

def _gate_fail_context(report_path):
    log_path = os.path.join(script_dir, "logs", "gate_fire_log.yaml")
    if not os.path.exists(log_path):
        return {"reason": "", "line": "", "classification": "unknown"}

    abs_report = os.path.abspath(report_path)
    rel_report = os.path.relpath(abs_report, script_dir)
    candidates = {abs_report, rel_report, os.path.normpath(report_path)}
    latest = ""
    try:
        with open(log_path, encoding="utf-8") as f:
            for line in f:
                if "result: FAIL" not in line:
                    continue
                file_value = _extract_field(line, "file")
                if not file_value:
                    continue
                normalized = _norm_path(file_value)
                if file_value in candidates or normalized in candidates or os.path.abspath(file_value) == abs_report:
                    latest = line.strip()
    except OSError:
        return {"reason": "", "line": "", "classification": "unknown"}

    if not latest:
        return {"reason": "", "line": "", "classification": "none"}

    reason = _extract_field(latest, "reasons")
    text = f"{reason} {latest}".lower()
    usage_markers = [
        "field_missing", "fill_this", "binary_checks", "lesson_candidate",
        "lessons_useful", "verdict", "status_valid", "purpose_validation",
        "assumption_invalidation", "self_gate_check", "report yaml",
        "missing", "must be dict", "must be list", "empty_lessons_useful",
    ]
    script_markers = [
        "script_error", "script error", "スクリプトエラー", "exit=1", "exit 1",
        "exit code 1", "traceback", "exception", "command not found",
        "syntax error", "unbound variable", "permission denied", "no such file",
        "python error", "runtime error",
    ]
    if any(marker in text for marker in script_markers) and not any(marker in text for marker in usage_markers):
        classification = "script_bug"
    else:
        classification = "usage_error"
    return {"reason": reason, "line": latest, "classification": classification}

gate_fail = _gate_fail_context(report_path)

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
    "task_id": task_id,
    "gate_fail_classification": gate_fail["classification"],
    "gate_fail_reason": gate_fail["reason"],
    "gate_fail_line": gate_fail["line"],
}))
PYEOF
)

# Validate extraction result
if [ -z "$extract_result" ]; then
    echo "[auto_failure] Error: extraction produced empty output (${REPORT_PATH})" >&2
    exit 1
fi

# Parse all JSON fields in a single python3 call (was 6 separate invocations)
action="" reason="" PROJECT="" TITLE="" DETAIL="" SOURCE_CMD="" AUTHOR=""
GATE_FAIL_CLASSIFICATION="" GATE_FAIL_REASON=""
eval "$(echo "$extract_result" | python3 -c "
import json, sys, shlex
d = json.load(sys.stdin)
mapping = [
    ('action', 'action', 'skip'),
    ('reason', 'reason', ''),
    ('project', 'PROJECT', 'unknown'),
    ('title', 'TITLE', 'unknown'),
    ('detail', 'DETAIL', ''),
    ('source_cmd', 'SOURCE_CMD', 'unknown'),
    ('author', 'AUTHOR', 'unknown'),
    ('gate_fail_classification', 'GATE_FAIL_CLASSIFICATION', ''),
    ('gate_fail_reason', 'GATE_FAIL_REASON', ''),
]
for json_key, var_name, default in mapping:
    v = d.get(json_key, default)
    print(f'{var_name}={shlex.quote(str(v))}')
")"

# Validate that eval properly populated action (guard against JSON parse failure)
if [ -z "$action" ]; then
    echo "[auto_failure] Error: JSON parse failed — extraction result unparseable (${REPORT_PATH})" >&2
    exit 1
fi

if [ "$action" = "skip" ]; then
    echo "[auto_failure] Skipped: ${reason} (${REPORT_PATH})"
    exit 0
fi

# Call lesson_write.sh with --status confirmed
echo "[auto_failure] Registering confirmed lesson: project=$PROJECT title=$TITLE source=$SOURCE_CMD"
bash "$SCRIPT_DIR/scripts/lesson_write.sh" "$PROJECT" "$TITLE" "$DETAIL" "$SOURCE_CMD" "$AUTHOR" "" --status confirmed

if [ "$GATE_FAIL_CLASSIFICATION" = "script_bug" ] && [ -x "$BULLETIN_SCRIPT" ]; then
    bulletin_content="auto_failure_lesson: ${SOURCE_CMD}/${AUTHOR} の失敗はスクリプトバグ疑い。将軍はコード修正cmdを起票されたし。gate_reason=${GATE_FAIL_REASON:-unknown}"
    if BULLETIN_NOTIFY=shogun bash "$BULLETIN_SCRIPT" karo "$bulletin_content" false action_required >/dev/null 2>&1; then
        echo "[auto_failure] Script-bug bulletin requested: source=$SOURCE_CMD"
    else
        echo "[auto_failure] WARN: script-bug bulletin failed (non-blocking)" >&2
    fi
fi

echo "[auto_failure] Confirmed lesson registered successfully"
