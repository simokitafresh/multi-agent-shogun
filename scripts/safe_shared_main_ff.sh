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

# Publish an already-descendant local main without touching the shared
# checkout.  This is deliberately a separate mode from convergence: callers
# must provide an independently verified GREEN result for the exact remote
# tip, and every non-eligible state returns success-with-no-push so a retrying
# gate records WAIT instead of turning an external condition into a failure.
safe_shared_main_auto_push() {
    local repo="$1" threshold="${2:-1}" ci_state="${3:-}" remote_tip local_head
    local relation behind ahead common_dir lock_file lock_fd before_head before_index before_dirty
    local temp_parent clean_repo push_rc published_tip after_head after_index after_dirty

    [[ "$threshold" =~ ^[1-9][0-9]*$ ]] || threshold=1
    if [[ "$ci_state" != "GREEN" ]]; then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s push=0 result=SKIP reason=ci_not_green\n' "${ci_state:-UNKNOWN}"
        return 0
    fi
    [[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "main" ]] || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH push=0 result=SKIP reason=branch_not_main\n'
        return 0
    }
    remote_tip="$(git -C "$repo" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
    [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH push=0 result=SKIP reason=remote_tip_unresolved\n'
        return 0
    }
    git -C "$repo" fetch -q origin refs/heads/main >/dev/null 2>&1 || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s push=0 result=SKIP reason=remote_tip_fetch_failed\n' "$remote_tip"
        return 0
    }
    local_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    relation="$(git -C "$repo" rev-list --left-right --count "${remote_tip}...${local_head}" 2>/dev/null || true)"
    read -r behind ahead <<< "$relation"
    [[ "$behind" =~ ^[0-9]+$ && "$ahead" =~ ^[0-9]+$ ]] || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s push=0 result=SKIP reason=relation_unresolved\n' "$remote_tip"
        return 0
    }
    if (( behind != 0 )); then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=behind_or_diverged\n' "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if (( ahead < threshold )); then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s threshold=%s push=0 result=SKIP reason=ahead_below_threshold\n' "$remote_tip" "$behind" "$ahead" "$threshold"
        return 0
    fi

    common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    lock_file="$common_dir/safe_shared_main_ff.lock"
    exec {lock_fd}>"$lock_file" || return 1
    if ! flock -n "$lock_fd"; then
        eval "exec ${lock_fd}>&-"
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=publication_lock_busy\n' "$remote_tip" "$behind" "$ahead"
        return 0
    fi

    before_head="$(git -C "$repo" rev-parse HEAD)"
    before_index="$(git -C "$repo" diff --cached --binary | sha256sum | awk '{print $1}')"
    before_dirty="$(git -C "$repo" status --porcelain=v1 --untracked-files=all | sha256sum | awk '{print $1}')"
    temp_parent="$(mktemp -d "${TMPDIR:-/tmp}/safe-shared-main-auto-push.XXXXXX")" || {
        flock -u "$lock_fd"; eval "exec ${lock_fd}>&-"; return 1;
    }
    clean_repo="$temp_parent/repo"
    cleanup_auto_push() {
        if [[ -d "$clean_repo" ]]; then
            git -C "$repo" worktree remove --force "$clean_repo" >/dev/null 2>&1 || true
        fi
        rmdir "$temp_parent" 2>/dev/null || true
        flock -u "$lock_fd"
        eval "exec ${lock_fd}>&-"
    }
    if ! git -C "$repo" worktree add --detach "$clean_repo" "$remote_tip" >/dev/null 2>&1; then
        cleanup_auto_push
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=isolated_worktree_unavailable\n' "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if ! git -C "$clean_repo" merge-base --is-ancestor "$remote_tip" "$before_head"; then
        cleanup_auto_push
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=remote_race_or_diverged\n' "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if git -C "$clean_repo" push origin "${before_head}:refs/heads/main" >/dev/null 2>&1; then
        published_tip="$(git -C "$repo" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
        if [[ ! "$published_tip" =~ ^[0-9a-f]{40}$ ]] || ! git -C "$repo" merge-base --is-ancestor "$before_head" "$published_tip"; then
            cleanup_auto_push
            printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=published_tip_unverified\n' "$remote_tip" "$behind" "$ahead"
            return 0
        fi
        push_rc=0
    else
        push_rc=$?
    fi
    after_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    after_index="$(git -C "$repo" diff --cached --binary | sha256sum | awk '{print $1}')"
    after_dirty="$(git -C "$repo" status --porcelain=v1 --untracked-files=all | sha256sum | awk '{print $1}')"
    cleanup_auto_push
    if (( push_rc != 0 )); then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=push_competition_or_hook_failure\n' "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if [[ "$before_head" != "$after_head" || "$before_index" != "$after_index" || "$before_dirty" != "$after_dirty" ]]; then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s published=%s push=0 result=BLOCK reason=shared_state_changed\n' "$remote_tip" "$published_tip"
        return 1
    fi
    printf 'SAFE_SHARED_MAIN_AUTO_PUSH remote_tip=%s published=%s behind=%s ahead=%s threshold=%s push=1 shared_head_unchanged=yes shared_index_unchanged=yes shared_dirty_unchanged=yes result=PASS\n' "$remote_tip" "$published_tip" "$behind" "$ahead" "$threshold"
    return 0
}

if [[ "${1:-}" == "--auto-push-if-ready" ]]; then
    [[ -n "${2:-}" && -n "${3:-}" && -z "${4:-}" ]] || {
        echo "usage: bash scripts/safe_shared_main_ff.sh --auto-push-if-ready <repo> <ci-state>" >&2
        exit 2
    }
    safe_shared_main_auto_push "$2" "${SAFE_SHARED_MAIN_FF_AUTO_PUSH_THRESHOLD:-1}" "$3"
    exit $?
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

shared_state_fingerprint() {
    local path
    {
        git -C "$ROOT" diff --no-ext-diff --binary
        git -C "$ROOT" diff --cached --no-ext-diff --binary
        while IFS= read -r -d '' path; do
            printf 'STATUS:%s\n' "$path"
            if [[ "$path" == '?? '* ]]; then
                path="${path#?? }"
                if [[ -f "$ROOT/$path" ]]; then
                    sha256sum "$ROOT/$path"
                fi
            fi
        done < <(git -C "$ROOT" status --porcelain=v1 -z --untracked-files=all)
    } | sha256sum | awk '{print $1}'
}

isolated_publish_fallback() {
    local target_head="$1" remote=origin push_ref=refs/heads/main
    local max_retries attempt remote_tip clean_repo temp_parent push_output
    local published_remote_sha cleanup_rc push_rc

    max_retries="${SAFE_SHARED_MAIN_FF_MAX_RETRIES:-2}"
    [[ "$max_retries" =~ ^[0-9]+$ ]] || max_retries=2
    temp_parent="$(mktemp -d "${TMPDIR:-/tmp}/safe-shared-main-ff.XXXXXX")" || return 1
    cleanup_isolated() {
        cleanup_rc=0
        if [[ -n "${clean_repo:-}" && -e "$clean_repo" ]]; then
            git -C "$ROOT" worktree remove --force "$clean_repo" >/dev/null 2>&1 || cleanup_rc=1
            [[ ! -e "$clean_repo" ]] || cleanup_rc=1
        fi
        rm -f -- "$temp_parent"/*
        [[ ! -d "$temp_parent" ]] || rmdir "$temp_parent" 2>/dev/null || cleanup_rc=1
        return "$cleanup_rc"
    }

    for ((attempt=0; attempt<=max_retries; attempt++)); do
        remote_tip="$(git -C "$ROOT" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')"
        [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || {
            echo "BLOCK: isolated fallback remote tip unavailable" >&2
            cleanup_isolated || true
            return 1
        }
        git -C "$ROOT" fetch -q "$remote" "$push_ref" >/dev/null 2>&1 || {
            echo "BLOCK: isolated fallback remote tip fetch failed" >&2
            cleanup_isolated || true
            return 1
        }

        clean_repo="$temp_parent/repo-$attempt"
        git -C "$ROOT" worktree add --detach "$clean_repo" "$remote_tip" >/dev/null 2>&1 || {
            echo "BLOCK: isolated fallback worktree creation failed" >&2
            cleanup_isolated || true
            return 1
        }
        if ! git -C "$clean_repo" merge --no-edit --no-autostash "$target_head" >/dev/null 2>"$temp_parent/merge-$attempt.err"; then
            echo "BLOCK: isolated fallback merge conflict" >&2
            sed -n '1,40p' "$temp_parent/merge-$attempt.err" >&2
            git -C "$clean_repo" merge --abort >/dev/null 2>&1 || true
            cleanup_isolated || true
            return 1
        fi

        push_output="$temp_parent/push-$attempt.out"
        if git -C "$clean_repo" push "$remote" "HEAD:$push_ref" >"$push_output" 2>&1; then
            published_remote_sha="$(git -C "$ROOT" ls-remote "$remote" "$push_ref" 2>/dev/null | awk 'NR==1 {print $1}')"
            if [[ "$published_remote_sha" =~ ^[0-9a-f]{40}$ ]] \
                && git -C "$ROOT" merge-base --is-ancestor "$target_head" "$published_remote_sha"; then
                cleanup_isolated || {
                    echo "BLOCK: isolated fallback cleanup failed" >&2
                    return 1
                }
                printf 'SAFE_SHARED_MAIN_FF_FALLBACK target=%s remote_tip=%s published=%s attempt=%s remote_contains_target=yes shared_head_unchanged=yes shared_index_unchanged=yes shared_dirty_unchanged=yes result=PASS\n' \
                    "$target_head" "$remote_tip" "$published_remote_sha" "$attempt"
                return 0
            fi
            echo "BLOCK: isolated fallback remote verification failed" >&2
            cat "$push_output" >&2
            cleanup_isolated || true
            return 1
        fi

        cat "$push_output" >&2
        push_rc=1
        if grep -Eqi 'cannot lock ref|non-fast-forward|fetch first|tip of your current branch is behind|remote contains work' "$push_output"; then
            push_rc=2
        fi
        cleanup_isolated || {
            echo "BLOCK: isolated fallback cleanup failed" >&2
            return 1
        }
        clean_repo=""
        if [[ "$push_rc" -ne 2 || "$attempt" -ge "$max_retries" ]]; then
            echo "BLOCK: isolated fallback push failed" >&2
            return 1
        fi
        echo "SAFE_SHARED_MAIN_FF_FALLBACK retry=$((attempt + 1))/$max_retries remote_tip_race=yes" >&2
    done
    return 1
}

if [[ -s "$overlap_file" ]]; then
    echo "BLOCK: fast-forward would overlap shared worktree changes:" >&2
    sed -n '1,40p' "$overlap_file" >&2
    shared_before="$(shared_state_fingerprint)"
    if isolated_publish_fallback "$target_head"; then
        shared_after="$(shared_state_fingerprint)"
        [[ "$shared_before" == "$shared_after" ]] || {
            echo "BLOCK: isolated fallback changed shared worktree state" >&2
            exit 1
        }
        exit 0
    fi
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
