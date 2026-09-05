#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -r "$ROOT/scripts/lib/publisher_single_flag.sh" ]]; then
    source "$ROOT/scripts/lib/publisher_single_flag.sh"
else
    # Unit fixtures may copy this script alone into an isolated repository.
    # Keep that harness self-contained while retaining the production helper.
    publisher_single_enabled() {
        local _publisher_root="${1:-${REPO_ROOT:-${ROOT:-${SCRIPT_DIR:-}}}}"
        [[ "${PUBLISHER_SINGLE:-0}" == 1 || ( -n "$_publisher_root" && -f "$_publisher_root/queue/flags/publisher_single" ) ]]
    }
fi
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
# provide the exact remote-tip CI state as telemetry, while ancestry and the
# shared-state invariant remain the publication admission checks.  GREEN,
# UNKNOWN, and RED all use the same normal push path; a CI verdict is observed
# after publication rather than used as a circular precondition for it.
safe_shared_main_auto_push() {
    publisher_single_enabled && { echo "PUBLISHER_SINGLE safe_shared_main_ff push=0 result=SKIP reason=publisher_request"; return 0; }
    local repo="$1" threshold="${2:-1}" ci_state="${3:-}" remote_tip local_head
    local relation behind ahead common_dir lock_file lock_fd before_head before_index before_dirty
    local current_remote_tip
    local temp_parent clean_repo push_rc published_tip after_head after_index after_dirty

    [[ "$threshold" =~ ^[1-9][0-9]*$ ]] || threshold=1
    ci_state="${ci_state:-UNKNOWN}"
    case "$ci_state" in
        GREEN|UNKNOWN|RED) ;;
        *)
            printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s push=0 result=SKIP reason=ci_state_invalid\n' "$ci_state"
            return 0
            ;;
    esac
    if [[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" != "main" ]]; then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s push=0 result=SKIP reason=branch_not_main\n' "$ci_state"
        return 0
    fi
    remote_tip="$(git -C "$repo" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
    [[ "$remote_tip" =~ ^[0-9a-f]{40}$ ]] || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s push=0 result=SKIP reason=remote_tip_unresolved\n' "$ci_state"
        return 0
    }
    git -C "$repo" fetch -q origin refs/heads/main >/dev/null 2>&1 || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s push=0 result=SKIP reason=remote_tip_fetch_failed\n' "$ci_state" "$remote_tip"
        return 0
    }
    local_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    relation="$(git -C "$repo" rev-list --left-right --count "${remote_tip}...${local_head}" 2>/dev/null || true)"
    read -r behind ahead <<< "$relation"
    [[ "$behind" =~ ^[0-9]+$ && "$ahead" =~ ^[0-9]+$ ]] || {
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s push=0 result=SKIP reason=relation_unresolved\n' "$ci_state" "$remote_tip"
        return 0
    }
    if (( behind != 0 )); then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=behind_or_diverged\n' "$ci_state" "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if (( ahead < threshold )); then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s threshold=%s push=0 result=SKIP reason=ahead_below_threshold\n' "$ci_state" "$remote_tip" "$behind" "$ahead" "$threshold"
        return 0
    fi

    common_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
    lock_file="$common_dir/safe_shared_main_ff.lock"
    exec {lock_fd}>"$lock_file" || return 1
    if ! flock -n "$lock_fd"; then
        eval "exec ${lock_fd}>&-"
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=publication_lock_busy\n' "$ci_state" "$remote_tip" "$behind" "$ahead"
        return 0
    fi

    before_head="$(git -C "$repo" rev-parse HEAD)"
    current_remote_tip="$(git -C "$repo" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
    if [[ "$current_remote_tip" != "$remote_tip" ]]; then
        flock -u "$lock_fd"
        eval "exec ${lock_fd}>&-"
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s current_remote_tip=%s push=0 result=SKIP reason=remote_race_or_diverged\n' "$ci_state" "$remote_tip" "${current_remote_tip:-unresolved}"
        return 0
    fi
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
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=isolated_worktree_unavailable\n' "$ci_state" "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if ! git -C "$clean_repo" merge-base --is-ancestor "$remote_tip" "$before_head"; then
        cleanup_auto_push
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=remote_race_or_diverged\n' "$ci_state" "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if git -C "$clean_repo" push origin "${before_head}:refs/heads/main" >/dev/null 2>&1; then
        published_tip="$(git -C "$repo" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
        if [[ ! "$published_tip" =~ ^[0-9a-f]{40}$ ]] || ! git -C "$repo" merge-base --is-ancestor "$before_head" "$published_tip"; then
            cleanup_auto_push
            printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=published_tip_unverified\n' "$ci_state" "$remote_tip" "$behind" "$ahead"
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
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s behind=%s ahead=%s push=0 result=SKIP reason=push_competition_or_hook_failure\n' "$ci_state" "$remote_tip" "$behind" "$ahead"
        return 0
    fi
    if [[ "$before_head" != "$after_head" || "$before_index" != "$after_index" || "$before_dirty" != "$after_dirty" ]]; then
        printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s published=%s push=0 result=BLOCK reason=shared_state_changed\n' "$ci_state" "$remote_tip" "$published_tip"
        return 1
    fi
    printf 'SAFE_SHARED_MAIN_AUTO_PUSH ci=%s remote_tip=%s published=%s behind=%s ahead=%s threshold=%s push=1 shared_head_unchanged=yes shared_index_unchanged=yes shared_dirty_unchanged=yes result=PASS\n' "$ci_state" "$remote_tip" "$published_tip" "$behind" "$ahead" "$threshold"
    return 0
}

# second-parent が merge base に対して追加した行の集合が prospective tree の同 path に
# 全て含まれていれば 0(保存されている)。追加行が無い(削除のみ/取得失敗)場合は 1 を返し、
# 呼出し元の従来判定(blob 不一致=regression)に委ねる。
safe_ff_second_parent_lines_preserved() {
    local repo="$1" base="$2" second="$3" prospective="$4" path="$5"
    local added prospective_file missing
    [[ -n "$base" && -n "$second" && -n "$prospective" && -n "$path" ]] || return 1
    added="$(git -C "$repo" diff "$base" "$second" -- "$path" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+{3} ' | cut -c2- | sort -u)" || return 1
    [[ -n "$added" ]] || return 1
    prospective_file="$(git -C "$repo" show "$prospective:$path" 2>/dev/null)" || return 1
    missing="$(comm -23 <(printf '%s\n' "$added") <(printf '%s\n' "$prospective_file" | sort -u) | wc -l | tr -d ' ')"
    [[ "$missing" -eq 0 ]]
}

verify_ours_equivalent_merge_trees() {
    local repo="$1" old_base="$2" target_head="$3" prospective_tree="${4:-}"
    local merge first_parent second_parent merge_tree first_tree changed_paths path
    local merge_base merge_base_tree published_head published_merges=0 ours_equivalent=0 nonempty_parent_diffs=0
    local first_blob parent_blob prospective_blob second_blob old_tree
    local -a new_merges=() merge_paths=() merge_regression_paths=() regression_paths=()
    local -A regression_seen=()

    mapfile -t new_merges < <(
        git -C "$repo" rev-list --merges "$old_base..$target_head"
    )
    # Published ours-equivalent merges remain allowed as history, but their
    # first-parent paths are still evidence for a prospective merge-tree
    # regression. This keeps the published-history exemption narrow.
    published_head="$(git -C "$repo" rev-parse --verify refs/remotes/origin/main^{commit} 2>/dev/null || true)"
    old_tree="$(git -C "$repo" rev-parse "$old_base^{tree}")"
    for merge in "${new_merges[@]}"; do
        [[ -n "$merge" ]] || continue
        read -r first_parent second_parent < <(
            git -C "$repo" show -s --format='%P' "$merge"
        )
        [[ -n "$first_parent" && -n "$second_parent" ]] || continue
        merge_tree="$(git -C "$repo" rev-parse "$merge^{tree}")"
        first_tree="$(git -C "$repo" rev-parse "$first_parent^{tree}")"
        [[ "$merge_tree" == "$first_tree" ]] || continue
        mapfile -t merge_paths < <(git -C "$repo" diff --name-only "$first_parent" "$second_parent")
        changed_paths="${#merge_paths[@]}"
        [[ "$changed_paths" -gt 0 ]] || continue

        if [[ -n "$published_head" ]] \
            && git -C "$repo" merge-base --is-ancestor "$merge" "$published_head"; then
            published_merges=$((published_merges + 1))
            # Only a local parent that contains the merge's second-parent
            # history can be regressed by replaying the published ours tree.
            # An unrelated ancestor (for example a normal fast-forward from
            # the fixture base) must retain the published-history exemption.
            if [[ -n "$prospective_tree" ]] \
                && git -C "$repo" merge-base --is-ancestor "$second_parent" "$old_base"; then
                for path in "${merge_paths[@]}"; do
                    first_blob="$(git -C "$repo" rev-parse --verify -q "$first_tree:$path" 2>/dev/null || printf \'__ABSENT__\')"
                    parent_blob="$(git -C "$repo" rev-parse --verify -q "$old_tree:$path" 2>/dev/null || printf \'__ABSENT__\')"
                    prospective_blob="$(git -C "$repo" rev-parse --verify -q "$prospective_tree:$path" 2>/dev/null || printf \'__ABSENT__\')"
                    if [[ "$first_blob" != "$parent_blob" \
                       && "$prospective_blob" != "$parent_blob" \
                       && -z "${regression_seen[$path]+yes}" ]]; then
                        regression_seen["$path"]=1
                        regression_paths+=("$path")
                    fi
                done
            fi
            continue
        fi

        # An unpublished ours-equivalent merge is unsafe only when it loses a
        # change introduced by its second parent. A merge whose second parent
        # is still at the merge base is normal local-first integration and
        # must not be mistaken for content loss from an ancestry merge.
        merge_regression_paths=()
        merge_base="$(git -C "$repo" merge-base "$first_parent" "$second_parent" 2>/dev/null || true)"
        merge_base_tree=""
        if [[ -n "$merge_base" ]]; then
            merge_base_tree="$(git -C "$repo" rev-parse "$merge_base^{tree}" 2>/dev/null || true)"
        fi
        if [[ -n "$prospective_tree" && -n "$merge_base_tree" ]]; then
            for path in "${merge_paths[@]}"; do
                [[ -n "$path" ]] || continue
                parent_blob="$(git -C "$repo" rev-parse --verify -q "$merge_base_tree:$path" 2>/dev/null || printf \'__ABSENT__\')"
                second_blob="$(git -C "$repo" rev-parse --verify -q "$second_parent:$path" 2>/dev/null || printf \'__ABSENT__\')"
                prospective_blob="$(git -C "$repo" rev-parse --verify -q "$prospective_tree:$path" 2>/dev/null || printf \'__ABSENT__\')"
                if [[ "$second_blob" != "$parent_blob" \
                   && "$prospective_blob" != "$second_blob" ]]; then
                    # 2026-09-02 将軍 D0: blob 不一致は損失の証明ではない。ID merge driver
                    # (queue/insights.yaml 等)が second-parent の追加行を含む superset を
                    # 作った merge(60d87b68d)を pre-push が regression と誤判定し便が 1h 停止した。
                    # second が merge base に対して足した行が prospective に全て残っていれば
                    # 内容は失われていない=regression ではない。
                    if safe_ff_second_parent_lines_preserved "$repo" "$merge_base" "$second_parent" "$prospective_tree" "$path"; then
                        continue
                    fi
                    merge_regression_paths+=("$path")
                fi
            done
        fi
        [[ "${#merge_regression_paths[@]}" -gt 0 ]] || continue

        ours_equivalent=$((ours_equivalent + 1))
        nonempty_parent_diffs=$((nonempty_parent_diffs + changed_paths))
        for path in "${merge_regression_paths[@]}"; do
            [[ -n "$path" ]] || continue
            if [[ -z "${regression_seen[$path]+yes}" ]]; then
                regression_seen["$path"]=1
                regression_paths+=("$path")
            fi
        done
        echo "BLOCK: target introduces ours-equivalent merge with non-empty second-parent tree diff" >&2
        echo "  merge=$merge first_parent=$first_parent second_parent=$second_parent changed_paths=$changed_paths" >&2
    done

    if [[ "${#regression_paths[@]}" -gt 0 ]]; then
        mapfile -t regression_paths < <(printf '%s\n' "${regression_paths[@]}" | sort -u)
        printf 'ANCESTRY-MERGE-REGRESSION paths=%s\n' "$(IFS=,; printf '%s' "${regression_paths[*]}")" >&2
    fi
    local merge_check_result=PASS
    if [[ "$ours_equivalent" -ne 0 || "${#regression_paths[@]}" -gt 0 ]]; then
        merge_check_result=BLOCK
    fi
    printf 'SAFE_SHARED_MAIN_FF_MERGE_CHECK target_new_merges=%s published_merges=%s ours_equivalent=%s parent_diff_paths=%s result=%s\n' \
        "${#new_merges[@]}" "$published_merges" "$ours_equivalent" "$nonempty_parent_diffs" \
        "$merge_check_result"
    if [[ "$merge_check_result" == BLOCK ]]; then
        return 2
    fi
    return 0
}

# A divergent shared checkout may carry a local-only commit that was already
# published by an equivalent tree on origin/main.  The shared ref may move to
# target only when every tree effect introduced by the local-only side is
# byte-for-byte and mode-for-mode present in target.  This deliberately does
# not create a merge commit: the target ancestry is the canonical publication
# history and the local commit is safe to discard only after its effects are
# proven retained.
verify_local_effects_in_target() {
    local repo="$1" old_head="$2" target_head="$3" base path old_entry target_entry
    local effect_count=0 mismatch_count=0
    local effects_file="${4:-}"
    base="$(git -C "$repo" merge-base "$old_head" "$target_head" 2>/dev/null || true)"
    [[ -n "$base" ]] || {
        echo "BLOCK: divergent histories have no merge base" >&2
        return 2
    }
    if [[ -n "$effects_file" ]]; then
        git -C "$repo" diff-tree --no-commit-id --name-only -r "$base" "$old_head" | sort -u >"$effects_file"
    else
        effects_file="$(mktemp "${TMPDIR:-/tmp}/safe-shared-main-effects.XXXXXX")"
        git -C "$repo" diff-tree --no-commit-id --name-only -r "$base" "$old_head" | sort -u >"$effects_file"
    fi
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        effect_count=$((effect_count + 1))
        old_entry="$(git -C "$repo" ls-tree -r "$old_head" -- "$path")"
        target_entry="$(git -C "$repo" ls-tree -r "$target_head" -- "$path")"
        if [[ "$old_entry" != "$target_entry" ]]; then
            mismatch_count=$((mismatch_count + 1))
            printf 'BLOCK: local-only tree effect is absent from target path=%s old=%s target=%s\n' \
                "$path" "${old_entry:-ABSENT}" "${target_entry:-ABSENT}" >&2
        fi
    done <"$effects_file"
    [[ -n "${4:-}" ]] || rm -f -- "$effects_file"
    printf 'SAFE_SHARED_MAIN_FF_LOCAL_EFFECT_CHECK base=%s effect_paths=%s mismatches=%s result=%s\n' \
        "$base" "$effect_count" "$mismatch_count" "$([[ "$mismatch_count" -eq 0 ]] && echo PASS || echo BLOCK)"
    [[ "$mismatch_count" -eq 0 ]]
}

if [[ "${1:-}" == "--verify-merge-tree" ]]; then
    [[ -n "${2:-}" && -n "${3:-}" && -n "${4:-}" && -n "${5:-}" && -z "${6:-}" ]] || {
        echo "usage: bash scripts/safe_shared_main_ff.sh --verify-merge-tree <repo> <parent> <target> <tree>" >&2
        exit 2
    }
    verify_ours_equivalent_merge_trees "$2" "$3" "$4" "$5"
    exit $?
fi

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
cleanup_preflight() {
    rm -f -- "$changed_file" "$dirty_file" "$overlap_file" "$merge_tree_file" \
        "${staged_file:-}" "${unstaged_file:-}" "${untracked_file:-}" "${index_backup_file:-}"
    if [[ -n "${backup_dir:-}" ]]; then
        rm -f -- "$backup_dir"/* 2>/dev/null || true
        rmdir -- "$backup_dir" 2>/dev/null || true
    fi
}
trap cleanup_preflight EXIT

mode=fast_forward
prospective_tree="$target_head"
if git -C "$ROOT" merge-base --is-ancestor "$target_head" "$old_head"; then
    mode=already_contains_target
    prospective_tree="$old_head"
elif ! git -C "$ROOT" merge-base --is-ancestor "$old_head" "$target_head"; then
    mode=diverged
    # D012: do not synthesize a merge in the shared checkout.  A local-only
    # side may be discarded only after every tree effect is proven present in
    # the canonical target tree.
    verify_local_effects_in_target "$ROOT" "$old_head" "$target_head" "$merge_tree_file" || exit 2
    prospective_tree="$target_head"
fi

verify_ours_equivalent_merge_trees "$ROOT" "$old_head" "$target_head" "$prospective_tree"

git -C "$ROOT" diff-tree --no-commit-id --name-only -r "$old_head" "$prospective_tree" | sort -u > "$changed_file"
staged_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-staged.XXXXXX")"
unstaged_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-unstaged.XXXXXX")"
untracked_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-untracked.XXXXXX")"
index_backup_file="$(mktemp "${TMPDIR:-/tmp}/shared-main-ff-index.XXXXXX")"
backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/shared-main-ff-backup.XXXXXX")"
git -C "$ROOT" diff --name-only | sort -u > "$unstaged_file"
git -C "$ROOT" diff --cached --name-only | sort -u > "$staged_file"

# A repository-wide untracked scan is both unnecessary for merge safety and
# prohibitively slow on the shared 9p worktree. Only an untracked path that the
# prospective tree changes can be overwritten, so probe that bounded set.
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    git -C "$ROOT" ls-files --others --exclude-standard -- "$path"
done < "$changed_file" | sort -u > "$untracked_file"
{
    cat "$unstaged_file"
    cat "$staged_file"
    cat "$untracked_file"
} | sort -u > "$dirty_file"
comm -12 "$changed_file" "$staged_file" > "$overlap_file"
if [[ -s "$overlap_file" ]]; then
    echo "BLOCK: staged changes overlap target paths:" >&2
    sed -n '1,40p' "$overlap_file" >&2
    exit 2
fi
if comm -12 "$changed_file" "$untracked_file" | grep -q .; then
    echo "BLOCK: untracked path would be overwritten by target convergence" >&2
    comm -12 "$changed_file" "$untracked_file" | sed -n '1,40p' >&2
    exit 2
fi

# Snapshot staged non-overlap entries before targetizing the index.  This
# prevents an unrelated staged change from silently becoming unstaged.
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    git -C "$ROOT" ls-files --stage -- "$path" >> "$index_backup_file"
done < "$staged_file"

# Save each unstaged tracked overlap as a real worktree copy plus explicit
# mode/hash metadata.  This is the recovery source if targetization fails.
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ ! -f "$ROOT/$path" || -L "$ROOT/$path" ]]; then
        echo "BLOCK: dirty tracked overlap must be a regular non-symlink file: $path" >&2
        exit 2
    fi
    backup_path="$backup_dir/$path"
    mkdir -p -- "$(dirname "$backup_path")"
    cp -a -- "$ROOT/$path" "$backup_path"
    dirty_hash="$(git -C "$ROOT" hash-object --no-filters -- "$path")"
    dirty_mode="$(stat -c '%a' -- "$ROOT/$path")"
    printf '%s\t%s\t%s\n' "$path" "$dirty_mode" "$dirty_hash" >> "$backup_dir/manifest"
done < "$unstaged_file"

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

# A patch fingerprint is tied to HEAD and therefore changes legitimately when
# the ref is synchronized.  For preservation checks use only status, path,
# blob hash, and worktree mode so the value remains comparable across HEADs.
dirty_worktree_fingerprint() {
    local entry path
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        path="${entry:3}"
        printf 'STATUS:%s\n' "$entry"
        if [[ -f "$ROOT/$path" || -L "$ROOT/$path" ]]; then
            printf 'MODE:%s HASH:%s\n' \
                "$(stat -c '%a' -- "$ROOT/$path")" \
                "$(git -C "$ROOT" hash-object --no-filters -- "$path")"
        fi
    done < <(git -C "$ROOT" status --porcelain=v1 --untracked-files=all) | sha256sum | awk '{print $1}'
}

cleanup_shared_sync() {
    rm -f -- "$changed_file" "$dirty_file" "$overlap_file" "$merge_tree_file" \
        "$staged_file" "$unstaged_file" "$untracked_file" "$index_backup_file"
    rm -f -- "$backup_dir"/* 2>/dev/null || true
    rmdir -- "$backup_dir" 2>/dev/null || true
}

restore_staged_index() {
    local path entry mode blob stage metadata
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        git -C "$ROOT" update-index --force-remove -- "$path" >/dev/null 2>&1 || true
    done < "$staged_file"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        path="${entry#*$'\t'}"
        metadata="${entry%%$'\t'*}"
        read -r mode blob stage <<< "$metadata"
        [[ -n "$path" && -n "$mode" && -n "$blob" ]] || return 1
        git -C "$ROOT" update-index --add --cacheinfo "$mode,$blob,$path"
    done < "$index_backup_file"
}

restore_dirty_overlap() {
    local path mode expected_hash actual_hash backup_path
    [[ -f "$backup_dir/manifest" ]] || return 0
    while IFS=$'\t' read -r path mode expected_hash; do
        [[ -n "$path" ]] || continue
        backup_path="$backup_dir/$path"
        [[ -e "$backup_path" || -L "$backup_path" ]] || return 1
        if [[ -e "$ROOT/$path" || -L "$ROOT/$path" ]]; then
            rm -f -- "$ROOT/$path"
        fi
        mkdir -p -- "$(dirname "$ROOT/$path")"
        cp -a -- "$backup_path" "$ROOT/$path"
        chmod "$mode" -- "$ROOT/$path"
        actual_hash="$(git -C "$ROOT" hash-object --no-filters -- "$path")"
        [[ "$actual_hash" == "$expected_hash" ]] || return 1
    done < "$backup_dir/manifest"
}

root_ref="$(git -C "$ROOT" symbolic-ref --quiet HEAD)"
before_head="$old_head"
before_index="$(git -C "$ROOT" diff --cached --binary | sha256sum | awk '{print $1}')"
before_dirty="$(dirty_worktree_fingerprint)"
rollback_needed=0

rollback_shared_sync() {
    local rollback_rc=0
    git -C "$ROOT" update-ref "$root_ref" "$old_head" "$target_head" || rollback_rc=1
    git -C "$ROOT" read-tree --reset -u "$old_head" || rollback_rc=1
    restore_staged_index || rollback_rc=1
    restore_dirty_overlap || rollback_rc=1
    return "$rollback_rc"
}

on_exit() {
    local rc=$?
    if [[ "$rollback_needed" == 1 ]]; then
        rollback_shared_sync || rc=1
    fi
    cleanup_shared_sync
    exit "$rc"
}
trap on_exit EXIT

if [[ "$mode" == already_contains_target ]]; then
    rollback_needed=0
    printf 'SAFE_SHARED_MAIN_FF_SYNC old=%s target=%s new=%s mode=%s changed_paths=0 dirty_paths=%s dirty_overlap_restored=yes index_preserved=yes non_target_dirty_preserved=yes result=PASS\n' \
        "$before_head" "$target_head" "$before_head" "$mode" "$(wc -l < "$dirty_file")"
    exit 0
fi

# D012: CAS ref movement plus read-tree is the only shared-root convergence
# operation.  No shared-root merge, rebase, or cherry-pick is permitted.
git -C "$ROOT" update-ref "$root_ref" "$target_head" "$old_head" || {
    echo "BLOCK: shared ref changed before non-merge synchronization" >&2
    exit 2
}
rollback_needed=1
git -C "$ROOT" read-tree --reset -u "$target_head" || {
    echo "BLOCK: target HEAD/index/worktree synchronization failed" >&2
    exit 1
}
restore_staged_index || {
    echo "BLOCK: unrelated staged index restoration failed" >&2
    exit 1
}
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    git -C "$ROOT" diff --quiet HEAD -- "$path" || {
        echo "BLOCK: targetized worktree does not match HEAD: $path" >&2
        exit 1
    }
    git -C "$ROOT" diff --cached --quiet HEAD -- "$path" || {
        echo "BLOCK: targetized index does not match HEAD: $path" >&2
        exit 1
    }
done < "$changed_file"
restore_dirty_overlap || {
    echo "BLOCK: dirty overlap exact restoration failed" >&2
    exit 1
}

after_head="$(git -C "$ROOT" rev-parse HEAD)"
after_index="$(git -C "$ROOT" diff --cached --binary | sha256sum | awk '{print $1}')"
after_dirty="$(dirty_worktree_fingerprint)"
[[ "$after_head" == "$target_head" ]] || { echo "BLOCK: target ref did not become HEAD" >&2; exit 1; }
[[ "$after_index" == "$before_index" ]] || { echo "BLOCK: staged index changed during synchronization" >&2; exit 1; }
[[ "$after_dirty" == "$before_dirty" ]] || { echo "BLOCK: dirty content or mode changed during synchronization" >&2; exit 1; }
git -C "$ROOT" merge-base --is-ancestor "$target_head" "$after_head" || {
    echo "BLOCK: target history is not contained after non-merge synchronization" >&2
    exit 1
}
rollback_needed=0
printf 'SAFE_SHARED_MAIN_FF_SYNC old=%s target=%s new=%s mode=%s changed_paths=%s dirty_paths=%s dirty_overlap_restored=yes index_preserved=yes non_target_dirty_preserved=yes result=PASS\n' \
    "$before_head" "$target_head" "$after_head" "$mode" "$(wc -l < "$changed_file")" "$(wc -l < "$dirty_file")"
