#!/usr/bin/env bash
# scripts/skill_recommend.sh — スキルTRIGGER照合 (コンパイルキャッシュ+AWK方式)
# Usage: bash scripts/skill_recommend.sh PROMPT_TEXT AGENT_ID SKILLS_DIR CURRENT_PROJECT
# Output: マッチしたスキル推薦テキスト (なければ空)
#
# 速度設計:
#   コンパイルキャッシュ有効時: stat(2ms) + awk照合(8ms) = ~10ms
#   コンパイルキャッシュ無効時: Python全スキャン(400ms) → キャッシュ生成 (初回のみ)
#   prompt_hashキャッシュヒット時: stat(2ms) + cat(3ms) = ~5ms
#
# コンパイルキャッシュTSV形式 (タブ区切り6列):
#   skill_name TAB role_marker TAB allowed_projects_csv TAB match_term TAB trigger_proj_csv TAB display_trigger
#
# @source: cmd_training_speed_skill_recommend_20260529
set -euo pipefail

_sr_prompt_text="${1:-}"
_sr_agent_id="${2:-unknown}"
_sr_skills_dir="${3:-}"
_sr_current_project="${4:-}"

[[ -n "${_sr_skills_dir}" ]] || return 0
[[ -d "${_sr_skills_dir}" ]] || return 0
[[ -n "${_sr_prompt_text//[[:space:]]/}" ]] || exit 0

# inbox nudge はスキップ (prompt_state_inject.shのsemanticと同じ判定)
[[ ! "${_sr_prompt_text}" =~ ^inbox[0-9]+$ ]] || exit 0

_sr_prompt_lower="${_sr_prompt_text,,}"

# キャッシュディレクトリ (/tmp = ext4, stat高速)
_sr_cache_dir="${SKILL_RECOMMEND_CACHE_DIR:-/tmp/skill_recommend_cache}"
# mkdir -p はディレクトリ未存在時のみ (サブプロセス回避)
[[ -d "${_sr_cache_dir}" ]] || mkdir -p "${_sr_cache_dir}" 2>/dev/null || true

# --- レイヤー1: prompt_hashキャッシュ (同一プロンプト=即return) ---
# bash-only hash: サブプロセスゼロ (sha256sum|awk 廃止)
_sr_h_len="${#_sr_prompt_lower}"
if (( _sr_h_len > 96 )); then
  _sr_h="${_sr_prompt_lower:0:64}__${_sr_prompt_lower: -32}"
else
  _sr_h="${_sr_prompt_lower}"
fi
_sr_prompt_hash="${_sr_h_len}_${_sr_h//[^a-z0-9]/_}"
_sr_cache_version="skill-trigger-v2"
_sr_prompt_cache="${_sr_cache_dir}/prompt_${_sr_agent_id//[^A-Za-z0-9_.-]/_}_${_sr_current_project//[^A-Za-z0-9_.-]/_}_${_sr_prompt_hash}"

if [[ -f "${_sr_prompt_cache}" ]]; then
  # bash read でバージョン確認 (sed サブプロセス廃止)
  IFS= read -r _sr_v_line < "${_sr_prompt_cache}" 2>/dev/null || true
  if [[ "${_sr_v_line}" == "v: ${_sr_cache_version}" ]]; then
    tail -n +3 "${_sr_prompt_cache}" 2>/dev/null || true
    exit 0
  fi
fi

# --- レイヤー2: コンパイルキャッシュ (TTL=3600s) ---
_sr_compiled_cache="${_sr_cache_dir}/compiled_triggers.tsv"
_sr_compiled_ttl="${SKILL_RECOMMEND_COMPILED_TTL:-3600}"

_sr_need_compile=0
if [[ ! -f "${_sr_compiled_cache}" ]]; then
  _sr_need_compile=1
else
  _sr_cache_ts="$(stat -c '%Y' "${_sr_compiled_cache}" 2>/dev/null || echo 0)"
  # printf builtin でタイムスタンプ取得 (date サブプロセス廃止)
  printf -v _sr_current_ts '%(%s)T' -1
  if (( _sr_current_ts - _sr_cache_ts > _sr_compiled_ttl )); then
    _sr_need_compile=1
  fi
fi

if (( _sr_need_compile )); then
  # コンパイルキャッシュ生成 (初回 or TTL切れ時のみ。約400ms)
  _sr_compile_tmp="$(mktemp "${_sr_compiled_cache}.XXXXXX")"
  SKILL_RECOMMEND_SKILLS_DIR="${_sr_skills_dir}" python3 - "${_sr_compile_tmp}" <<'COMPILE_PY'
import os
import re
import sys

out_path = sys.argv[1]
skills_dir = os.environ.get("SKILL_RECOMMEND_SKILLS_DIR", "")
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
            for follow in lines[idx + 1 :]:
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
    m = re.search(r"(?m)^allowed_projects:\s*\[([^\]]*)\]\s*$", frontmatter)
    if not m:
        return []
    return [x.strip().strip("\"'") for x in m.group(1).split(",") if x.strip()]


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
        for m in re.finditer(pattern, trigger, flags=re.IGNORECASE):
            raw = m.group(1)
            for part in re.split(r"[,|/、\s]+", raw):
                part = part.strip().strip("\"'")
                if part:
                    projects.append(part)
        cleaned = re.sub(pattern, "", cleaned, flags=re.IGNORECASE).strip()
    return cleaned.strip(" -:;、"), projects


def trigger_terms(trigger):
    terms = [trigger]
    for token in re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]{1,}", trigger):
        if token.isupper() or trigger.startswith("/"):
            terms.append(token)
    return terms


def extract_role_marker(text):
    m = re.search(r"【([^】]+)専用】", text[:2000])
    return m.group(1) if m else ""


rows = []
try:
    entries = sorted(os.scandir(skills_dir), key=lambda e: e.name)
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
    allowed = ",".join(extract_allowed_projects(frontmatter))
    role_marker = extract_role_marker(text)
    desc = extract_description(frontmatter)

    for trigger in extract_triggers(desc):
        clean_trigger, trigger_projs = split_project_constraint(trigger)
        trigger_proj_csv = ",".join(trigger_projs)
        for term in trigger_terms(clean_trigger):
            if term:
                rows.append(
                    f"{entry.name}\t{role_marker}\t{allowed}\t{term}\t{trigger_proj_csv}\t{clean_trigger}"
                )

# hardcoded codd-fix (prompt_state_inject.shと同一)
for trigger in ("codd fix", "事象修正", "現象修正"):
    rows.append(f"codd-fix\t\t\t{trigger}\t\t{trigger}")

with open(out_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(rows))
    if rows:
        fh.write("\n")
COMPILE_PY
  mv "${_sr_compile_tmp}" "${_sr_compiled_cache}"
fi

# --- レイヤー3: AWK照合 (~8ms) ---
_sr_result="$(
  awk -v prompt="${_sr_prompt_lower}" \
      -v agent="${_sr_agent_id}" \
      -v project="${_sr_current_project}" \
  'BEGIN {
    FS = "\t"
    n_matched = 0
  }
  {
    name     = $1
    role     = $2
    allowed  = $3
    term     = $4
    tproj    = $5
    disp     = $6

    # note: role_marker check is intentionally absent here, matching the original
    # detect_skill_triggers() Python inline script behavior (no role filtering).
    # Role filtering only applies in semantic_skill_recommendations() via filter_skills_for_agent().

    # allowed_projects check (frontmatter)
    if (allowed != "") {
      if (project == "") next
      found = 0
      n = split(allowed, ap, ",")
      for (i = 1; i <= n; i++) {
        if (ap[i] == project) { found = 1; break }
      }
      if (!found) next
    }

    # trigger project constraint check
    if (tproj != "") {
      if (project == "") next
      found = 0
      n = split(tproj, tp, ",")
      for (i = 1; i <= n; i++) {
        if (tp[i] == project) { found = 1; break }
      }
      if (!found) next
    }

    # substring match (case-insensitive via tolower in term at compile time)
    term_lower = tolower(term)
    if (term_lower == "" || index(prompt, term_lower) == 0) next

    # first match per skill only
    if (name in seen) next
    seen[name] = disp
    order[++n_matched] = name
  }
  END {
    if (n_matched == 0) exit 0
    # codd-fix dedup: if already in seen, skip re-add (hardcoded entries are last in TSV)
    print "⚠ SKILL TRIGGER HIT: 作業開始前に該当SKILL.mdを読め。"
    limit = n_matched > 5 ? 5 : n_matched
    for (i = 1; i <= limit; i++) {
      print "- /" order[i] " (matched: " seen[order[i]] ")"
    }
    if (n_matched > 5) {
      print "- ... and " (n_matched - 5) " more"
    }
  }' "${_sr_compiled_cache}" 2>/dev/null || true
)"

# prompt_hashキャッシュに保存
{
  printf 'v: %s\n' "${_sr_cache_version}"
  printf -- '---\n'
  printf '%s' "${_sr_result}"
} > "${_sr_prompt_cache}"

printf '%s' "${_sr_result}"
