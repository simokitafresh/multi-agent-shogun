#!/usr/bin/env bash
# ninja_scope_commit.sh — shared index上で指定pathだけを安全にcommitする
set -euo pipefail

# GA-222: このscript自身が置かれているdirectory(=multi-agent-shogunの
# scripts/)を動的に求める。ninja_scope_commit.shはDM-Signal等、別repoを
# cwdにして呼ばれることがあるため($repo_rootはそちらのrepo rootになる)、
# 後段でsourceするSSOT(scripts/lib/scope_path.sh)は「操作対象repo」ではなく
# 「このscript自身の設置場所」基準で解決する。cd実行より前に計算すること
# (BASH_SOURCEが相対pathの場合、後のcdでPWD基準の解決が狂うため)。
_ninja_scope_commit_self="${BASH_SOURCE[0]:-$0}"
[[ "$_ninja_scope_commit_self" = /* ]] || _ninja_scope_commit_self="$PWD/$_ninja_scope_commit_self"
NINJA_SCOPE_COMMIT_SCRIPT_DIR="$(cd "$(dirname "$_ninja_scope_commit_self")" && pwd)"
unset _ninja_scope_commit_self

usage() {
    echo "Usage: bash scripts/ninja_scope_commit.sh -m <message> [--patch <file> --base-blob <hash>] -- <path> [path ...]" >&2
}

message=""
patch_file=""
base_blob=""
while (($#)); do
    case "$1" in
        -m|--message)
            (($# >= 2)) || { usage; exit 2; }
            message="$2"
            shift 2
            ;;
        --patch)
            (($# >= 2)) || { usage; exit 2; }
            patch_file="$2"
            shift 2
            ;;
        --base-blob)
            (($# >= 2)) || { usage; exit 2; }
            base_blob="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "BLOCK: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[[ -n "$message" ]] || { echo "BLOCK: commit message is required" >&2; exit 2; }
(($# > 0)) || { echo "BLOCK: commit scope is empty" >&2; exit 2; }
if [[ -n "$patch_file" || -n "$base_blob" ]]; then
    [[ -n "$patch_file" && -n "$base_blob" ]] \
        || { echo "BLOCK: --patch and --base-blob must be used together" >&2; exit 2; }
    (($# == 1)) \
        || { echo "BLOCK: patch mode requires exactly one scope path" >&2; exit 2; }
    [[ "$base_blob" =~ ^[0-9a-f]{40}$ ]] \
        || { echo "BLOCK: --base-blob must be a full 40-hex object id" >&2; exit 2; }
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || { echo "BLOCK: not inside a git repository" >&2; exit 2; }
cd "$repo_root"

# A private GIT_INDEX_FILE isolates each commit tree, but `git commit` still
# shares COMMIT_EDITMSG, hooks, and the branch ref.  Concurrent callers used to
# overwrite one another's message and one loser could fail the ref update;
# callers running with `set -e` then lost their parent shell before its next
# command.  Serialize the complete transaction in the common git directory so
# linked worktrees and the main worktree use the same lock.
git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" \
    || { echo "BLOCK: cannot resolve git common directory" >&2; exit 2; }
[[ "$git_common_dir" = /* ]] || git_common_dir="$repo_root/$git_common_dir"
# WSL2/DrvFs上のflockは不安定なため、repository identityはcommon dirで
# 共有しつつ実lockはlock_path SSOTでext4側へ写像する。
# shellcheck source=scripts/lib/lock_path.sh
source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/lock_path.sh"
commit_lock_path="$(lock_path "$git_common_dir/ninja-scope-commit")"
exec {commit_lock_fd}>"$commit_lock_path" \
    || { echo "BLOCK: cannot open ninja scope commit lock" >&2; exit 2; }
flock -w 120 "$commit_lock_fd" \
    || { echo "BLOCK: cannot acquire ninja scope commit lock" >&2; exit 2; }

# The lock serializes this helper, but a direct `git add` does not participate
# in it.  Keep the real shared-index path and update entries with a compare
# against the snapshot taken before the commit.  This is the common boundary
# for patch and normal mode: a foreign stage is preserved, never reset merely
# because HEAD advanced.
shared_index_file="$(git rev-parse --git-path index)"
[[ "$shared_index_file" = /* ]] || shared_index_file="$repo_root/$shared_index_file"

advance_shared_index_entry() {
    local path="$1" expected_entry="$2" current_entry new_blob new_mode
    current_entry="$(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -- "$path" | awk '$3 == 0 {print $1 " " $2; exit}')"
    if [[ "$current_entry" != "$expected_entry" ]]; then
        echo "WARN: shared index changed concurrently; preserving newer staged entry: $path" >&2
        return 0
    fi
    if git cat-file -e "HEAD:$path" 2>/dev/null; then
        new_blob="$(git rev-parse "HEAD:$path")"
        new_mode="$(git ls-tree HEAD -- "$path" | awk 'NR==1 {print $1}')"
        [[ "$current_entry" == "$new_mode $new_blob" ]] && return 0
        GIT_INDEX_FILE="$shared_index_file" git update-index --add --cacheinfo "$new_mode,$new_blob,$path"
    else
        [[ -z "$current_entry" ]] && return 0
        GIT_INDEX_FILE="$shared_index_file" git update-index --force-remove -- "$path"
    fi
}

# GA-222: scope path正規化はscripts/lib/scope_path.sh(SSOT)に集約する。
# ここ(commit scopeのバリデーション)とsync_git_hooks.sh(is_in_scope判定)で
# 別々に正規化ロジックを持つと、片方だけ直して片方が取り残される形で
# 同じ穴が別のpath表現で繰り返し再発したため、両scriptとも同一helperのみを使う。
# shellcheck source=scripts/lib/scope_path.sh
source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/scope_path.sh"

paths=()
for path in "$@"; do
    [[ -n "$path" && "$path" != -* ]] \
        || { echo "BLOCK: invalid scope path: ${path:-<empty>}" >&2; exit 2; }
    # scope_path_normalizeは絶対path・".."を含むpath(出現位置を問わず)・
    # root相当に解決されるpath(空/"."/".."単体等)を全てfail-closedし、
    # 理由をstderrへ書く(このtry/exitはその理由をそのまま伝播させる)。
    normalized="$(scope_path_normalize "$path")" || exit 2
    if [[ -z "$patch_file" ]]; then
        [[ -e "$normalized" || -L "$normalized" ]] \
            || { echo "BLOCK: scope path does not exist: $normalized" >&2; exit 2; }
        [[ -n "$(git status --porcelain -- "$normalized")" ]] \
            || { echo "BLOCK: scope path has no changes: $normalized" >&2; exit 2; }
    fi
    paths+=("$normalized")
done

# 同一pathに複数agentのhunkが混在する場合の非対話入口。共有index/working treeを
# sourceにせず、HEADから作った専用indexへ明示patchだけを適用してcommitする。
# --base-blobはpatch作成時の基準を固定し、古いpatchの誤適用を事前BLOCKする。
if [[ -n "$patch_file" ]]; then
    [[ -f "$patch_file" && -s "$patch_file" ]] \
        || { echo "BLOCK: patch is missing or empty: $patch_file" >&2; exit 2; }
    patch_file="$(cd "$(dirname "$patch_file")" && pwd)/$(basename "$patch_file")"
    scope_path="${paths[0]}"
    if git cat-file -e "HEAD:$scope_path" 2>/dev/null; then
        head_blob="$(git rev-parse "HEAD:$scope_path")"
    else
        head_blob="0000000000000000000000000000000000000000"
    fi
    [[ "$head_blob" == "$base_blob" ]] \
        || { echo "BLOCK: base blob mismatch for $scope_path (expected $base_blob, HEAD has $head_blob)" >&2; exit 2; }
    shared_index_blob="$(git ls-files -s -- "$scope_path" | awk 'NR==1 {print $2}')"
    [[ "${shared_index_blob:-0000000000000000000000000000000000000000}" == "$head_blob" ]] \
        || { echo "BLOCK: scope path already has staged content in shared index: $scope_path" >&2; exit 2; }
    shared_index_entry_before="$(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -- "$scope_path" | awk '$3 == 0 {print $1 " " $2; exit}')"

    mapfile -t patch_paths < <(git apply --numstat -- "$patch_file" 2>/dev/null | awk '{print $3}')
    ((${#patch_paths[@]} > 0)) \
        || { echo "BLOCK: patch has no applicable file changes" >&2; exit 2; }
    for patch_path in "${patch_paths[@]}"; do
        [[ "$patch_path" == "$scope_path" ]] \
            || { echo "BLOCK: patch contains out-of-scope path: $patch_path" >&2; exit 2; }
    done

    temp_index="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-index.XXXXXX")"
    rm -f "$temp_index"
    cleanup_patch_index() { rm -f "$temp_index" "$temp_index.lock"; }
    trap cleanup_patch_index EXIT
    export GIT_INDEX_FILE="$temp_index"
    git read-tree HEAD
    git apply --cached --check -- "$patch_file" \
        || { echo "BLOCK: patch does not apply cleanly to the declared base" >&2; exit 2; }
    git apply --cached -- "$patch_file"
    [[ -n "$(git diff --cached --name-only)" ]] \
        || { echo "BLOCK: patch produced an empty index diff" >&2; exit 2; }
    [[ "$(git diff --cached --name-only)" == "$scope_path" ]] \
        || { echo "BLOCK: patch polluted temporary index scope" >&2; exit 2; }
    # git apply may relocate a hunk when identical context exists elsewhere.  A
    # clean exit alone therefore does not prove that the requested line range
    # entered the index.  Compare the patch's exact +/- line coordinates and
    # content with a zero-context diff generated from the temporary index.
    staged_patch="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-staged.XXXXXX")"
    cleanup_patch_index() { rm -f "$temp_index" "$temp_index.lock" "$staged_patch"; }
    git diff --cached --no-ext-diff --no-color --unified=0 -- "$scope_path" > "$staged_patch"
    python3 - "$patch_file" "$staged_patch" <<'PY' \
        || { echo "BLOCK: staged diff does not exactly match requested patch position/content" >&2; exit 2; }
import re
import sys

HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')

def changes(path):
    result = []
    old_line = new_line = None
    with open(path, encoding='utf-8', errors='surrogateescape') as stream:
        for raw in stream:
            line = raw.rstrip('\n')
            match = HUNK.match(line)
            if match:
                old_line, new_line = int(match.group(1)), int(match.group(3))
                continue
            if old_line is None or line.startswith(('--- ', '+++ ', '\\')):
                continue
            if line.startswith('-'):
                result.append(('-', old_line, line[1:]))
                old_line += 1
            elif line.startswith('+'):
                result.append(('+', new_line, line[1:]))
                new_line += 1
            elif line.startswith(' '):
                old_line += 1
                new_line += 1
    return result

expected, actual = changes(sys.argv[1]), changes(sys.argv[2])
if not expected or expected != actual:
    print(f'expected changes={expected!r}', file=sys.stderr)
    print(f'actual changes={actual!r}', file=sys.stderr)
    raise SystemExit(1)
PY
    git commit -m "$message"
    # HEAD更新後、共有indexの対象pathだけを新HEADへ追随させる。他pathのstageは
    # 一切変更せず、対象pathが旧HEAD由来の逆差分として残るindex汚染を防ぐ。
    unset GIT_INDEX_FILE
    advance_shared_index_entry "$scope_path" "$shared_index_entry_before"
    git rev-parse HEAD
    exit 0
fi

# Normal modeも共有indexをcommit sourceにしない。HEAD由来の専用indexへ
# 指定scopeだけをaddし、commit objectの入力自体を所有権分離する。
# 共有indexにscope自身が既にstage済みでも、それがprivate indexへaddした
# worktree blobと完全一致するなら所有内容は同一なので安全に続行できる。
# partial stage等で両者が異なる場合だけfail-closedする。これにより別workerの
# unrelated stageを保持したまま、各workerが事前stageした自身のscopeをcommit
# できる。post-commit更新用に共有index entryをsnapshotしておく。
declare -A shared_index_before=()
declare -A shared_scope_entries_before=()
declare -A shared_scope_staged_before=()
for scope_path in "${paths[@]}"; do
    shared_scope_entries_before["$scope_path"]="$(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -- "$scope_path")"
    if GIT_INDEX_FILE="$shared_index_file" git diff --cached --quiet -- "$scope_path"; then
        shared_scope_staged_before["$scope_path"]=0
    else
        shared_scope_staged_before["$scope_path"]=1
    fi
done
# Per-file snapshot is separate from the scope snapshot because a scope may be
# a directory.  The post-commit CAS-style check must compare each committed
# file with its own prior shared-index entry, not a tree/pathspec aggregate.
while IFS= read -r -d '' index_record; do
    index_meta="${index_record%%$'\t'*}"
    index_path="${index_record#*$'\t'}"
    shared_index_before["$index_path"]="${index_meta% 0}"
done < <(GIT_INDEX_FILE="$shared_index_file" git ls-files -s -z -- "${paths[@]}")

temp_index="$(mktemp "${TMPDIR:-/tmp}/ninja-scope-index.XXXXXX")"
rm -f "$temp_index"
cleanup_normal_index() { rm -f "$temp_index" "$temp_index.lock"; }
trap cleanup_normal_index EXIT
export GIT_INDEX_FILE="$temp_index"
git read-tree HEAD
git add -- "${paths[@]}"

for scope_path in "${paths[@]}"; do
    private_entries="$(git ls-files -s -- "$scope_path")"
    shared_entries="${shared_scope_entries_before[$scope_path]}"
    if [[ "${shared_scope_staged_before[$scope_path]}" == 1 && "$shared_entries" != "$private_entries" ]]; then
        echo "BLOCK: scope path has partial/foreign staged content that differs from worktree: $scope_path (use --patch)" >&2
        exit 2
    fi
done

# GA-222: commit前にgitが実際に発火するhookを正本(scripts/hooks/*.sh)と同期する。
# git add後に呼ぶことで、対象正本がこのcommitのscope内ならstaged(index)版、
# scope外(他agentの作業中/未確定分含む)ならHEAD(直近commit済み)版を使い分けられる。
# 正本が存在しないrepo(このrepoの規約非対象)では無害にno-op。
if [[ -f "$repo_root/scripts/sync_git_hooks.sh" ]]; then
    sync_args=()
    for scope_path in "${paths[@]}"; do
        sync_args+=(--scope-path "$scope_path")
    done
    bash "$repo_root/scripts/sync_git_hooks.sh" "${sync_args[@]}" \
        || { echo "BLOCK(GA-222): git hook sync failed — commit aborted" >&2; exit 1; }
fi
# GA-222と同じ理由(script冒頭コメント参照): 呼び出し時のcwdは対象repo
# ($repo_root、DM-Signal等)になり得るため、"$repo_root/../multi-agent-shogun"の
# 相対推測や"/mnt/c/tools/multi-agent-shogun"のWSL2固定パスはCI runner等の
# 別環境で解決に失敗しguardが無言でno-opになる。このscript自身の設置場所
# (NINJA_SCOPE_COMMIT_SCRIPT_DIR)は常にmulti-agent-shogun/scripts/を指すため
# それを基準にguardを解決する。
if [[ -f "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" ]]; then
    bash "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/dm_signal_research_reflux_guard.sh" check --repo "$repo_root"
fi
git commit -m "$message"
commit_hash="$(git rev-parse HEAD)"
mapfile -t committed < <(git diff-tree --no-commit-id --name-only -r HEAD)
unset GIT_INDEX_FILE

# 共有indexは指定scopeだけ新HEADへ追随。他pathのstageはblob/modeとも不変。
# commit中に別processがscopeの共有index entryを書き換えた場合は、その新しい
# stageを上書きせず保持する。事前stageがprivate entryと同一なら既にnew HEADと
# 一致するためupdate不要、cleanな旧HEAD entryだけをnew HEADへ進める。
for committed_path in "${committed[@]}"; do
    shared_entry_before="${shared_index_before[$committed_path]-}"
    advance_shared_index_entry "$committed_path" "$shared_entry_before"
done
cleanup_normal_index
trap - EXIT

# 二値postcondition: commit treeは指定scopeのみ、他者stageはそのまま残る。
# scope_path_is_in_scope(SSOT)で判定することで、正規化ロジックの重複を避ける。
for committed_path in "${committed[@]}"; do
    scope_path_is_in_scope "$committed_path" "${paths[@]}" \
        || { echo "FATAL: out-of-scope path entered commit: $committed_path" >&2; exit 1; }
done

# Commit直後に同一scopeへ自分のcommitと重なるdirty hunkが残れば、報告gateまで
# 遅延させずここで停止する。他者の並行作業による非重複hunkは許容する。
if [[ -f "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/report_commit_nonoverlap_filter.sh" ]]; then
    # shellcheck source=scripts/lib/report_commit_nonoverlap_filter.sh
    source "$NINJA_SCOPE_COMMIT_SCRIPT_DIR/lib/report_commit_nonoverlap_filter.sh"
    dirty_scope_paths="$({ git diff --name-only -- "${paths[@]}"; git diff --cached --name-only -- "${paths[@]}"; } | sort -u | sed '/^$/d')"
    if [[ -n "$dirty_scope_paths" ]]; then
        commit_probe="$(mktemp)"
        trap 'rm -f "${commit_probe:-}"' EXIT
        printf 'commit_hash: %s\n' "$commit_hash" > "$commit_probe"
        overlapping_dirty="$(filter_report_commit_nonoverlap_uncommitted "$repo_root" "$commit_probe" "$dirty_scope_paths")"
        rm -f "$commit_probe"
        trap - EXIT
        if [[ -n "$overlapping_dirty" ]]; then
            echo "BLOCK(GA-260): commit後も同一scopeにcommit hunkと重なる未commit差分あり:" >&2
            while IFS= read -r dirty_path; do
                [[ -n "$dirty_path" ]] && printf '  %s\n' "$dirty_path" >&2
            done <<< "$overlapping_dirty"
            echo "追加差分をscope commitして作業木を収束させてから報告せよ" >&2
            exit 1
        fi
    fi
fi

printf '%s\n' "$commit_hash"
