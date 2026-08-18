#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${1:-}" == "--repo" ]]; then
    [[ -n "${2:-}" && -n "${3:-}" && -z "${4:-}" ]] || {
        echo "usage: bash scripts/safe_shared_main_ff.sh [--repo <repo>] <target-commit>" >&2
        exit 2
    }
    ROOT="$(cd "$2" && pwd)"
    TARGET="$3"
else
    TARGET="${1:-}"
fi

if [[ -z "$TARGET" ]]; then
    echo "usage: bash scripts/safe_shared_main_ff.sh [--repo <repo>] <target-commit>" >&2
    exit 2
fi

# A private index inherited from a scoped commit is exactly the state that can
# advance main/index while leaving the shared worktree at an older generation.
unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

branch="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD || true)"
[[ "$branch" == "main" ]] || {
    echo "BLOCK: shared fast-forward requires branch main (got ${branch:-detached})" >&2
    exit 2
}

old_head="$(git -C "$ROOT" rev-parse HEAD)"
target_head="$(git -C "$ROOT" rev-parse "${TARGET}^{commit}")"
git -C "$ROOT" merge-base --is-ancestor "$old_head" "$target_head" || {
    echo "BLOCK: target is not a fast-forward descendant of shared main" >&2
    exit 2
}

changed_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-changed.XXXXXX")"
dirty_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-dirty.XXXXXX")"
overlap_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-overlap.XXXXXX")"
cleanup() { rm -f -- "$changed_file" "$dirty_file" "$overlap_file"; }
trap cleanup EXIT

git -C "$ROOT" diff --name-only "$old_head" "$target_head" | sort -u > "$changed_file"
{
    git -C "$ROOT" diff --name-only
    git -C "$ROOT" diff --cached --name-only
    git -C "$ROOT" ls-files --others --exclude-standard
} | sort -u > "$dirty_file"
comm -12 "$changed_file" "$dirty_file" > "$overlap_file"
if [[ -s "$overlap_file" ]]; then
    echo "BLOCK: fast-forward would overlap shared worktree changes:" >&2
    sed -n '1,40p' "$overlap_file" >&2
    exit 2
fi

git -C "$ROOT" merge --ff-only --no-autostash "$target_head"

while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    git -C "$ROOT" diff --quiet HEAD -- "$path" || {
        echo "BLOCK: post-fast-forward worktree does not match HEAD: $path" >&2
        exit 1
    }
    git -C "$ROOT" diff --cached --quiet HEAD -- "$path" || {
        echo "BLOCK: post-fast-forward index does not match HEAD: $path" >&2
        exit 1
    }
done < "$changed_file"

printf 'SAFE_SHARED_MAIN_FF old=%s new=%s changed_paths=%s result=PASS\n' \
    "$old_head" "$target_head" "$(wc -l < "$changed_file")"
