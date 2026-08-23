#!/usr/bin/env bash
# Codex PreToolUse adapter: persist Skill receipts and block actionable tools
# while an explicitly-required recommended skill has no receipt for this task.
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
ROOT="${SHOGUN_REPO_ROOT:-${_self%/scripts/hooks/codex_skill_execution_guard.sh}}"

CODEX_SKILL_EXECUTION_GUARD_TOTAL_T0_US="${EPOCHREALTIME/./}"
CODEX_SKILL_EXECUTION_GUARD_TOTAL_T0_US="${CODEX_SKILL_EXECUTION_GUARD_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$ROOT}"
if [[ -f "$ROOT/scripts/lib/defense_overhead_writer.sh" ]]; then
    source "$ROOT/scripts/lib/defense_overhead_writer.sh"
else
    defense_overhead_write_async() { return 0; }
fi
CODEX_SKILL_EXECUTION_GUARD_TOTAL_RECORDED=0
codex_skill_execution_guard_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${CODEX_SKILL_EXECUTION_GUARD_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    CODEX_SKILL_EXECUTION_GUARD_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - CODEX_SKILL_EXECUTION_GUARD_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async codex_skill_execution_guard codex_skill_execution_guard_total "$wall_ms" "$verdict" \
        "codex-skill-execution-guard-${BASHPID}-${CODEX_SKILL_EXECUTION_GUARD_TOTAL_T0_US}" || true
}
codex_skill_execution_guard_total_on_exit() { local rc=$?; codex_skill_execution_guard_record_total "$rc"; return "$rc"; }
trap codex_skill_execution_guard_total_on_exit EXIT

payload="$(cat 2>/dev/null || true)"
[[ -n "${payload//[[:space:]]/}" ]] || exit 0

tool_name="$(jq -r '.tool_name // .tool // .name // empty' <<<"$payload" 2>/dev/null || true)"
agent="${SHOGUN_AGENT_ID:-}"
if [[ -z "$agent" && -n "${TMUX_PANE:-}" ]]; then
    agent="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
[[ -n "$agent" ]] || agent="unknown"

# Every PreToolUse action reaches the same evidence verifier.  In particular,
# Read, Skill, taskless roles, and non-shell tools must not bypass the
# Bash/Write path.
tool_target="$(jq -r '.tool_input.file_path // .tool_input.filePath // .tool_input.path // .input.file_path // .input.path // empty' <<<"$payload" 2>/dev/null || true)"
command="$(jq -r '.tool_input.command // .tool_input.cmd // .input.command // .input.cmd // empty' <<<"$payload" 2>/dev/null || true)"
if [[ ! -x "$ROOT/scripts/hooks/three_layer_preflight.sh" ]]; then
    printf 'BLOCK: 三層preflight scriptが欠落。全PreToolUse actionをfail-closedで停止\n' >&2
    exit 2
fi
if ! bash "$ROOT/scripts/hooks/three_layer_preflight.sh" verify "$tool_name" "$tool_target" "$command" >/dev/null 2>&1; then
    printf 'BLOCK: 三層preflight証跡なし/無効。全PreToolUse actionは記憶DB・semantic・Obsidian検索後に実行せよ\n' >&2
    exit 2
fi

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
