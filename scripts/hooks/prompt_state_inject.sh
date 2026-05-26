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

record_semantic_no_match_metric() {
  local metrics_file="${PROMPT_STATE_SEMANTIC_NO_MATCH_FILE:-$SCRIPT_DIR/logs/semantic_no_match_metrics.log}"

  mkdir -p "$(dirname "$metrics_file")"
  {
    flock 9
    printf '%s\tsource=prompt_state_inject.sh\tagent_id=%s\tcount=1\n' "$timestamp" "$agent_id" >> "$metrics_file"
  } 9>"${metrics_file}.lock"
}

prompt_state_yaml_scalar() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '"%s"' "$value"
}

record_skill_recommendation_log() {
  local prompt_hash="$1"
  local skills="$2"
  local recommend_log="${PROMPT_STATE_SKILL_RECOMMEND_LOG_FILE:-$SCRIPT_DIR/logs/skill_recommend_log.yaml}"
  local skill_name

  [[ -n "$prompt_hash" ]] || return 0
  [[ -n "${skills//[[:space:]]/}" ]] || return 0

  mkdir -p "$(dirname "$recommend_log")"
  {
    flock -w 5 9 || return 0
    if [[ ! -s "$recommend_log" ]]; then
      printf 'recommendations:\n' > "$recommend_log"
    fi
    printf -- '- ts: %s\n' "$(prompt_state_yaml_scalar "$timestamp")" >> "$recommend_log"
    printf '  agent_id: %s\n' "$(prompt_state_yaml_scalar "$agent_id")" >> "$recommend_log"
    printf '  prompt_hash: %s\n' "$(prompt_state_yaml_scalar "$prompt_hash")" >> "$recommend_log"
    printf '  recommended_skills:\n' >> "$recommend_log"
    while IFS= read -r skill_name; do
      [[ -n "$skill_name" ]] || continue
      printf '  - %s\n' "$(prompt_state_yaml_scalar "$skill_name")" >> "$recommend_log"
    done <<< "$skills"
  } 9>"${recommend_log}.lock"

  python3 - "$recommend_log" <<'PY' >/dev/null 2>&1 || true
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    yaml.safe_load(fh)
PY
}

skill_names_from_recommendation_text() {
  sed -nE 's/^- \/([A-Za-z0-9_.-]+).*/\1/p'
}

skill_allowed_for_agent() {
  local skill_name="$1"
  local skills_dir="${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}"
  local skill_file="${skills_dir}/${skill_name}/SKILL.md"
  local marker

  [[ -f "$skill_file" ]] || return 1
  marker="$(sed -n '1,80p' "$skill_file" | grep -oE '【[^】]+専用】' | head -1 || true)"
  [[ -n "$marker" ]] || return 0

  case "$marker" in
    *将軍専用*) [[ "$agent_id" == "shogun" ]] ;;
    *家老専用*) [[ "$agent_id" == "karo" ]] ;;
    *軍師専用*) [[ "$agent_id" == "gunshi" ]] ;;
    *忍者専用*) [[ "$agent_id" != "shogun" && "$agent_id" != "karo" && "$agent_id" != "gunshi" ]] ;;
    *) return 0 ;;
  esac
}

filter_skills_for_agent() {
  local skill_name

  while IFS= read -r skill_name; do
    [[ -n "$skill_name" ]] || continue
    if skill_allowed_for_agent "$skill_name"; then
      printf '%s\n' "$skill_name"
    fi
  done
}

semantic_skill_recommendations() {
  local search_cmd="${PROMPT_STATE_SEMANTIC_SEARCH_CMD:-$SCRIPT_DIR/scripts/semantic_search.sh}"
  local cache_file
  local cache_version="role-filter-v1"
  local prompt_hash
  local cached_hash
  local cached_version
  local semantic_result
  local semantic_rc
  local skills
  local cache_tmp

  [[ -f "$search_cmd" ]] || return 0
  [[ -n "${prompt_text//[[:space:]]/}" ]] || return 0
  # Skip inbox nudge prompts (precision fix: inbox1 hash=86/111 FP)
  [[ ! "$prompt_text" =~ ^inbox[0-9]+$ ]] || return 0

  cache_file="/tmp/skill_recommend_cache_${agent_id//[^A-Za-z0-9_.-]/_}"
  prompt_hash="$(printf '%s' "$prompt_text" | sha256sum | awk '{print $1}')"
  if [[ -f "$cache_file" ]]; then
    cached_hash="$(sed -n '1s/^prompt_sha256: //p' "$cache_file" 2>/dev/null || true)"
    cached_version="$(sed -n '2s/^filter_version: //p' "$cache_file" 2>/dev/null || true)"
    if [[ "$cached_hash" == "$prompt_hash" && "$cached_version" == "$cache_version" ]]; then
      skills="$(sed '1,/^---$/d' "$cache_file" 2>/dev/null | skill_names_from_recommendation_text || true)"
      record_skill_recommendation_log "$prompt_hash" "$skills" 2>/dev/null || true
      sed '1,/^---$/d' "$cache_file" 2>/dev/null || true
      return 0
    fi
  fi

  cache_tmp="$(mktemp "${cache_file}.XXXXXX")"

  set +e
  semantic_result="$(
    SEMANTIC_INDEX_CACHE_DIR="${SEMANTIC_INDEX_CACHE_DIR:-$SCRIPT_DIR/tmp/semantic_index_cache}" \
      SEMANTIC_DISABLE_LLM=1 \
      SEMANTIC_DISABLE_CAUSAL=1 \
      SEMANTIC_DISABLE_MEMORY_DB=1 \
      timeout "${PROMPT_STATE_SKILL_SEMANTIC_TIMEOUT:-0.60}" bash "$search_cmd" "$prompt_text" 2>/dev/null
  )"
  semantic_rc=$?
  set -e
  [[ "$semantic_rc" -eq 0 ]] || return 0

  skills="$(
    SEMANTIC_RESULT="$semantic_result" python3 - <<'PY'
import os
import re

raw = os.environ.get("SEMANTIC_RESULT", "")
seen = set()
names = []
for line in raw.splitlines():
    match = re.match(r"^\s*-\s*skills\s*:\s*(.+?)\s*$", line)
    if not match:
        continue
    for item in re.split(r"[,、]", match.group(1)):
        name = item.strip().strip("`\"'")
        if not name or name.lower() in {"none", "no", "n/a", "null"} or name in {"なし", "無し"}:
            continue
        if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$", name):
            continue
        if name not in seen:
            seen.add(name)
            names.append(name)
print("\n".join(names[:5]))
PY
  )"
  skills="$(printf '%s\n' "$skills" | filter_skills_for_agent)"
  [[ -n "$skills" ]] || return 0
  record_skill_recommendation_log "$prompt_hash" "$skills" 2>/dev/null || true

  {
    printf '⚠ SKILL RECOMMENDATION: semantic_search一致。必要なら該当SKILL.mdを読め。\n'
    while IFS= read -r skill_name; do
      [[ -n "$skill_name" ]] || continue
      printf -- '- /%s (matched: semantic_search skills)\n' "$skill_name"
    done <<< "$skills"
  } | tee "$cache_tmp"
  {
    printf 'prompt_sha256: %s\n' "$prompt_hash"
    printf 'filter_version: %s\n' "$cache_version"
    printf -- '---\n'
    cat "$cache_tmp"
  } > "$cache_file"
  rm -f "$cache_tmp"
}

detect_skill_triggers() {
  local skills_dir="${PROMPT_STATE_SKILLS_DIR:-$SCRIPT_DIR/skills}"
  local projects_yaml="${PROMPT_STATE_PROJECTS_YAML:-$SCRIPT_DIR/config/projects.yaml}"
  local current_project="${PROMPT_STATE_CURRENT_PROJECT:-}"
  local trigger_output
  local semantic_output
  [[ -d "$skills_dir" ]] || {
    semantic_skill_recommendations
    return 0
  }
  if [[ -z "$current_project" && -f "$projects_yaml" ]]; then
    current_project="$(awk '/^current_project:[[:space:]]*/{print $2; exit}' "$projects_yaml" | tr -d '"'\''')"
  fi

  set +e
  trigger_output="$(PROMPT_TEXT="$prompt_text" SKILLS_DIR="$skills_dir" CURRENT_PROJECT="$current_project" timeout "${PROMPT_STATE_SKILL_TRIGGER_TIMEOUT:-0.10}" python3 - <<'PY'
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
)"
  set -e
  semantic_output="$(semantic_skill_recommendations)"
  if [[ -n "$trigger_output" ]]; then
    printf '%s\n' "$trigger_output"
  fi
  if [[ -n "$semantic_output" ]]; then
    [[ -z "$trigger_output" ]] || printf '\n'
    printf '%s\n' "$semantic_output"
  fi
}

# --- All roles: non-shogun receives only skill recommendations, otherwise stays silent. ---
if [[ "$agent_id" != "shogun" ]]; then
  skill_trigger_warning="$(detect_skill_triggers 2>/dev/null || true)"
  if [[ -n "$skill_trigger_warning" ]]; then
    _prompt_state_emit_output "UserPromptSubmit" "=== Skill Context (auto-injected) ===
timestamp: ${timestamp}
agent: ${agent_id}
${skill_trigger_warning}"
  fi
  exit 0
fi

	# --- Semantic auto-injection (first-layer only, no LLM fallback) ---
	_prompt_state_semantic_inject() {
	  local _psi_query="${1:0:300}"
	  local _psi_search_cmd="${PROMPT_STATE_SEMANTIC_SEARCH_CMD:-$SCRIPT_DIR/scripts/semantic_search.sh}"
	  local _psi_result _psi_rc
	  _psi_query="${_psi_query//$'\n'/ }"
	  [[ -z "${_psi_query// }" ]] && return 0
	  [[ -f "$_psi_search_cmd" ]] || return 0
	  set +e
	  _psi_result="$(
	    SEMANTIC_INDEX_CACHE_DIR="${SEMANTIC_INDEX_CACHE_DIR:-$SCRIPT_DIR/tmp/semantic_index_cache}" \
	      SEMANTIC_DISABLE_LLM=1 \
	      SEMANTIC_DISABLE_CAUSAL=1 \
	      SEMANTIC_DISABLE_MEMORY_DB=1 \
	      timeout "${PROMPT_STATE_SEMANTIC_TIMEOUT:-0.60}" bash "$_psi_search_cmd" "$_psi_query" 2>/dev/null
	  )"
	  _psi_rc=$?
	  set -e
	  if [[ "$_psi_rc" -eq 0 ]]; then
	    printf '%s' "$_psi_result"
	    return 0
	  fi
	  if [[ "$_psi_rc" -eq 1 ]]; then
	    record_semantic_no_match_metric 2>/dev/null || true
	  fi
	  return 0
	}

	memory_db_fts5_inject() {
	  local _psi_query="${1:0:300}"
	  local _psi_db_path="${PROMPT_STATE_LORD_RULING_CACHE_PATH:-/tmp/lord_ruling_cache.db}"
	  local _psi_result _psi_rc
	  _psi_query="${_psi_query//$'\n'/ }"
	  _psi_query="${_psi_query#"${_psi_query%%[![:space:]]*}"}"
	  _psi_query="${_psi_query%"${_psi_query##*[![:space:]]}"}"
	  [[ -f "$_psi_db_path" ]] || return 0

	  set +e
	  _psi_result="$(
	    PROMPT_STATE_FTS_QUERY="$_psi_query" PROMPT_STATE_FTS_DB="$_psi_db_path" \
	      timeout "${PROMPT_STATE_MEMORY_DB_TIMEOUT:-0.5}" python3 - <<'PY'
from __future__ import annotations

import os
import re
import sqlite3

TOKEN_RE = re.compile(r"[\u4e00-\u9fff]+|[\u30a0-\u30ff]+|[\u3040-\u309f]+|[A-Za-z]+|[0-9]+")
STOPWORDS = {
    "する",
    "した",
    "して",
    "ない",
    "ある",
    "いる",
    "これ",
    "それ",
    "とか",
    "から",
    "まで",
    "だけ",
    "など",
    "でも",
    "けど",
}


def like_terms_for_text(query: str, max_terms: int = 5) -> list[str]:
    normalized = " ".join(query.split())
    if not normalized:
        return []
    high_confidence: list[str] = []
    low_confidence: list[str] = []
    seen: set[str] = set()
    for match in TOKEN_RE.finditer(normalized):
        raw = match.group(0)
        is_high = (
            bool(re.fullmatch(r"[\u4e00-\u9fff]{2,}", raw))
            or bool(re.fullmatch(r"[\u30a0-\u30ff]{2,}", raw))
            or bool(re.fullmatch(r"[A-Za-z]{2,}", raw))
            or bool(re.fullmatch(r"[0-9]{2,}", raw))
        )
        is_low = bool(re.fullmatch(r"[\u3040-\u309f]{3,6}", raw)) and raw not in STOPWORDS
        if not is_high and not is_low:
            continue
        key = raw.casefold()
        if key in seen:
            continue
        seen.add(key)
        if is_high:
            high_confidence.append(raw)
        else:
            low_confidence.append(raw)
    return (high_confidence + low_confidence)[:max_terms]


def like_pattern(value: str) -> str:
    return f"%{value}%"


def build_where_clause(terms: list[str]) -> tuple[str, list[str]]:
    clauses: list[str] = []
    params: list[str] = []
    for term in terms:
        pattern = like_pattern(term)
        clauses.append("(summary LIKE ? OR detail LIKE ?)")
        params.extend([pattern, pattern])
    return " OR ".join(clauses), params


def one_line(value: object, max_len: int = 120) -> str:
    text = "" if value is None else str(value)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:max_len]


db_path = os.environ.get("PROMPT_STATE_FTS_DB", "")
terms = like_terms_for_text(os.environ.get("PROMPT_STATE_FTS_QUERY", ""))
if not db_path or not terms:
    raise SystemExit(0)

where_clause, params = build_where_clause(terms)
with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
    conn.execute("PRAGMA busy_timeout=500")
    rows = conn.execute(
        f"""
        SELECT ts, event_type, cmd_id, summary
        FROM lord_rulings
        WHERE {where_clause}
        ORDER BY ts DESC
        LIMIT 3
        """,
        params,
    ).fetchall()

if not rows:
    raise SystemExit(0)

print("lord_ruling_cache_matches:")
for ts, event_type, cmd_id, summary in rows:
    print(f"- ts: {one_line(ts, 40)}")
    print(f"  event_type: {one_line(event_type, 40)}")
    if cmd_id:
        print(f"  cmd_id: {one_line(cmd_id, 40)}")
    print(f"  summary: {one_line(summary)}")
PY
	  )"
	  _psi_rc=$?
	  set -e
	  [[ "$_psi_rc" -eq 0 ]] || return 0
	  [[ -n "$_psi_result" ]] || return 0
	  printf '%s' "$_psi_result"
	  return 0
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

# --- Semantic knowledge auto-injection (first-layer only, no LLM) ---
semantic_result="$(_prompt_state_semantic_inject "$prompt_text")"
if [[ -n "$semantic_result" ]]; then
  additional_context="${additional_context}
--- semantic_knowledge ---
${semantic_result}"
fi

memory_db_result="$(memory_db_fts5_inject "$prompt_text")"
if [[ -n "$memory_db_result" ]]; then
  additional_context="${additional_context}
--- memory_db_fts5 ---
${memory_db_result}"
fi

# --- Output JSON ---
_prompt_state_emit_output "UserPromptSubmit" "$additional_context"

exit 0
