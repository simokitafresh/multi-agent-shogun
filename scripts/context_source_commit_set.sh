#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/project_path.sh
source "$ROOT/scripts/lib/project_path.sh"
REGISTRY="$ROOT/scripts/config/context_source_commits.tsv"
context_path="${1:-}"
commit="${2:-}"
reason="${3:-}"
evidence="${4:-}"

[[ "$context_path" == context/*.md ]] || { echo 'BLOCK: context path must be context/*.md' >&2; exit 1; }
[[ "$commit" =~ ^[0-9a-f]{7,40}$ ]] || { echo 'BLOCK: commit must be 7-40 lowercase hex' >&2; exit 1; }
[[ -n "$reason" && -n "$evidence" ]] || { echo 'BLOCK: reason and evidence are required' >&2; exit 1; }
registry_projects="$(awk -F '\t' -v p="$context_path" '$1==p && $2!="" {print $2}' "$REGISTRY")"
registry_count="$(printf '%s\n' "$registry_projects" | awk 'NF {n++} END {print n+0}')"
if [[ "$registry_count" -gt 1 ]]; then
  echo 'BLOCK: duplicate context registry entry' >&2
  exit 1
elif [[ "$registry_count" -eq 1 ]]; then
  project="$(printf '%s\n' "$registry_projects" | awk 'NF {print; exit}')"
else
  # Non-registered project root contexts may still be selected by the
  # completion gate. Resolve only an exact, active config/projects.yaml
  # context_file mapping; ambiguous/missing mappings remain fail-closed.
  project="$(awk -v target="$context_path" '
    function flush() {
      if (id != "" && context_file == target && status == "active") {
        print id
        matches++
      }
    }
    /^[[:space:]]*-[[:space:]]+id:[[:space:]]+/ {
      flush()
      id=$0
      sub(/.*id:[[:space:]]+/, "", id)
      gsub(/[[:space:]"\047]+$/, "", id)
      context_file=""
      status="active"
      next
    }
    /^[[:space:]]+context_file:[[:space:]]+/ {
      context_file=$0
      sub(/.*context_file:[[:space:]]+/, "", context_file)
      gsub(/^[[:space:]"\047]+|[[:space:]"\047]+$/, "", context_file)
      next
    }
    /^[[:space:]]+status:[[:space:]]+/ {
      status=$0
      sub(/.*status:[[:space:]]+/, "", status)
      gsub(/^[[:space:]"\047]+|[[:space:]"\047]+$/, "", status)
      next
    }
    END {
      flush()
      if (matches != 1) exit 1
    }
  ' "$ROOT/config/projects.yaml")" || {
    echo 'BLOCK: context project mapping missing, inactive, or ambiguous' >&2
    exit 1
  }
fi
case "$project" in
  infra) repo="$ROOT" ;;
  *)
    repo="$(cd "$ROOT" && get_project_path "$project")" || {
      echo "BLOCK: unknown registry project: $project" >&2
      exit 1
    }
    ;;
esac
[[ -d "$repo/.git" ]] || { echo "BLOCK: source repo missing: $repo" >&2; exit 1; }
git -C "$repo" cat-file -e "${commit}^{commit}" 2>/dev/null || { echo "BLOCK: commit does not exist in $project repo" >&2; exit 1; }
git -C "$repo" merge-base --is-ancestor "$commit" HEAD || { echo "BLOCK: commit is not an ancestor of $project HEAD" >&2; exit 1; }

file="$ROOT/$context_path"
[[ -f "$file" ]] || { echo 'BLOCK: context file missing' >&2; exit 1; }
# Serialize the complete read-modify-replace transaction per context path.
# The lock lives beside the target so independent context files never contend.
exec 9>"${file}.source_commit.lock"
flock 9
python3 - "$file" "$commit" "$reason" "$evidence" <<'PY'
import datetime, os, re, sys, tempfile
path, commit, reason, evidence = sys.argv[1:]
text = open(path, encoding='utf-8').read()
line = f'<!-- source_commit:{commit} reason:{reason} evidence:{evidence} -->'
pattern = re.compile(r'<!--\s*source_commit:([0-9a-f]{7,40})[^\n]*?-->')
# A context can record several independently reviewed source commits.  Replace
# only this commit's prior marker (upsert); retaining the others is the contract.
updated = pattern.sub(lambda match: '' if match.group(1) == commit else match.group(0), text)
# cmd_karo_hotfix_control_plane_contracts_ga321_20260723: publish both
# freshness markers in the same atomic replacement.
today = datetime.date.today().isoformat()
last_updated = f'<!-- last_updated: {today} {reason} -->'
last_updated_pattern = re.compile(r'<!--\s*last_updated:\s*[^>\n]*-->')
if last_updated_pattern.search(updated):
    updated = last_updated_pattern.sub(last_updated, updated, count=1)
else:
    lines = updated.splitlines(True)
    lines.insert(min(1, len(lines)), last_updated + '\n')
    updated = ''.join(lines)
lines = updated.splitlines(True)
pos = next(
    (i + 1 for i, value in enumerate(lines) if 'last_updated:' in value),
    min(1, len(lines)),
)
lines.insert(pos, line + '\n')
updated = ''.join(lines)
fd, tmp = tempfile.mkstemp(prefix='.source-commit.', dir=os.path.dirname(path))
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write(updated); f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
echo "SOURCE_COMMIT_SET path=$context_path commit=$commit"
