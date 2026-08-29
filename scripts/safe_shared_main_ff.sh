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

common_dir="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"
exec 9>"$common_dir/safe_shared_main_ff.lock"
flock -x 9

branch="$(git -C "$ROOT" symbolic-ref --quiet --short HEAD || true)"
[[ "$branch" == "main" ]] || {
    echo "BLOCK: shared fast-forward requires branch main (got ${branch:-detached})" >&2
    exit 2
}

old_head="$(git -C "$ROOT" rev-parse HEAD)"
target_head="$(git -C "$ROOT" rev-parse "${TARGET}^{commit}")"

changed_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-changed.XXXXXX")"
dirty_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-dirty.XXXXXX")"
overlap_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-overlap.XXXXXX")"
merge_tree_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-merge-tree.XXXXXX")"
cleanup() { rm -f -- "$changed_file" "$dirty_file" "$overlap_file" "$merge_tree_file"; }
trap cleanup EXIT

mode=fast_forward
prospective_tree="$target_head"
if git -C "$ROOT" merge-base --is-ancestor "$target_head" "$old_head"; then
    mode=already_contains_target
    prospective_tree="$old_head"
elif ! git -C "$ROOT" merge-base --is-ancestor "$old_head" "$target_head"; then
    mode=diverged
    if ! git -C "$ROOT" merge-tree --write-tree "$old_head" "$target_head" > "$merge_tree_file"; then
        echo "BLOCK: divergent histories have merge conflicts in isolated merge-tree" >&2
        sed -n '1,40p' "$merge_tree_file" >&2
        exit 2
    fi
    prospective_tree="$(sed -n '1p' "$merge_tree_file")"
    git -C "$ROOT" cat-file -e "${prospective_tree}^{tree}" || {
        echo "BLOCK: isolated merge-tree did not produce a valid tree" >&2
        exit 2
    }
fi

# An ours merge (or an equivalent hand-built tree) can make target commits
# ancestors while retaining only the first-parent tree. Enumerate only merge
# commits newly reachable from target (old_head..target_head); comparing every
# historical hunk made the hot path slow and confused intentional later edits
# with this exact tree-level invariant.
verify_target_merge_trees() {
    local merge first_parent second_parent merge_tree first_tree changed_paths
    local -a new_merges=()
    mapfile -t new_merges < <(
        git -C "$ROOT" rev-list --merges "$old_head..$target_head"
    )
    local ours_equivalent=0 nonempty_parent_diffs=0
    for merge in "${new_merges[@]}"; do
        [[ -n "$merge" ]] || continue
        read -r first_parent second_parent < <(
            git -C "$ROOT" show -s --format='%P' "$merge"
        )
        [[ -n "$first_parent" && -n "$second_parent" ]] || continue
        merge_tree="$(git -C "$ROOT" rev-parse "$merge^{tree}")"
        first_tree="$(git -C "$ROOT" rev-parse "$first_parent^{tree}")"
        [[ "$merge_tree" == "$first_tree" ]] || continue
        changed_paths="$(git -C "$ROOT" diff --name-only "$first_parent" "$second_parent" | awk 'NF{n++} END{print n+0}')"
        [[ "$changed_paths" -gt 0 ]] || continue
        ours_equivalent=$((ours_equivalent + 1))
        nonempty_parent_diffs=$((nonempty_parent_diffs + changed_paths))
        echo "BLOCK: target introduces ours-equivalent merge with non-empty second-parent tree diff" >&2
        echo "  merge=$merge first_parent=$first_parent second_parent=$second_parent changed_paths=$changed_paths" >&2
    done
    printf 'SAFE_SHARED_MAIN_FF_MERGE_CHECK target_new_merges=%s ours_equivalent=%s parent_diff_paths=%s result=%s\n' \
        "${#new_merges[@]}" "$ours_equivalent" "$nonempty_parent_diffs" \
        "$([[ "$ours_equivalent" -eq 0 ]] && echo PASS || echo BLOCK)"
    if [[ "$ours_equivalent" -ne 0 ]]; then
        return 2
    fi
    return 0
}

verify_target_merge_trees

git -C "$ROOT" diff-tree --no-commit-id --name-only -r "$old_head" "$prospective_tree" | sort -u > "$changed_file"
{
    git -C "$ROOT" diff --name-only
    git -C "$ROOT" diff --cached --name-only
} | sort -u > "$dirty_file"

# A repository-wide untracked scan is both unnecessary for merge safety and
# prohibitively slow on the shared 9p worktree. Only an untracked path that the
# prospective tree changes can be overwritten, so probe that bounded set.
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    git -C "$ROOT" ls-files --others --exclude-standard -- "$path"
done < "$changed_file" | sort -u >> "$dirty_file"
sort -u -o "$dirty_file" "$dirty_file"
comm -12 "$changed_file" "$dirty_file" > "$overlap_file"
if [[ -s "$overlap_file" ]]; then
    echo "BLOCK: fast-forward would overlap shared worktree changes:" >&2
    sed -n '1,40p' "$overlap_file" >&2
    exit 2
fi

case "$mode" in
    fast_forward)
        git -C "$ROOT" merge --ff-only --no-autostash "$target_head"
        ;;
    diverged)
        git -C "$ROOT" merge --no-edit --no-autostash -m "Merge remote shared main safely" "$target_head"
        ;;
    already_contains_target)
        :
        ;;
esac

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

new_head="$(git -C "$ROOT" rev-parse HEAD)"
git -C "$ROOT" merge-base --is-ancestor "$target_head" "$new_head" || {
    echo "BLOCK: target history is not contained after convergence" >&2
    exit 1
}
printf 'SAFE_SHARED_MAIN_FF old=%s target=%s new=%s mode=%s changed_paths=%s dirty_paths=%s result=PASS\n' \
    "$old_head" "$target_head" "$new_head" "$mode" "$(wc -l < "$changed_file")" "$(wc -l < "$dirty_file")"
