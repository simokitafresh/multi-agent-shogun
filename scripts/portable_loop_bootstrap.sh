#!/usr/bin/env bash
# portable_loop_bootstrap.sh — install a minimal learning-loop core into any project.
# Usage: bash scripts/portable_loop_bootstrap.sh <target_dir>

set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: portable_loop_bootstrap.sh <target_dir>

Installs a project-local learning-loop core:
  .learning-loop/{lessons.yaml,insights.yaml,memory/events.jsonl,semantic-map.md,inbox/}
  scripts/learning-loop/{report_gate.py,lesson_write.sh,insight_write.sh,memory_write.sh,inbox_write.sh,semantic_search.sh}
  docs/learning-loop-portable-core.md
EOF
}

target_dir="${1:-}"
if [[ -z "$target_dir" || "$target_dir" == "-h" || "$target_dir" == "--help" ]]; then
    usage
    exit 2
fi

mkdir -p "$target_dir"
target_dir="$(cd "$target_dir" && pwd)"

core_dir="$target_dir/.learning-loop"
script_dir="$target_dir/scripts/learning-loop"
doc_dir="$target_dir/docs"

mkdir -p "$core_dir/inbox" "$core_dir/memory" "$script_dir" "$doc_dir"

if [[ ! -f "$core_dir/lessons.yaml" ]]; then
    cat > "$core_dir/lessons.yaml" <<'EOF'
lessons: []
EOF
fi

if [[ ! -f "$core_dir/insights.yaml" ]]; then
    cat > "$core_dir/insights.yaml" <<'EOF'
insights: []
EOF
fi

touch "$core_dir/memory/events.jsonl"

if [[ ! -f "$core_dir/semantic-map.md" ]]; then
    cat > "$core_dir/semantic-map.md" <<'EOF'
# Semantic Map

| concept | aliases | resources |
|---|---|---|
EOF
fi

cat > "$script_dir/report_gate.py" <<'PY'
#!/usr/bin/env python3
"""Minimal report gate for portable learning-loop reports.

Accepts JSON or simple YAML. Required fields:
worker_id, parent_cmd, status=completed, result.summary, purpose_validation,
files_modified, lesson_candidate.found, lessons_useful, binary_checks.*[].result.
All binary check results must be "yes" or "no"; all yes means PASS.
"""

import json
import re
import sys
from pathlib import Path


def load_report(path: Path):
    text = path.read_text(encoding="utf-8")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(text)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return parse_simple_yaml(text)


def parse_simple_yaml(text: str):
    data = {}
    current = None
    in_binary = False
    current_ac = None
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not raw.startswith(" ") and ":" in stripped:
            key, value = stripped.split(":", 1)
            current = key.strip()
            in_binary = current == "binary_checks"
            if value.strip():
                data[current] = scalar(value)
            else:
                data.setdefault(current, {})
            continue
        if current == "result" and stripped.startswith("summary:"):
            data.setdefault("result", {})["summary"] = scalar(stripped.split(":", 1)[1])
        elif current == "lesson_candidate" and stripped.startswith("found:"):
            data.setdefault("lesson_candidate", {})["found"] = scalar(stripped.split(":", 1)[1])
        elif current == "purpose_validation" and stripped.startswith("fit:"):
            data.setdefault("purpose_validation", {})["fit"] = scalar(stripped.split(":", 1)[1])
        elif in_binary and re.match(r"^[A-Za-z0-9_-]+:", stripped):
            current_ac = stripped.split(":", 1)[0]
            data.setdefault("binary_checks", {}).setdefault(current_ac, [])
        elif in_binary and stripped.startswith("result:") and current_ac:
            data["binary_checks"][current_ac].append({"result": scalar(stripped.split(":", 1)[1])})
    return data


def scalar(value: str):
    value = value.strip().strip("\"'")
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    return value


def get_nested(data, *keys):
    cur = data
    for key in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
    return cur


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: report_gate.py <report>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"FAIL: report not found: {path}", file=sys.stderr)
        return 1
    data = load_report(path)
    failures = []
    for key in ("worker_id", "parent_cmd", "status", "files_modified", "lessons_useful"):
        if data.get(key) in (None, "", [], {}):
            failures.append(f"{key}: missing")
    if data.get("status") != "completed":
        failures.append("status: must be completed")
    if get_nested(data, "result", "summary") in (None, ""):
        failures.append("result.summary: missing")
    if data.get("purpose_validation") in (None, "", {}, []):
        failures.append("purpose_validation: missing")
    if get_nested(data, "lesson_candidate", "found") is None:
        failures.append("lesson_candidate.found: missing")

    results = []
    bcs = data.get("binary_checks")
    if not isinstance(bcs, dict) or not bcs:
        failures.append("binary_checks: missing")
    else:
        for ac, checks in bcs.items():
            if not isinstance(checks, list) or not checks:
                failures.append(f"binary_checks.{ac}: missing checks")
                continue
            for i, item in enumerate(checks):
                result = str((item or {}).get("result", "")).strip()
                if result not in ("yes", "no"):
                    failures.append(f"binary_checks.{ac}[{i}].result: must be yes/no")
                else:
                    results.append(result)
    if failures:
        print("FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1
    verdict = "PASS" if all(result == "yes" for result in results) else "FAIL"
    print(verdict)
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x "$script_dir/report_gate.py"

cat > "$script_dir/lesson_write.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
store="${LEARNING_LOOP_LESSONS_FILE:-$root/.learning-loop/lessons.yaml}"
title="${1:?title required}"
detail="${2:?detail required}"
source="${3:-manual}"
author="${4:-unknown}"
ts="$(date -Iseconds)"
mkdir -p "$(dirname "$store")"
[[ -f "$store" ]] || printf 'lessons: []\n' > "$store"
{
  flock -w 5 200
  if grep -qx 'lessons: \[\]' "$store"; then
    printf 'lessons:\n' > "$store"
  fi
  id="L$(date +%Y%m%d%H%M%S)"
  {
    printf -- '- id: %s\n' "$id"
    printf '  title: "%s"\n' "${title//\"/\\\"}"
    printf '  detail: "%s"\n' "${detail//\"/\\\"}"
    printf '  source: "%s"\n' "${source//\"/\\\"}"
    printf '  author: "%s"\n' "${author//\"/\\\"}"
    printf '  created_at: "%s"\n' "$ts"
  } >> "$store"
  printf 'OK: %s\n' "$id"
} 200>"$store.lock"
SH
chmod +x "$script_dir/lesson_write.sh"

cat > "$script_dir/insight_write.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
store="${LEARNING_LOOP_INSIGHTS_FILE:-$root/.learning-loop/insights.yaml}"
message="${1:?message required}"
priority="${2:-medium}"
source="${3:-manual}"
case "$priority" in high|medium|low) ;; *) echo "ERROR: priority must be high/medium/low" >&2; exit 2 ;; esac
ts="$(date -Iseconds)"
mkdir -p "$(dirname "$store")"
[[ -f "$store" ]] || printf 'insights: []\n' > "$store"
{
  flock -w 5 200
  if grep -qx 'insights: \[\]' "$store"; then
    printf 'insights:\n' > "$store"
  fi
  id="INS-$(date +%Y%m%d%H%M%S)"
  {
    printf -- '- id: %s\n' "$id"
    printf '  message: "%s"\n' "${message//\"/\\\"}"
    printf '  priority: "%s"\n' "$priority"
    printf '  source: "%s"\n' "${source//\"/\\\"}"
    printf '  status: pending\n'
    printf '  created_at: "%s"\n' "$ts"
  } >> "$store"
  printf 'OK: %s\n' "$id"
} 200>"$store.lock"
SH
chmod +x "$script_dir/insight_write.sh"

cat > "$script_dir/memory_write.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
store="${LEARNING_LOOP_MEMORY_FILE:-$root/.learning-loop/memory/events.jsonl}"
text="${1:?knowledge text required}"
source="${2:-manual}"
mkdir -p "$(dirname "$store")"
python3 - "$store" "$text" "$source" <<'PY'
import json, sys, time, uuid
path, text, source = sys.argv[1:4]
row = {"id": str(uuid.uuid4()), "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "type": "knowledge", "text": text, "source": source}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
print("OK:", row["id"])
PY
SH
chmod +x "$script_dir/memory_write.sh"

cat > "$script_dir/inbox_write.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
agent="${1:?agent required}"
message="${2:?message required}"
type="${3:-message}"
from="${4:-unknown}"
store="$root/.learning-loop/inbox/$agent.yaml"
mkdir -p "$(dirname "$store")"
[[ -f "$store" ]] || printf 'messages:\n' > "$store"
{
  flock -w 5 200
  id="MSG-$(date +%Y%m%d%H%M%S)"
  {
    printf -- '- id: %s\n' "$id"
    printf '  from: "%s"\n' "${from//\"/\\\"}"
    printf '  type: "%s"\n' "${type//\"/\\\"}"
    printf '  content: "%s"\n' "${message//\"/\\\"}"
    printf '  read: false\n'
    printf '  timestamp: "%s"\n' "$(date -Iseconds)"
  } >> "$store"
  printf 'OK: %s\n' "$id"
} 200>"$store.lock"
SH
chmod +x "$script_dir/inbox_write.sh"

cat > "$script_dir/semantic_search.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
query="${1:?query required}"
map="${LEARNING_LOOP_SEMANTIC_MAP:-$root/.learning-loop/semantic-map.md}"
memory="${LEARNING_LOOP_MEMORY_FILE:-$root/.learning-loop/memory/events.jsonl}"
status=1
if [[ -f "$map" ]] && grep -i -- "$query" "$map"; then
  status=0
fi
if [[ -f "$memory" ]] && grep -i -- "$query" "$memory"; then
  status=0
fi
exit "$status"
SH
chmod +x "$script_dir/semantic_search.sh"

cat > "$script_dir/report_template.yaml" <<'EOF'
worker_id: ""
parent_cmd: ""
status: pending
result:
  summary: ""
purpose_validation:
  fit: true
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: ""
lessons_useful: []
binary_checks:
  AC1:
  - check: ""
    result: ""
EOF

cat > "$doc_dir/learning-loop-portable-core.md" <<'EOF'
# Learning Loop Portable Core

This project contains a minimal learning-loop core installed by `scripts/portable_loop_bootstrap.sh`.

## Boundary

Portable core:
- report gate: `scripts/learning-loop/report_gate.py`
- lesson registration: `scripts/learning-loop/lesson_write.sh`
- insight storage: `scripts/learning-loop/insight_write.sh`
- memory append: `scripts/learning-loop/memory_write.sh`
- semantic lookup: `scripts/learning-loop/semantic_search.sh`
- inbox append: `scripts/learning-loop/inbox_write.sh`
- stores: `.learning-loop/`

Project-specific layer:
- agent roles, task routing, dashboards, deployment, CI, and project knowledge
- any terminal multiplexer setup
- machine-specific absolute paths

## Smoke Test

```bash
bash scripts/learning-loop/lesson_write.sh "First lesson" "Record a reusable rule" "smoke" "local"
bash scripts/learning-loop/insight_write.sh "First insight" medium smoke
bash scripts/learning-loop/memory_write.sh "portable core installed" smoke
python3 scripts/learning-loop/report_gate.py path/to/report.yaml
```

Reports must set `status: completed`, `result.summary`, `purpose_validation`, `files_modified`,
`lesson_candidate.found`, `lessons_useful`, and `binary_checks.*[].result` with `yes` or `no`.
All binary checks must be `yes` for the gate to print `PASS`.
EOF

echo "OK: installed portable learning-loop core into $target_dir"
