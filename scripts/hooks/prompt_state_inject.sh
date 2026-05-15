#!/usr/bin/env bash
# @source: cmd_452 (UserPromptSubmit snapshot注入hook)
set -eu

_prompt_state_self="${BASH_SOURCE[0]}"
[[ "$_prompt_state_self" != /* ]] && _prompt_state_self="$PWD/$_prompt_state_self"
SCRIPT_DIR="${_prompt_state_self%/scripts/hooks/prompt_state_inject.sh}"
unset _prompt_state_self

_prompt_state_json_get() {
  local _prompt_state_field="$1"
  local _prompt_state_default="$2"
  local _prompt_state_value

  if [[ "$_prompt_state_field" == ".prompt" ]]; then
    if _prompt_state_value="$(jq -r 'try (.prompt // "") catch ""' 2>/dev/null <<<"$payload")"; then
      printf '%s' "$_prompt_state_value"
      return 0
    fi
  fi

  JSON_PAYLOAD="$payload" JSON_FIELD="$_prompt_state_field" JSON_DEFAULT="$_prompt_state_default" python3 - <<'PY'
import json
import os
import sys

payload = os.environ.get("JSON_PAYLOAD", "")
field = os.environ.get("JSON_FIELD", "")
default = os.environ.get("JSON_DEFAULT", "")

try:
    obj = json.loads(payload)
except Exception:
    raise SystemExit(1)

field_map = {
    ".prompt": "prompt",
}
key = field_map.get(field)
if key is None:
    raise SystemExit(1)

value = obj.get(key, default)
if value is None:
    value = default
if not isinstance(value, str):
    value = str(value)
sys.stdout.write(value)
PY
}

_prompt_state_emit_output() {
  local _prompt_state_event="$1"
  local _prompt_state_context="$2"
  local _prompt_state_json

  if _prompt_state_json="$(jq -Rs --arg event_name "$_prompt_state_event" '{hookSpecificOutput:{hookEventName:$event_name,additionalContext:.}}' 2>/dev/null <<<"$_prompt_state_context")"; then
    printf '%s\n' "$_prompt_state_json"
    return 0
  fi

  printf '%s' "$_prompt_state_context" | HOOK_EVENT_NAME="$_prompt_state_event" python3 -c '
import json
import os
import sys

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": os.environ["HOOK_EVENT_NAME"],
        "additionalContext": sys.stdin.read(),
    }
}, ensure_ascii=False))
'
}

# --- Read stdin JSON (type: user_prompt_submit) ---
payload="$(cat 2>/dev/null || true)"
if [[ -z "$payload" ]]; then
  exit 0
fi

prompt_text="$(_prompt_state_json_get ".prompt" "")" || {
  exit 0
}

# --- Get agent_id from tmux ---
agent_id="unknown"
if command -v tmux >/dev/null 2>&1; then
  if [[ -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  elif [[ -n "${TMUX:-}" ]]; then
    agent_id="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || echo "unknown")"
  fi
fi
if [[ -z "$agent_id" ]]; then
  agent_id="unknown"
fi
agent_id="${PROMPT_STATE_AGENT_ID:-$agent_id}"

# --- shogun only (exit 0 for all others) ---
if [[ "$agent_id" != "shogun" ]]; then
  exit 0
fi

# --- Timestamp (ISO 8601) ---
printf -v timestamp '%(%Y-%m-%dT%H:%M:%S%z)T' -1
if [[ "$timestamp" =~ ^(.+)([+-][0-9]{2})([0-9]{2})$ ]]; then
  timestamp="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
fi

count_lord_responses() {
  local lord_conversation_file="$1"
  [[ -f "$lord_conversation_file" ]] || {
    printf '0\n'
    return 0
  }

  python3 - "$lord_conversation_file" <<'PY'
import json
import sys

count = 0
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") == "inbound" and entry.get("source") == "lord":
            count += 1
print(count)
PY
}

record_shogun_growth_metrics() {
  local lord_response_count="$1"
  local metrics_file="${PROMPT_STATE_GROWTH_METRICS_FILE:-$SCRIPT_DIR/logs/shogun_growth_metrics.yaml}"

  mkdir -p "$(dirname "$metrics_file")"
  {
    flock 9
    {
      printf -- '- timestamp: "%s"\n' "$timestamp"
      printf '  source: "prompt_state_inject.sh"\n'
      printf '  agent_id: "%s"\n' "$agent_id"
      printf '  lord_response_count: %s\n' "$lord_response_count"
    } >> "$metrics_file"
  } 9>"${metrics_file}.lock"
}

detect_skill_triggers() {
  local skills_dir="${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}"
  local projects_yaml="${PROMPT_STATE_PROJECTS_YAML:-$SCRIPT_DIR/config/projects.yaml}"
  local current_project="${PROMPT_STATE_CURRENT_PROJECT:-}"
  [[ -d "$skills_dir" ]] || {
    return 0
  }
  if [[ -z "$current_project" && -f "$projects_yaml" ]]; then
    current_project="$(awk '/^current_project:[[:space:]]*/{print $2; exit}' "$projects_yaml" | tr -d '"'\''')"
  fi

  PROMPT_TEXT="$prompt_text" SKILLS_DIR="$skills_dir" CURRENT_PROJECT="$current_project" python3 - <<'PY'
import os
import re
import sys

prompt = os.environ.get("PROMPT_TEXT", "")
skills_dir = os.environ.get("SKILLS_DIR", "")
current_project = os.environ.get("CURRENT_PROJECT", "").strip()
prompt_lower = prompt.lower()
top_key_re = re.compile(r"^[A-Za-z_-]+:")


def extract_frontmatter(text):
    lines = text.replace("\r", "").splitlines()
    if not lines or lines[0] != "---":
        return ""
    try:
        end = lines.index("---", 1)
    except ValueError:
        return ""
    return "\n".join(lines[1:end])


def extract_description(frontmatter):
    if not frontmatter:
        return ""
    lines = frontmatter.splitlines()
    for idx, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        tail = line.split(":", 1)[1].strip()
        if tail in ("|", ">"):
            chunks = []
            for follow in lines[idx + 1:]:
                if top_key_re.match(follow):
                    break
                if follow[:1].isspace():
                    chunks.append(follow.lstrip())
                else:
                    break
            return "\n".join(chunks).strip()
        return tail.strip("\"'")
    return ""


def extract_allowed_projects(frontmatter):
    match = re.search(r"(?m)^allowed_projects:\s*\[([^\]]*)\]\s*$", frontmatter)
    if not match:
        return []
    return [
        item.strip().strip("\"'")
        for item in match.group(1).split(",")
        if item.strip()
    ]


def extract_triggers(description):
    triggers = []
    for line in description.splitlines():
        if re.match(r"^\s*TRIGGER\s*:", line, re.IGNORECASE):
            content = line.split(":", 1)[1]
            for part in re.split(r"[、,]", content):
                part = part.strip()
                if part:
                    triggers.append(part)
    return triggers


def split_project_constraint(trigger):
    projects = []
    patterns = [
        r"\[\s*project(?:s)?\s*[:=]\s*([^\]]+)\]",
        r"\(\s*project(?:s)?\s*[:=]\s*([^)]+)\)",
        r"project(?:s)?\s*[:=]\s*([A-Za-z0-9_-]+(?:\s*[|/]\s*[A-Za-z0-9_-]+)*)",
    ]
    cleaned = trigger
    for pattern in patterns:
        for match in re.finditer(pattern, trigger, flags=re.IGNORECASE):
            raw = match.group(1)
            for part in re.split(r"[,|/、\s]+", raw):
                part = part.strip().strip("\"'")
                if part:
                    projects.append(part)
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE).strip()
    return cleaned.strip(" -:;、"), projects


def project_allowed(projects):
    if not projects:
        return True
    return bool(current_project) and current_project in projects


def trigger_terms(trigger):
    terms = [trigger]
    for token in re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]{1,}", trigger):
        # Uppercase acronyms such as CDP/DB are intentional routing keys.
        if token.isupper() or trigger.startswith("/"):
            terms.append(token)
    return terms


matches = []
try:
    entries = sorted(os.scandir(skills_dir), key=lambda item: item.name)
except OSError:
    entries = []

for entry in entries:
    if not entry.is_dir():
        continue
    skill_file = os.path.join(entry.path, "SKILL.md")
    if not os.path.isfile(skill_file):
        continue
    try:
        with open(skill_file, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        continue

    frontmatter = extract_frontmatter(text)
    if not project_allowed(extract_allowed_projects(frontmatter)):
        continue

    desc = extract_description(frontmatter)
    for trigger in extract_triggers(desc):
        clean_trigger, trigger_projects = split_project_constraint(trigger)
        if not project_allowed(trigger_projects):
            continue
        for term in trigger_terms(clean_trigger):
            if term and term.lower() in prompt_lower:
                matches.append((entry.name, clean_trigger))
                break
        if matches and matches[-1][0] == entry.name:
            break

for name, trigger in (
    ("codd-fix", "codd fix"),
    ("codd-fix", "事象修正"),
    ("codd-fix", "現象修正"),
):
    if trigger.lower() in prompt_lower and not any(item[0] == name for item in matches):
        matches.append((name, trigger))

if not matches:
    sys.exit(0)

print("⚠ SKILL TRIGGER HIT: 作業開始前に該当SKILL.mdを読め。")
for name, trigger in matches[:5]:
    print(f"- /{name} (matched: {trigger})")
if len(matches) > 5:
    print(f"- ... and {len(matches) - 5} more")
PY
}

# --- Growth metrics: automatic lord response count recording ---
lord_conversation_file="${PROMPT_STATE_LORD_CONVERSATION_FILE:-$SCRIPT_DIR/queue/lord_conversation.jsonl}"
lord_response_count="$(count_lord_responses "$lord_conversation_file" 2>/dev/null || printf '0\n')"
record_shogun_growth_metrics "$lord_response_count" 2>/dev/null || true

# --- Inbox unread count ---
inbox_file="$SCRIPT_DIR/queue/inbox/${agent_id}.yaml"
unread_count=0
if [[ -f "$inbox_file" ]]; then
  unread_count="$(awk '/^[[:space:]]*read:[[:space:]]*false[[:space:]]*$/{c++} END{print c+0}' "$inbox_file" 2>/dev/null || echo 0)"
  if [[ ! "$unread_count" =~ ^[0-9]+$ ]]; then
    unread_count=0
  fi
fi

# --- karo_snapshot ---
snapshot_file="$SCRIPT_DIR/queue/karo_snapshot.txt"
karo_snapshot="unavailable"
if [[ -f "$snapshot_file" ]]; then
  karo_snapshot="$(< "$snapshot_file")"
  if [[ -z "$karo_snapshot" ]]; then
    karo_snapshot="unavailable"
  fi
fi

# --- 研究日誌全文注入モード検知 ---
research_diary_mode=false
research_diary_file="$SCRIPT_DIR/memory/dialogue_preprocessing_research_20260331.md"
if echo "$prompt_text" | grep -qiE '研究日誌|日誌を読め|日誌を読んで|diary'; then
  if [[ -f "$research_diary_file" ]]; then
    research_diary_mode=true
  fi
fi

if [[ "$research_diary_mode" == "true" ]]; then
  # --- 研究日誌全文注入モード（サイズ制限なし） ---
  diary_content="$(cat "$research_diary_file")"
  verification_questions="
---検証問（各1行で回答。回答なしに作業開始するな。クリア後の新しい将軍として答えよ）---
Q1: 今セッションの作業と研究日誌のどのPhaseが因果的に接続するか？
Q2: 研究日誌の中で最も驚いた転換点はどれか？なぜか？
Q3: 研究日誌から今の問題に適用できる原理は何か？
Q4: Phase Nの結論がPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）
Q5: 研究日誌のどのPhaseで殿が将軍の前提を崩したか？今の自分にも同じ前提はないか？確認せよ"

  additional_context="=== 研究日誌全文注入（殿指示検知） ===
timestamp: ${timestamp}
agent: ${agent_id}
--- karo_snapshot ---
${karo_snapshot}
--- 研究日誌（Phase 0から順に追体験せよ） ---
${diary_content}
${verification_questions}"

  _prompt_state_emit_output "UserPromptSubmit" "$additional_context"
  exit 0
fi

# --- 通常モード: Build additionalContext (max 500 chars) ---
# 未読3件以上: 強い警告を注入（殿との対話中にinbox確認を先送りする構造を強制で潰す）
inbox_warning=""
# 1通でも重要な報告が含まれる可能性(殿指摘2026-04-16)。全未読で警告
if (( unread_count >= 1 )); then
  inbox_warning="
⚠️ INBOX ${unread_count}件未読。殿に応答する前にinboxと掲示板を確認せよ。"
fi

# --- Question pattern detection → confirmation injection (cmd_2293) ---
question_warning=""
if echo "$prompt_text" | grep -qiE '\?|？|分かるか|確認|どう|即答|知って'; then
  current_project="unknown"
  projects_yaml="$SCRIPT_DIR/config/projects.yaml"
  if [[ -f "$projects_yaml" ]]; then
    current_project="$(grep '^current_project:' "$projects_yaml" | awk '{print $2}' | tr -d '"')"
    [[ -z "$current_project" ]] && current_project="unknown"
  fi
  question_warning="
⚠ 質問検知。回答前にprojects/${current_project}.yaml + context/${current_project}.mdを確認してから答えよ。"
fi

# --- Skill trigger detection: prompt keywords → mandatory skill reminder ---
skill_trigger_warning="$(detect_skill_triggers 2>/dev/null || true)"
if [[ -n "$skill_trigger_warning" ]]; then
  skill_trigger_warning="
${skill_trigger_warning}"
fi

header="=== Session Context (auto-injected) ==="
fixed_part="${header}
source: unknown
timestamp: ${timestamp}
agent: ${agent_id}
inbox_unread: ${unread_count}${inbox_warning}${question_warning}${skill_trigger_warning}
--- karo_snapshot ---
"

fixed_len=${#fixed_part}
max_total=500
snapshot_budget=$((max_total - fixed_len))

if (( snapshot_budget < 0 )); then
  snapshot_budget=0
fi

if (( ${#karo_snapshot} > snapshot_budget )); then
  karo_snapshot="${karo_snapshot:0:$snapshot_budget}"
fi

additional_context="${fixed_part}${karo_snapshot}"

# --- Output JSON ---
_prompt_state_emit_output "UserPromptSubmit" "$additional_context"

exit 0
