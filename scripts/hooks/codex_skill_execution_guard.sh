#!/usr/bin/env bash
# Codex PreToolUse adapter: persist Skill receipts and block actionable tools
# while an explicitly-required recommended skill has no receipt for this task.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${SHOGUN_REPO_ROOT:-${_self%/scripts/hooks/codex_skill_execution_guard.sh}}"

payload="$(cat 2>/dev/null || true)"
[[ -n "${payload//[[:space:]]/}" ]] || exit 0

tool_name="$(jq -r '.tool_name // .tool // .name // empty' <<<"$payload" 2>/dev/null || true)"
agent="${SHOGUN_AGENT_ID:-}"
if [[ -z "$agent" && -n "${TMUX_PANE:-}" ]]; then
    agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
[[ -n "$agent" ]] || agent="unknown"

task_file="${SHOGUN_TASK_FILE:-$ROOT/queue/tasks/${agent}.yaml}"
[[ -f "$task_file" ]] || exit 0

task_id="$(python3 - "$task_file" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
task = data.get("task") or {}
print(str(task.get("task_id") or task.get("parent_cmd") or ""))
PY
)"
[[ -n "$task_id" ]] || exit 0

if [[ "$tool_name" == "Skill" ]]; then
    skill="$(jq -r '.tool_input.skill // .tool_input.name // .input.skill // .input.name // empty' <<<"$payload" 2>/dev/null || true)"
    skill="${skill#/}"
    [[ -n "$skill" ]] || exit 0
    log_script="$ROOT/scripts/skill_execution_log.sh"
    if [[ -x "$log_script" ]]; then
        SKILL_EXECUTION_LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$ROOT/logs/skill_execution_log.yaml}" \
            bash "$log_script" "$skill" "$agent" PASS "" codex_pretool "$task_id" "$ROOT/skills/$skill/SKILL.md" true
    fi
    exit 0
fi

case "$tool_name" in
    Bash|exec_command|unified_exec|Write|Edit|MultiEdit|apply_patch) ;;
    *) exit 0 ;;
esac

missing="$(
python3 - "$task_file" "${SKILL_EXECUTION_LOG_FILE:-$ROOT/logs/skill_execution_log.yaml}" "$task_id" "$agent" <<'PY'
import sys, yaml

task_path, log_path, task_id, agent = sys.argv[1:]
task_doc = yaml.safe_load(open(task_path, encoding="utf-8")) or {}
task = task_doc.get("task") or {}
if str(task.get("status") or "") not in {"assigned", "acknowledged", "in_progress"}:
    raise SystemExit

required = set()
for value in task.get("required_recommended_skills") or []:
    required.add(str(value).strip().lstrip("/"))

recommended = task.get("recommended_skills") or []
if task.get("recommended_skills_required") is True:
    for value in recommended:
        if isinstance(value, dict):
            value = value.get("name") or value.get("skill")
        required.add(str(value).strip().lstrip("/"))
else:
    for value in recommended:
        if isinstance(value, dict) and value.get("required") is True:
            required.add(str(value.get("name") or value.get("skill") or "").strip().lstrip("/"))

required.discard("")
if not required:
    raise SystemExit

try:
    log_doc = yaml.safe_load(open(log_path, encoding="utf-8")) or {}
except (FileNotFoundError, yaml.YAMLError):
    log_doc = {}

used = set()
for entry in log_doc.get("executions") or []:
    if not isinstance(entry, dict):
        continue
    if str(entry.get("executor") or "") != agent:
        continue
    if str(entry.get("source") or "") != task_id:
        continue
    if str(entry.get("result") or "").upper() != "PASS":
        continue
    if str(entry.get("used", "true")).lower() == "false":
        continue
    used.add(str(entry.get("skill") or "").strip().lstrip("/"))

print(",".join(sorted(required - used)))
PY
)"

if [[ -n "$missing" ]]; then
    printf 'BLOCK: required recommended skill receipt missing for task=%s agent=%s skills=%s\n' \
        "$task_id" "$agent" "$missing" >&2
    exit 2
fi

