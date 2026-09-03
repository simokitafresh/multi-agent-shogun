#!/usr/bin/env bash
# publisher_c2a_merge.sh — karo lane: publisher C2a RC(base_blob_mismatch)になった
# task commit を isolated clone で origin/main へ 3-way 統合し、Published-By trailer 付きの
# merge commit として push する。shared worktree では git merge を行わない(D012)。
#
# Usage: bash scripts/publisher_c2a_merge.sh <task_id> <commit_sha> [<conflict_path>]
#   conflict_path 既定=queue/insights.yaml。衝突時は task commit が親から変えた
#   `- id:` block だけを origin 版へ置換して解決する(台帳 append との文脈衝突用)。
#
# 2026-09-03 家老: 09:33〜10:40 に 4 件(0812/0912 kotaro, 0920 hayate, 1014 kotaro)を
# 手順で回収したが、手書き merge message に Published-By trailer が無く §15 条件(1)の
# trailer 率を 45/50 に落とした(将軍 msg_20260903_104037)。手順を script 化して trailer を固定する。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_ID="${1:-}"; COMMIT="${2:-}"; CONFLICT_PATH="${3:-queue/insights.yaml}"
[[ -n "$TASK_ID" && -n "$COMMIT" ]] || { echo "usage: publisher_c2a_merge.sh <task_id> <commit_sha> [<conflict_path>]" >&2; exit 2; }
git -C "$ROOT" cat-file -e "${COMMIT}^{commit}" 2>/dev/null || { echo "publisher_c2a_merge: commit not found in root objects: $COMMIT" >&2; exit 2; }
ORIGIN_URL="$(git -C "$ROOT" remote get-url origin)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/publisher_c2a_merge.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
RESOLVER="$WORK/resolve_blocks.py"
cat >"$RESOLVER" <<'PY'
import re, subprocess, sys
commit, path = sys.argv[1], sys.argv[2]
base = subprocess.check_output(["git", "show", f"HEAD:{path}"], text=True)
theirs = subprocess.check_output(["git", "show", f"{commit}:{path}"], text=True)
parent = subprocess.check_output(["git", "show", f"{commit}^:{path}"], text=True)
def blocks(text):
    return {m.group(1): m.group(0) for m in re.finditer(r"(?m)^- id: (\S+)\n(?:(?!^- id: ).*\n?)*", text)}
tb, pb = blocks(theirs), blocks(parent)
changed = [i for i in tb if pb.get(i) != tb[i]]
out, applied = base, 0
for i in changed:
    m = re.search(r"(?m)^- id: " + re.escape(i) + r"\n(?:(?!^- id: ).*\n?)*", out)
    if m:
        out = out[: m.start()] + tb[i] + out[m.end():]
        applied += 1
open(path, "w", encoding="utf-8").write(out)
print(f"publisher_c2a_merge: block-resolve path={path} changed={len(changed)} applied={applied}")
if applied != len(changed):
    raise SystemExit("publisher_c2a_merge: unresolved block(s) — manual review required")
PY
MSG="publisher: task=${TASK_ID} c2a-merge ${COMMIT:0:9} (karo lane: C2a base_blob_mismatch ${CONFLICT_PATH} を isolated clone で 3-way 統合)

Published-By: karo-lane c2a-merge task=${TASK_ID} source=${COMMIT}"
bash "$ROOT/scripts/publisher_queue.sh" lock-run --bound 300 -- bash -c '
set -euo pipefail
root="$1"; url="$2"; work="$3"; commit="$4"; path="$5"; resolver="$6"; msg="$7"
git clone -q --reference "$root" --branch main "$url" "$work/clone"
cd "$work/clone"
git fetch -q "$root" "$commit"
if git -c user.name=karo -c user.email=karo@shogun.local merge --no-ff --no-commit "$commit" >/dev/null 2>&1; then
    :
else
    conflicts="$(git diff --name-only --diff-filter=U)"
    [ "$conflicts" = "$path" ] || { echo "publisher_c2a_merge: unexpected conflicts: ${conflicts:-<none>}" >&2; exit 3; }
    git checkout HEAD -- "$path"
    python3 "$resolver" "$commit" "$path"
    python3 -c "import sys,yaml; yaml.safe_load(open(sys.argv[1], encoding=\"utf-8\"))" "$path"
    git add -- "$path"
fi
git -c user.name=karo -c user.email=karo@shogun.local commit -q -m "$msg"
git push -q origin HEAD:main
echo "publisher_c2a_merge: pushed $(git rev-parse --short HEAD) task=$(git log -1 --format=%s | cut -c1-60)"
' _ "$ROOT" "$ORIGIN_URL" "$WORK" "$COMMIT" "$CONFLICT_PATH" "$RESOLVER" "$MSG"
git -C "$ROOT" fetch -q origin
git -C "$ROOT" merge-base --is-ancestor "$COMMIT" origin/main && echo "publisher_c2a_merge: ancestor OK ${COMMIT:0:9} -> origin/main $(git -C "$ROOT" rev-parse --short origin/main)"
