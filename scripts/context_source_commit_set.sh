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
project="$(awk -F '\t' -v p="$context_path" '$1==p {if (++n==1) v=$2} END {if (n==1) print v; else exit 1}' "$REGISTRY")" || {
  echo 'BLOCK: context registry entry missing or duplicate' >&2; exit 1;
}
case "$project" in
  infra) repo="$ROOT" ;;
  dm-signal) repo="$(cd "$ROOT" && get_project_path "$project")" ;;
  *) echo "BLOCK: unknown registry project: $project" >&2; exit 1 ;;
esac
[[ -d "$repo/.git" ]] || { echo "BLOCK: source repo missing: $repo" >&2; exit 1; }
git -C "$repo" cat-file -e "${commit}^{commit}" 2>/dev/null || { echo "BLOCK: commit does not exist in $project repo" >&2; exit 1; }
git -C "$repo" merge-base --is-ancestor "$commit" HEAD || { echo "BLOCK: commit is not an ancestor of $project HEAD" >&2; exit 1; }

file="$ROOT/$context_path"
[[ -f "$file" ]] || { echo 'BLOCK: context file missing' >&2; exit 1; }
python3 - "$file" "$commit" "$reason" "$evidence" <<'PY'
import os, re, sys, tempfile
path, commit, reason, evidence = sys.argv[1:]
text = open(path, encoding='utf-8').read()
line = f'<!-- source_commit:{commit} reason:{reason} evidence:{evidence} -->'
pattern = re.compile(r'<!--\s*source_commit:[0-9a-f]{7,40}[^\n]*?-->')
match = pattern.search(text)
if match:
    updated = text[:match.start()] + line + pattern.sub('', text[match.end():])
else:
    lines = text.splitlines(True)
    pos = next((i + 1 for i, v in enumerate(lines[:8]) if 'last_updated:' in v), min(1, len(lines)))
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
