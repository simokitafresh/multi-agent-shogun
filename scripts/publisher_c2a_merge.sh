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
# cmd_4478 §6.1-7: 単一 on_exit=元 rc 保存→既存 cleanup→PASS/FAIL を同期記録(fail-open)→元 rc 返却。telemetry 失敗でも本処理 rc 不変。
_C2A_T0="${EPOCHREALTIME/./}"; _C2A_T0="${_C2A_T0:0:16}"
_c2a_on_exit() {
    local rc=$?
    rm -rf -- "$WORK"
    (
        set +e
        . "$ROOT/scripts/lib/defense_overhead_writer.sh" || exit 0
        _now="${EPOCHREALTIME/./}"; _now="${_now:0:16}"
        _ms=$(( (_now - _C2A_T0 + 999) / 1000 )); [ "$_ms" -ge 0 ] || _ms=0
        _verdict=PASS; [ "$rc" -eq 0 ] || _verdict=FAIL
        defense_overhead_write publisher_c2a c2a_merge_total "$_ms" "$_verdict" \
            "c2a:${TASK_ID}:${COMMIT:0:12}:$$" "{\"task_id\":\"${TASK_ID}\",\"rc\":${rc}}"
    ) >/dev/null 2>&1 || true
    exit "$rc"
}
trap _c2a_on_exit EXIT
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
# PUBLISHER_C2A_MERGE_NOLOCK=1: 呼出し元が既に publisher lock を保持している(U1b の run_locked 等)
# 場合は lock-run を重ねない(flock は再入不可)。
if [[ "${PUBLISHER_C2A_MERGE_NOLOCK:-0}" = 1 ]]; then
    _c2a_runner=(bash -c)
else
    _c2a_runner=(bash "$ROOT/scripts/publisher_queue.sh" lock-run --bound 300 -- bash -c)
fi
"${_c2a_runner[@]}" '
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
c2a_target="$(git -C "$ROOT" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)"
[[ "$c2a_target" =~ ^[0-9a-f]{40}$ ]] || {
    echo "publisher_c2a_merge: origin/main unresolved after c2a push" >&2
    exit 1
}
# C2a publication may leave the shared root on a local-only equivalent commit
# with dirty runtime files.  Reconcile it immediately through the non-merge
# CAS/read-tree lane, which verifies local tree effects and restores exact
# dirty overlap before the next validator cycle can observe stale HEAD.
if [[ -x "$ROOT/scripts/safe_shared_main_ff.sh" ]]; then
    bash "$ROOT/scripts/safe_shared_main_ff.sh" --repo "$ROOT" "$c2a_target"
else
    # Minimal publisher fixtures may intentionally omit the optional shared
    # checkout helper; production roots always carry it and take this lane.
    echo "publisher_c2a_merge: shared sync helper unavailable; sync=SKIP" >&2
fi
git -C "$ROOT" merge-base --is-ancestor "$COMMIT" origin/main && echo "publisher_c2a_merge: ancestor OK ${COMMIT:0:9} -> origin/main $(git -C "$ROOT" rev-parse --short origin/main)"
